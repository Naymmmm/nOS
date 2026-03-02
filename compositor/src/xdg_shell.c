/* noscomp/src/xdg_shell.c — xdg-shell window management */
#define WLR_USE_UNSTABLE

#include <stdlib.h>
#include <string.h>

#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/util/log.h>
#include <wlr/util/edges.h>

#include "noscomp.h"

/* ---- Helpers ---- */

void focus_view(struct nos_view *view, struct wlr_surface *surface) {
    if (!view) return;
    struct nos_server *server = view->server;
    struct wlr_seat   *seat   = server->seat;

    struct wlr_surface *prev = seat->keyboard_state.focused_surface;
    if (prev == surface) return;

    if (prev) {
        /* Deactivate the previous toplevel */
        struct wlr_xdg_toplevel *prev_toplevel =
            wlr_xdg_toplevel_try_from_wlr_surface(prev);
        if (prev_toplevel)
            wlr_xdg_toplevel_set_activated(prev_toplevel, false);
    }

    /* Move the view to front */
    wlr_scene_node_raise_to_top(&view->scene_tree->node);
    wl_list_remove(&view->link);
    wl_list_insert(&server->views, &view->link);

    wlr_xdg_toplevel_set_activated(view->xdg_toplevel, true);

    struct wlr_keyboard *kb = wlr_seat_get_keyboard(seat);
    if (kb) {
        wlr_seat_keyboard_notify_enter(seat, surface,
            kb->keycodes, kb->num_keycodes, &kb->modifiers);
    }
}

struct nos_view *view_at(struct nos_server *server, double lx, double ly,
                          struct wlr_surface **surface, double *sx, double *sy) {
    struct wlr_scene_node *node =
        wlr_scene_node_at(&server->scene->tree.node, lx, ly, sx, sy);
    if (!node || node->type != WLR_SCENE_NODE_BUFFER)
        return NULL;

    struct wlr_scene_buffer *sbuf = wlr_scene_buffer_from_node(node);
    struct wlr_scene_surface *ssurface =
        wlr_scene_surface_try_from_buffer(sbuf);
    if (!ssurface) return NULL;
    *surface = ssurface->surface;

    struct wlr_scene_tree *tree = node->parent;
    while (tree && !tree->node.data)
        tree = tree->node.parent;
    return tree ? tree->node.data : NULL;
}

/* ---- View lifecycle ---- */

static void view_handle_map(struct wl_listener *listener, void *data) {
    struct nos_view *view = wl_container_of(listener, view, map);
    wl_list_insert(&view->server->views, &view->link);
    focus_view(view, view->xdg_toplevel->base->surface);
    anim_start_open(view);
}

static void view_handle_unmap(struct wl_listener *listener, void *data) {
    struct nos_view *view = wl_container_of(listener, view, unmap);
    /* If we're grabbing this view, release it */
    if (view == view->server->grabbed_view)
        view->server->grabbed_view = NULL;
    wl_list_remove(&view->link);
}

static void view_handle_destroy(struct wl_listener *listener, void *data) {
    struct nos_view *view = wl_container_of(listener, view, destroy);
    wl_list_remove(&view->map.link);
    wl_list_remove(&view->unmap.link);
    wl_list_remove(&view->destroy.link);
    wl_list_remove(&view->request_move.link);
    wl_list_remove(&view->request_resize.link);
    wl_list_remove(&view->request_maximize.link);
    wl_list_remove(&view->request_fullscreen.link);
    free(view);
}

static void view_handle_request_move(struct wl_listener *listener, void *data) {
    struct nos_view *view = wl_container_of(listener, view, request_move);
    /* Begin interactive move */
    struct nos_server *server = view->server;
    server->grabbed_view  = view;
    server->grab_x        = server->cursor->x - view->x;
    server->grab_y        = server->cursor->y - view->y;
    server->resize_edges  = 0;
    wobble_impulse(&view->wobble,
        (float)(server->cursor->x - view->x) * 0.01f, 0.0f);
}

