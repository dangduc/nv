#import <Cocoa/Cocoa.h>
#import "NVBrowserSession.h"
#import "NoteObject.h"
#import "GlobalPrefs.h"
#import "NVSearchService.h"

static NSUInteger bodyReads, notifications;
static double Now(void) { return (double)clock_gettime_nsec_np(CLOCK_UPTIME_RAW)/1e6; }
static void Check(BOOL value, const char *message) { if (!value) { fprintf(stderr,"FAIL %s\n",message); exit(1); } }
NSString *NoteTitleColumnString = @"title";
@implementation NoteObject
- (id)initWithNoteBody:(NSAttributedString *)body title:(NSString *)title delegate:(id)owner format:(NSInteger)format labels:(NSString *)labels {
    if ((self=[super init])) {
        contentString=[body mutableCopy]; titleString=[title copy]; labelString=[labels copy];
        CFUUIDRef uuid=CFUUIDCreate(NULL); uniqueNoteIDBytes=CFUUIDGetUUIDBytes(uuid); CFRelease(uuid);
    }
    return self;
}
- (CFUUIDBytes *)uniqueNoteIDBytes { return &uniqueNoteIDBytes; }
- (NSMutableAttributedString *)contentString { bodyReads++; return contentString; }
- (void)dealloc { [contentString release]; [titleString release]; [labelString release]; [super dealloc]; }
@end
@implementation GlobalPrefs
+ (GlobalPrefs *)defaultPrefs { static GlobalPrefs *prefs; if(!prefs) prefs=[[self alloc] init]; return prefs; }
- (BOOL)tableIsReverseSorted { return NO; }
- (BOOL)tableColumnsShowPreview { return NO; }
- (BOOL)autoCompleteSearches { return YES; }
@end
@implementation FastListDataSource
#include "datasource.inc"
- (void)dealloc { free(objects); [super dealloc]; }
@end
@interface Library : NSObject { @public NSMutableArray *notes; }
- (NSArray *)allNotes;
@end
@implementation Library
- (NSArray *)allNotes { return notes; }
@end
@interface Owner : NSObject
@end
@implementation Owner
- (BOOL)notationListShouldChange:(id)session { return YES; }
- (void)notationListMightChange:(id)session { }
- (void)notationListDidChange:(id)session { }
- (void)browserSessionSearchStateDidChange:(id)session { notifications++; }
- (void)browserSessionSearchDidComplete:(id)session { }
- (NoteObject *)selectedNoteObject { return nil; }
@end
@interface GateService : NVSearchService { @public NSUInteger requests, identity; NVSearchCompletion complete; }
@end
@implementation GateService
- (NSUInteger)requestForOwner:(id)owner query:(NSString *)query completion:(NVSearchCompletion)completion {
    requests++; identity++; [complete release]; complete=[completion copy]; return identity;
}
- (BOOL)isRequestCurrent:(NSUInteger)request forOwner:(id)owner { return request && request==identity; }
- (void)cancelRequestsForOwner:(id)owner { identity++; [complete release]; complete=nil; }
- (void)dealloc { [complete release]; [super dealloc]; }
@end
@interface NVSearchResult (FixtureConstruction)
- (id)initWithRequestID:(NSUInteger)requestID revision:(NSUInteger)revision query:(NVSearchQuery *)query snapshots:(NSArray *)snapshots titles:(NSArray *)titles fuzzy:(NSArray *)fuzzy;
@end
@interface NVBrowserSession (Measurement)
- (void)publishFuzzyResult:(NVSearchResult *)result;
@end
@interface Capture : NSObject {
@public NVSearchService *searchService; Library *library; NSUInteger searchSnapshotRevision, invalidations;
}
- (NVSearchNoteSnapshot *)searchSnapshotForNote:(NoteObject *)note;
- (void)invalidateBrowserSearches;
- (void)searchableNoteDidChange:(NoteObject *)note;
@end
@implementation Capture
#include "capture.inc"
- (void)invalidateBrowserSearches { invalidations++; }
@end
int main(void) {
    @autoreleasepool {
        printf("case,notes,rows,trial,elapsed_ms,body_reads,requests\n");
        for (NSNumber *size in @[@1000,@10000]) {
            @autoreleasepool {
                NSUInteger count=[size unsignedIntegerValue];
                Library *library=[[[Library alloc] init] autorelease]; library->notes=[NSMutableArray array];
                NSMutableString *source=[NSMutableString string]; while([source length]<5243) [source appendString:@"A project note records a meeting agenda and weekly plans.\n"];
                NSMutableArray *ids=[NSMutableArray array];
                for(NSUInteger i=0;i<count;i++) {
                    NoteObject *note=[[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:source] autorelease] title:[NSString stringWithFormat:@"A meeting %08lu",count-i] delegate:nil format:0 labels:@"planning"] autorelease];
                    [library->notes addObject:note]; [ids addObject:[NSData dataWithBytes:[note uniqueNoteIDBytes] length:16]];
                }
                Capture *capture=[[[Capture alloc] init] autorelease]; capture->library=library; capture->searchService=[[[NVSearchService alloc] init] autorelease];
                NSMutableArray *snapshots=[NSMutableArray array];
                double start=Now(); for(NoteObject *note in library->notes) [snapshots addObject:[capture searchSnapshotForNote:note]];
                printf("capture,%lu,0,0,%.3f,%lu,0\n",count,Now()-start,bodyReads);
                [capture->searchService synchronizeWithSnapshots:snapshots];
                for(NSUInteger trial=0;trial<5;trial++) {
                    NoteObject *note=[library->notes lastObject]; [(NSMutableAttributedString *)[note contentString] replaceCharactersInRange:NSMakeRange(0,1) withString:trial%2?@"a":@"b"];
                    bodyReads=0; start=Now(); [capture searchableNoteDidChange:note];
                    printf("changed_snapshot,%lu,0,%lu,%.3f,%lu,0\n",count,trial,Now()-start,bodyReads);
                    Check(capture->invalidations==trial+1,"one invalidation per changed capture");
                    bodyReads=0; start=Now(); [capture searchableNoteDidChange:note];
                    printf("same_snapshot,%lu,0,%lu,%.3f,%lu,0\n",count,trial,Now()-start,bodyReads);
                    Check(capture->invalidations==trial+1,"same content keeps snapshot identity");
                }
                NVBrowserSession *session=[[[NVBrowserSession alloc] initWithLibrary:(id)library] autorelease];
                Owner *owner=[[[Owner alloc] init] autorelease]; [session setDelegate:owner];
                GateService *service=[[[GateService alloc] init] autorelease]; [session setSearchService:service]; [session setSearchMode:@"fuzzy"]; [session filterNotesFromString:@"meeting"];
                NVSearchQuery *query=[[[NVSearchQuery alloc] initWithString:@"meeting"] autorelease];
                for(NSUInteger overlap=0;overlap<2;overlap++) {
                    NVSearchResult *result=[[[NVSearchResult alloc] initWithRequestID:service->identity revision:1 query:query snapshots:snapshots titles:overlap?ids:@[] fuzzy:ids] autorelease];
                    for(NSUInteger trial=0;trial<5;trial++) {
                        bodyReads=0; start=Now(); [session publishFuzzyResult:result];
                        printf("publish,%lu,%lu,%lu,%.3f,%lu,%lu\n",count,[session resultCount],trial,Now()-start,bodyReads,service->requests);
                        Check([session resultCount]==count*(overlap+1)&&[session distinctResultNoteCount]==count,"complete occurrence publication");
                        Check(bodyReads==0,"publication does not read note bodies");
                        NSUInteger before=service->requests; start=Now(); [session libraryDidChange];
                        printf("display_refresh,%lu,%lu,%lu,%.3f,%lu,%lu\n",count,[session resultCount],trial,Now()-start,bodyReads,service->requests-before);
                        Check(service->requests==before,"display refresh does not rescore");
                        start=Now(); for(NSUInteger i=0;i<100;i++) [session filterNotesFromString:@"meeting"];
                        printf("repeat_query_100,%lu,%lu,%lu,%.3f,%lu,%lu\n",count,[session resultCount],trial,Now()-start,bodyReads,service->requests-before);
                        Check(service->requests==before,"identical queries preserve request");
                        NSArray *keys=[session rowKeysAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,[session resultCount])]];
                        start=Now(); NSIndexSet *indexes=[session indexesForRowKeys:keys];
                        printf("resolve_all_row_keys,%lu,%lu,%lu,%.3f,%lu,0\n",count,[session resultCount],trial,Now()-start,bodyReads);
                        Check([indexes count]==[session resultCount],"all occurrence keys resolve uniquely");
                    }
                }
                [session setDelegate:nil];
                [capture->searchService invalidate];
            }
        }
        fprintf(stderr,"PASS: native publication, snapshot, and request identity checks\n");
    }
    return 0;
}
