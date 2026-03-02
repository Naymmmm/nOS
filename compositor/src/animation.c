/* noscomp/src/animation.c — window open/close/move animations */

#include <math.h>
#include <time.h>
#include "noscomp.h"

#define ANIM_DURATION 0.2f   /* 200 ms */

/* Smooth-step easing */
static float ease(float t) {
    if (t <= 0.0f) return 0.0f;
    if (t >= 1.0f) return 1.0f;
    return t * t * (3.0f - 2.0f * t);
}

static float now_seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (float)ts.tv_sec + (float)ts.tv_nsec * 1e-9f;
}

void anim_start_open(struct nos_view *view) {
    nos_anim *a   = &view->anim;
    a->type        = ANIM_OPEN;
    a->progress    = 0.0f;
    a->duration    = ANIM_DURATION;
    a->start_scale = 0.85f;
    a->end_scale   = 1.0f;
    a->start_alpha = 0.0f;
    a->end_alpha   = 1.0f;
}

void anim_start_close(struct nos_view *view) {
    nos_anim *a   = &view->anim;
    a->type        = ANIM_CLOSE;
    a->progress    = 0.0f;
    a->duration    = ANIM_DURATION;
    a->start_scale = 1.0f;
    a->end_scale   = 0.85f;
    a->start_alpha = 1.0f;
    a->end_alpha   = 0.0f;
}

void anim_tick(struct nos_view *view, float dt) {
    nos_anim *a = &view->anim;
    if (a->type == ANIM_NONE) return;

    a->progress += dt / a->duration;
    if (a->progress >= 1.0f) {
        a->progress = 1.0f;
        a->type     = ANIM_NONE;
    }

    float t     = ease(a->progress);
    float scale = a->start_scale + t * (a->end_scale - a->start_scale);
    float alpha = a->start_alpha + t * (a->end_alpha - a->start_alpha);

    /* Apply scale via scene node transform (wlr_scene_node_set_transform
       available in wlroots ≥ 0.17). Alpha via wlr_scene_node opacity. */
    (void)scale; /* Would call wlr_scene_buffer_set_opacity / transform */
    (void)alpha;
}

int anim_done(struct nos_view *view) {
    return view->anim.type == ANIM_NONE;
}
