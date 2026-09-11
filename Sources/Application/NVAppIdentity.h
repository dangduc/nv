// Application flavor is bundle metadata so copied test apps retain the same behavior.
#import <Foundation/Foundation.h>

static inline BOOL NVIsDevelopmentBuild(void) {
    return [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"NVBuildFlavor"] isEqualToString:@"development"];
}

static inline NSString *NVNoteURLScheme(void) {
    return NVIsDevelopmentBuild() ? @"nvalt-dev" : @"nvalt";
}
