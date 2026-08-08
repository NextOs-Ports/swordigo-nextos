/*
 * main.c — Swordigo 1.4.12 so-loader for NextOS (Mali-450, aarch64)
 *
 * Thin Android shell replica: GLES1.1 + OpenAL + AAsset + MusicPlayer JNI,
 * pad→touch / FWKeyboard. Blueprint: NaGaa95 swordigo_nx (same APK build).
 */
#define _GNU_SOURCE
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include <GLES/gl.h>
#include <SDL2/SDL.h>

#include "error.h"
#include "imports.h"
#include "jni_fake.h"
#include "music_player.h"
#include "so_util.h"
#include "util.h"

#define MEMORY_MB 384
#define SO_NAME "libswordigo.so"
#define REFERENCE_VIEW_W 1280.0f
#define REFERENCE_VIEW_H 720.0f

/* Bionic reads the stack canary from TLS_SLOT_STACK_GUARD (tpidr_el0 + 0x28),
 * a slot glibc does not reserve, so on some firmwares a freshly created thread
 * finds a different value there than the one the function prologue stored and
 * the game aborts with "stack smashing detected".  A used, 16-byte aligned,
 * never-written thread-local pad anchors the first TLS block right after the
 * 16-byte TCB, which keeps the whole Bionic guard slot stable on every thread.
 * Same audited fix as the proven Bully and Prizefighters 2 runtimes. */
__attribute__((aligned(16), used))
_Thread_local char g_bionic_guard_pad[256] = { 1 };

int screen_width = 1280;
int screen_height = 720;

static char data_path[512];
static SDL_Window *g_win;
static SDL_GLContext g_ctx;
static volatile int g_running = 1;
static double g_time;

/* ---- overlay hide (pad used) — same symbols/offsets as swordigo_nx 1.4.12 ---- */
#define GAME_OVERLAY_INIT_SYMBOL \
  "_ZN5Caver15GameOverlayView17InitWithGameStateERKN5boost10shared_ptrINS_9GameStateEEE"
#define GAME_OVERLAY_DESTROY_SYMBOL "_ZN5Caver15GameOverlayViewD1Ev"
#define GAME_OVERLAY_VISIBILITY_SYMBOL \
  "_ZN5Caver15GameOverlayView26SetControlButtonsInvisibleEb"
#define OVERLAY_INIT_TRAMPOLINE_OFFSET 0x6af8d8
#define OVERLAY_DESTROY_TRAMPOLINE_OFFSET 0x6af918
#define MAX_GAME_OVERLAYS 8

typedef void (*GameOverlayInitFn)(void *view, const void *state);
typedef void (*GameOverlayDestroyFn)(void *view);
typedef void (*GameOverlayVisibilityFn)(void *view, int hidden);

static GameOverlayInitFn game_overlay_init_original;
static GameOverlayDestroyFn game_overlay_destroy_original;
static GameOverlayVisibilityFn set_game_overlay_invisible;
static void *game_overlays[MAX_GAME_OVERLAYS];
static int touch_controls_hidden;

static uintptr_t install_game_hook(const char *symbol, uintptr_t replacement,
                                   uintptr_t trampoline_offset) {
  uintptr_t target = so_find_addr(symbol);
  if (!target) {
    debugPrintf("overlay hook: missing %s\n", symbol);
    return 0;
  }
  uint32_t *trampoline = (uint32_t *)((uintptr_t)text_base + trampoline_offset);
  memcpy(trampoline, (const void *)target, 16);
  trampoline[4] = 0x58000051u; /* ldr x17, #8 */
  trampoline[5] = 0xd61f0220u; /* br x17 */
  *(uint64_t *)(trampoline + 6) = target + 16;
  hook_arm64(target, replacement);
  return (uintptr_t)trampoline;
}

static void set_touch_controls_hidden(int hidden) {
  touch_controls_hidden = hidden;
  if (!set_game_overlay_invisible)
    return;
  for (int i = 0; i < MAX_GAME_OVERLAYS; i++)
    if (game_overlays[i])
      set_game_overlay_invisible(game_overlays[i], hidden);
}

static void game_overlay_init_hook(void *view, const void *state) {
  game_overlay_init_original(view, state);
  for (int i = 0; i < MAX_GAME_OVERLAYS; i++) {
    if (game_overlays[i] == view) {
      set_game_overlay_invisible(view, touch_controls_hidden);
      return;
    }
    if (!game_overlays[i]) {
      game_overlays[i] = view;
      set_game_overlay_invisible(view, touch_controls_hidden);
      return;
    }
  }
}

static void game_overlay_destroy_hook(void *view) {
  for (int i = 0; i < MAX_GAME_OVERLAYS; i++)
    if (game_overlays[i] == view)
      game_overlays[i] = NULL;
  game_overlay_destroy_original(view);
}

