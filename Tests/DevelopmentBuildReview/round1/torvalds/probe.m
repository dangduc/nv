// Native read-only review: no NSApplication, Launch Services registration, or preferences writes.
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

static void Check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", [message UTF8String]); exit(1); }
}

static NSDictionary *ReadPlist(NSString *path, NSPropertyListFormat *format) {
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    Check(data != nil, [@"read " stringByAppendingString:path]);
    id value = [NSPropertyListSerialization propertyListWithData:data options:0 format:format error:&error];
    Check([value isKindOfClass:[NSDictionary class]], [NSString stringWithFormat:@"parse %@: %@", path, error]);
    return value;
}

static UInt32 Signature(NSBundle *bundle) {
    CFBundleRef native = CFBundleCreate(kCFAllocatorDefault, (CFURLRef)[bundle bundleURL]);
    Check(native != NULL, @"CFBundleCreate accepts the bundle");
    UInt32 type = 0, creator = 0;
    CFBundleGetPackageInfo(native, &type, &creator);
    Check(type == 0x4150504c, @"native package type is APPL");
    CFRelease(native);
    return creator;
}

static NSArray *Schemes(NSDictionary *info) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *entry in info[@"CFBundleURLTypes"])
        if (entry[@"CFBundleURLSchemes"]) [result addObjectsFromArray:entry[@"CFBundleURLSchemes"]];
    return result;
}

static NSDictionary *Configuration(NSDictionary *project, NSString *name) {
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    NSUInteger count = 0;
    for (NSDictionary *object in [project[@"objects"] allValues]) {
        if ([object[@"isa"] isEqual:@"XCBuildConfiguration"] && [object[@"name"] isEqual:name]) {
            [settings addEntriesFromDictionary:object[@"buildSettings"]];
            count++;
        }
    }
    Check(count == 2, @"both project and target configuration exist");
    return settings;
}

