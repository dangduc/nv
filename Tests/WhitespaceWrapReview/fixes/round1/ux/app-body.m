    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = app.library;
        [self searchForString:@""]; Pump();
        [[GlobalPrefs defaultPrefs] setNoteBodyFont:[NSFont fontWithName:@"Menlo-Regular" size:18] sender:self];
        NoteObject *note = MakeNote(library,@"Character-wrap fix review",@"");
        [self revealNote:note options:0]; Pump();
        LinkingEditor *view = [self valueForKey:@"textView"];
        [self.window setContentSize:NSMakeSize(560,640)];
        [self.window makeKeyAndOrderFront:self]; [self.window makeFirstResponder:view]; Pump();
        NSMutableArray *results = [NSMutableArray array];
        for (NSString *prefix in @[@"alpha beta",@"one two three four alpha beta"]) {
            NSUInteger count = 49-prefix.length;
            NSString *beforeSource = [prefix stringByAppendingString:[@"" stringByPaddingToLength:count withString:@" " startingAtIndex:0]];
            [note setContentString:[[[NSAttributedString alloc] initWithString:beforeSource] autorelease]]; Pump();
            Check([(NSParagraphStyle *)[view.textStorage attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL] lineBreakMode] == NSLineBreakByCharWrapping,
                @"production source attributes choose character wrapping");
            NSUInteger beta = [prefix rangeOfString:@"beta"].location;
            [view setSelectedRange:NSMakeRange(beforeSource.length,0)];
            NSDictionary *beforeWord = MarkerPoint(view,beta), *beforeCaret = NativeCaretPoint(view);
            Check([beforeWord[@"y"] doubleValue] == 0,@"existing final word fits on first line before Space");
            SendSpace(view,NO); Pump();
            Check([view.string isEqual:[beforeSource stringByAppendingString:@" "]] && NSEqualRanges(view.selectedRange,NSMakeRange(50,0)),
                @"actual Space appends only one ordinary source space");
            NSDictionary *afterWord = MarkerPoint(view,beta), *afterCaret = NativeCaretPoint(view);
            Check([beforeWord isEqual:afterWord],@"overflowing Space leaves existing final word in place");
            Check([afterCaret[@"y"] doubleValue] > [beforeCaret[@"y"] doubleValue] && [afterCaret[@"x"] doubleValue] < 30,
                @"overflowing Space advances caret near left edge of next line");
            [view deleteBackward:self]; Pump();
            Check([view.string isEqual:beforeSource] && NSEqualRanges(view.selectedRange,NSMakeRange(49,0)),@"native Backspace removes only the appended space");
            Check([MarkerPoint(view,beta) isEqual:beforeWord] && [NativeCaretPoint(view) isEqual:beforeCaret],@"Backspace restores caret without displacing the word");
            [results addObject:@{@"prefix":prefix,@"spacesBeforeKey":@(count),@"wordBefore":beforeWord,@"wordAfter":afterWord,
                @"caretBefore":beforeCaret,@"caretAfter":afterCaret,@"caretDeleted":NativeCaretPoint(view)}];
        }
        [note setContentString:[[[NSAttributedString alloc] initWithString:@""] autorelease]]; Pump();
        [view setSelectedRange:NSMakeRange(0,0)];
        for (NSUInteger i=0;i<201;i++) {
            SendSpace(view,i>0);
            Check(view.string.length==i+1 && NSEqualRanges(view.selectedRange,NSMakeRange(i+1,0)),@"repeated native Space preserves logical source position");
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
        }
        Pump();
        NSString *spaces = [@"" stringByPaddingToLength:201 withString:@" " startingAtIndex:0];
        Check([view.string isEqual:spaces] && [[[note contentString] string] isEqual:spaces],@"201 ordinary spaces reach source and note model");
        Check(NativeLineRecords(view).count>1 && [NativeCaretPoint(view)[@"y"] doubleValue]>view.textContainerInset.height,@"201 spaces wrap with caret on a later line");
        [results addObject:@{@"fixture":@"201 spaces",@"lines":NativeLineRecords(view),@"caret":NativeCaretPoint(view)}];
        [[GlobalPrefs defaultPrefs] setNoteBodyFont:[NSFont fontWithName:@"Helvetica" size:14] sender:self];
        NSString *proportional = [@"alpha beta" stringByAppendingString:spaces];
        [note setContentString:[[[NSAttributedString alloc] initWithString:proportional] autorelease]]; Pump();
        Check([MarkerPoint(view,6)[@"y"] doubleValue]==0 && NativeLineRecords(view).count>1,@"proportional font retains the fitting word while spaces wrap");
        NSParagraphStyle *style = [view.textStorage attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
        NSParagraphStyle *normal = [NSParagraphStyle defaultParagraphStyle];
        Check(style.lineBreakMode==NSLineBreakByCharWrapping && style.lineSpacing==normal.lineSpacing && [style.tabStops isEqual:normal.tabStops],
            @"font refresh keeps character wrapping and native line spacing and tab stops");
        [results addObject:@{@"fixture":@"Helvetica 14",@"lines":NativeLineRecords(view)}];
        [[GlobalPrefs defaultPrefs] setNoteBodyFont:[NSFont fontWithName:@"Menlo-Regular" size:18] sender:self];
        NSString *illustration = [NSString stringWithFormat:@"Ordinary spaces wrap naturally.\n\nStart>%@<End\n\nSource text is unchanged.",[@"" stringByPaddingToLength:151 withString:@" " startingAtIndex:0]];
        [note setContentString:[[[NSAttributedString alloc] initWithString:illustration] autorelease]];
        [self setNotesListHeight:65]; Pump(); Pump();
        [view setSelectedRange:NSMakeRange([illustration rangeOfString:@"<End"].location,0)];
        [view.layoutManager ensureLayoutForTextContainer:view.textContainer]; [self.window display];
        NSView *capture = self.window.contentView.superview;
        NSBitmapImageRep *bitmap = [capture bitmapImageRepForCachingDisplayInRect:capture.bounds];
        [capture cacheDisplayInRect:capture.bounds toBitmapImageRep:bitmap];
        Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithUTF8String:getenv("NV_REVIEW_CAPTURE")] atomically:YES],@"save actual disposable app screenshot");
        Check([[NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted error:NULL]
            writeToFile:[NSString stringWithUTF8String:getenv("NV_FIX_GEOMETRY")] atomically:YES],@"save exact production fix geometry");
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"CHAR WRAP UX FIX PASSED (%lu checks)",(unsigned long)Checks);
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) {
        NSLog(@"CHAR WRAP UX FIX EXCEPTION %@ %@\n%@",exception.name,exception.reason,exception.callStackSymbols);
        exit(1);
    }
}
@end
