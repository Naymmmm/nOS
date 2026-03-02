/* noscomp/src/input.c — keyboard, pointer, seat */
#define WLR_USE_UNSTABLE

#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_input_device.h>
#include <wlr/types/wlr_keyboard.h>
#include <wlr/types/wlr_pointer.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_xcursor_manager.h>
#include <wlr/util/log.h>
#include <xkbcommon/xkbcommon.h>

#include "noscomp.h"

/* ---- Keyboard ---- */

static bool handle_keybinding(struct nos_server *server, xkb_keysym_t sym) {
    switch (sym) {
    case XKB_KEY_Escape:
        wl_display_terminate(server->wl_display);
        return true;
    case XKB_KEY_F1: {
        /* cycle focus */
        if (wl_list_length(&server->views) < 2) return false;
        struct nos_view *next =
            wl_container_of(server->views.prev, next, link);
        focus_view(next, next->xdg_toplevel->base->surface);
        return true;
    }
    default:
        return false;
    }
}

static void keyboard_handle_modifiers(struct wl_listener *listener, void *data) {
    struct nos_keyboard *kb = wl_container_of(listener, kb, modifiers);
    wlr_seat_set_keyboard(kb->server->seat, kb->wlr_keyboard);
    wlr_seat_keyboard_notify_modifiers(kb->server->seat,
        &kb->wlr_keyboard->modifiers);
}

static void keyboard_handle_key(struct wl_listener *listener, void *data) {
    struct nos_keyboard *kb  = wl_container_of(listener, kb, key);
    struct nos_server   *srv = kb->server;
    struct wlr_keyboard_key_event *event = data;

    uint32_t keycode = event->keycode + 8;
    const xkb_keysym_t *syms;
    int nsyms = xkb_state_key_get_syms(
        kb->wlr_keyboard->xkb_state, keycode, &syms);

    bool handled = false;
    uint32_t mods = wlr_keyboard_get_modifiers(kb->wlr_keyboard);
    if ((mods & WLR_MODIFIER_ALT) && event->state == WL_KEYBOARD_KEY_STATE_PRESSED) {
        for (int i = 0; i < nsyms; i++)
            handled = handle_keybinding(srv, syms[i]);
    }

    if (!handled) {
        wlr_seat_set_keyboard(srv->seat, kb->wlr_keyboard);
        wlr_seat_keyboard_notify_key(srv->seat, event->time_msec,
            event->keycode, event->state);
    }
}

static void keyboard_handle_destroy(struct wl_listener *listener, void *data) {
    struct nos_keyboard *kb = wl_container_of(listener, kb, destroy);
    wl_list_remove(&kb->modifiers.link);
    wl_list_remove(&kb->key.link);
    wl_list_remove(&kb->destroy.link);
    wl_list_remove(&kb->link);
    free(kb);
}

static void server_new_keyboard(struct nos_server *server,
                                struct wlr_input_device *device) {
    struct wlr_keyboard *wlr_kb = wlr_keyboard_from_input_device(device);
    struct nos_keyboard *kb = calloc(1, sizeof(*kb));
    kb->server       = server;
    kb->wlr_keyboard = wlr_kb;

    struct xkb_context *ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    struct xkb_keymap  *map = xkb_keymap_new_from_names(ctx, NULL,
        XKB_KEYMAP_COMPILE_NO_FLAGS);
    wlr_keyboard_set_keymap(wlr_kb, map);
    xkb_keymap_unref(map);
    xkb_context_unref(ctx);
    wlr_keyboard_set_repeat_info(wlr_kb, 25, 600);

    kb->modifiers.notify = keyboard_handle_modifiers;
    kb->key.notify       = keyboard_handle_key;
    kb->destroy.notify   = keyboard_handle_destroy;
    wl_signal_add(&wlr_kb->events.modifiers, &kb->modifiers);
    wl_signal_add(&wlr_kb->events.key,       &kb->key);
    wl_signal_add(&device->events.destroy,   &kb->destroy);

    wlr_seat_set_keyboard(server->seat, wlr_kb);
    wl_list_insert(&server->keyboards, &kb->link);
}

/* ---- Pointer ---- */

static void process_cursor_motion(struct nos_server *server, uint32_t time) {
    double sx, sy;
    struct wlr_seat    *seat    = server->seat;
    struct wlr_surface *surface = NULL;

    /* Interactive move */
    if (server->grabbed_view && server->resize_edges == 0) {
        struct nos_view *view = server->grabbed_view;
        view->x = (int)(server->cursor->x - server->grab_x);
        view->y = (int)(server->cursor->y - server->grab_y);
        wlr_scene_node_set_position(&view->scene_tree->node, view->x, view->y);
        wobble_impulse(&view->wobble,
            (float)(server->cursor->x - server->grab_x) * 0.005f,
            (float)(server->cursor->y - server->grab_y) * 0.005f);
        return;
    }

    struct nos_view *view = view_at(server,
        server->cursor->x, server->cursor->y, &surface, &sx, &sy);

    if (!view) {
        wlr_cursor_set_xcursor(server->cursor, server->cursor_mgr, "default");
    }

    if (surface) {
        wlr_seat_pointer_notify_enter(seat, surface, sx, sy);
        wlr_seat_pointer_notify_motion(seat, time, sx, sy);
    } else {
        wlr_seat_pointer_clear_focus(seat);
    }
}

