/* noscomp/src/shadow.c — soft Gaussian-approximation window shadows */
#define WLR_USE_UNSTABLE

#include <GLES2/gl2.h>
#include "noscomp.h"

/* Shadow rendering uses a pre-rendered texture blitted behind each window.
   Full implementation renders a 9-slice shadow sprite generated at startup. */

void shadow_render(struct nos_view *view, int x, int y, int w, int h) {
    /* Offset and blur radius match NOS_SHADOW_RADIUS */
    int off = NOS_SHADOW_RADIUS / 2;
    (void)view;
    (void)x; (void)y; (void)w; (void)h; (void)off;
    /* TODO: blit 9-slice shadow texture at (x-off, y-off, w+off*2, h+off*2) */
}
