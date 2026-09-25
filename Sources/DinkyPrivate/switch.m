#import "switch.h"
#import "skylight.h"
#import "query.h"

#import <AppKit/AppKit.h>
#import <float.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <mach/mach_time.h>
#import <objc/runtime.h>

// Private CGEvent field numbers for a synthetic Dock swipe. Shared by the Tuna and mimi forms.
static const int kEventTypeField = 55;             // kCGSEventTypeField
static const int kEventDockControl = 30;           // kCGSEventDockControl
static const int kGestureHIDType = 110;            // kCGEventGestureHIDType
static const int kHIDEventTypeDockSwipe = 23;      // kIOHIDEventTypeDockSwipe
static const int kGestureSwipeMask = 115;          // kCGEventGestureSwipeMask
static const int kGestureSwipeMotion = 123;        // kCGEventGestureSwipeMotion
static const int kGestureMotionHorizontal = 1;     // kCGGestureMotionHorizontal
static const int kGestureSwipeProgress = 124;      // kCGEventGestureSwipeProgress
static const int kGestureSwipePositionX = 125;     // kCGEventGestureSwipePositionX
static const int kGestureSwipePositionY = 126;     // kCGEventGestureSwipePositionY
static const int kGestureSwipeVelocityX = 129;     // kCGEventGestureSwipeVelocityX
static const int kGestureSwipeVelocityY = 130;     // kCGEventGestureSwipeVelocityY
static const int kGesturePhase = 132;              // kCGEventGesturePhase
static const int kGesturePhaseAlias = 134;         // kCGEventGesturePhaseAlias
static const int kGestureZoomDeltaY = 138;         // kCGEventGestureZoomDeltaY
static const int kSourceUnixProcessIDAlias = 169;  // kCGEventSourceUnixProcessIDAlias
static const int kPhaseBegan = 1;
static const int kPhaseChanged = 2;
static const int kPhaseEnded = 4;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#pragma mark - Tuna form (Tuna app/SystemExtension/SpacesRuntime.swift)

// Tuna: velocity 2000 scaled by steps, one began/changed/ended per step, no delay, no IOHID payload.
static bool tuna_post_phase(int phase, bool right, double velocity)
{
    CGEventRef event = CGEventCreate(NULL);
    if (!event) return false;

    double progress = (double)FLT_TRUE_MIN;  // Swift Float.leastNonzeroMagnitude
    CGEventSetIntegerValueField(event, kEventTypeField, kEventDockControl);
    CGEventSetIntegerValueField(event, kGestureHIDType, kHIDEventTypeDockSwipe);
    CGEventSetIntegerValueField(event, kGesturePhase, phase);
    CGEventSetIntegerValueField(event, kGestureSwipeMotion, kGestureMotionHorizontal);
    CGEventSetDoubleValueField(event, kGestureSwipeProgress, right ? progress : -progress);
    CGEventSetDoubleValueField(event, kGestureSwipeVelocityX, right ? velocity : -velocity);
    CGEventSetDoubleValueField(event, kGestureSwipeVelocityY, right ? velocity : -velocity);
    CGEventPost(kCGSessionEventTap, event);
    CFRelease(event);
    return true;
}

static bool tuna_post_swipe(bool right, int steps)
{
    double velocity = 2000.0 * (steps > 1 ? steps : 1);
    for (int i = 0; i < steps; i++) {
        if (!tuna_post_phase(kPhaseBegan, right, velocity)) return false;
        if (!tuna_post_phase(kPhaseChanged, right, velocity)) return false;
        if (!tuna_post_phase(kPhaseEnded, right, velocity)) return false;
    }
    return true;
}

#pragma mark - mimi form (mimi internal/native/space.m + dockswipe.m)

// IOHID queue layout the Dock reads out of a synthetic dock swipe on macOS 27+. From mimi dockswipe.m.
#pragma pack(push, 1)
typedef struct {
    uint32_t size;
    uint32_t type;
    uint32_t options;
    uint8_t depth;
    uint8_t reserved[3];
} IOHIDEventBase;

