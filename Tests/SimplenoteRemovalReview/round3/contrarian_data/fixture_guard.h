// Extracted verbatim by run.py; assertion reporter is rebound by prefix.h.
// Decode only the obsolete fixture fields into test records. The production
// decoder deliberately ignores these keys and exposes no remote-service API.
@interface NVLegacyFixtureArchiveFields : NSObject <NSCoding> {
    NSDictionary *fields;
}
- (id)fieldForKey:(NSString *)key;
@end
@implementation NVLegacyFixtureArchiveFields
- (id)initWithCoder:(NSCoder *)coder {
    if ((self = [super init])) {
        NSMutableDictionary *decoded = [NSMutableDictionary dictionary];
        for (NSString *key in @[@"prefs", @"notesData", @"deletedNoteSet", @"syncServiceAccounts", @"syncServicesMD"]) {
            if (![coder containsValueForKey:key]) continue;
            id value = [coder decodeObjectForKey:key];
            if (value) [decoded setObject:value forKey:key];
        }
        fields = [decoded copy];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder {
    [NSException raise:NSInternalInconsistencyException format:@"Legacy fixture inspection is decode-only"];
}
- (id)fieldForKey:(NSString *)key { return [fields objectForKey:key]; }
- (void)dealloc { [fields release]; [super dealloc]; }
@end

static id SourceInspectLegacyFixtureArchive(NSData *data, NSString *key) {
    NSKeyedUnarchiver *decoder = [[[NSKeyedUnarchiver alloc] initForReadingWithData:data] autorelease];
    for (NSString *className in @[@"FrozenNotation", @"NotationPrefs", @"NoteObject", @"DeletedNoteObject"])
        [decoder setClass:[NVLegacyFixtureArchiveFields class] forClassName:className];
    return [decoder decodeObjectForKey:key];
}

static void SourceCheckLegacyFixtureMetadata(NSData *data) {
    NVLegacyFixtureArchiveFields *root = SourceInspectLegacyFixtureArchive(data, @"root");
    NSDictionary *accounts = [[root fieldForKey:@"prefs"] fieldForKey:@"syncServiceAccounts"];
    Check([[accounts objectForKey:@"SN"] isEqual:@{@"enabled": @YES, @"username": @"fixture@example.invalid", @"frequency": @1}],
          @"legacy fixture contains the exact enabled account under the recognized SN identifier");
    NSArray *notes = SourceInspectLegacyFixtureArchive([[root fieldForKey:@"notesData"] uncompressedData], @"notes");
    Check([notes count] == 1 && [[[[notes firstObject] fieldForKey:@"syncServicesMD"] objectForKey:@"SN"] isEqual:
          @{@"key": @"legacy-remote-note", @"version": @7, @"dirty": @YES, @"modify": @700000123.5, @"SepStr": @"e\n\n#"}],
          @"legacy fixture contains recognized pending upload metadata on its local note");
    NSSet *deleted = [root fieldForKey:@"deletedNoteSet"];
    Check([deleted count] == 1 && [[[[[deleted allObjects] firstObject] fieldForKey:@"syncServicesMD"] objectForKey:@"SN"] isEqual:
          @{@"key": @"legacy-remote-deletion", @"version": @11, @"dirty": @YES, @"modify": @700000124.5}],
          @"legacy fixture contains recognized pending deletion metadata on its tombstone");
}

