#import <Cocoa/Cocoa.h>
#import "NVAppIdentity.h"
static NSUInteger Checks,Callbacks;
static void Check(BOOL value,NSString *message) { Checks++; if(!value){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);} }
@CONSTANTS@
static void sendCallbacksForGlobalPrefs(id object,SEL selector,id sender){Callbacks++;}
#define SEND_CALLBACKS() do { Callbacks++; } while(0)
@interface GlobalPrefs : NSObject { NSUserDefaults *defaults; }
@end
@implementation GlobalPrefs
- (id)init { if((self=[super init])) defaults=[NSUserDefaults standardUserDefaults]; return self; }
@PREFERENCE_METHODS@
@end

@interface AppController : NSObject { NSDictionary *state; }
- (id)initWithState:(NSDictionary *)value;
- (NSDictionary *)browserWindowState;
- (void)restoreBrowserWindowState:(NSDictionary *)value;
@end
@implementation AppController
- (id)initWithState:(NSDictionary *)value { if((self=[super init])) state=[value copy]; return self; }
- (NSDictionary *)browserWindowState { return state; }
- (void)restoreBrowserWindowState:(NSDictionary *)value { [state release]; state=[value copy]; }
- (void)dealloc { [state release]; [super dealloc]; }
@end
@interface NVApplicationController : NSObject { BOOL terminating,restoring; NSMutableArray *browsers; }
- (id)initWithStates:(NSArray *)states;
- (NSArray *)browserControllers;
- (void)newWindow:(id)sender;
@end
@implementation NVApplicationController
- (id)initWithStates:(NSArray *)states {
    if((self=[super init])) { browsers=[[NSMutableArray alloc] init]; for(NSDictionary *state in states) [browsers addObject:[[[AppController alloc] initWithState:state] autorelease]]; }
    return self;
}
- (NSArray *)browserControllers { return browsers; }
- (void)newWindow:(id)sender { [browsers addObject:[[[AppController alloc] initWithState:@{}] autorelease]]; }
@WINDOW_METHODS@
- (void)dealloc { [browsers release]; [super dealloc]; }
@end
static NSArray *States(NSString *flavor,BOOL updated) {
    NSMutableArray *states=[NSMutableArray array];
    for(NSUInteger i=0;i<(updated?1:2);i++) [states addObject:@{@"layoutVersion":@2,@"presentationVersion":@1,
        @"search":[NSString stringWithFormat:@"%@ query %lu %@",flavor,(unsigned long)i,updated?@"changed":@"original"],
        @"searchMode":[flavor isEqual:@"development"]?@"fuzzy":@"exact",@"note":[flavor stringByAppendingFormat:@"-fixture-%lu",(unsigned long)i],
        @"selection":updated?@"{8, 3}":@"{1, 2}",@"viewingNote":@NO,@"viewerIdentifier":@"markdown",@"bodyState":@{@"sourceScroll":@"{0, 40}"}}];
    return states;
}
static NSColor *Light(BOOL dev,BOOL updated) { return [NSColor colorWithCalibratedWhite:updated?0.25:dev?0.85:0.15 alpha:1]; }
static NSColor *Dark(BOOL dev,BOOL updated) { return [NSColor colorWithCalibratedWhite:updated?0.75:dev?0.20:0.90 alpha:1]; }
int main(int argc,const char **argv) {
    @autoreleasepool {
        Check(argc==3,@"flavor and phase are present");
        NSString *flavor=@(argv[1]),*phase=@(argv[2]),*domain=[NSBundle mainBundle].bundleIdentifier;
        Check([domain hasPrefix:@"org.nvalt.round3.ux."],@"only the generated review domain is accessible");
        BOOL dev=[flavor isEqual:@"development"],updated=[phase isEqual:@"update"]||[phase isEqual:@"read-updated"];
        Check(NVIsDevelopmentBuild()==dev,@"the copied metadata retains the expected build flavor");
        NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
        // These two registration values match the production initializer, checked by the runner.
        [defaults registerDefaults:@{ShowWordCount:@YES,MakeURLsClickableKey:@YES}];
        GlobalPrefs *prefs=[[[GlobalPrefs alloc] init] autorelease];
        if([phase isEqual:@"reset"]) {
            [defaults removePersistentDomainForName:domain];
            Check([defaults synchronize],@"reset of the generated domain synchronizes");
        }
        if([phase isEqual:@"seed"]||[phase isEqual:@"fresh"]||[phase isEqual:@"reset"]) {
            Check([defaults arrayForKey:NVBrowserWindowsKey]==nil,@"fresh or reset app has no peer window restoration state");
            Check([prefs showWordCount] && [prefs URLsAreClickable],@"fresh or reset app retains standard registered settings");
            Check([prefs backgroundTextColor]==nil && [prefs darkBackgroundTextColor]==nil,@"fresh or reset app has no peer custom colors");
        }
        if([phase isEqual:@"seed"]||[phase isEqual:@"update"]) {
            [prefs setShowWordCount:updated?YES:!dev];
            [prefs setMakeURLsClickable:updated?NO:dev sender:nil];
            [prefs setBackgroundTextColor:Light(dev,updated) sender:nil];
            [prefs setDarkBackgroundTextColor:Dark(dev,updated) sender:nil];
            NVApplicationController *coordinator=[[[NVApplicationController alloc] initWithStates:States(flavor,updated)] autorelease];
            [coordinator saveWindowStates];
            Check(Callbacks==4,@"the actual preference setters request their change callbacks");
            Check([defaults synchronize],@"settings and restoration state synchronize");
        } else if([phase hasPrefix:@"read"]) {
            Check([prefs showWordCount]==(updated?YES:!dev),@"relaunch retains only this flavor's word-count setting");
            Check([prefs URLsAreClickable]==(updated?NO:dev),@"relaunch retains only this flavor's link-click setting");
            Check([[prefs backgroundTextColor] isEqual:Light(dev,updated)],@"relaunch retains this flavor's custom light background");
            Check([[prefs darkBackgroundTextColor] isEqual:Dark(dev,updated)],@"relaunch retains this flavor's custom dark background");
            NVApplicationController *coordinator=[[[NVApplicationController alloc] initWithStates:@[@{}]] autorelease];
            [coordinator restoreWindowStates];
            NSArray *restored=[[coordinator browserControllers] valueForKey:@"browserWindowState"];
            Check([restored isEqual:States(flavor,updated)],@"actual restoration dispatch retains this flavor's windows, queries, source selection, and mode");
        }
        NSDictionary *record=@{@"flavor":flavor,@"phase":phase,@"checks":@(Checks),@"windows":[defaults arrayForKey:NVBrowserWindowsKey]?:@[],
            @"showWordCount":@([prefs showWordCount]),@"URLsAreClickable":@([prefs URLsAreClickable]),@"callbacks":@(Callbacks)};
        NSData *data=[NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingPrettyPrinted error:NULL];
        fwrite(data.bytes,1,data.length,stdout);putchar('\n');
    }
    return 0;
}
