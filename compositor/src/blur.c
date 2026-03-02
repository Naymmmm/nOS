/* noscomp/src/blur.c — Kawase multi-pass OpenGL blur */
#define WLR_USE_UNSTABLE

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <wlr/util/log.h>

#include "noscomp.h"

/* ---- GLSL shaders ---- */

static const char *VERT_SRC =
    "attribute vec2 position;\n"
    "attribute vec2 texcoord;\n"
    "varying vec2 v_texcoord;\n"
    "void main() {\n"
    "    gl_Position = vec4(position, 0.0, 1.0);\n"
    "    v_texcoord  = texcoord;\n"
    "}\n";

/* Kawase downsample/upsample — offset controls kernel spread */
static const char *KAWASE_FRAG_SRC =
    "precision mediump float;\n"
    "uniform sampler2D tex;\n"
    "uniform vec2      halfpixel;\n"
    "uniform float     offset;\n"
    "varying vec2 v_texcoord;\n"
    "void main() {\n"
    "    vec2 uv = v_texcoord;\n"
    "    vec4 sum = texture2D(tex, uv + vec2(-halfpixel.x * 2.0, 0.0) * offset);\n"
    "    sum     += texture2D(tex, uv + vec2(-halfpixel.x, halfpixel.y)  * offset) * 2.0;\n"
    "    sum     += texture2D(tex, uv + vec2(0.0, halfpixel.y * 2.0) * offset);\n"
    "    sum     += texture2D(tex, uv + vec2(halfpixel.x, halfpixel.y)   * offset) * 2.0;\n"
    "    sum     += texture2D(tex, uv + vec2(halfpixel.x * 2.0, 0.0) * offset);\n"
    "    sum     += texture2D(tex, uv + vec2(halfpixel.x, -halfpixel.y)  * offset) * 2.0;\n"
    "    sum     += texture2D(tex, uv + vec2(0.0, -halfpixel.y * 2.0) * offset);\n"
    "    sum     += texture2D(tex, uv + vec2(-halfpixel.x, -halfpixel.y) * offset) * 2.0;\n"
    "    gl_FragColor = sum / 12.0;\n"
    "}\n";

static GLuint compile_shader(GLenum type, const char *src) {
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, NULL);
    glCompileShader(s);
    GLint ok; glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char buf[512];
        glGetShaderInfoLog(s, sizeof(buf), NULL, buf);
        wlr_log(WLR_ERROR, "Shader compile error: %s", buf);
    }
    return s;
}

static GLuint build_program(const char *vert, const char *frag) {
    GLuint vs = compile_shader(GL_VERTEX_SHADER, vert);
    GLuint fs = compile_shader(GL_FRAGMENT_SHADER, frag);
    GLuint p  = glCreateProgram();
    glAttachShader(p, vs);
    glAttachShader(p, fs);
    glLinkProgram(p);
    glDeleteShader(vs);
    glDeleteShader(fs);
    return p;
}

/* Per-output blur state stored in nos_output.blur_* fields.
   We also keep the program as a static singleton. */
static GLuint s_blur_prog = 0;
static GLint  s_loc_tex, s_loc_halfpixel, s_loc_offset;
static GLuint s_quad_vbo;

static const GLfloat QUAD[] = {
    /* pos      uv  */
    -1,-1,  0,0,
     1,-1,  1,0,
    -1, 1,  0,1,
     1, 1,  1,1,
};

static void ensure_blur_prog(void) {
    if (s_blur_prog) return;
    s_blur_prog    = build_program(VERT_SRC, KAWASE_FRAG_SRC);
    s_loc_tex      = glGetUniformLocation(s_blur_prog, "tex");
    s_loc_halfpixel= glGetUniformLocation(s_blur_prog, "halfpixel");
    s_loc_offset   = glGetUniformLocation(s_blur_prog, "offset");

    glGenBuffers(1, &s_quad_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, s_quad_vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(QUAD), QUAD, GL_STATIC_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

void blur_init_output(struct nos_output *output) {
    ensure_blur_prog();

    int w = output->wlr_output->width;
    int h = output->wlr_output->height;
    if (w == 0 || h == 0) { w = 1920; h = 1080; }
    output->blur_w = w / 2;
    output->blur_h = h / 2;

    glGenFramebuffers(2, output->blur_fbo);
    glGenTextures(2,    output->blur_tex);

    for (int i = 0; i < 2; i++) {
        glBindTexture(GL_TEXTURE_2D, output->blur_tex[i]);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA,
            output->blur_w, output->blur_h, 0,
            GL_RGBA, GL_UNSIGNED_BYTE, NULL);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

        glBindFramebuffer(GL_FRAMEBUFFER, output->blur_fbo[i]);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
            GL_TEXTURE_2D, output->blur_tex[i], 0);
    }
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glBindTexture(GL_TEXTURE_2D, 0);
}

void blur_finish_output(struct nos_output *output) {
    glDeleteFramebuffers(2, output->blur_fbo);
    glDeleteTextures(2,    output->blur_tex);
    memset(output->blur_fbo, 0, sizeof(output->blur_fbo));
    memset(output->blur_tex, 0, sizeof(output->blur_tex));
}

static void draw_quad(void) {
    glBindBuffer(GL_ARRAY_BUFFER, s_quad_vbo);
    GLint pos_loc = 0, uv_loc = 1;
    glEnableVertexAttribArray(pos_loc);
    glEnableVertexAttribArray(uv_loc);
    glVertexAttribPointer(pos_loc, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), (void*)0);
    glVertexAttribPointer(uv_loc,  2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), (void*)(2*sizeof(GLfloat)));
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glDisableVertexAttribArray(pos_loc);
    glDisableVertexAttribArray(uv_loc);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

void blur_pass(struct nos_output *output, int passes) {
    if (!output->blur_fbo[0] || !s_blur_prog) return;
    if (passes < 1) passes = 1;
    if (passes > 8) passes = 8;

    glUseProgram(s_blur_prog);
    glViewport(0, 0, output->blur_w, output->blur_h);

    int src = 0, dst = 1;
    for (int i = 0; i < passes * 2; i++) {
        glBindFramebuffer(GL_FRAMEBUFFER, output->blur_fbo[dst]);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, output->blur_tex[src]);
        glUniform1i(s_loc_tex, 0);
        float hp_x = 0.5f / (float)output->blur_w;
        float hp_y = 0.5f / (float)output->blur_h;
        glUniform2f(s_loc_halfpixel, hp_x, hp_y);
        float offset = (i < passes) ? (float)(i + 1) : (float)(passes * 2 - i);
        glUniform1f(s_loc_offset, offset);
        draw_quad();
        int tmp = src; src = dst; dst = tmp;
    }
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glUseProgram(0);
}