static void install_game_overlay_hooks(void) {
  set_game_overlay_invisible =
      (GameOverlayVisibilityFn)so_find_addr_rx(GAME_OVERLAY_VISIBILITY_SYMBOL);
  so_make_text_writable();
  game_overlay_init_original = (GameOverlayInitFn)install_game_hook(
      GAME_OVERLAY_INIT_SYMBOL, (uintptr_t)game_overlay_init_hook,
      OVERLAY_INIT_TRAMPOLINE_OFFSET);
  game_overlay_destroy_original = (GameOverlayDestroyFn)install_game_hook(
      GAME_OVERLAY_DESTROY_SYMBOL, (uintptr_t)game_overlay_destroy_hook,
      OVERLAY_DESTROY_TRAMPOLINE_OFFSET);
  so_make_text_executable();
  so_flush_caches();
}

/* ---- Native entry points ---- */
static void (*setFilesDir)(void *, void *, void *);
static void (*setCacheDir)(void *, void *, void *);
static void (*setAssetManager)(void *, void *, void *);
static void (*setupNativeInterface)(void *, void *);
static void (*setupApplication)(void *, void *);
static void (*setApplicationViewSize)(void *, void *, int, int, int, int, int);
static void (*handleApplicationLaunch)(void *, void *);
static void (*applicationDidBecomeActive)(void *, void *);
static void (*updateApplication)(void *, void *, float);
static void (*drawApplication)(void *, void *);
static void (*handleTouchEvent)(void *, void *, int, int, double, float, float,
                                float, float, int);
static void (*initMusicPlayer)(void *, void *);
static void (*googleSignInCompleted)(void *, void *, uint8_t);
static void (*handleMenuButtonPress)(void *, void *);
static void (*handleBackButtonPress)(void *, void *);
static void (*textInputTextDidChange)(void *, void *, void *);
static void (*textInputDidFinish)(void *, void *);
static void (*handleApplicationQuit)(void *, void *);

static void *(*sharedKeyboard)(void);
static void (*sendKeyDownEvent)(void *, unsigned, unsigned, double);
static void (*sendKeyUpEvent)(void *, unsigned, unsigned, double);
static void *(*sharedAudioSystem)(void);
static void (*shutdownAudioSystem)(void *);

static void resolve_entry_points(void) {
#define E(var, sym)                                                            \
  var = (void *)so_find_addr_rx("Java_com_touchfoo_swordigo_" sym);            \
  if (!var)                                                                    \
    fatal_error("missing JNI %s", sym)
  E(setFilesDir, "Native_setFilesDir");
  E(setCacheDir, "Native_setCacheDir");
  E(setAssetManager, "Native_setAssetManager");
  E(setupNativeInterface, "Native_setupNativeInterface");
  E(setupApplication, "Native_setupApplication");
  E(setApplicationViewSize, "Native_setApplicationViewSize");
  E(handleApplicationLaunch, "Native_handleApplicationLaunch");
  E(applicationDidBecomeActive, "Native_applicationDidBecomeActive");
  E(updateApplication, "Native_updateApplication");
  E(drawApplication, "Native_drawApplication");
  E(handleTouchEvent, "Native_handleTouchEvent");
  E(initMusicPlayer, "MusicPlayer_initMusicPlayer");
  E(googleSignInCompleted, "Native_googleSignInCompleted");
  E(textInputTextDidChange, "Native_textInputTextDidChange");
  E(textInputDidFinish, "Native_textInputDidFinish");
#undef E
  handleMenuButtonPress =
      (void *)so_find_addr_safe("Java_com_touchfoo_swordigo_Native_handleMenuButtonPress");
  handleBackButtonPress =
      (void *)so_find_addr_safe("Java_com_touchfoo_swordigo_Native_handleBackButtonPress");
  handleApplicationQuit =
      (void *)so_find_addr_safe("Java_com_touchfoo_swordigo_Native_handleApplicationQuit");

  sharedKeyboard =
      (void *)so_find_addr_rx("_ZN5Caver10FWKeyboard14sharedKeyboardEv");
  sendKeyDownEvent =
      (void *)so_find_addr_rx("_ZN5Caver10FWKeyboard16SendKeyDownEventEjjd");
  sendKeyUpEvent =
      (void *)so_find_addr_rx("_ZN5Caver10FWKeyboard14SendKeyUpEventEjjd");
  sharedAudioSystem =
      (void *)so_find_addr_safe("_ZN5Caver11AudioSystem12sharedSystemEv");
  shutdownAudioSystem =
      (void *)so_find_addr_safe("_ZN5Caver11AudioSystem8ShutdownEv");
}

/* ---- input ---- */
enum { KEY_LEFT = 0x25, KEY_UP = 0x26, KEY_RIGHT = 0x27 };
#define A_R 1
#define A_T 2

typedef struct {
  int sdl_btn;
  int id;
  int flags;
  float ax, ay;
} Ctrl;

/* Hitboxes on 1280x720 overlay (swordigo_nx). SDL = Xbox layout:
 * X=attack, B=magic, Y=item, A=jump (keyboard), LB=magic-equip, Start=menu, RB=back */