static void CheckBundle(NSBundle *bundle, BOOL development, NSDictionary *settings, NSString *language) {
    NSString *name = development ? @"nvALT Development" : @"nvALT";
    NSString *identifier = development ? @"net.elasticthreads.nv.development" : @"net.elasticthreads.nv";
    NSString *flavor = development ? @"development" : @"release";
    NSString *rank = development ? @"None" : @"Default";
    NSDictionary *info = [bundle infoDictionary];
    Check(bundle != nil && info != nil, @"NSBundle loads built metadata");
    Check([[bundle bundleIdentifier] isEqual:identifier], @"native bundle identifier");
    for (NSString *key in @[@"CFBundleName", @"CFBundleDisplayName", @"CFBundleExecutable"])
        Check([[bundle objectForInfoDictionaryKey:key] isEqual:name], [@"localized identity " stringByAppendingString:key]);
    Check([[[bundle executableURL] lastPathComponent] isEqual:name], @"executable path with spaces resolves");
    Check([[NSFileManager defaultManager] isExecutableFileAtPath:[[bundle executableURL] path]], @"resolved executable exists");
    Check([[bundle objectForInfoDictionaryKey:@"NVBuildFlavor"] isEqual:flavor], @"runtime flavor agrees with artifact");
    NSArray *selected = [NSBundle preferredLocalizationsFromArray:[bundle localizations] forPreferences:@[language]];
    Check([[selected firstObject] isEqual:language], @"explicit native localization selection");
    NSString *strings = [bundle pathForResource:@"InfoPlist" ofType:@"strings" inDirectory:nil forLocalization:language];
    Check(strings != nil, @"native lookup finds each localized InfoPlist.strings");
    NSDictionary *localized = ReadPlist(strings, NULL);
    for (NSString *key in @[@"CFBundleName", @"CFBundleDisplayName", @"NVBuildFlavor"])
        Check(!localized[key] || [localized[key] isEqual:info[key]], @"localized metadata cannot override build identity");
    UInt32 expected = development ? 0x4e764476 : 0x4ea06cc3;
    Check(Signature(bundle) == expected, @"native creator signature retains four MacRoman bytes");
    NSData *package = [NSData dataWithContentsOfFile:[[bundle bundlePath] stringByAppendingPathComponent:@"Contents/PkgInfo"]];
    if (package) {
        UInt32 words[] = { CFSwapInt32HostToBig(0x4150504c), CFSwapInt32HostToBig(expected) };
        Check([package isEqual:[NSData dataWithBytes:words length:sizeof(words)]], @"PkgInfo agrees with CFBundle metadata");
    }
    Check([settings[@"PRODUCT_NAME"] isEqual:name], @"native project parser preserves product name");
    Check([settings[@"PRODUCT_BUNDLE_IDENTIFIER"] isEqual:identifier], @"project and built bundle IDs agree");
    Check([settings[@"NV_BUNDLE_SIGNATURE"] isEqual:info[@"CFBundleSignature"]], @"native project preserves Unicode release signature");
    Check([settings[@"NV_BUILD_FLAVOR"] isEqual:flavor], @"project and runtime flavors agree");
    Check([settings[@"NV_DOCUMENT_HANDLER_RANK"] isEqual:rank], @"project document rank");
    for (NSDictionary *document in info[@"CFBundleDocumentTypes"])
        Check([document[@"LSHandlerRank"] isEqual:rank], @"built document rank");
    NSArray *schemes = development ? @[@"nvalt-dev", @"nv-dev"] : @[@"nvalt", @"nv"];
    Check([Schemes(info) isEqual:schemes], @"registered URL schemes are flavor-specific");
    for (NSString *scheme in schemes) {
        NSURL *URL = [NSURL URLWithString:[scheme stringByAppendingString:@"://find/Review%20caf%C3%A9/?NV=A%2FB%3D"]];
        Check([[URL scheme] isEqual:scheme] && [[URL host] isEqual:@"find"] &&
              [[URL path] isEqual:@"/Review café"] && [[URL query] isEqual:@"NV=A%2FB%3D"],
              @"native URL parsing preserves command, title, and UUID query");
    }
    printf("PASS: %s %s native bundle/config, locale resources, signature=%08x, URL parsing\n",
           [flavor UTF8String], [language UTF8String], Signature(bundle));
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        Check(argc >= 6, @"project, development app, release app, baseline app, language arguments");
        NSPropertyListFormat format = 0;
        NSDictionary *project = ReadPlist(@(argv[1]), &format);
        Check(format == NSPropertyListOpenStepFormat, @"native parser accepts the actual Xcode project syntax");
        NSBundle *development = [NSBundle bundleWithPath:@(argv[2])];
        NSBundle *release = [NSBundle bundleWithPath:@(argv[3])];
        NSBundle *baseline = [NSBundle bundleWithPath:@(argv[4])];
        CheckBundle(development, YES, Configuration(project, @"Development"), @(argv[5]));
        CheckBundle(release, NO, Configuration(project, @"ForBuilding"), @(argv[5]));
        Check(Signature(release) == Signature(baseline), @"release native creator code is unchanged from baseline");
        NSDictionary *old = [baseline infoDictionary], *now = [release infoDictionary];
        for (NSString *key in @[@"CFBundleName", @"CFBundleIdentifier", @"CFBundleExecutable", @"CFBundleSignature",
                               @"CFBundleVersion", @"CFBundleShortVersionString", @"CFBundlePackageType", @"NSServices",
                               @"UTImportedTypeDeclarations", @"OSAScriptingDefinition"])
            Check([old[key] isEqual:now[key]], [@"release compatibility " stringByAppendingString:key]);
        Check([Schemes(old) isEqual:Schemes(now)], @"release keeps both legacy URL schemes after dictionary consolidation");
        NSMutableArray *documents = [NSMutableArray array];
        for (NSDictionary *document in now[@"CFBundleDocumentTypes"]) {
            NSMutableDictionary *copy = [[document mutableCopy] autorelease];
            [copy removeObjectForKey:@"LSHandlerRank"];
            [documents addObject:copy];
        }
        Check([documents isEqual:old[@"CFBundleDocumentTypes"]], @"release document formats and roles are preserved");
        puts("PASS: release baseline native signature and external registration compatibility");
    }
    return 0;
}
