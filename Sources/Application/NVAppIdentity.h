// Application flavor is bundle metadata so copied test apps retain the same behavior.
#import <Foundation/Foundation.h>

static inline BOOL NVIsDevelopmentBuild(void) {
    return [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"NVBuildFlavor"] isEqualToString:@"development"];
}

// Keep existing support files and backup histories across product renames.
static inline NSString *NVApplicationSupportDirectoryName(void) {
    return NVIsDevelopmentBuild() ? @"nvALT Development" : @"nvALT";
}

static inline NSString *NVNoteURLScheme(void) {
    return NVIsDevelopmentBuild() ? @"nvalt-dev" : @"nvalt";
}