typedef struct {
    IOHIDEventBase base;
    int32_t positionX;
    int32_t positionY;
    int32_t positionZ;
    uint32_t swipeMask;
    uint16_t gestureMotion;
    uint16_t gestureFlavor;
    int32_t swipeProgress;
} IOHIDFluidTouchGestureData;

typedef struct {
    IOHIDEventBase base;
    int32_t velocityX;
    int32_t velocityY;
    int32_t velocityZ;
} IOHIDVelocityEventData;

typedef struct {
    uint64_t timestamp;
    uint64_t senderID;
    uint32_t options;
    uint32_t attributeLength;
    uint32_t eventCount;
} IOHIDSystemQueueElementHeader;
#pragma pack(pop)

_Static_assert(sizeof(IOHIDEventBase) == 16, "unexpected IOHID event base layout");
_Static_assert(sizeof(IOHIDFluidTouchGestureData) == 40, "unexpected IOHID fluid gesture layout");
_Static_assert(sizeof(IOHIDVelocityEventData) == 28, "unexpected IOHID velocity layout");
_Static_assert(sizeof(IOHIDSystemQueueElementHeader) == 28, "unexpected IOHID queue header layout");

static const uint32_t kIOHIDEventTypeVelocity = 9;
static const uint32_t kIOHIDEventTypeFluidTouchGesture = 23;
static const uint16_t kIOHIDGestureFlavorDockPrimary = 3;
static const uint16_t kRawIOHIDPayloadField = 4205;
static const uint8_t kEventDataFormatVersion = 2;

static const double kMimiZoomDeltaY = 3.0;          // empirically required
static const double kMimiPositionX = 0.1;           // empirically required
static const double kMimiVelocity = 9999.0;         // high enough to skip the animation
static const CFTimeInterval kMimiStepDelay = 0.03;  // mimi kMimiSpaceGestureProcessingDelay

static int32_t fixed_1616(double value)
{
    int32_t fixed = (int32_t)(value * 65536.0);
    if (fixed == 0 && value != 0.0) return value > 0.0 ? 1 : -1;
    return fixed;
}

static uint8_t *build_iohid_payload(CGEventRef event, size_t *outLength)
{
    int64_t phase = CGEventGetIntegerValueField(event, kGesturePhase);
    int64_t motion = CGEventGetIntegerValueField(event, kGestureSwipeMotion);
    int64_t swipeMask = CGEventGetIntegerValueField(event, kGestureSwipeMask);
    double progress = CGEventGetDoubleValueField(event, kGestureSwipeProgress);
    double posX = CGEventGetDoubleValueField(event, kGestureSwipePositionX);
    double posY = CGEventGetDoubleValueField(event, kGestureSwipePositionY);
    double velX = CGEventGetDoubleValueField(event, kGestureSwipeVelocityX);
    double velY = CGEventGetDoubleValueField(event, kGestureSwipeVelocityY);

    // A real trackpad only reports velocity once the fingers lift.
    bool includeVelocity = (velX != 0.0 || velY != 0.0 || phase == kPhaseEnded);

    size_t length = sizeof(IOHIDSystemQueueElementHeader) + sizeof(IOHIDFluidTouchGestureData);
    if (includeVelocity) length += sizeof(IOHIDVelocityEventData);

    uint8_t *payload = calloc(1, length);
    if (!payload) return NULL;

    IOHIDSystemQueueElementHeader *header = (IOHIDSystemQueueElementHeader *)payload;
    uint64_t timestamp = CGEventGetTimestamp(event);
    header->timestamp = timestamp != 0 ? timestamp : mach_absolute_time();
    header->eventCount = includeVelocity ? 2 : 1;

    IOHIDFluidTouchGestureData *fluid = (IOHIDFluidTouchGestureData *)(payload + sizeof(IOHIDSystemQueueElementHeader));
    fluid->base.size = sizeof(IOHIDFluidTouchGestureData);
    fluid->base.type = kIOHIDEventTypeFluidTouchGesture;
    fluid->base.options = (uint32_t)((phase & 0xFF) << 24);
    fluid->positionX = fixed_1616(posX);
    fluid->positionY = fixed_1616(posY);
    fluid->swipeMask = (uint32_t)swipeMask;
    fluid->gestureMotion = (uint16_t)motion;
    fluid->gestureFlavor = kIOHIDGestureFlavorDockPrimary;
    fluid->swipeProgress = fixed_1616(progress);

    if (includeVelocity) {
        IOHIDVelocityEventData *velocity = (IOHIDVelocityEventData *)(payload + sizeof(IOHIDSystemQueueElementHeader) + sizeof(IOHIDFluidTouchGestureData));
        velocity->base.size = sizeof(IOHIDVelocityEventData);
        velocity->base.type = kIOHIDEventTypeVelocity;
        velocity->base.depth = 1;
        velocity->velocityX = fixed_1616(velX);
        velocity->velocityY = fixed_1616(velY);
    }

    *outLength = length;
    return payload;
}