static const Ctrl button_map[] = {
    {SDL_CONTROLLER_BUTTON_X, 6, A_R, 335.0f, 105.0f},              /* attack */
    {SDL_CONTROLLER_BUTTON_B, 7, A_R, 190.0f, 240.0f},              /* magic */
    {SDL_CONTROLLER_BUTTON_Y, 8, 0, 640.0f, 75.0f},                 /* item */
    {SDL_CONTROLLER_BUTTON_LEFTSHOULDER, 9, A_R | A_T, 150.0f, 65.0f}, /* magic equip */
};

/* Field instrument, off unless SWORDIGO_DEBUG_TAP="ax,ay[,flags]" is set:
 * presses one overlay hitbox every few seconds so an unmapped on-screen button
 * can be identified on the device.  Never used by the shipped launcher. */
static float g_debug_tap_ax = -1.0f, g_debug_tap_ay = -1.0f;
static int g_debug_tap_flags = A_R;

static SDL_GameController *g_pad;
static uint32_t pad_prev;
static int left_prev, right_prev, jump_prev;

enum { TOUCH_BEGAN = 1, TOUCH_ENDED = 2, TOUCH_CANCELLED = 3, TOUCH_MOVED = 4 };
static void emit_touch(int phase, int id, float x, float y);

/* Right-stick cursor (LEGO pattern): view coords, Y bottom-origin like touches. */
static float g_cursor_x = -1.0f, g_cursor_y = -1.0f;
static int g_cursor_show;
static int g_cursor_r3_prev;
static int g_cursor_touch_hold;
static float g_cursor_tx, g_cursor_ty;

static void cursor_ensure(void) {
  if (g_cursor_x < 0.0f) {
    g_cursor_x = (float)screen_width * 0.5f;
    g_cursor_y = (float)screen_height * 0.5f;
  }
}

static void cursor_draw_overlay(void) {
  if (g_cursor_show <= 0 || g_cursor_x < 0.0f)
    return;
  cursor_ensure();
  const float cx = g_cursor_x, cy = g_cursor_y;
  const float W = (float)screen_width, H = (float)screen_height;

  GLboolean was_tex = glIsEnabled(GL_TEXTURE_2D);
  GLboolean was_blend = glIsEnabled(GL_BLEND);
  GLboolean was_depth = glIsEnabled(GL_DEPTH_TEST);
  GLboolean was_cull = glIsEnabled(GL_CULL_FACE);
  GLboolean was_scis = glIsEnabled(GL_SCISSOR_TEST);
  GLboolean was_light = glIsEnabled(GL_LIGHTING);
  GLboolean was_fog = glIsEnabled(GL_FOG);
  GLboolean was_alpha = glIsEnabled(GL_ALPHA_TEST);
  GLboolean was_colmat = glIsEnabled(GL_COLOR_MATERIAL);
  GLint prev_vp[4];
  GLint prev_tex = 0;
  GLboolean depth_mask = GL_TRUE;
  glGetIntegerv(GL_VIEWPORT, prev_vp);
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &prev_tex);
  glGetBooleanv(GL_DEPTH_WRITEMASK, &depth_mask);

  GLboolean was_va = glIsEnabled(GL_VERTEX_ARRAY);
  GLboolean was_ca = glIsEnabled(GL_COLOR_ARRAY);
  GLboolean was_na = glIsEnabled(GL_NORMAL_ARRAY);
  GLboolean was_ta = glIsEnabled(GL_TEXTURE_COORD_ARRAY);

  glMatrixMode(GL_PROJECTION);
  glPushMatrix();
  glLoadIdentity();
  glOrthof(0.0f, W, 0.0f, H, -1.0f, 1.0f);
  glMatrixMode(GL_MODELVIEW);
  glPushMatrix();
  glLoadIdentity();

  glViewport(0, 0, screen_width, screen_height);
  glBindTexture(GL_TEXTURE_2D, 0);
  glDisable(GL_TEXTURE_2D);
  glDisable(GL_DEPTH_TEST);
  glDepthMask(GL_FALSE);
  glDisable(GL_CULL_FACE);
  glDisable(GL_SCISSOR_TEST);
  glDisable(GL_LIGHTING);
  glDisable(GL_FOG);
  glDisable(GL_ALPHA_TEST);
  glDisable(GL_COLOR_MATERIAL);
  glDisableClientState(GL_COLOR_ARRAY);
  glDisableClientState(GL_NORMAL_ARRAY);
  glDisableClientState(GL_TEXTURE_COORD_ARRAY);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);

  /* Tip at cursor; shaft points down-right (ortho Y-up). Outline then white. */
  float base[6][2] = {
      {cx, cy},
      {cx, cy - 26.0f},
      {cx + 18.0f, cy - 18.0f},
      {cx + 6.0f, cy - 17.0f},
      {cx + 11.0f, cy - 28.0f},
      {cx + 15.0f, cy - 26.0f},
  };
  glEnableClientState(GL_VERTEX_ARRAY);
  for (int pass = 0; pass < 2; pass++) {
    float verts[6][2];
    for (int i = 0; i < 6; i++) {
      verts[i][0] = base[i][0];
      verts[i][1] = base[i][1];
    }
    if (pass == 0) {
      for (int i = 1; i < 6; i++) {
        verts[i][0] += (base[i][0] - base[0][0]) * 0.22f;
        verts[i][1] += (base[i][1] - base[0][1]) * 0.22f;
      }
      glColor4f(0.0f, 0.0f, 0.0f, 1.0f);
    } else {
      glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
    }
    glVertexPointer(2, GL_FLOAT, 0, verts);
    glDrawArrays(GL_TRIANGLES, 0, 6);
  }
  if (!was_va)
    glDisableClientState(GL_VERTEX_ARRAY);
  if (was_ca)
    glEnableClientState(GL_COLOR_ARRAY);
  if (was_na)
    glEnableClientState(GL_NORMAL_ARRAY);
  if (was_ta)
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);

  glMatrixMode(GL_MODELVIEW);
  glPopMatrix();
  glMatrixMode(GL_PROJECTION);
  glPopMatrix();
  glViewport(prev_vp[0], prev_vp[1], prev_vp[2], prev_vp[3]);
  glBindTexture(GL_TEXTURE_2D, (GLuint)prev_tex);
  glDepthMask(depth_mask);
  if (was_tex)
    glEnable(GL_TEXTURE_2D);
  else
    glDisable(GL_TEXTURE_2D);
  if (was_blend)
    glEnable(GL_BLEND);
  else
    glDisable(GL_BLEND);
  if (was_depth)
    glEnable(GL_DEPTH_TEST);
  else
    glDisable(GL_DEPTH_TEST);
  if (was_cull)
    glEnable(GL_CULL_FACE);
  else
    glDisable(GL_CULL_FACE);
  if (was_scis)
    glEnable(GL_SCISSOR_TEST);
  else
    glDisable(GL_SCISSOR_TEST);
  if (was_light)
    glEnable(GL_LIGHTING);
  else
    glDisable(GL_LIGHTING);
  if (was_fog)
    glEnable(GL_FOG);
  else
    glDisable(GL_FOG);
  if (was_alpha)
    glEnable(GL_ALPHA_TEST);
  else
    glDisable(GL_ALPHA_TEST);
  if (was_colmat)
    glEnable(GL_COLOR_MATERIAL);
  else
    glDisable(GL_COLOR_MATERIAL);
  glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
}

