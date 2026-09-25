#pragma once
#import <Foundation/Foundation.h>

typedef NS_ENUM(int, DinkySwitchPath) { DinkySwitchPathTuna, DinkySwitchPathMimi, DinkySwitchPathBridged, DinkySwitchPathKeys, DinkySwitchPathNumber };

// Posts the switch on the display with displayUUID and returns whether posting succeeded. Refuses an
// unknown display. Does not wait for the switch, but the mimi path warps the cursor to that display
// for the swipe when it is elsewhere and waits about 60 ms to put it back.
bool dinky_switch_to_space_index(DinkySwitchPath path, int fromIndex, int toIndex, uint64_t targetSpaceID, CFStringRef displayUUID);
