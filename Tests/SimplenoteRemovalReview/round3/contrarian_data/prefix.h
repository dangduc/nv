#import <Cocoa/Cocoa.h>
#import "NSData_transformations.h"
#import "NoteObject.h"
#import "NotationPrefs.h"
#import "FrozenNotation.h"
#import "NSString_NV.h"

static NSMutableArray *GuardOutcomes;
static void RecordGuardCheck(BOOL result, NSString *description) {
    [GuardOutcomes addObject:@(result)];
    NSLog(@"GUARD %@: %@", result ? @"ACCEPT" : @"REJECT", description);
}
#define Check RecordGuardCheck
#include "fixture_guard.h"
#undef Check

static BOOL LocalValuesMatch(NoteObject *note, NotationPrefs *prefs) {
    const CFUUIDBytes identifier = { 0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe,
        0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef };
    NSString *body = @"# Local café 😀\r\n\tunsent changes\n";
    return note && memcmp([note uniqueNoteIDBytes], &identifier, sizeof(identifier)) == 0 &&
        [[[note contentString] string] isEqual:body] &&
        [[note valueForKey:@"titleString"] isEqual:@"Local synced title"] &&
        [[note valueForKey:@"labelString"] isEqual:@"keep, 日本語"] &&
        [note logSequenceNumber] == 1 &&
        [[note valueForKey:@"createdDate"] doubleValue] == 700000000.25 &&
        [[note valueForKey:@"modifiedDate"] doubleValue] == 700000123.5 &&
        [[note sourceDataReturningError:NULL] isEqual:[body dataUsingEncoding:NSUTF8StringEncoding]] &&
        [[prefs sourceMetadataForNoteUUID:[NSString uuidStringWithBytes:identifier]]
            isEqual:@{@"syntax": @"markdown"}];
}

static BOOL RawArchiveHasKey(NSData *data, NSString *key) {
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data
        options:NSPropertyListImmutable format:NULL error:NULL];
    for (id value in [plist objectForKey:@"$objects"])
        if ([value isKindOfClass:[NSDictionary class]] && [value objectForKey:key]) return YES;
    return NO;
}