static void update_cursor(void) {
  cursor_ensure();
  int want_tap = 0;
  float wx = 0.0f, wy = 0.0f;

  if (g_pad) {
    const float scale = 1.0f / 32767.0f;
    int raw_rx = SDL_GameControllerGetAxis(g_pad, SDL_CONTROLLER_AXIS_RIGHTX);
    int raw_ry = SDL_GameControllerGetAxis(g_pad, SDL_CONTROLLER_AXIS_RIGHTY);
    const int CURSOR_DZ = 12000;
    if (abs(raw_rx) > CURSOR_DZ || abs(raw_ry) > CURSOR_DZ) {
      const float speed = 14.0f;
      if (abs(raw_rx) > CURSOR_DZ)
        g_cursor_x += (float)raw_rx * scale * speed;
      /* SDL Y+: down; view Y+: up — invert. */
      if (abs(raw_ry) > CURSOR_DZ)
        g_cursor_y -= (float)raw_ry * scale * speed;
      if (g_cursor_x < 0.0f)
        g_cursor_x = 0.0f;
      else if (g_cursor_x > (float)screen_width)
        g_cursor_x = (float)screen_width;
      if (g_cursor_y < 0.0f)
        g_cursor_y = 0.0f;
      else if (g_cursor_y > (float)screen_height)
        g_cursor_y = (float)screen_height;
      g_cursor_show = 120;
    } else if (g_cursor_show > 0) {
      g_cursor_show--;
    }
  } else if (g_cursor_show > 0) {
    g_cursor_show--;
  }

  int r3 = g_pad &&
           SDL_GameControllerGetButton(g_pad, SDL_CONTROLLER_BUTTON_RIGHTSTICK);
  if (r3 && !g_cursor_r3_prev) {
    want_tap = 1;
    wx = g_cursor_x;
    wy = g_cursor_y;
    g_cursor_show = 60;
  }
  g_cursor_r3_prev = r3;

  if (g_cursor_touch_hold > 0) {
    g_cursor_touch_hold--;
    if (g_cursor_touch_hold == 0)
      emit_touch(TOUCH_ENDED, 9, g_cursor_tx, g_cursor_ty);
    else
      emit_touch(TOUCH_MOVED, 9, g_cursor_tx, g_cursor_ty);
  } else if (want_tap) {
    g_cursor_tx = wx;
    g_cursor_ty = wy;
    emit_touch(TOUCH_BEGAN, 9, g_cursor_tx, g_cursor_ty);
    g_cursor_touch_hold = 6;
    debugPrintf("cursor: R3 tap (%.0f,%.0f)\n", g_cursor_tx, g_cursor_ty);
  }
}