static void server_cursor_motion(struct wl_listener *listener, void *data) {
    struct nos_server *server = wl_container_of(listener, server, cursor_motion);
    struct wlr_pointer_motion_event *event = data;
    wlr_cursor_move(server->cursor, &event->pointer->base,
        event->delta_x, event->delta_y);
    process_cursor_motion(server, event->time_msec);
}

static void server_cursor_motion_absolute(struct wl_listener *listener, void *data) {
    struct nos_server *server =
        wl_container_of(listener, server, cursor_motion_absolute);
    struct wlr_pointer_motion_absolute_event *event = data;
    wlr_cursor_warp_absolute(server->cursor, &event->pointer->base,
        event->x, event->y);
    process_cursor_motion(server, event->time_msec);
}

static void server_cursor_button(struct wl_listener *listener, void *data) {
    struct nos_server *server = wl_container_of(listener, server, cursor_button);
    struct wlr_pointer_button_event *event = data;

    wlr_seat_pointer_notify_button(server->seat, event->time_msec,
        event->button, event->state);

    if (event->state == WLR_BUTTON_RELEASED) {
        server->grabbed_view = NULL;
        return;
    }

    double sx, sy;
    struct wlr_surface *surface = NULL;
    struct nos_view *view = view_at(server,
        server->cursor->x, server->cursor->y, &surface, &sx, &sy);
    if (view) focus_view(view, surface);
}

static void server_cursor_axis(struct wl_listener *listener, void *data) {
    struct nos_server *server = wl_container_of(listener, server, cursor_axis);
    struct wlr_pointer_axis_event *event = data;
    wlr_seat_pointer_notify_axis(server->seat, event->time_msec,
        event->orientation, event->delta, event->delta_discrete,
        event->source);
}

static void server_cursor_frame(struct wl_listener *listener, void *data) {
    struct nos_server *server = wl_container_of(listener, server, cursor_frame);
    wlr_seat_pointer_notify_frame(server->seat);
}

/* ---- Seat requests ---- */

static void server_request_cursor(struct wl_listener *listener, void *data) {
    struct nos_server *server = wl_container_of(listener, server, request_cursor);
    struct wlr_seat_pointer_request_set_cursor_event *event = data;
    struct wlr_seat_client *focused = server->seat->pointer_state.focused_client;
    if (focused == event->seat_client)
        wlr_cursor_set_surface(server->cursor, event->surface,
            event->hotspot_x, event->hotspot_y);
}

static void server_request_set_selection(struct wl_listener *listener, void *data) {
    struct nos_server *server =
        wl_container_of(listener, server, request_set_selection);
    struct wlr_seat_request_set_selection_event *event = data;
    wlr_seat_set_selection(server->seat, event->source, event->serial);
}

/* ---- New input device ---- */

static void server_new_input(struct wl_listener *listener, void *data) {
    struct nos_server     *server = wl_container_of(listener, server, new_input);
    struct wlr_input_device *dev  = data;

    switch (dev->type) {
    case WLR_INPUT_DEVICE_KEYBOARD:
        server_new_keyboard(server, dev);
        break;
    case WLR_INPUT_DEVICE_POINTER:
        wlr_cursor_attach_input_device(server->cursor, dev);
        break;
    default:
        break;
    }

    uint32_t caps = WL_SEAT_CAPABILITY_POINTER;
    if (!wl_list_empty(&server->keyboards))
        caps |= WL_SEAT_CAPABILITY_KEYBOARD;
    wlr_seat_set_capabilities(server->seat, caps);
}

/* ---- Init ---- */

void input_init(struct nos_server *server) {
    server->cursor = wlr_cursor_create();
    wlr_cursor_attach_output_layout(server->cursor, server->output_layout);

    server->cursor_mgr = wlr_xcursor_manager_create(NULL, 24);

    server->cursor_motion.notify          = server_cursor_motion;
    server->cursor_motion_absolute.notify = server_cursor_motion_absolute;
    server->cursor_button.notify          = server_cursor_button;
    server->cursor_axis.notify            = server_cursor_axis;
    server->cursor_frame.notify           = server_cursor_frame;
    wl_signal_add(&server->cursor->events.motion,          &server->cursor_motion);
    wl_signal_add(&server->cursor->events.motion_absolute, &server->cursor_motion_absolute);
    wl_signal_add(&server->cursor->events.button,          &server->cursor_button);
    wl_signal_add(&server->cursor->events.axis,            &server->cursor_axis);
    wl_signal_add(&server->cursor->events.frame,           &server->cursor_frame);

    server->seat = wlr_seat_create(server->wl_display, "seat0");
    server->request_cursor.notify        = server_request_cursor;
    server->request_set_selection.notify = server_request_set_selection;
    wl_signal_add(&server->seat->events.request_set_cursor,    &server->request_cursor);
    wl_signal_add(&server->seat->events.request_set_selection, &server->request_set_selection);

    server->new_input.notify = server_new_input;
    wl_signal_add(&server->backend->events.new_input, &server->new_input);
}
