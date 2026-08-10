/* SPDX-License-Identifier: GPL-3.0-only */
#ifndef SWORDIGO_GL_PROVIDER_POLICY_H
#define SWORDIGO_GL_PROVIDER_POLICY_H

/* Conservative filename prefilter only.  A positive result still requires
 * symbol validation and a real EGL initialization against the live kernel. */
int gl_provider_name_compatible(const char *video_backend,
                                const char *provider_name);

#endif
