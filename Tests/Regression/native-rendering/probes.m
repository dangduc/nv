// Injected only into the disposable app copy made by run.py.
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <objc/runtime.h>
#import "AppController.h"
#import "NVApplicationController.h"
#import "NVBrowserSession.h"
#import "NoteObject.h"
#import "LinkingEditor.h"
#import "GlobalPrefs.h"
#import "NSFileManager_NV.h"
#import "ODBEditor.h"

static NSString *TestDirectory;
static NSUInteger Checks;
static void Check(BOOL result, NSString *description) {
    if (!result) { NSLog(@"FAIL: %@", description); exit(1); }
    NSLog(@"PASS: %@", description); Checks++;
}
static void Pump(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; }
static void TraceFixture(NSString *stage, AppController *browser, NoteObject *note) {
    NVApplicationController *app = [NVApplicationController sharedController];
    LinkingEditor *editor = [browser valueForKey:@"textView"];
    NSTableView *table = [browser valueForKey:@"notesTableView"];
    NVBrowserSession *session = [browser browserSession];
    NSLog(@"RENDERING_FIXTURE %@ browser=%p active=%p appActive=%d key=%d main=%d registered=%d library=%p libraryDelegate=%p sessionLibrary=%p hasLaunched=%@ colorScheme=%@ notes=%lu query=%@ rows=%ld row=%ld noteIndex=%lu selected=%p expected=%p editable=%d firstResponder=%@:%p editor=%p body=%@ noteBody=%@",
        stage, browser, [app activeBrowser], [NSApp isActive], [[browser window] isKeyWindow], [[browser window] isMainWindow],
        [[app browserControllers] containsObject:browser], [app library], [[app library] delegate], [session library],
        [browser valueForKey:@"hasLaunched"], [browser valueForKey:@"userScheme"], (unsigned long)[[app library] totalNoteCount],
        [session searchString], (long)[table numberOfRows], (long)[table selectedRow],
        (unsigned long)[session indexInFilteredListForNoteIdenticalTo:note], [browser selectedNoteObject], note,
        [editor isEditable], [[[browser window] firstResponder] class], [[browser window] firstResponder], editor,
        [editor string], [[note contentString] string]);
}
static void ActivateBrowser(AppController *browser) {
    [NSApp activateIgnoringOtherApps:YES];
    [[browser window] makeKeyAndOrderFront:browser];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while ((![NSApp isActive] || ![[browser window] isKeyWindow] ||
        [[NVApplicationController sharedController] activeBrowser] != browser) && [deadline timeIntervalSinceNow] > 0) Pump();
    BOOL ready = [NSApp isActive] && [[browser window] isKeyWindow] &&
        [[NVApplicationController sharedController] activeBrowser] == browser;
    if (!ready) TraceFixture(@"activation-timeout", browser, [browser selectedNoteObject]);
    Check(ready, @"native activation makes the fixture browser key and active");
}
static void RevealFixtureNote(AppController *browser, NoteObject *note) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while ([[browser browserSession] indexInFilteredListForNoteIdenticalTo:note] == NSNotFound &&
        [deadline timeIntervalSinceNow] > 0) Pump();
    TraceFixture(@"before-reveal", browser, note);
    Check([[browser browserSession] indexInFilteredListForNoteIdenticalTo:note] != NSNotFound,
        @"the fixture note is visible in its browser session before reveal");
    [browser revealNote:note options:0]; Pump();
    if ([browser selectedNoteObject] != note) TraceFixture(@"selection-mismatch", browser, note);
    Check([browser selectedNoteObject] == note, @"the fixture browser selects the expected note before editor operations");
}
static void Swap(Class cls, SEL original, SEL replacement) {
    method_exchangeImplementations(class_getInstanceMethod(cls, original), class_getInstanceMethod(cls, replacement));
}
static CGFloat ColorDistance(NSColor *first, NSColor *second) {
    first = [first colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    second = [second colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    if (!first || !second) return CGFLOAT_MAX;
    return MAX(fabs([first redComponent] - [second redComponent]),
        MAX(fabs([first greenComponent] - [second greenComponent]),
            fabs([first blueComponent] - [second blueComponent])));
}
static void SetColors(AppController *browser, BOOL dark) {
    [browser setForegrndColor:dark ? [NSColor whiteColor] : [NSColor blackColor]];
    [browser setBackgrndColor:dark ? [NSColor blackColor] : [NSColor whiteColor]];
    [browser updateColorScheme];
}
static NSDictionary *DrawingAttributes(LinkingEditor *editor, NSUInteger index, NSRangePointer range) {
    NSLayoutManager *layout = [editor layoutManager];
    NSDictionary *temporary = [layout temporaryAttributesAtCharacterIndex:index effectiveRange:range];
    return [editor layoutManager:layout shouldUseTemporaryAttributes:temporary forDrawingToScreen:YES
        atCharacterIndex:index effectiveRange:range];
}
static void CheckBitmap(LinkingEditor *editor, NSRange characters, NSColor *foreground, NSColor *background, NSString *name) {
    NSLayoutManager *layout = [editor layoutManager];
    [layout ensureLayoutForTextContainer:[editor textContainer]];
    NSRange glyphs = [layout glyphRangeForCharacterRange:characters actualCharacterRange:NULL];
    NSRect rect = [layout boundingRectForGlyphRange:glyphs inTextContainer:[editor textContainer]];
    NSPoint origin = [editor textContainerOrigin];
    rect = NSIntegralRect(NSOffsetRect(rect, origin.x, origin.y));
    Check(!NSIsEmptyRect(rect) && NSContainsRect([editor visibleRect], rect), @"capture contains the visible text run");
    NSBitmapImageRep *bitmap = [editor bitmapImageRepForCachingDisplayInRect:rect];
    [editor cacheDisplayInRect:rect toBitmapImageRep:bitmap];
    NSUInteger matchingPixels = 0;
    for (NSInteger y = 0; y < [bitmap pixelsHigh]; y++) {
        for (NSInteger x = 0; x < [bitmap pixelsWide]; x++) {
            NSColor *pixel = [bitmap colorAtX:x y:y];
            if (ColorDistance(pixel, foreground) < .25 && ColorDistance(pixel, background) > .4) matchingPixels++;
        }
    }
    const char *artifacts = getenv("NV_RENDERING_ARTIFACTS");
    if (artifacts) {
        NSString *path = [[NSString stringWithUTF8String:artifacts] stringByAppendingPathComponent:[name stringByAppendingString:@".png"]];
        Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],
            @"editor bitmap artifact writes successfully");
    }
    NSLog(@"RENDERING_BITMAP %@ matching_pixels=%lu", name, (unsigned long)matchingPixels);
    Check(matchingPixels > 10, [name stringByAppendingString:@" contains visible glyphs in the expected foreground"]);
}
static void CheckEditor(AppController *browser, NSRange url, BOOL clickable, NSString *name) {
    LinkingEditor *editor = [browser valueForKey:@"textView"];
    NSTextStorage *storage = [editor textStorage];
    NSRange ordinary = [[editor string] rangeOfString:@"ordinary"];
    NSColor *linkColor = [[editor preferredLinkAttributes] objectForKey:NSForegroundColorAttributeName];
    Check(clickable ? linkColor != nil : linkColor == nil, @"link color follows the clickable URL preference");
    Check(clickable ? [[[editor linkTextAttributes] objectForKey:NSUnderlineStyleAttributeName] integerValue] == NSUnderlineStyleSingle :
        [[editor linkTextAttributes] count] == 0, @"clickable URLs retain their link appearance and disabled URLs use plain appearance");
    for (NSValue *value in @[[NSValue valueWithRange:ordinary], [NSValue valueWithRange:url]]) {
        NSRange characters = [value rangeValue];
        BOOL isURL = NSEqualRanges(characters, url);
        NSColor *expected = isURL && clickable ? linkColor : [browser foregrndColor];
        // The bitmap assertion exercises AppKit drawing before the delegate assertion.
        CheckBitmap(editor, characters, expected, [browser backgrndColor],
            [name stringByAppendingString:isURL ? @"-url" : @"-ordinary"]);
        NSRange range;
        NSDictionary *attributes = DrawingAttributes(editor, characters.location, &range);
        NSColor *effective = attributes[NSForegroundColorAttributeName] ?:
            [storage attribute:NSForegroundColorAttributeName atIndex:characters.location effectiveRange:NULL] ?: [NSColor blackColor];
        Check(ColorDistance(effective, expected) < .01,
            @"the editor uses its owning browser foreground or preferred link foreground");
        NSRange linkRange;
        [storage attribute:NSLinkAttributeName atIndex:characters.location effectiveRange:&linkRange];
        Check(NSLocationInRange(characters.location, range) && NSMaxRange(range) <= NSMaxRange(linkRange),
            @"temporary display attributes stop at each link boundary");
    }
    Check([storage attribute:NSLinkAttributeName atIndex:url.location effectiveRange:NULL] != nil,
        @"preference and color changes retain the parsed URL attribute");
}