static void ctrl_point(int flags, float ax, float ay, float *x, float *y) {
  float sx = (float)screen_width / REFERENCE_VIEW_W;
  float sy = (float)screen_height / REFERENCE_VIEW_H;
  ax *= sx;
  ay *= sy;
  *x = (flags & A_R) ? (float)screen_width - ax : ax;
  *y = (flags & A_T) ? (float)screen_height - ay : ay;
}

static int touch_tap_count(int phase) {
  return phase == TOUCH_BEGAN || phase == TOUCH_ENDED ? 1 : 0;
}

static void emit_touch(int phase, int id, float x, float y) {
  handleTouchEvent(fake_env, NULL, phase, id, g_time, x, y, x, y,
                   touch_tap_count(phase));
}

static void emit_touch_drag(int phase, int id, float x, float y, float ox,
                            float oy) {
  handleTouchEvent(fake_env, NULL, phase, id, g_time, x, y, ox, oy,
                   touch_tap_count(phase));
}

static void drive_button(int held, int was_held, int id, float x, float y) {
  if (held)
    emit_touch(was_held ? TOUCH_MOVED : TOUCH_BEGAN, id, x, y);
  else if (was_held)
    emit_touch(TOUCH_ENDED, id, x, y);
}

static void drive_key(int held, int was_held, unsigned key) {
  if (held == was_held || !sharedKeyboard || !sendKeyDownEvent || !sendKeyUpEvent)
    return;
  void *kb = sharedKeyboard();
  if (!kb)
    return;
  if (held)
    sendKeyDownEvent(kb, key, 0, g_time);
  else
    sendKeyUpEvent(kb, key, 0, g_time);
}

static uint32_t pad_buttons(void) {
  uint32_t m = 0;
  if (!g_pad)
    return 0;
  for (int i = 0; i < (int)(sizeof(button_map) / sizeof(button_map[0])); i++)
    if (SDL_GameControllerGetButton(g_pad, button_map[i].sdl_btn))
      m |= (1u << i);
  if (SDL_GameControllerGetButton(g_pad, SDL_CONTROLLER_BUTTON_START))
    m |= (1u << 16);
  if (SDL_GameControllerGetButton(g_pad, SDL_CONTROLLER_BUTTON_DPAD_LEFT))
    m |= (1u << 18);
  if (SDL_GameControllerGetButton(g_pad, SDL_CONTROLLER_BUTTON_DPAD_RIGHT))
    m |= (1u << 19);
  if (SDL_GameControllerGetButton(g_pad, SDL_CONTROLLER_BUTTON_A))
    m |= (1u << 20); /* jump */
  if (SDL_GameControllerGetButton(g_pad, SDL_CONTROLLER_BUTTON_RIGHTSHOULDER))
    m |= (1u << 21); /* back */
  return m;
}

/* Drives the debug hitbox: press for ~0.4 s once every 3 s. */
static void debug_tap_step(void) {
  static int held;
  static unsigned frame;
  float x, y;

  if (g_debug_tap_ax < 0.0f)
    return;
  frame++;
  int want = (frame % 180u) < 24u;
  if (want == held)
    return;
  held = want;
  ctrl_point(g_debug_tap_flags, g_debug_tap_ax, g_debug_tap_ay, &x, &y);
  emit_touch(want ? TOUCH_BEGAN : TOUCH_ENDED, 15, x, y);
  debugPrintf("debug-tap: %s overlay(%.0f,%.0f) screen(%.0f,%.0f)\n",
              want ? "down" : "up", g_debug_tap_ax, g_debug_tap_ay, x, y);
}

static void update_pad(void) {
  debug_tap_step();
  if (!g_pad) {
    for (int i = 0; i < SDL_NumJoysticks(); i++) {
      if (SDL_IsGameController(i)) {
        g_pad = SDL_GameControllerOpen(i);
        if (g_pad)
          debugPrintf("pad: opened %s\n", SDL_GameControllerName(g_pad));
        break;
      }
    }
  }
  if (!g_pad)
    return;

  Sint16 lx = SDL_GameControllerGetAxis(g_pad, SDL_CONTROLLER_AXIS_LEFTX);
  Sint16 ly = SDL_GameControllerGetAxis(g_pad, SDL_CONTROLLER_AXIS_LEFTY);
  int stick_active = lx < -10000 || lx > 10000 || ly < -10000 || ly > 10000;
  uint32_t down = pad_buttons();
  int controller_used = down || pad_prev || stick_active;

  for (int i = 0; i < (int)(sizeof(button_map) / sizeof(button_map[0])); i++) {
    float x, y;
    ctrl_point(button_map[i].flags, button_map[i].ax, button_map[i].ay, &x, &y);
    int held = (down >> i) & 1;
    int was = (pad_prev >> i) & 1;
    drive_button(held, was, button_map[i].id, x, y);
  }

  if ((down & (1u << 16)) && !(pad_prev & (1u << 16)) && handleMenuButtonPress)
    handleMenuButtonPress(fake_env, NULL);
  if ((down & (1u << 21)) && !(pad_prev & (1u << 21)) && handleBackButtonPress)
    handleBackButtonPress(fake_env, NULL);

  int left_now = ((down >> 18) & 1) || lx < -10000;
  int right_now = ((down >> 19) & 1) || lx > 10000;
  int jump_now = (down >> 20) & 1;
  drive_key(left_now, left_prev, KEY_LEFT);
  drive_key(right_now, right_prev, KEY_RIGHT);
  drive_key(jump_now, jump_prev, KEY_UP);
  left_prev = left_now;
  right_prev = right_now;
  jump_prev = jump_now;

  /* SELECT+START exit */
  if (SDL_GameControllerGetButton(g_pad, SDL_CONTROLLER_BUTTON_BACK) &&
      SDL_GameControllerGetButton(g_pad, SDL_CONTROLLER_BUTTON_START))
    g_running = 0;

  if (controller_used)
    set_touch_controls_hidden(1);
  pad_prev = down;
}

