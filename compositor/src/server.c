/* noscomp/src/server.c — Wayland server init and event loop */
#define WLR_USE_UNSTABLE

#include <stdlib.h>
#include <string.h>

#include <wayland-server-core.h>
#include <wlr/backend.h>
#include <wlr/render/allocator.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_data_device.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_subcompositor.h>
#include <wlr/util/log.h>

#include "noscomp.h"

void server_init(struct nos_server *server) {
    memset(server, 0, sizeof(*server));

    server->wl_display = wl_display_create();

    server->backend = wlr_backend_autocreate(server->wl_display, NULL);
    if (!server->backend) {
        wlr_log(WLR_ERROR, "Failed to create wlr_backend");
        exit(1);
    }

    server->renderer = wlr_renderer_autocreate(server->backend);
    if (!server->renderer) {
        wlr_log(WLR_ERROR, "Failed to create wlr_renderer");
        exit(1);
    }
    wlr_renderer_init_wl_display(server->renderer, server->wl_display);

    server->allocator = wlr_allocator_autocreate(server->backend, server->renderer);
    if (!server->allocator) {
        wlr_log(WLR_ERROR, "Failed to create wlr_allocator");
        exit(1);
    }

    wlr_compositor_create(server->wl_display, 5, server->renderer);
    wlr_subcompositor_create(server->wl_display);
    wlr_data_device_manager_create(server->wl_display);

    server->output_layout = wlr_output_layout_create();
    if (!server->output_layout) {
        wlr_log(WLR_ERROR, "Failed to create output layout");
        exit(1);
    }

    wl_list_init(&server->outputs);
    wl_list_init(&server->views);
    wl_list_init(&server->keyboards);

    server->scene = wlr_scene_create();
    server->scene_layout = wlr_scene_attach_output_layout(
        server->scene, server->output_layout);

    server->workspace       = 0;
    server->workspace_count = 4;

    output_init(server);
    xdg_shell_init(server);
    layer_shell_init(server);
    input_init(server);
    decoration_init(server);
}

void server_run(struct nos_server *server) {
    wl_display_run(server->wl_display);
}

void server_finish(struct nos_server *server) {
    wl_display_destroy_clients(server->wl_display);
    wlr_output_layout_destroy(server->output_layout);
    wlr_backend_destroy(server->backend);
    wl_display_destroy(server->wl_display);
}
