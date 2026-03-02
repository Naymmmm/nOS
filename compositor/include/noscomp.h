#ifndef NOSCOMP_H
#define NOSCOMP_H

#define WLR_USE_UNSTABLE

#include <wayland-server-core.h>
#include <wlr/backend.h>
#include <wlr/render/allocator.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_data_device.h>
#include <wlr/types/wlr_input_device.h>
#include <wlr/types/wlr_keyboard.h>
#include <wlr/types/wlr_layer_shell_v1.h>
#include <wlr/types/wlr_output.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_pointer.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_subcompositor.h>
#include <wlr/types/wlr_xcursor_manager.h>
#include <wlr/types/wlr_xdg_decoration_v1.h>
#include <wlr/types/wlr_xdg_output_v1.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/util/log.h>
#include <xkbcommon/xkbcommon.h>

/* ---- Colour palette (dark theme defaults, overridden at runtime) ---- */
#define NOS_BG_R       0.031f
#define NOS_BG_G       0.031f
#define NOS_BG_B       0.102f

#define NOS_BORDER_R   0.392f
#define NOS_BORDER_G   0.549f
#define NOS_BORDER_B   1.000f
#define NOS_BORDER_A   0.220f

#define NOS_GLOW_R     0.302f
#define NOS_GLOW_G     0.545f
#define NOS_GLOW_B     1.000f
#define NOS_GLOW_A     0.450f

#define NOS_CORNER_RADIUS  12
#define NOS_SHADOW_RADIUS  24
#define NOS_BORDER_WIDTH    1

/* ---- Forward declarations ---- */
struct nos_server;
struct nos_output;
struct nos_view;
struct nos_keyboard;

/* ---- Animation state ---- */
typedef enum {
    ANIM_NONE = 0,
    ANIM_OPEN,
    ANIM_CLOSE,
    ANIM_MOVE,
    ANIM_WORKSPACE_SLIDE,
} nos_anim_type;

typedef struct nos_anim {
    nos_anim_type type;
    float         progress;   /* 0.0 → 1.0 */
    float         duration;   /* seconds    */
    int           start_x, start_y;
    int           end_x,   end_y;
    float         start_scale, end_scale;
    float         start_alpha, end_alpha;
    struct wl_event_source *timer;
} nos_anim;

/* ---- Wobble physics ---- */
typedef struct nos_wobble {
    float vel_x, vel_y;
    float spring_k;
    float damping;
    int   active;
} nos_wobble;

/* ---- View (toplevel window) ---- */
struct nos_view {
    struct wl_list             link;
    struct nos_server         *server;
    struct wlr_xdg_toplevel   *xdg_toplevel;
    struct wlr_scene_tree     *scene_tree;

    struct wl_listener  map;
    struct wl_listener  unmap;
    struct wl_listener  destroy;
    struct wl_listener  request_move;
    struct wl_listener  request_resize;
    struct wl_listener  request_maximize;
    struct wl_listener  request_fullscreen;

    int x, y;
    nos_anim   anim;
    nos_wobble wobble;
};

/* ---- Keyboard ---- */
struct nos_keyboard {
    struct wl_list           link;
    struct nos_server       *server;
    struct wlr_keyboard     *wlr_keyboard;
    struct wl_listener       modifiers;
    struct wl_listener       key;
    struct wl_listener       destroy;
};

/* ---- Output ---- */
struct nos_output {
    struct wl_list          link;
    struct nos_server      *server;
    struct wlr_output      *wlr_output;
    struct wlr_scene_output *scene_output;
    struct wl_listener      frame;
    struct wl_listener      request_state;
    struct wl_listener      destroy;
    /* blur framebuffer */
    unsigned int            blur_fbo[2];
    unsigned int            blur_tex[2];
    int                     blur_w, blur_h;
};

/* ---- Main server ---- */
struct nos_server {
    struct wl_display          *wl_display;
    struct wlr_backend         *backend;
    struct wlr_renderer        *renderer;
    struct wlr_allocator       *allocator;
    struct wlr_scene           *scene;
    struct wlr_scene_output_layout *scene_layout;

    struct wlr_xdg_shell       *xdg_shell;
    struct wl_listener          new_xdg_toplevel;
    struct wl_listener          new_xdg_popup;

    struct wlr_layer_shell_v1  *layer_shell;
    struct wl_listener          new_layer_surface;

    struct wlr_cursor          *cursor;
    struct wlr_xcursor_manager *cursor_mgr;
    struct wl_listener          cursor_motion;
    struct wl_listener          cursor_motion_absolute;
    struct wl_listener          cursor_button;
    struct wl_listener          cursor_axis;
    struct wl_listener          cursor_frame;

    struct wlr_seat            *seat;
    struct wl_listener          new_input;
    struct wl_listener          request_cursor;
    struct wl_listener          request_set_selection;

    struct wlr_output_layout   *output_layout;
    struct wl_list              outputs;
    struct wl_listener          new_output;

    struct wl_list              views;
    struct wl_list              keyboards;

    struct nos_view            *grabbed_view;
    double                      grab_x, grab_y;
    struct wlr_box              grab_geobox;
    uint32_t                    resize_edges;

    /* current workspace (0-indexed) */
    int                         workspace;
    int                         workspace_count;
};

/* ---- Function prototypes ---- */

/* server.c */
void server_init(struct nos_server *server);
void server_run(struct nos_server *server);
void server_finish(struct nos_server *server);

/* output.c */
void output_init(struct nos_server *server);

/* xdg_shell.c */
void xdg_shell_init(struct nos_server *server);

/* layer_shell.c */
void layer_shell_init(struct nos_server *server);
struct nos_view *view_at(struct nos_server *server, double lx, double ly,
                         struct wlr_surface **surface, double *sx, double *sy);
void focus_view(struct nos_view *view, struct wlr_surface *surface);

/* input.c */
void input_init(struct nos_server *server);

/* blur.c */
void blur_init_output(struct nos_output *output);
void blur_pass(struct nos_output *output, int passes);
void blur_finish_output(struct nos_output *output);

/* animation.c */
void anim_start_open(struct nos_view *view);
void anim_start_close(struct nos_view *view);
void anim_tick(struct nos_view *view, float dt);
int  anim_done(struct nos_view *view);

/* wobble.c */
void wobble_init(struct nos_wobble *w);
void wobble_impulse(struct nos_wobble *w, float vx, float vy);
void wobble_tick(struct nos_wobble *w, float dt);

/* decoration.c */
void decoration_init(struct nos_server *server);
void decoration_render_view(struct nos_view *view);

#endif /* NOSCOMP_H */
