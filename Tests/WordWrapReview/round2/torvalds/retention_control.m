#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
static NSUInteger Alive;
@interface AttributeMarker : NSObject
@end
@implementation AttributeMarker
- (id)init { if ((self=[super init])) Alive++; return self; }
- (void)dealloc { Alive--; [super dealloc]; }
@end
int main(int argc, const char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        @autoreleasepool {
            NSTextStorage *storage=[[NSTextStorage alloc] init];
            NSLayoutManager *layout=[[NSLayoutManager alloc] init];
            NSTextContainer *container=[[NSTextContainer alloc] initWithSize:NSMakeSize(160,44)];
            [storage addLayoutManager:layout];
            [layout addTextContainer:container];
            layout.typesetter=[[[NSATSTypesetter alloc] init] autorelease];
            NSDictionary *attrs=@{NSFontAttributeName:[NSFont fontWithName:@"Menlo-Regular" size:18],
                @"ReviewMarker":[[[AttributeMarker alloc] init] autorelease]};
            NSString *source=[@"" stringByPaddingToLength:4096 withString:@"alpha beta gamma delta " startingAtIndex:0];
            [storage setAttributedString:[[[NSAttributedString alloc] initWithString:source attributes:attrs] autorelease]];
            if (argc>1) {
                NSAttributedString *snapshot=[storage attributedSubstringFromRange:NSMakeRange(0,source.length)];
                CTTypesetterRef measure=CTTypesetterCreateWithAttributedString((CFAttributedStringRef)snapshot);
                CTLineRef line=CTTypesetterCreateLine(measure,CFRangeMake(0,11));
                CFRelease(line);
                CFRelease(measure);
            }
            [layout ensureLayoutForTextContainer:container];
            [storage setAttributedString:[[[NSAttributedString alloc] initWithString:@""] autorelease]];
            [layout ensureLayoutForTextContainer:container];
            [container release];
            [layout release];
            [storage release];
        }
        printf("{\"coreTextControl\":%s,\"markersAliveAfterPool\":%lu}\n",argc>1?"true":"false",(unsigned long)Alive);
    }
    return 0;
}