/* mouse/touch → view space (bottom-origin Y like the engine) */
static void handle_pointer_event(const SDL_Event *e) {
  float x = 0, y = 0;
  int phase = 0;
  int id = 0;
  if (e->type == SDL_FINGERDOWN || e->type == SDL_FINGERMOTION ||
      e->type == SDL_FINGERUP) {
    x = e->tfinger.x * (float)screen_width;
    y = (1.0f - e->tfinger.y) * (float)screen_height;
    id = (int)(e->tfinger.fingerId & 0x7fffffff);
    if (e->type == SDL_FINGERDOWN)
      phase = TOUCH_BEGAN;
    else if (e->type == SDL_FINGERUP)
      phase = TOUCH_ENDED;
    else
      phase = TOUCH_MOVED;
    set_touch_controls_hidden(0);
  } else if (e->type == SDL_MOUSEBUTTONDOWN || e->type == SDL_MOUSEBUTTONUP ||
             e->type == SDL_MOUSEMOTION) {
    if (e->type == SDL_MOUSEMOTION && !(e->motion.state & SDL_BUTTON_LMASK))
      return;
    x = (float)(e->type == SDL_MOUSEMOTION ? e->motion.x : e->button.x);
    float sy = (float)(e->type == SDL_MOUSEMOTION ? e->motion.y : e->button.y);
    y = (float)screen_height - sy;
    id = 0;
    if (e->type == SDL_MOUSEBUTTONDOWN)
      phase = TOUCH_BEGAN;
    else if (e->type == SDL_MOUSEBUTTONUP)
      phase = TOUCH_ENDED;
    else
      phase = TOUCH_MOVED;
    set_touch_controls_hidden(0);
  } else
    return;
  emit_touch(phase, id, x, y);
}

static void *exit_deadline(void *arg) {
  (void)arg;
  sleep(2);
  _exit(0);
  return NULL;
}

static void request_exit(void) {
  g_running = 0;
}

