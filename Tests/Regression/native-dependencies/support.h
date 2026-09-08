#import <WebKit/WebKit.h>
#import "PreviewController.h"
#import "AppController_Importing.h"
#import "AlienNoteImporter.h"
#import "DeletedNoteObject.h"
#import "AttributedPlainText.h"
#import "SimplenoteSession.h"
#import "SimplenoteEntryCollector.h"

@interface SimplenoteSession (FixtureAccess)
- (id)initWithUsername:(NSString *)username andPassword:(NSString *)password;
- (SyncResponseFetcher *)loginFetcher;
- (SyncResponseFetcher *)listFetcher;
- (SyncResponseFetcher *)changesFetcher;
@end

@interface NVSyncFixtureReceiver : NSObject {
@public
    NSArray *fullList, *partialList, *removedList;
    NSString *failure;
}
@end
@implementation NVSyncFixtureReceiver
- (void)syncSession:(id)session receivedFullNoteList:(NSArray *)entries { fullList = [entries copy]; }
- (void)syncSession:(id)session receivedPartialNoteList:(NSArray *)entries withRemovedList:(NSArray *)removed {
    partialList = [entries copy]; removedList = [removed copy];
}
- (void)syncSession:(id)session didStopWithError:(NSString *)error { failure = [error copy]; }
- (void)syncResponseFetcher:(id)fetcher receivedData:(NSData *)data returningError:(NSString *)error { failure = [error copy]; }
- (void)dealloc { [fullList release]; [partialList release]; [removedList release]; [failure release]; [super dealloc]; }
@end
