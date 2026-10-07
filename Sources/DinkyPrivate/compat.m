#import "compat.h"
#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/Foundation.h>

// Before macOS 27 the Dock does not act on switch.m's augmented swipe: on 15.8.1, 0 of 10 adjacent
// switches land. It takes the plain event InstantSpaceSwitcher posts on those releases (MIT,
// Sources/ISS/ISS.c iss_post_dock_swipe), where positive is toward higher Space indices:
//
// - three phases, each with the smallest progress that still carries a direction. Full progress switches
//   too, but the Space being left is drawn once more before the new one;
// - every step posted back to back, with the velocity scaled by the step count, and no wait between them.
//
// Measured on 15.8.1: 10 of 10 adjacent switches at about 80 ms, and four steps in 85 ms.
// 26 is taken to match 15 because InstantSpaceSwitcher draws the line at 27; it has not been measured.
bool dinky_post_legacy_swipes(double sign, int count, bool settle)
{
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27) return false;

    static const int phases[] = {1, 2, 4};  // began, changed, ended
    double velocity = sign * 2000.0 * count;
    for (int step = 0; step < count; step++) {
        for (int i = 0; i < 3; i++) {
            CGEventRef event = CGEventCreate(NULL);
            if (!event) return true;
            CGEventSetIntegerValueField(event, 55, 30);    // kCGSEventTypeField, kCGSEventDockControl
            CGEventSetIntegerValueField(event, 110, 23);   // kCGEventGestureHIDType, kIOHIDEventTypeDockSwipe
            CGEventSetIntegerValueField(event, 132, phases[i]);            // kCGEventGesturePhase
            CGEventSetDoubleValueField(event, 124, sign * 0.000016);       // kCGEventGestureSwipeProgress
            CGEventSetIntegerValueField(event, 123, 1);    // kCGEventGestureSwipeMotion, horizontal
            CGEventSetDoubleValueField(event, 129, velocity);              // kCGEventGestureSwipeVelocityX
            CGEventSetDoubleValueField(event, 130, velocity);              // kCGEventGestureSwipeVelocityY
            CGEventPost(kCGSessionEventTap, event);
            CFRelease(event);
        }
    }
    if (settle) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.03, false);
    return true;
}
