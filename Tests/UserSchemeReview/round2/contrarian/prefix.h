#import "../../round1/contrarian/prefix.h"
#import "AppController.h"
#import "LinkingEditor.h"

static NSColor *ContrarianHighlight(AppController *browser, NSUInteger index) {
    LinkingEditor *editor = [browser valueForKey:@"textView"];
    return [[editor layoutManager] temporaryAttribute:NSBackgroundColorAttributeName
        atCharacterIndex:index effectiveRange:NULL];
}