static int gl_init(void) {
  const char *debug_tap = getenv("SWORDIGO_DEBUG_TAP");
  if (debug_tap && *debug_tap) {
    float ax = -1.0f, ay = -1.0f;
    int flags = A_R;
    if (sscanf(debug_tap, "%f,%f,%d", &ax, &ay, &flags) >= 2) {
      g_debug_tap_ax = ax;
      g_debug_tap_ay = ay;
      g_debug_tap_flags = flags;
      debugPrintf("debug-tap: armed overlay(%.0f,%.0f) flags=%d\n", ax, ay, flags);
    }
  }

  if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER | SDL_INIT_TIMER) != 0) {
    fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
    return -1;
  }
  SDL_DisplayMode dm;
  if (SDL_GetDesktopDisplayMode(0, &dm) == 0 && dm.w > 0 && dm.h > 0) {
    screen_width = dm.w;
    screen_height = dm.h;
  }
  const char *ew = getenv("SWORDIGO_W");
  const char *eh = getenv("SWORDIGO_H");
  if (ew)
    screen_width = atoi(ew);
  if (eh)
    screen_height = atoi(eh);

  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 1);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1);
  SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 8);
  /* No alpha in the window config.  A firmware whose scanout honours per-pixel
   * alpha (KMSDRM plane in ARGB8888 -- ArkOS/ROCKNIX/DarkOS R36S) shows a frame
   * the game left at alpha 0 as transparent, which reads as a black screen with
   * the engine perfectly alive: audio, music and input all running.  Amlogic's
   * OSD ignores alpha, which is why the same build draws fine here.  Asking for
   * a config without alpha makes the game's alpha irrelevant to the scanout;
   * present_opaque_alpha() below covers the firmwares that hand out an alpha
   * config anyway (these attributes are minimums, not exact matches). */
  SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, 0);
  SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);
  SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);

  g_win = SDL_CreateWindow("Swordigo", SDL_WINDOWPOS_UNDEFINED,
                           SDL_WINDOWPOS_UNDEFINED, screen_width, screen_height,
                           SDL_WINDOW_OPENGL | SDL_WINDOW_FULLSCREEN);
  if (!g_win) {
    fprintf(stderr, "SDL_CreateWindow: %s\n", SDL_GetError());
    return -1;
  }
  g_ctx = SDL_GL_CreateContext(g_win);
  if (!g_ctx) {
    fprintf(stderr, "SDL_GL_CreateContext: %s\n", SDL_GetError());
    return -1;
  }
  SDL_GL_MakeCurrent(g_win, g_ctx);
  SDL_GL_SetSwapInterval(1);
  /* The window size a firmware grants is not always the size it draws into
   * (KMSDRM and scaled panels differ).  Touch hitboxes and the viewport must
   * follow the real drawable, otherwise the HUD lands off-target on some
   * devices -- the zoom class of bug seen in the LEGO/LOTR ports. */
  {
    int draw_w = 0, draw_h = 0;
    SDL_GL_GetDrawableSize(g_win, &draw_w, &draw_h);
    if (draw_w > 0 && draw_h > 0 &&
        (draw_w != screen_width || draw_h != screen_height)) {
      debugPrintf("gl: drawable %dx%d overrides window %dx%d\n", draw_w, draw_h,
                  screen_width, screen_height);
      screen_width = draw_w;
      screen_height = draw_h;
    }
  }
  int got_alpha = -1, got_depth = -1;
  SDL_GL_GetAttribute(SDL_GL_ALPHA_SIZE, &got_alpha);
  SDL_GL_GetAttribute(SDL_GL_DEPTH_SIZE, &got_depth);
  /* A black-screen report is only actionable with the video driver, the config
   * the firmware actually granted (alpha above all) and the GL blob in use. */
  const GLubyte *renderer = glGetString(GL_RENDERER);
  const GLubyte *version = glGetString(GL_VERSION);
  debugPrintf("gl: GLES1.1 %dx%d alpha=%d depth=%d driver='%s'\n", screen_width,
              screen_height, got_alpha, got_depth,
              SDL_GetCurrentVideoDriver() ? SDL_GetCurrentVideoDriver() : "?");
  debugPrintf("gl: renderer='%s' version='%s'\n",
              renderer ? (const char *)renderer : "?",
              version ? (const char *)version : "?");
  return 0;
}

/* Force the frame opaque immediately before the present.  GLES1.1 has no core
 * framebuffer object, but the game may bind one through GL_OES_framebuffer_object
 * and a clear aimed at a bound FBO would leave the window untouched -- the trap
 * that cost Horizon Chase v1.2.0 -- so framebuffer 0 is rebound explicitly when
 * the extension entry point exists.  Runs once per frame and logs once. */
#ifndef GL_FRAMEBUFFER_OES
#define GL_FRAMEBUFFER_OES 0x8D40
#endif
static void present_opaque_alpha(void) {
  static void (*bind_framebuffer_oes)(GLenum, GLuint);
  static int resolved = 0, logged = 0;
  if (!resolved) {
    resolved = 1;
    bind_framebuffer_oes = SDL_GL_GetProcAddress("glBindFramebufferOES");
  }

  GLboolean scissor = glIsEnabled(GL_SCISSOR_TEST);
  GLfloat clear_colour[4];
  glGetFloatv(GL_COLOR_CLEAR_VALUE, clear_colour);
  if (scissor)
    glDisable(GL_SCISSOR_TEST);
  if (bind_framebuffer_oes)
    bind_framebuffer_oes(GL_FRAMEBUFFER_OES, 0);
  glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_TRUE);
  glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT);
  glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
  glClearColor(clear_colour[0], clear_colour[1], clear_colour[2],
               clear_colour[3]);
  if (scissor)
    glEnable(GL_SCISSOR_TEST);

  if (!logged) {
    logged = 1;
    debugPrintf("gl: opaque-alpha present active (fbo rebind=%s)\n",
                bind_framebuffer_oes ? "yes" : "unavailable");
  }
}

static void check_data(void) {
  struct stat st;
  if (stat(SO_NAME, &st) < 0)
    fatal_error("missing %s (place libswordigo.so next to the binary)", SO_NAME);
  if (stat("assets/resources", &st) < 0)
    fatal_error("missing assets/resources (extract from APK)");
  if (stat("res/7c.mp3", &st) < 0)
    fatal_error("missing res/*.mp3 (extract APK res/ folder)");
}

