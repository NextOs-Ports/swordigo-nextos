/*
 * Resolve GLES1 only after SDL owns a live context.
 *
 * Some KMSDRM firmware stacks cannot expose their device-enumeration entry
 * points when libEGL/libGLES are loaded as startup dependencies.  SDL is the
 * lifecycle owner here, so keep the loader free of those DT_NEEDED entries and
 * resolve the exact GLES calls after SDL_GL_CreateContext succeeds.
 */
#define _GNU_SOURCE
#include <SDL2/SDL.h>
#define EGLAPI extern __attribute__((visibility("hidden")))
#define GL_API extern __attribute__((visibility("hidden")))
#include <EGL/egl.h>
#include <GLES/gl.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

#define HIDDEN __attribute__((visibility("hidden")))

static void *gl_symbol(const char *name) {
  void *symbol = SDL_GL_GetProcAddress(name);
  if (!symbol) {
    fprintf(stderr, "FATAL ERROR: GLES entry point missing: %s\n", name);
    abort();
  }
  return symbol;
}

#define GL_VOID0(name)                                                        \
  HIDDEN void name(void) {                                                    \
    typedef void (*Fn)(void);                                                 \
    static Fn fn;                                                             \
    if (!fn) fn = (Fn)gl_symbol(#name);                                       \
    fn();                                                                     \
  }
#define GL_VOID1(name, T1, A1)                                                \
  HIDDEN void name(T1 A1) {                                                   \
    typedef void (*Fn)(T1);                                                   \
    static Fn fn;                                                             \
    if (!fn) fn = (Fn)gl_symbol(#name);                                       \
    fn(A1);                                                                   \
  }
#define GL_VOID2(name, T1, A1, T2, A2)                                       \
  HIDDEN void name(T1 A1, T2 A2) {                                            \
    typedef void (*Fn)(T1, T2);                                               \
    static Fn fn;                                                             \
    if (!fn) fn = (Fn)gl_symbol(#name);                                       \
    fn(A1, A2);                                                               \
  }
#define GL_VOID3(name, T1, A1, T2, A2, T3, A3)                               \
  HIDDEN void name(T1 A1, T2 A2, T3 A3) {                                     \
    typedef void (*Fn)(T1, T2, T3);                                           \
    static Fn fn;                                                             \
    if (!fn) fn = (Fn)gl_symbol(#name);                                       \
    fn(A1, A2, A3);                                                           \
  }
#define GL_VOID4(name, T1, A1, T2, A2, T3, A3, T4, A4)                       \
  HIDDEN void name(T1 A1, T2 A2, T3 A3, T4 A4) {                              \
    typedef void (*Fn)(T1, T2, T3, T4);                                       \
    static Fn fn;                                                             \
    if (!fn) fn = (Fn)gl_symbol(#name);                                       \
    fn(A1, A2, A3, A4);                                                       \
  }

GL_VOID1(glActiveTexture, GLenum, texture)
GL_VOID2(glBindBuffer, GLenum, target, GLuint, buffer)
GL_VOID2(glBindTexture, GLenum, target, GLuint, texture)
GL_VOID2(glBlendFunc, GLenum, sfactor, GLenum, dfactor)
GL_VOID4(glBufferData, GLenum, target, GLsizeiptr, size, const void *, data,
         GLenum, usage)
GL_VOID4(glBufferSubData, GLenum, target, GLintptr, offset, GLsizeiptr, size,
         const void *, data)
GL_VOID1(glClear, GLbitfield, mask)
GL_VOID4(glClearColor, GLclampf, red, GLclampf, green, GLclampf, blue, GLclampf,
         alpha)
GL_VOID1(glClearDepthf, GLclampf, depth)
GL_VOID1(glClearStencil, GLint, s)
GL_VOID4(glColor4f, GLfloat, red, GLfloat, green, GLfloat, blue, GLfloat, alpha)
GL_VOID4(glColor4ub, GLubyte, red, GLubyte, green, GLubyte, blue, GLubyte,
         alpha)
GL_VOID4(glColorMask, GLboolean, red, GLboolean, green, GLboolean, blue,
         GLboolean, alpha)
GL_VOID4(glColorPointer, GLint, size, GLenum, type, GLsizei, stride,
         const void *, pointer)

HIDDEN void glCompressedTexImage2D(GLenum target, GLint level,
                                   GLenum internalformat, GLsizei width,
                                   GLsizei height, GLint border,
                                   GLsizei image_size, const void *data) {
  typedef void (*Fn)(GLenum, GLint, GLenum, GLsizei, GLsizei, GLint, GLsizei,
                     const void *);
  static Fn fn;
  if (!fn) fn = (Fn)gl_symbol("glCompressedTexImage2D");
  fn(target, level, internalformat, width, height, border, image_size, data);
}

GL_VOID1(glCullFace, GLenum, mode)
GL_VOID2(glDeleteBuffers, GLsizei, count, const GLuint *, buffers)
GL_VOID2(glDeleteTextures, GLsizei, count, const GLuint *, textures)
GL_VOID1(glDepthFunc, GLenum, func)
GL_VOID1(glDepthMask, GLboolean, flag)
GL_VOID1(glDisable, GLenum, cap)
GL_VOID1(glDisableClientState, GLenum, array)
GL_VOID3(glDrawArrays, GLenum, mode, GLint, first, GLsizei, count)
GL_VOID4(glDrawElements, GLenum, mode, GLsizei, count, GLenum, type,
         const void *, indices)
GL_VOID1(glEnable, GLenum, cap)
GL_VOID1(glEnableClientState, GLenum, array)
GL_VOID0(glFinish)
GL_VOID0(glFlush)
GL_VOID2(glGenBuffers, GLsizei, count, GLuint *, buffers)
GL_VOID2(glGenTextures, GLsizei, count, GLuint *, textures)
GL_VOID2(glGetBooleanv, GLenum, pname, GLboolean *, params)

HIDDEN GLenum glGetError(void) {
  typedef GLenum (*Fn)(void);
  static Fn fn;
  if (!fn) fn = (Fn)gl_symbol("glGetError");
  return fn();
}

GL_VOID2(glGetFloatv, GLenum, pname, GLfloat *, params)
GL_VOID2(glGetIntegerv, GLenum, pname, GLint *, params)

HIDDEN const GLubyte *glGetString(GLenum name) {
  typedef const GLubyte *(*Fn)(GLenum);
  static Fn fn;
  if (!fn) fn = (Fn)gl_symbol("glGetString");
  return fn(name);
}

HIDDEN GLboolean glIsEnabled(GLenum cap) {
  typedef GLboolean (*Fn)(GLenum);
  static Fn fn;
  if (!fn) fn = (Fn)gl_symbol("glIsEnabled");
  return fn(cap);
}

GL_VOID3(glLightf, GLenum, light, GLenum, pname, GLfloat, param)
GL_VOID3(glLightfv, GLenum, light, GLenum, pname, const GLfloat *, params)
GL_VOID2(glLightModelfv, GLenum, pname, const GLfloat *, params)
GL_VOID0(glLoadIdentity)
GL_VOID1(glLoadMatrixf, const GLfloat *, matrix)
GL_VOID3(glMaterialfv, GLenum, face, GLenum, pname, const GLfloat *, params)
GL_VOID1(glMatrixMode, GLenum, mode)
GL_VOID3(glNormalPointer, GLenum, type, GLsizei, stride, const void *, pointer)

HIDDEN void glOrthof(GLfloat left, GLfloat right, GLfloat bottom, GLfloat top,
                     GLfloat near_value, GLfloat far_value) {
  typedef void (*Fn)(GLfloat, GLfloat, GLfloat, GLfloat, GLfloat, GLfloat);
  static Fn fn;
  if (!fn) fn = (Fn)gl_symbol("glOrthof");
  fn(left, right, bottom, top, near_value, far_value);
}

GL_VOID2(glPixelStorei, GLenum, pname, GLint, param)
GL_VOID0(glPopMatrix)
GL_VOID0(glPushMatrix)

HIDDEN void glReadPixels(GLint x, GLint y, GLsizei width, GLsizei height,
                         GLenum format, GLenum type, void *pixels) {
  typedef void (*Fn)(GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void *);
  static Fn fn;
  if (!fn) fn = (Fn)gl_symbol("glReadPixels");
  fn(x, y, width, height, format, type, pixels);
}

GL_VOID3(glScalef, GLfloat, x, GLfloat, y, GLfloat, z)
GL_VOID4(glScissor, GLint, x, GLint, y, GLsizei, width, GLsizei, height)
GL_VOID3(glStencilFunc, GLenum, func, GLint, ref, GLuint, mask)
GL_VOID3(glStencilOp, GLenum, sfail, GLenum, dpfail, GLenum, dppass)
GL_VOID4(glTexCoordPointer, GLint, size, GLenum, type, GLsizei, stride,
         const void *, pointer)
GL_VOID3(glTexEnvfv, GLenum, target, GLenum, pname, const GLfloat *, params)
GL_VOID3(glTexEnvi, GLenum, target, GLenum, pname, GLint, param)

HIDDEN void glTexImage2D(GLenum target, GLint level, GLint internalformat,
                         GLsizei width, GLsizei height, GLint border,
                         GLenum format, GLenum type, const void *pixels) {
  typedef void (*Fn)(GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum,
                     GLenum, const void *);
  static Fn fn;
  if (!fn) fn = (Fn)gl_symbol("glTexImage2D");
  fn(target, level, internalformat, width, height, border, format, type, pixels);
}

GL_VOID3(glTexParameterf, GLenum, target, GLenum, pname, GLfloat, param)
GL_VOID3(glTexParameteri, GLenum, target, GLenum, pname, GLint, param)
GL_VOID3(glTranslatef, GLfloat, x, GLfloat, y, GLfloat, z)
GL_VOID4(glVertexPointer, GLint, size, GLenum, type, GLsizei, stride,
         const void *, pointer)
GL_VOID4(glViewport, GLint, x, GLint, y, GLsizei, width, GLsizei, height)

HIDDEN __eglMustCastToProperFunctionPointerType
eglGetProcAddress(const char *name) {
  void *symbol = SDL_GL_GetProcAddress(name);
  if (symbol)
    return (__eglMustCastToProperFunctionPointerType)symbol;

  static void *egl;
  static __eglMustCastToProperFunctionPointerType (*real_get_proc)(
      const char *);
  if (!egl)
    egl = dlopen("libEGL.so.1", RTLD_NOW | RTLD_LOCAL);
  if (egl && !real_get_proc)
    real_get_proc = (__eglMustCastToProperFunctionPointerType (*)(const char *))
        dlsym(egl, "eglGetProcAddress");
  return real_get_proc ? real_get_proc(name) : NULL;
}
