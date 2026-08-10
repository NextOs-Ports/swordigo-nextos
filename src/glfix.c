/* glfix.c — GL provider repair by observed capability (no device names).
 *
 * Field evidence (dArkOS4Clone/G350, DarkOsRE R36S, dArkOSen): the firmware's
 * versioned SONAMEs are crossed — libGLESv1_CM.so.1 / libEGL.so.1 resolve to
 * Mesa builds with no driver behind them while the real Mali blob sits behind
 * the unversioned names (libGLESv1_CM.so -> libMali.so).  The binary binds by
 * SONAME, so it gets a context that accepts every call and draws nothing:
 * glGetString(GL_RENDERER) comes back NULL, audio and input keep running and
 * the panel stays black.
 *
 * The one safe, observable condition is the empty renderer string measured on
 * the real context.  A healthy Mesa (Panfrost on ROCKNIX) reports a proper
 * renderer and is left completely alone.  When the condition holds and a Mali
 * blob exporting the GLES1 entry points exists, the fix re-executes the same
 * binary with LD_PRELOAD pointing at the blob: preloaded objects take over
 * symbol resolution ahead of the crossed SONAMEs.  LD_LIBRARY_PATH cannot do
 * this (the SONAME chain wins) — proven in the field before this fix.
 *
 * Controls:
 *   SWORDIGO_GLFIX=0            disable entirely.
 *   SWORDIGO_GLFIX_BLOB=/path   force a specific provider object.
 * A marker env var stops any re-exec loop after one attempt.
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <dlfcn.h>
#include <fnmatch.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "glfix.h"
#include "util.h"

#define GLFIX_MARKER "SWORDIGO_GLFIX_APPLIED"

static char **g_saved_argv;

void glfix_set_argv(char **argv) { g_saved_argv = argv; }

/* Blob variants that never drive a KMSDRM panel: the dummy/stub blobs accept
 * every call and draw nothing (a second black screen, silently), and the
 * x11/wayland variants target a windowing system this fleet does not run. */
static int glfix_variant_rejected(const char *name) {
  return strstr(name, "dummy") || strstr(name, "stub") ||
         strstr(name, "x11") || strstr(name, "wayland");
}

/* A usable provider must export the GLES1 entry points this game calls and
 * its own EGL.  dlsym proves it instead of trusting the file name. */
static int glfix_blob_usable(const char *path) {
  void *handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL);
  if (!handle) {
    debugPrintf("glfix: %s rejected (dlopen: %s)\n", path, dlerror());
    return 0;
  }
  int ok = dlsym(handle, "glOrthof") != NULL &&
           dlsym(handle, "eglGetDisplay") != NULL;
  dlclose(handle);
  if (!ok)
    debugPrintf("glfix: %s rejected (no glOrthof/eglGetDisplay)\n", path);
  return ok;
}

/* Deliberate pattern order: the -gbm variant matches SDL's KMSDRM backend and
 * must win over an alphabetical scan (which would find -dummy first). */
static const char *const glfix_patterns[] = {
    "libmali*-gbm.so*",  "libmali-bifrost-*.so*", "libmali-midgard-*.so*",
    "libmali.so*",       "libMali.so*",           "libGLES_mali.so*",
};
static const char *const glfix_dirs[] = {
    "/usr/lib/aarch64-linux-gnu", "/lib/aarch64-linux-gnu",
    "/usr/lib64", "/usr/lib", "/lib",
};

static int glfix_find_blob(char *out, size_t out_size) {
  const char *forced = getenv("SWORDIGO_GLFIX_BLOB");
  if (forced && *forced) {
    if (access(forced, R_OK) == 0 && glfix_blob_usable(forced)) {
      snprintf(out, out_size, "%s", forced);
      return 1;
    }
    debugPrintf("glfix: forced blob unusable: %s\n", forced);
    return 0;
  }
  for (size_t p = 0; p < sizeof(glfix_patterns) / sizeof(glfix_patterns[0]);
       p++) {
    for (size_t d = 0; d < sizeof(glfix_dirs) / sizeof(glfix_dirs[0]); d++) {
      DIR *dir = opendir(glfix_dirs[d]);
      if (!dir)
        continue;
      struct dirent *entry;
      while ((entry = readdir(dir)) != NULL) {
        if (fnmatch(glfix_patterns[p], entry->d_name, 0) != 0)
          continue;
        if (glfix_variant_rejected(entry->d_name)) {
          debugPrintf("glfix: %s/%s skipped (variant unfit for KMSDRM)\n",
                      glfix_dirs[d], entry->d_name);
          continue;
        }
        char candidate[1024];
        snprintf(candidate, sizeof(candidate), "%s/%s", glfix_dirs[d],
                 entry->d_name);
        if (glfix_blob_usable(candidate)) {
          snprintf(out, out_size, "%s", candidate);
          closedir(dir);
          return 1;
        }
      }
      closedir(dir);
    }
  }
  return 0;
}

int glfix_renderer_is_broken(const char *renderer) {
  return renderer == NULL || renderer[0] == '\0';
}

/* Called once, right after the real context reported its renderer string.
 * Returns only when no repair applies; on repair it re-execs the process. */
void glfix_maybe_reexec(const char *renderer, void (*teardown)(void)) {
  const char *mode = getenv("SWORDIGO_GLFIX");
  if (mode && mode[0] == '0') {
    debugPrintf("glfix: disabled by SWORDIGO_GLFIX=0\n");
    return;
  }
  if (!glfix_renderer_is_broken(renderer))
    return;
  if (getenv(GLFIX_MARKER)) {
    debugPrintf("glfix: renderer still empty after preload; giving up\n");
    return;
  }
  char blob[1024];
  if (!glfix_find_blob(blob, sizeof(blob))) {
    debugPrintf("glfix: empty renderer but no usable Mali blob found\n");
    return;
  }
  const char *previous = getenv("LD_PRELOAD");
  char preload[2048];
  if (previous && *previous)
    snprintf(preload, sizeof(preload), "%s:%s", blob, previous);
  else
    snprintf(preload, sizeof(preload), "%s", blob);
  debugPrintf("glfix: empty renderer on the crossed-SONAME stack; "
              "re-executing with LD_PRELOAD=%s\n", preload);
  if (teardown)
    teardown();
  setenv("LD_PRELOAD", preload, 1);
  setenv(GLFIX_MARKER, "1", 1);
  if (g_saved_argv)
    execv("/proc/self/exe", g_saved_argv);
  debugPrintf("glfix: execv failed; continuing without repair\n");
}
