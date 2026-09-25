#import "focus.h"
#import "skylight.h"

// yabai src/window_manager.h
#define kCPSUserGenerated 0x200

// yabai window_manager_make_key_window: synthesized key-window event, posted as down (0x01) then up (0x02).
static void make_key_window(ProcessSerialNumber *psn, uint32_t windowID)
{
    uint8_t bytes[0xf8];
    memset(bytes, 0, 0xf8);
    bytes[0x04] = 0xf8;
    bytes[0x3a] = 0x10;
    memcpy(bytes + 0x3c, &windowID, sizeof(uint32_t));
    memset(bytes + 0x20, 0xff, 0x10);

    bytes[0x08] = 0x01;
    SLPSPostEventRecordTo(psn, bytes);

    bytes[0x08] = 0x02;
    SLPSPostEventRecordTo(psn, bytes);
}

// yabai window_manager_focus_window_with_raise, without the scripting addition.
bool dinky_focus_window_private(pid_t pid, uint32_t windowID)
{
    ProcessSerialNumber psn = {0};
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    OSStatus status = GetProcessForPID(pid, &psn);
#pragma clang diagnostic pop
    if (status != noErr) return false;

    CGError err = _SLPSSetFrontProcessWithOptions(&psn, windowID, kCPSUserGenerated);
    make_key_window(&psn, windowID);
    return err == kCGErrorSuccess;
}
