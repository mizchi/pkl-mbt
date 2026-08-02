#ifdef __APPLE__

#include <spawn.h>

// moonbitlang/async 0.20.3 aliases the macOS 26 SDK's
// posix_spawn_file_actions_addchdir_np name to an un-suffixed symbol.
// The macOS 26.2 SDK and libSystem still export only the _np spelling,
// so release linking otherwise fails with an undefined symbol. Keep this
// forwarding shim at the executable boundary until async drops the alias.
int posix_spawn_file_actions_addchdir(
    posix_spawn_file_actions_t *file_actions,
    const char *path) {
  return posix_spawn_file_actions_addchdir_np(file_actions, path);
}

#endif
