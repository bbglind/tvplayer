#ifndef RUNNER_LEGACY_KEYRING_H_
#define RUNNER_LEGACY_KEYRING_H_

#include <flutter_linux/flutter_linux.h>

// Reads and clears the flutter_secure_storage keyring item of an earlier
// application ID over the "tvplayer/legacy_keyring" method channel:
//
//   read(String legacyId) -> the stored value or null (no old item)
//   clear(String legacyId) -> null
//
// Items are matched by their "account" attribute only: the plugin's schema
// name is not reliable. Writing the item for the current ID is left to the
// plugin. Nothing is logged here.
void legacy_keyring_register(FlView* view);

#endif  // RUNNER_LEGACY_KEYRING_H_