@interface NSFileManager (NVRenderingTestPaths)
- (NSString *)nv_renderingSupportDirectory;
@end
@implementation NSFileManager (NVRenderingTestPaths)
- (NSString *)nv_renderingSupportDirectory { return [TestDirectory stringByAppendingPathComponent:@"Support"]; }
@end

@interface ODBEditor (NVRenderingIsolation)
- (void)nv_skipRenderingExternalEditorInitialization:(id)prefs;
@end
@implementation ODBEditor (NVRenderingIsolation)
- (void)nv_skipRenderingExternalEditorInitialization:(id)prefs { }
@end

@interface AppController (NVRenderingTests)
- (void)nv_renderingLaunch:(NSNotification *)notification;
- (void)nv_renderingDelayed;
- (void)nv_runRenderingTests;
@end
@implementation AppController (NVRenderingTests)
+ (void)load {
    const char *directory = getenv("NV_WINDOW_TEST_DIRECTORY");
    if (!directory) return;
    TestDirectory = [[NSString stringWithUTF8String:directory] copy];
    Swap(self, @selector(applicationDidFinishLaunching:), @selector(nv_renderingLaunch:));
    Swap(self, @selector(runDelayedUIActionsAfterLaunch), @selector(nv_renderingDelayed));
    Swap([NSFileManager class], @selector(applicationSupportDirectory), @selector(nv_renderingSupportDirectory));
    Swap([ODBEditor class], @selector(initializeDatabase:), @selector(nv_skipRenderingExternalEditorInitialization:));
}
- (void)nv_renderingDelayed { }
- (void)nv_renderingLaunch:(NSNotification *)notification {
    [self setupViewsAfterAppAwakened];
    FSRef directory;
    OSStatus err = FSPathMakeRef((const UInt8 *)[[TestDirectory stringByAppendingPathComponent:@"Notes"] fileSystemRepresentation], &directory, NULL);
    Check(err == noErr, @"temporary library directory exists");
    NotationController *library = [[[NotationController alloc] initWithDirectoryRef:&directory error:&err] autorelease];
    Check(library != nil && err == noErr, @"temporary library opens");
    [self setNotationController:library];
    [self prepareAdditionalWindow];
    [NSApp activateIgnoringOtherApps:YES];
    [[self window] makeKeyAndOrderFront:self];
    [self performSelector:@selector(nv_runRenderingTests) withObject:nil afterDelay:0.3];
}
- (void)nv_runRenderingTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        GlobalPrefs *prefs = [GlobalPrefs defaultPrefs];
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        Check(peer != self, @"two separate browser controllers exist");
        LinkingEditor *editor = [self valueForKey:@"textView"];
        LinkingEditor *peerEditor = [peer valueForKey:@"textView"];
        for (AppController *browser in @[self, peer]) {
            [[browser window] setContentSize:NSMakeSize(1000, 650)];
            [browser setNotesListHeight:120];
            [browser setUserColorScheme:browser];
            Check([[browser valueForKey:@"userScheme"] integerValue] == 2,
                @"the fixture uses explicit editor colors instead of automatic appearance colors");
        }
        NSString *body = @"ordinary https://example.invalid/path tail";
        NSRange url = [body rangeOfString:@"https://example.invalid/path"];
        for (NSNumber *typedClickable in @[@YES, @NO]) {
            ActivateBrowser(self);
            SetColors(self, NO); SetColors(peer, NO);
            [prefs setMakeURLsClickable:[typedClickable boolValue] sender:self];
            NoteObject *note = [[[NoteObject alloc] initWithNoteBody:[[[NSAttributedString alloc] initWithString:@"Replace this text"] autorelease]
                title:@"Typed URL rendering" delegate:library format:[library currentNoteStorageFormat] labels:@""] autorelease];
            [library addNewNote:note]; Pump();
            RevealFixtureNote(self, note);
            Check([[self window] makeFirstResponder:editor] && [[self window] firstResponder] == editor,
                @"the primary editor owns keyboard input before the typed replacement");
            TraceFixture(@"before-insert", self, note);
            [editor insertText:body replacementRange:NSMakeRange(0, [[editor string] length])]; Pump();
            TraceFixture(@"after-insert", self, note);
            Check([[editor string] isEqual:body], @"typed replacement reaches the primary editor");
            RevealFixtureNote(peer, note);
            Check([[peerEditor string] isEqual:body] && [[editor string] isEqual:body], @"the peer reveals the same typed body");
            Check([[editor textStorage] attribute:NSLinkAttributeName atIndex:url.location effectiveRange:NULL] != nil,
                @"editor insertion parses the URL with clickable URLs initially on or off");
            Check([editor textStorage] == [peerEditor textStorage], @"both browser editors share the same text storage");
            Check([[editor layoutManager] delegate] == editor && [[peerEditor layoutManager] delegate] == peerEditor,
                @"each browser editor owns its display delegate");
            NSAttributedString *storedBefore = [[[editor textStorage] copy] autorelease];
            NSData *archiveBefore = [NSKeyedArchiver archivedDataWithRootObject:[note contentString]];
            NSAttributedString *archivedBefore = [NSKeyedUnarchiver unarchiveObjectWithData:archiveBefore];
            NSColor *storedForeground = [storedBefore attribute:NSForegroundColorAttributeName atIndex:url.location effectiveRange:NULL] ?: [NSColor blackColor];
            Check(ColorDistance(storedForeground, [NSColor blackColor]) < .01, @"the typed URL starts with the stored black foreground");
            for (NSNumber *clickable in @[@NO, @YES, @NO]) {
                [prefs setMakeURLsClickable:[clickable boolValue] sender:self];
                for (NSNumber *dark in @[@NO, @YES]) {
                    SetColors(self, [dark boolValue]); SetColors(peer, ![dark boolValue]);
                    [editor removeHighlightedTerms]; [peerEditor removeHighlightedTerms];
                    [editor setSelectedRange:NSMakeRange([body length], 0)];
                    [peerEditor setSelectedRange:NSMakeRange([body length], 0)];
                    ActivateBrowser(peer);
                    [[self window] makeFirstResponder:[self valueForKey:@"notesTableView"]];
                    [[peer window] makeFirstResponder:[peer valueForKey:@"notesTableView"]]; Pump();
                    NSString *name = [NSString stringWithFormat:@"typed-%@-clickable-%@-primary-dark-%@", typedClickable, clickable, dark];
                    CheckEditor(self, url, [clickable boolValue], [name stringByAppendingString:@"-primary"]);
                    CheckEditor(peer, url, [clickable boolValue], [name stringByAppendingString:@"-peer"]);
                    [editor highlightTermsTemporarilyReturningFirstRange:[NSString stringWithFormat:@"\"%@\"", body] avoidHighlight:NO];
                    for (NSNumber *index in @[@0, @(url.location), @(NSMaxRange(url))]) {
                        NSRange range;
                        NSDictionary *temporary = [[editor layoutManager] temporaryAttributesAtCharacterIndex:[index unsignedIntegerValue] effectiveRange:&range];
                        NSColor *highlight = temporary[NSBackgroundColorAttributeName];
                        Check(highlight != nil, @"the editor creates a real search highlight across ordinary text and URL boundaries");
                        NSRange linkRange;
                        [[editor textStorage] attribute:NSLinkAttributeName atIndex:[index unsignedIntegerValue] effectiveRange:&linkRange];
                        NSRange expectedRange = NSIntersectionRange(range, linkRange);
                        NSDictionary *rendered = DrawingAttributes(editor, [index unsignedIntegerValue], &range);
                        Check([rendered[NSBackgroundColorAttributeName] isEqual:highlight] && NSEqualRanges(range, expectedRange),
                            @"foreground substitution retains the search background and exact link boundary");
                        Check([[peerEditor layoutManager] temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:[index unsignedIntegerValue]
                            effectiveRange:NULL] == nil, @"search highlights remain local to their browser layout");
                    }
                    Check([[editor textStorage] isEqualToAttributedString:storedBefore], @"color changes and display preserve the shared attributed text");
                    NSData *archiveAfter = [NSKeyedArchiver archivedDataWithRootObject:[note contentString]];
                    Check([[NSKeyedUnarchiver unarchiveObjectWithData:archiveAfter] isEqualToAttributedString:archivedBefore],
                        @"color changes and display preserve the archived note attributes");
                }
            }
        }
        NSDictionary *temporary = @{NSBackgroundColorAttributeName: [NSColor yellowColor]};
        NSRange range = NSMakeRange(0, [body length]);
        NSDictionary *printed = [editor layoutManager:[editor layoutManager] shouldUseTemporaryAttributes:temporary
            forDrawingToScreen:NO atCharacterIndex:url.location effectiveRange:&range];
        Check(printed == temporary && NSEqualRanges(range, NSMakeRange(0, [body length])),
            @"non-screen drawing leaves the caller attributes and range unchanged");
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"NATIVE RENDERING TESTS PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
@end
