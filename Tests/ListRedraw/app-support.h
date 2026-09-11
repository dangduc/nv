#import "ETScrollView.h"
#import "NotesTableView.h"

static BOOL OpaqueForNegativeControl(id object, SEL selector) { return YES; }
static NSData *Pixels(NSBitmapImageRep *image) {
    return [NSData dataWithBytes:image.bitmapData length:image.bytesPerRow * image.pixelsHigh];
}
