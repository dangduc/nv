#import "AppController_Preview.h"
#import "PreviewController.h"
#import "NVNoteContentSnapshot.h"
#import "NVNoteEditingSession.h"
#import "NoteObject.h"
#import "NotationPrefs.h"
#import "LinkingEditor.h"
#import "ETNoteScrollView.h"
#import "EmptyView.h"
#import "NSString_NV.h"

static NSString *NotePresentationKey(NoteObject *note) {
    return note ? [NSString uuidStringWithBytes:*[note uniqueNoteIDBytes]] : nil;
}

@implementation AppController (Preview)
- (BOOL)isViewingNote { return viewingNote; }
- (NSString *)selectedViewerIdentifier { return selectedViewerIdentifier; }

- (void)setupBodyPresentation {
    CGFloat y = NSHeight([splitSubview bounds]) - 88;
    bodyModeControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(14, y, 154, 24)];
    [bodyModeControl setSegmentCount:2];
    [bodyModeControl setLabel:NSLocalizedString(@"Source", nil) forSegment:0];
    [bodyModeControl setLabel:NSLocalizedString(@"Preview", nil) forSegment:1];
    [bodyModeControl setTrackingMode:NSSegmentSwitchTrackingSelectOne];
    [bodyModeControl setTarget:self]; [bodyModeControl setAction:@selector(selectBodyMode:)];
    [bodyModeControl setAutoresizingMask:NSViewMinYMargin];
    [bodyModeControl setAccessibilityLabel:NSLocalizedString(@"Note mode", nil)];
    [splitSubview addSubview:bodyModeControl];
    sourceSyntaxControl = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(178, y, 190, 24) pullsDown:NO];
    viewerTypeControl = [[NSPopUpButton alloc] initWithFrame:[sourceSyntaxControl frame] pullsDown:NO];
    for (NSPopUpButton *control in @[sourceSyntaxControl, viewerTypeControl]) {
        [control setAutoresizingMask:NSViewMinYMargin]; [control setTarget:self];
        [splitSubview addSubview:control];
    }
    for (NSArray *entry in @[@[@"Plain Text", @"plain"], @[@"Markdown", @"markdown"], @[@"Textile", @"textile"], @[@"HTML", @"html"], @[@"JSON", @"json"], @[@"Org", @"org"]]) {
        [sourceSyntaxControl addItemWithTitle:NSLocalizedString(entry[0], nil)];
        [[sourceSyntaxControl lastItem] setRepresentedObject:entry[1]];
    }
    for (NSArray *entry in @[@[@"Markdown", @"markdown"], @[@"Textile", @"textile"], @[@"HTML", @"html"]]) {
        [viewerTypeControl addItemWithTitle:NSLocalizedString(entry[0], nil)];
        [[viewerTypeControl lastItem] setRepresentedObject:entry[1]];
    }
    [sourceSyntaxControl setAction:@selector(selectSourceSyntax:)];
    [sourceSyntaxControl setAccessibilityLabel:NSLocalizedString(@"Source syntax", nil)];
    [sourceSyntaxControl setToolTip:NSLocalizedString(@"Source syntax controls highlighting and insertion commands.", nil)];
    [viewerTypeControl setAction:@selector(selectPreviewMode:)];
    [viewerTypeControl setAccessibilityLabel:NSLocalizedString(@"Preview format", nil)];
    [viewerTypeControl setToolTip:NSLocalizedString(@"Preview format does not change the note source.", nil)];
    [self updateBodyPresentation];
}

