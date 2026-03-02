/* noscomp/src/main.c — entry point */
#define WLR_USE_UNSTABLE

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>

#include <wlr/util/log.h>

#include "noscomp.h"

static struct nos_server g_server;

static void handle_sigterm(int sig) {
    (void)sig;
    wl_display_terminate(g_server.wl_display);
}

int main(int argc, char *argv[]) {
    wlr_log_init(WLR_DEBUG, NULL);

    const char *startup_cmd = NULL;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--startup") && i + 1 < argc) {
            startup_cmd = argv[++i];
        } else if (!strcmp(argv[i], "--help")) {
            fprintf(stdout,
                "noscomp — Nosface Wayland compositor\n"
                "Usage: noscomp [--startup CMD]\n");
            return 0;
        }
    }

    signal(SIGTERM, handle_sigterm);
    signal(SIGINT,  handle_sigterm);

    server_init(&g_server);

    /* Advertise the socket */
    const char *socket = wl_display_add_socket_auto(g_server.wl_display);
    if (!socket) {
        wlr_log(WLR_ERROR, "Unable to open Wayland socket");
        server_finish(&g_server);
        return 1;
    }

    if (!wlr_backend_start(g_server.backend)) {
        wlr_log(WLR_ERROR, "Failed to start backend");
        server_finish(&g_server);
        return 1;
    }

    setenv("WAYLAND_DISPLAY", socket, true);
    setenv("XDG_SESSION_TYPE", "wayland", true);
    wlr_log(WLR_INFO, "Wayland compositor running on WAYLAND_DISPLAY=%s", socket);

    if (startup_cmd) {
        if (fork() == 0) {
            execl("/bin/sh", "/bin/sh", "-c", startup_cmd, NULL);
            _exit(1);
        }
    }

    server_run(&g_server);
    server_finish(&g_server);
    return 0;
}
