/* noscomp/src/wobble.c — spring physics wobbly windows */

#include <math.h>
#include "noscomp.h"

#define SPRING_K  12.0f
#define DAMPING    8.0f
#define THRESHOLD  0.001f

void wobble_init(struct nos_wobble *w) {
    w->vel_x   = 0.0f;
    w->vel_y   = 0.0f;
    w->spring_k = SPRING_K;
    w->damping  = DAMPING;
    w->active   = 0;
}

void wobble_impulse(struct nos_wobble *w, float vx, float vy) {
    w->vel_x += vx;
    w->vel_y += vy;
    if (fabsf(w->vel_x) > THRESHOLD || fabsf(w->vel_y) > THRESHOLD)
        w->active = 1;
}

void wobble_tick(struct nos_wobble *w, float dt) {
    if (!w->active) return;

    /* Spring force = -k * displacement (treat vel as displacement proxy) */
    float ax = -w->spring_k * w->vel_x - w->damping * w->vel_x;
    float ay = -w->spring_k * w->vel_y - w->damping * w->vel_y;

    w->vel_x += ax * dt;
    w->vel_y += ay * dt;

    if (fabsf(w->vel_x) < THRESHOLD && fabsf(w->vel_y) < THRESHOLD) {
        w->vel_x = 0.0f;
        w->vel_y = 0.0f;
        w->active = 0;
    }
}