static void view_handle_request_resize(struct wl_listener *listener, void *data) {
    struct wlr_xdg_toplevel_resize_event *event = data;
    struct nos_view *view = wl_container_of(listener, view, request_resize);
    struct nos_server *server = view->server;
    server->grabbed_view  = view;
    server->resize_edges  = event->edges;
    struct wlr_box geo;
    wlr_xdg_surface_get_geometry(view->xdg_toplevel->base, &geo);
    server->grab_geobox = geo;
    server->grab_geobox.x += view->x;
    server->grab_geobox.y += view->y;
    server->grab_x = server->cursor->x;
    server->grab_y = server->cursor->y;
}

static void view_handle_request_maximize(struct wl_listener *listener, void *data) {
    struct nos_view *view = wl_container_of(listener, view, request_maximize);
    wlr_xdg_surface_schedule_configure(view->xdg_toplevel->base);
}

static void view_handle_request_fullscreen(struct wl_listener *listener, void *data) {
    struct nos_view *view = wl_container_of(listener, view, request_fullscreen);
    wlr_xdg_surface_schedule_configure(view->xdg_toplevel->base);
}

/* ---- New toplevel ---- */

/* In wlroots 0.17.1 (Ubuntu), xdg_shell only fires new_surface.
   We check the role to distinguish toplevels from popups. */
static void server_handle_new_xdg_surface(struct wl_listener *listener, void *data) {
    struct nos_server      *server  = wl_container_of(listener, server, new_xdg_toplevel);
    struct wlr_xdg_surface *surface = data;

    if (surface->role == WLR_XDG_SURFACE_ROLE_POPUP) {
        /* Popup: attach to parent scene tree */
        struct wlr_xdg_surface *parent =
            wlr_xdg_surface_try_from_wlr_surface(surface->popup->parent);
        if (!parent) return;
        struct wlr_scene_tree *parent_tree = parent->data;
        surface->data = wlr_scene_xdg_surface_create(parent_tree, surface);
        return;
    }

    /* Toplevel */
    struct wlr_xdg_toplevel *toplevel = surface->toplevel;

    struct nos_view *view = calloc(1, sizeof(*view));
    view->server       = server;
    view->xdg_toplevel = toplevel;
    view->scene_tree   = wlr_scene_xdg_surface_create(
        &server->scene->tree, toplevel->base);
    view->scene_tree->node.data = view;
    toplevel->base->data = view->scene_tree;

    wobble_init(&view->wobble);

    view->map.notify              = view_handle_map;
    view->unmap.notify            = view_handle_unmap;
    view->destroy.notify          = view_handle_destroy;
    view->request_move.notify     = view_handle_request_move;
    view->request_resize.notify   = view_handle_request_resize;
    view->request_maximize.notify = view_handle_request_maximize;
    view->request_fullscreen.notify = view_handle_request_fullscreen;

    wl_signal_add(&toplevel->base->surface->events.map,    &view->map);
    wl_signal_add(&toplevel->base->surface->events.unmap,  &view->unmap);
    wl_signal_add(&toplevel->base->events.destroy,         &view->destroy);
    wl_signal_add(&toplevel->events.request_move,          &view->request_move);
    wl_signal_add(&toplevel->events.request_resize,        &view->request_resize);
    wl_signal_add(&toplevel->events.request_maximize,      &view->request_maximize);
    wl_signal_add(&toplevel->events.request_fullscreen,    &view->request_fullscreen);
}

void xdg_shell_init(struct nos_server *server) {
    server->xdg_shell = wlr_xdg_shell_create(server->wl_display, 3);
    /* Use new_surface (0.17) — new_toplevel/new_popup split is wlroots ≥ 0.18 */
    server->new_xdg_toplevel.notify = server_handle_new_xdg_surface;
    wl_signal_add(&server->xdg_shell->events.new_surface, &server->new_xdg_toplevel);
}
