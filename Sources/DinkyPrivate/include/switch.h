#pragma once
#import <Foundation/Foundation.h>

typedef NS_ENUM(int, DinkySwitchPath) { DinkySwitchPathTuna, DinkySwitchPathMimi, DinkySwitchPathBridged, DinkySwitchPathKeys, DinkySwitchPathNumber };

// Posts the switch and returns whether posting succeeded. Does not wait.
bool dinky_switch_to_space_index(DinkySwitchPath path, int fromIndex, int toIndex, uint64_t targetSpaceID, CFStringRef displayUUID);