- (void)captureBodyPresentation {
    NSString *key = NotePresentationKey(currentNote);
    if (!key) return;
    NSMutableDictionary *state = [[[noteBodyStates objectForKey:key] mutableCopy] autorelease] ?: [NSMutableDictionary dictionary];
    // Hidden source layouts can clamp their clip origin while notes change.
    // That display work does not change the user's saved Source position.
    if (!viewingNote || ![state objectForKey:@"sourceScroll"])
        [state setObject:NSStringFromPoint([[textScrollView contentView] bounds].origin) forKey:@"sourceScroll"];
    BOOL pendingLoadingCapture = viewingNote && [previewController loading] &&
        [previewController hasPendingViewerStateCaptureForSnapshot:[previewController snapshot] viewerIdentifier:[previewController viewerIdentifier]];
    // A return still waiting for its exact read has no newer cache to save.
    if (viewingNote && previewController && !pendingLoadingCapture) {
        NSMutableDictionary *viewers = [[[state objectForKey:@"viewers"] mutableCopy] autorelease] ?: [NSMutableDictionary dictionary];
        [viewers setObject:[previewController viewerState] ?: @{} forKey:selectedViewerIdentifier];
        [state setObject:viewers forKey:@"viewers"];
    }
    [noteBodyStates setObject:state forKey:key];
    if (viewingNote && previewController) {
        NSUInteger stateGeneration = presentationStateGeneration;
        NVNoteContentSnapshot *requestedSnapshot = [previewController snapshot];
        NSArray *requestKey = @[[requestedSnapshot libraryIdentifier] ?: @"", [requestedSnapshot noteIdentifier] ?: @"", [previewController viewerIdentifier] ?: @""];
        id request = [[[NSObject alloc] init] autorelease];
        if (!viewerStateCaptureRequests) viewerStateCaptureRequests = [[NSMutableDictionary alloc] init];
        [viewerStateCaptureRequests setObject:request forKey:requestKey];
        [previewController captureViewerStateWithCompletion:^(NVNoteContentSnapshot *snapshot, NSString *identifier, NSDictionary *viewerState) {
            if ([viewerStateCaptureRequests objectForKey:requestKey] != request || stateGeneration != presentationStateGeneration) return;
            NSString *libraryIdentifier = [[[[self sharedNotationController] notesDirectoryURL] URLByResolvingSymlinksInPath] path];
            if (![[snapshot libraryIdentifier] isEqual:libraryIdentifier] ||
                ![[snapshot noteIdentifier] length] || ![identifier length]) return;
            NSString *capturedKey = [snapshot noteIdentifier];
            NSMutableDictionary *capturedState = [[[noteBodyStates objectForKey:capturedKey] mutableCopy] autorelease] ?: [NSMutableDictionary dictionary];
            NSMutableDictionary *viewers = [[[capturedState objectForKey:@"viewers"] mutableCopy] autorelease] ?: [NSMutableDictionary dictionary];
            [viewers setObject:viewerState ?: @{} forKey:identifier];
            [capturedState setObject:viewers forKey:@"viewers"];
            [noteBodyStates setObject:capturedState forKey:capturedKey];
        }];
    }
}
- (void)restoreSourceScroll {
    if (!currentNote) return;
    NSString *scroll = [[noteBodyStates objectForKey:NotePresentationKey(currentNote)] objectForKey:@"sourceScroll"];
    if ([scroll isKindOfClass:[NSString class]]) {
        NSPoint point = NSPointFromString(scroll);
        // A hidden editor can still have the previous short note's height.
        // Lay out through the saved viewport before AppKit clamps the origin.
        if (!viewingNote && (point.x > 0 || point.y > 0))
            [[textView layoutManager] ensureLayoutForBoundingRect:NSMakeRect(0, 0, point.x + NSWidth([textView bounds]), point.y + NSHeight([[textScrollView contentView] bounds])) inTextContainer:[textView textContainer]];
        [textView scrollPoint:point];
    }
}
- (void)updateBodyPresentation {
    BOOL hasNote = currentNote != nil;
    [bodyModeControl setEnabled:hasNote]; [bodyModeControl setSelectedSegment:viewingNote ? 1 : 0];
    [sourceSyntaxControl setEnabled:hasNote]; [viewerTypeControl setEnabled:hasNote];
    [sourceSyntaxControl selectItemAtIndex:[sourceSyntaxControl indexOfItemWithRepresentedObject:hasNote ? [currentNote sourceSyntaxIdentifier] : @"plain"]];
    [viewerTypeControl selectItemAtIndex:[viewerTypeControl indexOfItemWithRepresentedObject:selectedViewerIdentifier]];
    [textScrollView setHidden:viewingNote || !hasNote]; [editorStatusView setHidden:hasNote];
    if (viewingNote && hasNote) {
        if (!previewController) {
            previewController = [[PreviewController alloc] init];
            NSView *viewer = [previewController view];
            [viewer setFrame:[textScrollView frame]];
            [viewer setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
            [splitSubview addSubview:viewer];
        }
        [[previewController view] setHidden:NO];
    } else [[previewController view] setHidden:YES];
    [self layoutNoteHeader];
    [toolbar validateVisibleItems];
}
- (void)setViewingNote:(BOOL)viewing {
    if ((viewing && !currentNote) || viewingNote == viewing) return;
    [self captureBodyPresentation];
    if (viewing) {
        // Finalize only the editor being hidden. A peer's composition can defer
        // the shared commit; the viewer then uses the last committed note body.
        if ([textView hasMarkedText]) [textView unmarkText];
        [editingSession commitPendingTextChanges];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"TextFinderShouldHide" object:self];
    }
    viewingNote = viewing;
    [self updateBodyPresentation];
    if (viewing) [self updateViewerSnapshot];
    else {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateViewerSnapshot) object:nil];
        [previewController cancelRendering]; [self restoreSourceScroll];
    }
}
- (void)focusNoteBody {
    [window makeFirstResponder:viewingNote && currentNote ? [previewController webView] : (NSView *)textView];
}
- (IBAction)selectBodyMode:(id)sender {
    [self setViewingNote:[bodyModeControl selectedSegment] == 1]; [self focusNoteBody];
}
- (IBAction)togglePreview:(id)sender { [self setViewingNote:!viewingNote]; [self focusNoteBody]; }
- (IBAction)toggleSourcePreview:(id)sender { [self togglePreview:sender]; }
- (IBAction)toggleSourceView:(id)sender { [self setViewingNote:NO]; [self focusNoteBody]; }
- (void)ensurePreviewIsVisible { [self setViewingNote:YES]; }
- (IBAction)selectSourceSyntax:(id)sender {
    if (!currentNote) return;
    NSString *syntax = [sender isKindOfClass:[NSPopUpButton class]] ? [[sender selectedItem] representedObject] : [sender representedObject];
    if ([syntax isKindOfClass:[NSString class]]) [currentNote setSourceSyntaxIdentifier:syntax];
    [self updateBodyPresentation];
}
- (void)sourceSyntaxChanged:(NSNotification *)notification {
    if ([notification object] != currentNote) return;
    [self updateBodyPresentation]; [self postTextUpdate];
}
- (IBAction)selectPreviewMode:(id)sender {
    NSString *identifier = [sender isKindOfClass:[NSPopUpButton class]] ? [[sender selectedItem] representedObject] : [sender representedObject];
    if (![@[@"markdown", @"textile", @"html"] containsObject:identifier]) return;
    [self captureBodyPresentation];
    [selectedViewerIdentifier release]; selectedViewerIdentifier = [identifier copy];
    if (viewingNote) { [self updateBodyPresentation]; [self updateViewerSnapshot]; }
    else [self setViewingNote:YES];
    [self focusNoteBody];
}
- (void)postTextUpdate {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"TextViewHasChangedContents" object:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateViewerSnapshot) object:nil];
    if (viewingNote && currentNote) [self performSelector:@selector(updateViewerSnapshot) withObject:nil afterDelay:0.12];
}
- (void)updateViewerSnapshot {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateViewerSnapshot) object:nil];
    if (!viewingNote || !currentNote) return;
    [self updateBodyPresentation];
    NSURL *libraryURL = [[[self sharedNotationController] notesDirectoryURL] URLByResolvingSymlinksInPath];
    NSString *notePath = [[self sharedNotationController] currentNoteStorageFormat] == PlainTextFormat ? [currentNote noteFilePath] : nil;
    NSURL *assetRoot = [notePath length] ? [NSURL fileURLWithPath:[notePath stringByDeletingLastPathComponent] isDirectory:YES] : libraryURL;
    NSString *libraryIdentifier = [libraryURL path];
    if (!libraryIdentifier) return;
    NVNoteContentSnapshot *snapshot = [[[NVNoteContentSnapshot alloc]
        initWithLibraryIdentifier:libraryIdentifier
        noteIdentifier:NotePresentationKey(currentNote) generation:++viewerGeneration
        title:titleOfNote(currentNote) source:[[currentNote contentString] string]
        contentType:[currentNote sourceSyntaxIdentifier] assetRootURL:assetRoot] autorelease];
    NVNoteContentSnapshot *previous = [previewController snapshot];
    BOOL changedPresentation = ![[previous libraryIdentifier] isEqual:libraryIdentifier] ||
        ![[previous noteIdentifier] isEqual:NotePresentationKey(currentNote)] ||
        ![[previewController viewerIdentifier] isEqual:selectedViewerIdentifier];
    NSDictionary *state = changedPresentation ?
        [[[noteBodyStates objectForKey:NotePresentationKey(currentNote)] objectForKey:@"viewers"] objectForKey:selectedViewerIdentifier] : nil;
    [previewController displaySnapshot:snapshot viewerIdentifier:selectedViewerIdentifier];
    // A rapid A → B → A can return before A's exact DOM capture completes.
    // Its navigation barrier will install that result; cached restoration here
    // would supersede the outstanding capture with older state.
    if (changedPresentation && ![previewController hasPendingViewerStateCaptureForSnapshot:snapshot viewerIdentifier:selectedViewerIdentifier])
        [previewController restoreViewerState:state ?: @{}];
}
- (void)discardViewer {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateViewerSnapshot) object:nil];
    [viewerStateCaptureRequests release]; viewerStateCaptureRequests = nil;
    [previewController close]; [[previewController view] removeFromSuperview];
    [previewController release]; previewController = nil;
}
- (IBAction)savePreview:(id)sender { [self ensurePreviewIsVisible]; [previewController saveHTML:sender]; }
- (IBAction)printPreview:(id)sender { [self ensurePreviewIsVisible]; [previewController printPreview:sender]; }
- (IBAction)performFindPanelAction:(id)sender {
    if (viewingNote) [previewController performFindPanelAction:sender];
    else [textView performFindPanelAction:sender];
}
@end
