#import <Cocoa/Cocoa.h>
#import <malloc/malloc.h>
@interface AppController:NSObject
- (NSColor*)foregrndColor;
@end
@implementation AppController
- (NSColor*)foregrndColor{return NSColor.blackColor;}
@end
@interface ProbeApplication:NSObject
- (id)delegate;
@end
@implementation ProbeApplication
- (id)delegate{static AppController*d;static dispatch_once_t once;dispatch_once(&once,^{d=[AppController new];});return d;}
@end
static ProbeApplication*ProbeApp;
#define NSApp ProbeApp
static BOOL ColorsEqualWith8BitChannels(NSColor*a,NSColor*b){return [a isEqual:b];}
@interface ProbePrefs:NSObject{NSDictionary*noteBodyAttributes;}
- (NSFont*)noteBodyFont;
@end
@implementation ProbePrefs
- (NSFont*)noteBodyFont{return (NSFont*)[NSNull null];}
/*GETTER*/
@end
int main(void){@autoreleasepool{
    ProbeApp=[ProbeApplication new];ProbePrefs*p=[ProbePrefs new];
    NSMutableSet*objects=[NSMutableSet set];size_t total=0;
    for(NSUInteger i=0;i<10000;i++){@autoreleasepool{
        NSDictionary*a=[p noteBodyAttributes];id style=a[NSParagraphStyleAttributeName];
        NSValue*identity=[NSValue valueWithPointer:style];
        if(![objects containsObject:identity]){[objects addObject:identity];total+=malloc_size(style);}
        if([style lineBreakMode]!=NSLineBreakByCharWrapping)return 1;
    }}
    printf("{\"calls\":10000,\"distinctLiveStyles\":%lu,\"styleObjectAllocationBytes\":%lu}\n",(unsigned long)objects.count,(unsigned long)total);
}return 0;}
