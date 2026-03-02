/* noscomp/src/decoration.c — server-side glass window decorations */
#define WLR_USE_UNSTABLE

#include <stdlib.h>

#include <wlr/types/wlr_xdg_decoration_v1.h>
#include <wlr/util/log.h>

#include "noscomp.h"

static void decoration_handle_destroy(struct wl_listener *listener, void *data) {
    struct wl_listener *l = listener;
    wl_list_remove(&l->link);
    free(l);
}

static void decoration_handle_request_mode(struct wl_listener *listener, void *data) {
    struct wlr_xdg_toplevel_decoration_v1 *dec = data;
    /* Always use server-side decoration */
    wlr_xdg_toplevel_decoration_v1_set_mode(dec,
        WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);
}

static void server_handle_new_decoration(struct wl_listener *listener, void *data) {
    struct wlr_xdg_toplevel_decoration_v1 *dec = data;

    wlr_xdg_toplevel_decoration_v1_set_mode(dec,
        WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);

    struct wl_listener *req = calloc(1, sizeof(*req));
    req->notify = decoration_handle_request_mode;
    wl_signal_add(&dec->events.request_mode, req);

    struct wl_listener *destroy = calloc(1, sizeof(*destroy));
    destroy->notify = decoration_handle_destroy;
    wl_signal_add(&dec->events.destroy, destroy);
}

void decoration_init(struct nos_server *server) {
    struct wlr_xdg_decoration_manager_v1 *mgr =
        wlr_xdg_decoration_manager_v1_create(server->wl_display);

    static struct wl_listener new_dec;
    new_dec.notify = server_handle_new_decoration;
    wl_signal_add(&mgr->events.new_toplevel_decoration, &new_dec);
}

void decoration_render_view(struct nos_view *view) {
    /* Rendering handled by the GLSL shader pipeline in output.c.
       This function is a hook for future SSD title-bar painting. */
    (void)view;
}
