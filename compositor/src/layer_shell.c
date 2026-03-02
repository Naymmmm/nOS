/* noscomp/src/layer_shell.c — wlr-layer-shell-v1 support (bar + dock) */
#define WLR_USE_UNSTABLE

#include <stdlib.h>
#include <wlr/types/wlr_layer_shell_v1.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/util/log.h>
#include "noscomp.h"

static void layer_surface_handle_map(struct wl_listener *listener, void *data) {
    /* Layer surfaces (bar, dock) are mapped into scene tree automatically */
    wlr_log(WLR_DEBUG, "layer surface mapped");
}

static void layer_surface_handle_unmap(struct wl_listener *listener, void *data) {
    wlr_log(WLR_DEBUG, "layer surface unmapped");
}

static void layer_surface_handle_destroy(struct wl_listener *listener, void *data) {
    struct wl_listener *ls = listener;
    wl_list_remove(&ls->link);
    free(ls);
}

static void server_handle_new_layer_surface(struct wl_listener *listener, void *data) {
    struct nos_server *server =
        wl_container_of(listener, server, new_layer_surface);
    struct wlr_layer_surface_v1 *layer_surface = data;

    struct wlr_scene_layer_surface_v1 *scene_layer =
        wlr_scene_layer_surface_v1_create(
            &server->scene->tree, layer_surface);

    if (!scene_layer) {
        return;
    }

    /* Arrange layer to the correct output */
    if (!layer_surface->output && !wl_list_empty(&server->outputs)) {
        struct nos_output *output =
            wl_container_of(server->outputs.next, output, link);
        layer_surface->output = output->wlr_output;
    }
}

void layer_shell_init(struct nos_server *server) {
    server->layer_shell = wlr_layer_shell_v1_create(server->wl_display, 4);
    server->new_layer_surface.notify = server_handle_new_layer_surface;
    wl_signal_add(&server->layer_shell->events.new_surface,
                  &server->new_layer_surface);
}