// mimi MimiDockSwipeAugment: serialize the event, append the IOHID payload as a trailing field, rebuild.
static CGEventRef dock_swipe_augment(CGEventRef event)
{
    CFDataRef data = CGEventCreateData(kCFAllocatorDefault, event);
    if (!data) {
        fputs("switch: could not serialize dock swipe event\n", stderr);
        return NULL;
    }

    const uint8_t *bytes = CFDataGetBytePtr(data);
    CFIndex length = CFDataGetLength(data);
    if (length < 4 || bytes[0] != 0 || bytes[1] != 0 || bytes[2] != 0 || bytes[3] != kEventDataFormatVersion) {
        fprintf(stderr, "switch: unexpected event data format (length=%ld)\n", (long)length);
        CFRelease(data);
        return NULL;
    }

    size_t payloadLength = 0;
    uint8_t *payload = build_iohid_payload(event, &payloadLength);
    if (!payload) {
        CFRelease(data);
        return NULL;
    }

    // Serialized event, then big-endian payload length and field ID, then the payload.
    size_t newLength = (size_t)length + 4 + payloadLength;
    uint8_t *newBytes = malloc(newLength);
    if (!newBytes) {
        free(payload);
        CFRelease(data);
        return NULL;
    }
    memcpy(newBytes, bytes, (size_t)length);
    newBytes[length] = (uint8_t)((payloadLength >> 8) & 0xFF);
    newBytes[length + 1] = (uint8_t)(payloadLength & 0xFF);
    newBytes[length + 2] = (uint8_t)((kRawIOHIDPayloadField >> 8) & 0xFF);
    newBytes[length + 3] = (uint8_t)(kRawIOHIDPayloadField & 0xFF);
    memcpy(newBytes + length + 4, payload, payloadLength);
    free(payload);
    CFRelease(data);

    CFDataRef newData = CFDataCreate(kCFAllocatorDefault, newBytes, (CFIndex)newLength);
    free(newBytes);
    if (!newData) return NULL;

    CGEventRef augmented = CGEventCreateFromData(kCFAllocatorDefault, newData);
    CFRelease(newData);
    if (!augmented) fputs("switch: could not rebuild dock swipe event from data\n", stderr);
    return augmented;
}

// mimi mimiCreateAugmentedDockSwipeEvent. sign is +1 toward higher Space indices.
static CGEventRef mimi_create_event(int phase, double sign)
{
    CGEventRef event = CGEventCreate(NULL);
    if (!event) return NULL;

    CGEventSetIntegerValueField(event, kEventTypeField, kEventDockControl);
    CGEventSetIntegerValueField(event, kGestureHIDType, kHIDEventTypeDockSwipe);
    CGEventSetIntegerValueField(event, kGestureSwipeMotion, kGestureMotionHorizontal);
    CGEventSetIntegerValueField(event, kGesturePhase, phase);
    CGEventSetIntegerValueField(event, kGesturePhaseAlias, phase);

    // The payload uses the raw HID sign convention, opposite to the Space-index direction.
    CGEventSetDoubleValueField(event, kGestureSwipeProgress, -sign);
    CGEventSetDoubleValueField(event, kGestureSwipePositionX, kMimiPositionX);
    CGEventSetDoubleValueField(event, kGestureZoomDeltaY, kMimiZoomDeltaY);
    CGEventSetDoubleValueField(event, kSourceUnixProcessIDAlias, (double)mach_absolute_time());

    if (phase == kPhaseEnded) {
        // DINKY_SWIPE_VELOCITY overrides mimi's 9999 for experiments.
        double velocity = kMimiVelocity;
        const char *env = getenv("DINKY_SWIPE_VELOCITY");
        if (env && atof(env) > 0) velocity = atof(env);
        CGEventSetDoubleValueField(event, kGestureSwipeVelocityX, -sign * velocity);
    }

    CGEventRef augmented = dock_swipe_augment(event);
    CFRelease(event);
    return augmented;
}

