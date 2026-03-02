/* noscomp/src/output.c — output management and render pipeline */
#define WLR_USE_UNSTABLE

#include <stdlib.h>

#include <wlr/types/wlr_output.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/util/log.h>

#include "noscomp.h"

/* ---- Frame callback ---- */
static void output_handle_frame(struct wl_listener *listener, void *data) {
    struct nos_output *output =
        wl_container_of(listener, output, frame);
    struct wlr_scene *scene = output->server->scene;

    struct wlr_scene_output *scene_output =
        wlr_scene_get_scene_output(scene, output->wlr_output);

    /* Kawase blur pass before compositing */
    blur_pass(output, 2);

    wlr_scene_output_commit(scene_output, NULL);

    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    wlr_scene_output_send_frame_done(scene_output, &now);
}

static void output_handle_request_state(struct wl_listener *listener, void *data) {
    struct nos_output *output =
        wl_container_of(listener, output, request_state);
    const struct wlr_output_event_request_state *event = data;
    wlr_output_commit_state(output->wlr_output, event->state);
}

static void output_handle_destroy(struct wl_listener *listener, void *data) {
    struct nos_output *output =
        wl_container_of(listener, output, destroy);
    blur_finish_output(output);
    wl_list_remove(&output->frame.link);
    wl_list_remove(&output->request_state.link);
    wl_list_remove(&output->destroy.link);
    wl_list_remove(&output->link);
    free(output);
}

static void server_handle_new_output(struct wl_listener *listener, void *data) {
    struct nos_server *server =
        wl_container_of(listener, server, new_output);
    struct wlr_output *wlr_output = data;

    wlr_output_init_render(wlr_output, server->allocator, server->renderer);

    /* Pick the preferred mode — use wlr_output_state API (wlroots ≥ 0.17) */
    struct wlr_output_state state;
    wlr_output_state_init(&state);
    wlr_output_state_set_enabled(&state, true);
    if (!wl_list_empty(&wlr_output->modes)) {
        struct wlr_output_mode *mode = wlr_output_preferred_mode(wlr_output);
        wlr_output_state_set_mode(&state, mode);
    }
    if (!wlr_output_commit_state(wlr_output, &state)) {
        wlr_log(WLR_ERROR, "Failed to commit output state");
        wlr_output_state_finish(&state);
        return;
    }
    wlr_output_state_finish(&state);

    struct nos_output *output = calloc(1, sizeof(*output));
    output->server     = server;
    output->wlr_output = wlr_output;

    output->frame.notify         = output_handle_frame;
    output->request_state.notify = output_handle_request_state;
    output->destroy.notify       = output_handle_destroy;
    wl_signal_add(&wlr_output->events.frame,         &output->frame);
    wl_signal_add(&wlr_output->events.request_state, &output->request_state);
    wl_signal_add(&wlr_output->events.destroy,        &output->destroy);

    wl_list_insert(&server->outputs, &output->link);

    struct wlr_output_layout_output *layout_output =
        wlr_output_layout_add_auto(server->output_layout, wlr_output);
    struct wlr_scene_output *scene_output =
        wlr_scene_output_create(server->scene, wlr_output);
    wlr_scene_output_layout_add_output(server->scene_layout,
                                       layout_output, scene_output);
    output->scene_output = scene_output;

    blur_init_output(output);
}

void output_init(struct nos_server *server) {
    server->new_output.notify = server_handle_new_output;
    wl_signal_add(&server->backend->events.new_output, &server->new_output);
}
