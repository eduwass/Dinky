// Private SkyLight / CGS declarations shared by every .m file in DinkyPrivate.
// Signatures copied from yabai src/misc/extern.h.
#pragma once
#include <ApplicationServices/ApplicationServices.h>

extern int SLSMainConnectionID(void);
extern int SLSGetSpaceManagementMode(int cid);
extern CFArrayRef SLSCopyManagedDisplaySpaces(int cid);
extern uint64_t SLSManagedDisplayGetCurrentSpace(int cid, CFStringRef uuid);
extern CFStringRef SLSCopyManagedDisplayForSpace(int cid, uint64_t sid);
extern CFStringRef SLSCopyActiveMenuBarDisplayIdentifier(int cid);
extern int SLSSpaceGetType(int cid, uint64_t sid);
extern CFArrayRef SLSCopySpacesForWindows(int cid, int selector, CFArrayRef window_list);
extern CFArrayRef SLSCopyWindowsWithOptionsAndTags(int cid, uint32_t owner, CFArrayRef spaces, uint32_t options, uint64_t *set_tags, uint64_t *clear_tags);

extern CFTypeRef SLSWindowQueryWindows(int cid, CFArrayRef windows, int count);
extern CFTypeRef SLSWindowQueryResultCopyWindows(CFTypeRef window_query);
extern int SLSWindowIteratorGetCount(CFTypeRef iterator);
extern bool SLSWindowIteratorAdvance(CFTypeRef iterator);
extern uint32_t SLSWindowIteratorGetParentID(CFTypeRef iterator);
extern uint32_t SLSWindowIteratorGetWindowID(CFTypeRef iterator);
extern uint64_t SLSWindowIteratorGetTags(CFTypeRef iterator);
extern uint64_t SLSWindowIteratorGetAttributes(CFTypeRef iterator);
extern int SLSWindowIteratorGetLevel(CFTypeRef iterator);

// Declared for completeness. PLAN.md: do not use as a fallback for the bridged move.
extern void SLSMoveWindowsToManagedSpace(int cid, CFArrayRef window_list, uint64_t sid);

extern CGError SLSGetWindowOwner(int cid, uint32_t wid, int *wcid);
extern CGError SLSConnectionGetPID(int cid, pid_t *pid);
extern OSStatus _SLPSGetFrontProcess(ProcessSerialNumber *psn);
extern CGError _SLPSSetFrontProcessWithOptions(ProcessSerialNumber *psn, uint32_t wid, uint32_t mode);
extern CGError SLPSPostEventRecordTo(ProcessSerialNumber *psn, uint8_t *bytes);

// The bridged operation dispatcher is a non-exported C++ static in SkyLight
// (mangled "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation").
// It cannot be linked or dlsym'd; it must be found by walking SkyLight's Mach-O symbol table
// (yabai macho_find_symbol, mimi mimi_macho_find_symbol). The argument is the operation object.
typedef int64_t (*SLSPerformAsynchronousBridgedWindowManagementOperationFn)(void *operation);