int main(int argc, char **argv) {
  setvbuf(stdout, NULL, _IOLBF, 0);
  setvbuf(stderr, NULL, _IOLBF, 0);

  if (argc > 1 && chdir(argv[1]) == 0)
    debugPrintf("chdir %s\n", argv[1]);
  if (!getcwd(data_path, sizeof(data_path)))
    snprintf(data_path, sizeof(data_path), ".");

  unlink("debug.log");
  debugPrintf("=== swordigo NextOS — data=%s ===\n", data_path);
  check_data();

  size_t heap_size = (size_t)MEMORY_MB * 1024 * 1024;
  void *heap = mmap(NULL, heap_size, PROT_READ | PROT_WRITE | PROT_EXEC,
                    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (heap == MAP_FAILED)
    fatal_error("mmap heap failed");

  if (so_load(SO_NAME, heap, heap_size) < 0)
    fatal_error("so_load(%s) failed", SO_NAME);
  if (so_relocate() < 0)
    fatal_error("so_relocate failed");
  if (so_resolve(dynlib_functions, dynlib_functions_count, 1) < 0)
    fatal_error("so_resolve failed");

  /* Overlay hide hooks optional — trampoline slots are Switch-port specific;
   * enable with SWORDIGO_OVERLAY_HOOKS=1 once offsets are re-verified. */
  if (getenv("SWORDIGO_OVERLAY_HOOKS"))
    install_game_overlay_hooks();
  resolve_entry_points();

  so_finalize();
  so_flush_caches();
  so_record_phdr("libswordigo.so");

  so_execute_init_array();
  so_free_temp();

  if (gl_init() < 0)
    fatal_error("GL init failed");
  init_openal();

  jni_init();
  jni_configure_text_input(textInputTextDidChange, textInputDidFinish);

  setFilesDir(fake_env, NULL, jni_make_string(data_path));
  setCacheDir(fake_env, NULL, jni_make_string(data_path));
  setAssetManager(fake_env, NULL, NULL);
  googleSignInCompleted(fake_env, NULL, 0);
  handleApplicationLaunch(fake_env, NULL);

  music_init(data_path);
  initMusicPlayer(fake_env, jni_make_object("MusicPlayer"));

  setupNativeInterface(fake_env, NULL);
  setupApplication(fake_env, NULL);
  setApplicationViewSize(fake_env, NULL, screen_width, screen_height, 1,
                         screen_width, screen_height);
  applicationDidBecomeActive(fake_env, NULL);

  debugPrintf("boot complete — entering loop\n");

  /* Remote tap: echo "tap X Y" > /dev/shm/swordigo_ctl  (view bottom-origin Y) */
  static int ctl_up_frame = -1;
  static float ctl_x, ctl_y;
  int frame = 0;

  Uint32 last = SDL_GetTicks();
  while (g_running) {
    SDL_Event e;
    while (SDL_PollEvent(&e)) {
      if (e.type == SDL_QUIT)
        request_exit();
      else if (e.type == SDL_CONTROLLERDEVICEADDED && !g_pad) {
        g_pad = SDL_GameControllerOpen(e.cdevice.which);
      } else if (e.type == SDL_CONTROLLERDEVICEREMOVED && g_pad &&
                 e.cdevice.which ==
                     SDL_JoystickInstanceID(SDL_GameControllerGetJoystick(g_pad))) {
        SDL_GameControllerClose(g_pad);
        g_pad = NULL;
      } else
        handle_pointer_event(&e);
    }
    if (ctl_up_frame >= 0 && frame >= ctl_up_frame) {
      emit_touch(TOUCH_ENDED, 8, ctl_x, ctl_y);
      ctl_up_frame = -1;
    }
    if ((frame % 5) == 0) {
      FILE *cf = fopen("/dev/shm/swordigo_ctl", "r");
      if (cf) {
        char cmd[16] = {0};
        float x = 0, y = 0;
        if (fscanf(cf, "%15s %f %f", cmd, &x, &y) >= 1) {
          if (!strcmp(cmd, "tap")) {
            ctl_x = x;
            ctl_y = y;
            emit_touch(TOUCH_BEGAN, 8, x, y);
            ctl_up_frame = frame + 6;
            debugPrintf("[ctl] tap %.0f,%.0f @f%d\n", x, y, frame);
          } else if (!strcmp(cmd, "cursor")) {
            g_cursor_x = x;
            g_cursor_y = y;
            g_cursor_show = 300;
            debugPrintf("[ctl] cursor %.0f,%.0f\n", x, y);
          } else if (!strcmp(cmd, "quit")) {
            request_exit();
          }
        }
        fclose(cf);
        unlink("/dev/shm/swordigo_ctl");
      }
    }
    frame++;
    update_pad();
    update_cursor();
    jni_update();

    Uint32 now = SDL_GetTicks();
    float dt = (now - last) / 1000.0f;
    last = now;
    if (dt <= 0.0f || dt > 0.1f)
      dt = 1.0f / 60.0f;
    g_time += dt;

    updateApplication(fake_env, NULL, dt);
    drawApplication(fake_env, NULL);
    cursor_draw_overlay();
    present_opaque_alpha();
    SDL_GL_SwapWindow(g_win);
  }

  pthread_t d;
  if (pthread_create(&d, NULL, exit_deadline, NULL) == 0)
    pthread_detach(d);

  music_deinit();
  if (sharedAudioSystem && shutdownAudioSystem) {
    void *as = sharedAudioSystem();
    if (as)
      shutdownAudioSystem(as);
  }
  if (handleApplicationQuit)
    handleApplicationQuit(fake_env, NULL);
  deinit_openal();
  _exit(0);
}
