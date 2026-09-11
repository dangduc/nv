#import <Foundation/Foundation.h>
#import <Carbon/Carbon.h>
#import "NVAppIdentity.h"

static unsigned Finds, Creates;
static OSErr FindError, CreateError;
static NSString *CreatedName;
static void Check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}
static OSErr FindFolderProbe(short domain, OSType folder, Boolean create, FSRef *result) {
    Finds++;
    Check(domain == kUserDomain && folder == kApplicationSupportFolderType && create,
          @"default notes root stays in user Application Support");
    return FindError;
}
static OSErr CreateProbe(const FSRef *parent, CFStringRef name, FSRef *result) {
    Creates++;
    CreatedName = (NSString *)name;
    return CreateError;
}
#define FSFindFolder FindFolderProbe
#define CreateDirectoryIfNotPresent CreateProbe
@interface DirectoryProbe : NSObject
+ (OSStatus)getDefaultNotesDirectoryRef:(FSRef *)notesDir;
@end
@implementation DirectoryProbe
@DIRECTORY_METHOD@
@end

int main(int argc, const char **argv) {
    @autoreleasepool {
        Check(argc == 2, @"expected flavor argument");
        BOOL development = !strcmp(argv[1], "development");
        NSBundle *bundle = [NSBundle mainBundle];
        Check(NVIsDevelopmentBuild() == development, @"bundle flavor survives identifier changes");
        NSArray *registrations = [bundle objectForInfoDictionaryKey:@"CFBundleURLTypes"];
        NSArray *schemes = [[registrations objectAtIndex:0] objectForKey:@"CFBundleURLSchemes"];
        Check([[schemes objectAtIndex:0] isEqual:NVNoteURLScheme()], @"generated URL scheme matches built registration");
        FSRef notes;
        Check([DirectoryProbe getDefaultNotesDirectoryRef:&notes] == noErr, @"directory success");
        Check(Finds == 1 && Creates == 1, @"one root lookup and child creation");
        Check([CreatedName isEqual:development ? @"Notational Data Development" : @"Notational Data"],
              @"default notes child isolates the flavor");
        FindError = -123;
        Check([DirectoryProbe getDefaultNotesDirectoryRef:&notes] == -123 && Creates == 1,
              @"failed root lookup creates no child and returns its error");
        FindError = 0; CreateError = -124;
        Check([DirectoryProbe getDefaultNotesDirectoryRef:&notes] == -124,
              @"failed child creation returns its error");
        printf("PASS: %s, identifier=%s, scheme=%s, folder=%s\n", argv[1],
               [[bundle bundleIdentifier] UTF8String], [NVNoteURLScheme() UTF8String], [CreatedName UTF8String]);
    }
    return 0;
}
