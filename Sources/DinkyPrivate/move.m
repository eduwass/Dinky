#import "move.h"
#import "skylight.h"
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>

// Mach-O walk lifted from mimi internal/native/space.m (mimi_macho_find_*), same as yabai macho_find_symbol.

static struct mach_header_64 *dinky_macho_find_image_header(const char *target_name, uint64_t *slide)
{
    uint32_t image_count = _dyld_image_count();
    for (uint32_t i = 0; i < image_count; ++i) {
        const char *image_name = _dyld_get_image_name(i);
        if (image_name && strcmp(image_name, target_name) == 0) {
            *slide = _dyld_get_image_vmaddr_slide(i);
            return (struct mach_header_64 *)_dyld_get_image_header(i);
        }
    }
    return NULL;
}

static struct segment_command_64 *dinky_macho_find_linkedit_segment(struct mach_header_64 *header)
{
    uint64_t offset = sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < header->ncmds; ++i) {
        struct load_command *cmd = (struct load_command *)((uint8_t *)header + offset);
        if (cmd->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *segment = (struct segment_command_64 *)cmd;
            if (strcmp(segment->segname, SEG_LINKEDIT) == 0) return segment;
        }
        offset += cmd->cmdsize;
    }
    return NULL;
}

static struct symtab_command *dinky_macho_find_symtab_command(struct mach_header_64 *header)
{
    uint64_t offset = sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < header->ncmds; ++i) {
        struct load_command *cmd = (struct load_command *)((uint8_t *)header + offset);
        if (cmd->cmd == LC_SYMTAB) return (struct symtab_command *)cmd;
        offset += cmd->cmdsize;
    }
    return NULL;
}

static void *dinky_macho_find_symbol(const char *target_image, const char *target_symbol)
{
    uint64_t slide = 0;
    struct mach_header_64 *header = dinky_macho_find_image_header(target_image, &slide);
    if (!header) return NULL;
    struct segment_command_64 *linkedit = dinky_macho_find_linkedit_segment(header);
    if (!linkedit) return NULL;
    struct symtab_command *symtab = dinky_macho_find_symtab_command(header);
    if (!symtab) return NULL;

    uint8_t *base = (uint8_t *)(uintptr_t)(linkedit->vmaddr - linkedit->fileoff + slide);
    const char *strings = (const char *)(base + symtab->stroff);
    struct nlist_64 *symbols = (struct nlist_64 *)(base + symtab->symoff);
    for (uint32_t i = 0; i < symtab->nsyms; ++i) {
        if (strcmp(strings + symbols[i].n_un.n_strx, target_symbol) == 0) {
            return (void *)(uintptr_t)(symbols[i].n_value + slide);
        }
    }
    return NULL;
}

static SLSPerformAsynchronousBridgedWindowManagementOperationFn dinky_dispatcher(void)
{
    static SLSPerformAsynchronousBridgedWindowManagementOperationFn fn = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fn = (SLSPerformAsynchronousBridgedWindowManagementOperationFn)dinky_macho_find_symbol(
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
            "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation");
    });
    return fn;
}

// Declared so ARC knows init returns +1.
@protocol DinkyBridgedMoveOperation <NSObject>
- (instancetype)initWithWindows:(id)windows spaceID:(uint64_t)spaceID;
@end

bool dinky_move_windows_to_space(const uint32_t *windowIDs, int count, uint64_t spaceID)
{
    SLSPerformAsynchronousBridgedWindowManagementOperationFn perform = dinky_dispatcher();
    if (!perform) {
        fputs("move: SLSPerformAsynchronousBridgedWindowManagementOperation not found in SkyLight symtab\n", stderr);
        return false;
    }

    Class cls = objc_getClass("SLSBridgedMoveWindowsToManagedSpaceOperation");
    if (!cls) {
        fputs("move: class SLSBridgedMoveWindowsToManagedSpaceOperation not found\n", stderr);
        return false;
    }

    NSMutableArray *windows = [NSMutableArray arrayWithCapacity:count];
    for (int i = 0; i < count; ++i) {
        int32_t wid = (int32_t)windowIDs[i];
        [windows addObject:CFBridgingRelease(CFNumberCreate(NULL, kCFNumberSInt32Type, &wid))];
    }

    id<DinkyBridgedMoveOperation> operation = [(id<DinkyBridgedMoveOperation>)[cls alloc] initWithWindows:windows spaceID:spaceID];
    if (!operation) {
        fputs("move: initWithWindows:spaceID: returned nil\n", stderr);
        return false;
    }

    perform((__bridge void *)operation);
    return true;
}
