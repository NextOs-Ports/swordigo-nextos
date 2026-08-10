/* glfix.h — GL provider repair by observed capability. */
#ifndef SWORDIGO_GLFIX_H
#define SWORDIGO_GLFIX_H

void glfix_set_argv(char **argv);
int glfix_renderer_is_broken(const char *renderer);
/* teardown runs just before the re-exec (destroy SDL window/context). */
void glfix_maybe_reexec(const char *renderer, void (*teardown)(void));

#endif