// mimi mimiPostAugmentedDockSwipe.
static bool mimi_post_swipe(double sign)
{
    static const int phases[] = {kPhaseBegan, kPhaseChanged, kPhaseEnded};
    for (size_t i = 0; i < sizeof(phases) / sizeof(phases[0]); i++) {
        CGEventRef event = mimi_create_event(phases[i], sign);
        if (!event) {
            fprintf(stderr, "switch: failed to build augmented dock swipe event (phase=%d)\n", phases[i]);
            return false;
        }
        CGEventPost(kCGSessionEventTap, event);
        CFRelease(event);
    }
    return true;
}

// mimi MimiFocusSpaceUsingGesture, augmented branch. mimi pumps the run loop after every step and
// once more for count+1 delays at the end; we skip the wait after the last step, Swift polls instead.
static bool mimi_post_swipes(double sign, int count)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{ [NSApplication sharedApplication]; });  // mimiEnsureApplication

    for (int i = 0; i < count; i++) {
        if (!mimi_post_swipe(sign)) return false;
        if (i < count - 1) CFRunLoopRunInMode(kCFRunLoopDefaultMode, kMimiStepDelay, false);
    }
    return true;
}

#pragma clang diagnostic pop

#pragma mark - Bridged form

// mimi mimi_macho_find_symbol: walk an image's LC_SYMTAB for a non-exported symbol.
static void *macho_find_symbol(const char *targetImage, const char *targetSymbol)
{
    struct mach_header_64 *header = NULL;
    intptr_t slide = 0;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strcmp(name, targetImage) == 0) {
            header = (struct mach_header_64 *)_dyld_get_image_header(i);
            slide = _dyld_get_image_vmaddr_slide(i);
            break;
        }
    }
    if (!header) return NULL;

    struct segment_command_64 *linkedit = NULL;
    struct symtab_command *symtab = NULL;
    uint8_t *cursor = (uint8_t *)header + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        struct load_command *cmd = (struct load_command *)cursor;
        if (cmd->cmd == LC_SEGMENT_64 && strcmp(((struct segment_command_64 *)cmd)->segname, SEG_LINKEDIT) == 0) {
            linkedit = (struct segment_command_64 *)cmd;
        } else if (cmd->cmd == LC_SYMTAB) {
            symtab = (struct symtab_command *)cmd;
        }
        cursor += cmd->cmdsize;
    }
    if (!linkedit || !symtab) return NULL;

    uint8_t *base = (uint8_t *)(linkedit->vmaddr - linkedit->fileoff + slide);
    struct nlist_64 *symbols = (struct nlist_64 *)(base + symtab->symoff);
    const char *strings = (const char *)(base + symtab->stroff);
    for (uint32_t i = 0; i < symtab->nsyms; i++) {
        if (strcmp(strings + symbols[i].n_un.n_strx, targetSymbol) == 0) {
            return (void *)(symbols[i].n_value + slide);
        }
    }
    return NULL;
}

@protocol DinkySetCurrentSpaceOperation <NSObject>
- (instancetype)initWithDisplayIdentifier:(NSString *)displayIdentifier spaceID:(uint64_t)spaceID;
@end

