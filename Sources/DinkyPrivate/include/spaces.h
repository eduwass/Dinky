#pragma once
#import <Foundation/Foundation.h>

// Creates one user Space on the display through the bridged SLSBridgedSpaceCreateOperation.
// Returns the new Space ID, or 0 with the reason on stderr.
uint64_t dinky_create_space(CFStringRef displayUUID);
