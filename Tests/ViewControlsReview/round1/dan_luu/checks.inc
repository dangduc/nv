- (void)nv_runTests {
  @try {
    NVApplicationController *app = [NVApplicationController sharedController];
    NotationController *library = [app library];
    [prefsController setShowWordCount:YES]; // Legacy inverted preference: YES hides.
    NSMutableString *large = [NSMutableString string];
    for (NSUInteger i = 0; i < 20000; i++) [large appendString:@"alpha "];
    NoteObject *note = [MakeNote(library, @"Word count scaling", large) retain];
    [self revealNote:note options:0]; Pump();
    NSMutableArray *browsers = [NSMutableArray arrayWithObject:self];
    NSLog(@"MEASURE fixture characters=%lu words=20000", [large length]);
    for (NSUInteger target = 1; target <= 4; target *= 2) {
      while ([browsers count] < target) {
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        [peer revealNote:note options:0]; Pump(); [browsers addObject:peer];
      }
      Check([[app browserControllers] count] == target, @"fixture has the requested number of browser windows");
      for (AppController *browser in browsers) {
        Check([browser selectedNoteObject] == note, @"every window displays the same shared note");
        Check([browser valueForKey:@"previewController"] == nil, @"Source-only window has no preview provider");
      }
      for (NSUInteger repeat=0; repeat<2; repeat++) {
        CountCalls=LayoutCalls=0; CountMilliseconds=0;
        double start=[NSDate timeIntervalSinceReferenceDate];
        [prefsController setShowWordCount:NO];
        double elapsed=([NSDate timeIntervalSinceReferenceDate]-start)*1000;
        NSLog(@"MEASURE wordcount windows=%lu repeat=%lu calls=%lu count_ms=%.3f total_ms=%.3f layouts=%lu", target,repeat,CountCalls,CountMilliseconds,elapsed,LayoutCalls);
        Check(CountCalls == target, @"one global Word Count command counts once in each browser");
        for (AppController *browser in browsers)
          Check([[[browser valueForKey:@"wordCounter"] stringValue] isEqual:@"20000 words"], @"all windows show the correct shared note count");
        [prefsController setShowWordCount:YES]; Pump();
      }
      CountCalls=LayoutCalls=DisplayCalls=JSCalls=0; CountMilliseconds=0;
      double start=[NSDate timeIntervalSinceReferenceDate];
      for (NSUInteger repeat=0; repeat<10; repeat++) {
        [prefsController setShowTitleInTopSection:NO sender:nil];
        [prefsController setShowTagsInTopSection:NO sender:nil];
        [prefsController setShowBodyControlsInTopSection:NO sender:nil];
        [prefsController setShowTitleInTopSection:YES sender:nil];
        [prefsController setShowTagsInTopSection:YES sender:nil];
        [prefsController setShowBodyControlsInTopSection:YES sender:nil];
      }
      double elapsed=([NSDate timeIntervalSinceReferenceDate]-start)*1000;
      NSLog(@"MEASURE headers windows=%lu commands=60 layouts=%lu count_calls=%lu display_calls=%lu js_calls=%lu total_ms=%.3f",target,LayoutCalls,CountCalls,DisplayCalls,JSCalls,elapsed);
      Check(LayoutCalls == 60*target && CountCalls == 0, @"header toggles perform one layout per browser without word counting");
      Check(DisplayCalls == 0 && JSCalls == 0, @"Source-only header toggles perform no viewer renders or DOM reads");
      for (AppController *browser in browsers) Check([browser valueForKey:@"previewController"] == nil, @"header toggles keep Source-only preview unallocated");
      Pump();
    }
    // Separate single-browser count from global dispatch, using the same method and note.
    CountCalls=0; CountMilliseconds=0;
    [self updateWordCount:YES];
    NSLog(@"MEASURE single_browser_control attached_windows=4 count_calls=%lu count_ms=%.3f",CountCalls,CountMilliseconds);
    Check(CountCalls == 1, @"single-browser control actually executes one full count");
    NSUInteger expectedLayouts = [[[[app editingSessionForNote:note] textStorage] layoutManagers] count];
    Check(expectedLayouts == 4, @"word counting releases its temporary substring observers before return");
    // Already-created hidden provider must stay idle through header/list reflow.
    NoteObject *html = [MakeNote(library, @"Hidden viewer", @"<p>read only</p>") retain];
    [self nv_activateBrowser]; [self revealNote:html options:0]; Pump();
    NSMenuItem *viewerChoice = [[[NSMenuItem alloc] init] autorelease]; [viewerChoice setRepresentedObject:@"html"];
    [self selectPreviewMode:viewerChoice];
    PreviewController *provider = [self valueForKey:@"previewController"];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (([provider loading] || ![provider renderedHTML]) && [deadline timeIntervalSinceNow]>0) Pump();
    NSLog(@"VIEWER fixture provider=%@ selected=%@ mode=%d loading=%d error=%@ displays=%lu js=%lu",provider,[self selectedNoteObject],viewingNote,[provider loading],[provider renderError],DisplayCalls,JSCalls);
    Check(![provider loading] && [provider renderedHTML] != nil, @"control renders a real WKWebView before hiding it");
    [self setViewingNote:NO]; for(NSUInteger i=0;i<8;i++) Pump();
    CountCalls=LayoutCalls=DisplayCalls=JSCalls=0;
    for (NSUInteger repeat=0;repeat<4;repeat++) {
      [prefsController setShowTitleInTopSection:NO sender:nil]; [prefsController setShowNotesList:NO sender:nil];
      [prefsController setShowTitleInTopSection:YES sender:nil]; [prefsController setShowNotesList:YES sender:nil];
      Pump();
    }
    for(NSUInteger i=0;i<8;i++) Pump();
    NSLog(@"MEASURE hidden_viewer display_calls=%lu js_calls=%lu layout_calls=%lu",DisplayCalls,JSCalls,LayoutCalls);
    Check(DisplayCalls==0 && JSCalls==0, @"hidden preview remains idle during header and notes list changes");
    Check([[[note contentString] string] isEqual:large], @"layout and word count commands preserve exact source characters");
    [html release]; [note release];
    NSLog(@"DAN LUU REVIEW PASSED: %lu checks",Checks);
    [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.1];
  } @catch (NSException *exception) { NSLog(@"FAIL exception: %@",exception); exit(1); }
}