static bool bridged_set_current_space(uint64_t spaceID, CFStringRef displayUUID)
{
    static SLSPerformAsynchronousBridgedWindowManagementOperationFn perform = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dinky_connection();  // make sure SkyLight is loaded and initialised
        perform = (SLSPerformAsynchronousBridgedWindowManagementOperationFn)macho_find_symbol(
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
            "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation");
    });
    if (!perform) {
        fputs("switch: could not resolve SLSPerformAsynchronousBridgedWindowManagementOperation\n", stderr);
        return false;
    }

    Class cls = objc_getClass("SLSBridgedManagedDisplaySetCurrentSpaceOperation");
    if (!cls) {
        fputs("switch: SLSBridgedManagedDisplaySetCurrentSpaceOperation not found\n", stderr);
        return false;
    }

    // Runtime encoding is @32@0:8@16Q24 and the displayIdentifier property is NSString. Sent through a
    // protocol rather than a cast objc_msgSend so ARC gets alloc/init ownership right.
    id operation = [(id<DinkySetCurrentSpaceOperation>)[cls alloc] initWithDisplayIdentifier:(__bridge NSString *)displayUUID spaceID:spaceID];
    if (!operation) {
        fputs("switch: could not create SLSBridgedManagedDisplaySetCurrentSpaceOperation\n", stderr);
        return false;
    }

    perform((__bridge void *)operation);
    return true;
}

#pragma mark - Plain keyboard shortcuts (Mission Control's own bindings)

// Control down as its own flags-changed event, the key, then Control up, the way a keyboard does it.
static void post_key(CGKeyCode code, CGEventFlags flags)
{
    CGEventRef ctrlDown = CGEventCreateKeyboardEvent(NULL, 59, true);
    CGEventRef down = CGEventCreateKeyboardEvent(NULL, code, true);
    CGEventRef up = CGEventCreateKeyboardEvent(NULL, code, false);
    CGEventRef ctrlUp = CGEventCreateKeyboardEvent(NULL, 59, false);
    CGEventSetType(ctrlDown, kCGEventFlagsChanged);
    CGEventSetType(ctrlUp, kCGEventFlagsChanged);
    CGEventSetFlags(ctrlDown, flags);
    CGEventSetFlags(down, flags);
    CGEventSetFlags(up, flags);
    CGEventSetFlags(ctrlUp, 0);
    // Tag our own events so the hotkeys tap lets them through.
    CGEventSetIntegerValueField(down, kCGEventSourceUserData, 0x64696E6B);
    CGEventSetIntegerValueField(up, kCGEventSourceUserData, 0x64696E6B);
    CGEventPost(kCGSessionEventTap, ctrlDown);
    CGEventPost(kCGSessionEventTap, down);
    CGEventPost(kCGSessionEventTap, up);
    CGEventPost(kCGSessionEventTap, ctrlUp);
    CFRelease(ctrlDown);
    CFRelease(down);
    CFRelease(up);
    CFRelease(ctrlUp);
}

// Control-Left / Control-Right, once per step, back to back.
static bool keys_post_arrows(bool right, int steps)
{
    // Arrow keys carry the secondary-fn bit on Apple keyboards, and the hotkey (symbolic hotkey 79/81,
    // flags 0x840000) is registered with it, so Control alone is ignored.
    for (int i = 0; i < steps; i++) post_key(right ? 124 : 123, kCGEventFlagMaskControl | kCGEventFlagMaskSecondaryFn);
    return true;
}

// Control-<digit>: "Switch to Desktop N". Key codes for the digits 1 to 9.
static bool keys_post_number(int index)
{
    static const CGKeyCode digits[] = {18, 19, 20, 21, 23, 22, 26, 28, 25};
    if (index < 1 || index > 9) return false;
    post_key(digits[index - 1], kCGEventFlagMaskControl);
    return true;
}

bool dinky_switch_to_space_index(DinkySwitchPath path, int fromIndex, int toIndex, uint64_t targetSpaceID, CFStringRef displayUUID)
{
    int steps = abs(toIndex - fromIndex);
    bool right = toIndex > fromIndex;

    switch (path) {
    case DinkySwitchPathTuna:
        return tuna_post_swipe(right, steps);
    case DinkySwitchPathMimi:
        return mimi_post_swipes(right ? 1.0 : -1.0, steps);
    case DinkySwitchPathBridged:
        return bridged_set_current_space(targetSpaceID, displayUUID);
    case DinkySwitchPathKeys:
        return keys_post_arrows(right, steps);
    case DinkySwitchPathNumber:
        return keys_post_number(toIndex);
    }
    return false;
}
