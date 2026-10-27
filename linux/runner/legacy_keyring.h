#ifndef RUNNER_LEGACY_KEYRING_H_
#define RUNNER_LEGACY_KEYRING_H_

#include <flutter_linux/flutter_linux.h>

// Moves the flutter_secure_storage keyring item of an earlier application
// ID to the current one, over the "tvplayer/legacy_keyring" method channel:
//
//   migrate(String legacyId) -> "migrated", "none" (no old item) or
//                               "exists" (current ID already has an item)
//
// The old item is cleared only after the copy reads back identical. The
// secret stays in native code and is never logged.
void legacy_keyring_register(FlView* view);

#endif  // RUNNER_LEGACY_KEYRING_H_
