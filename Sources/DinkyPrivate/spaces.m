#import "spaces.h"
#import "query.h"
#import "skylight.h"
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>

// Space creation is a synchronous bridged operation: it returns a result object carrying the new Space ID.
// Its dispatcher is another non-exported static next to the asynchronous one move.m uses.
// On 27.0 the exported SLSSpaceCreate builds this same operation and calls this same dispatcher.
typedef id (*SLSPerformSynchronousBridgedWindowManagementOperationFn)(id operation);

// Mach-O walk lifted from move.m (mimi mimi_macho_find_*, yabai macho_find_symbol).
static void *dinky_spaces_find_symbol(const char *targetImage, const char *targetSymbol)
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

    uint8_t *base = (uint8_t *)(uintptr_t)(linkedit->vmaddr - linkedit->fileoff + slide);
    const char *strings = (const char *)(base + symtab->stroff);
    struct nlist_64 *symbols = (struct nlist_64 *)(base + symtab->symoff);
    for (uint32_t i = 0; i < symtab->nsyms; i++) {
        if (strcmp(strings + symbols[i].n_un.n_strx, targetSymbol) == 0) {
            return (void *)(uintptr_t)(symbols[i].n_value + slide);
        }
    }
    return NULL;
}

static SLSPerformSynchronousBridgedWindowManagementOperationFn dinky_sync_dispatcher(void)
{
    static SLSPerformSynchronousBridgedWindowManagementOperationFn fn = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dinky_connection();  // make sure SkyLight is loaded and initialised
        fn = (SLSPerformSynchronousBridgedWindowManagementOperationFn)dinky_spaces_find_symbol(
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
            "__ZL54_SLSPerformSynchronousBridgedWindowManagementOperationP46SLSSynchronousBridgedWindowManagementOperation");
    });
    return fn;
}

// Runtime encodings on 27.0: initWithOptions:values: is @28@0:8I16@20, the result is a
// SLSBridgedWindowManagementOperationSpaceIDResult with -spaceID (Q16@0:8).
@protocol DinkyBridgedSpaceCreateOperation <NSObject>
- (instancetype)initWithOptions:(uint32_t)options values:(NSDictionary *)values;
@end

@protocol DinkyBridgedSpaceIDResult <NSObject>
- (uint64_t)spaceID;
@end

uint64_t dinky_create_space(CFStringRef displayUUID)
{
    SLSPerformSynchronousBridgedWindowManagementOperationFn perform = dinky_sync_dispatcher();
    if (!perform) {
        fputs("spaces: _SLSPerformSynchronousBridgedWindowManagementOperation not found in SkyLight symtab\n", stderr);
        return 0;
    }

    Class cls = objc_getClass("SLSBridgedSpaceCreateOperation");
    if (!cls) {
        fputs("spaces: class SLSBridgedSpaceCreateOperation not found\n", stderr);
        return 0;
    }

    // Keys as bobrwm's createNativeSpace passes them: a user Space (type 0) on the given display.
    NSDictionary *values = @{
        @"type": @(DinkySpaceTypeUser),
        @"Display Identifier": (__bridge NSString *)displayUUID,
    };
    id operation = [(id<DinkyBridgedSpaceCreateOperation>)[cls alloc] initWithOptions:0 values:values];
    if (!operation) {
        fputs("spaces: initWithOptions:values: returned nil\n", stderr);
        return 0;
    }

    id result = perform(operation);
    if (![result respondsToSelector:@selector(spaceID)]) {
        fprintf(stderr, "spaces: create returned %s, not a Space ID result\n", result ? class_getName([result class]) : "nil");
        return 0;
    }
    uint64_t spaceID = [(id<DinkyBridgedSpaceIDResult>)result spaceID];
    if (spaceID == 0) fputs("spaces: create returned Space ID 0\n", stderr);
    return spaceID;
}
