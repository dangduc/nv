#import "NotationPrefs.h"
#import "AlienNoteImporter.h"
#import "FrozenNotation.h"
#import "NSString_NV.h"

@interface NVReviewSourceOwner : NSObject {
@public
    NotationPrefs *prefs;
}
@end
@implementation NVReviewSourceOwner
- (NotationPrefs*)notationPrefs { return prefs; }
@end

static NSData *SourceBytes(NSString *text, NSStringEncoding encoding, NSData *bom) {
    NSMutableData *data = [NSMutableData dataWithData:bom ?: [NSData data]];
    [data appendData:[text dataUsingEncoding:encoding allowLossyConversion:NO]];
    return data;
}
