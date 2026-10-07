// Differences between macOS releases, kept out of the files they apply to.
#pragma once
#include <stdbool.h>

// Before macOS 27: posts `count` Dock swipes (sign +1 toward higher Space indices) and returns true.
// With `settle`, waits long enough for the Dock to read them before returning, for a caller that is
// about to move the cursor back. On 27 and later does nothing and returns false.
bool dinky_post_legacy_swipes(double sign, int count, bool settle);

// SLSWindowIteratorGetCornerRadii arrives with macOS 26. Before it SkyLight reports no radius, so borders
// would be square; this is the radius JankyBorders draws its round style with on those releases.
#define DINKY_LEGACY_CORNER_RADIUS 9
