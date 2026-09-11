    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = app.library;
        [self searchForString:@""]; Pump();
        NoteObject *note = MakeNote(library,@"Whitespace UX review",@"");
        [note setSourceSyntaxIdentifier:@"plain"];
        [self revealNote:note options:0]; Pump();
        LinkingEditor *view = [self valueForKey:@"textView"];
        [self.window makeKeyAndOrderFront:self];
        [self.window makeFirstResponder:view];
        NSString *gap = [@"" stringByPaddingToLength:151 withString:@" " startingAtIndex:0];
        NSArray *fixtures = @[
            @{@"name":@"arrow-observation", @"source":[NSString stringWithFormat:@"Start →%@← End",gap]},
            @{@"name":@"ordinary-prose", @"source":[@"" stringByPaddingToLength:450 withString:@"alpha beta gamma delta epsilon zeta eta theta. " startingAtIndex:0]},
            @{@"name":@"double-spaced-prose", @"source":[@"" stringByPaddingToLength:450 withString:@"alpha  beta  gamma  delta  epsilon  zeta  eta.  " startingAtIndex:0]},
            @{@"name":@"word-before-gap", @"source":[NSString stringWithFormat:@"alpha beta%@omega",gap]},
            @{@"name":@"unbroken-prefix", @"source":[NSString stringWithFormat:@"Start→%@←End",gap]},
            @{@"name":@"spaces-only", @"source":gap},
            @{@"name":@"tabs-and-nbsp", @"source":[@"" stringByPaddingToLength:200 withString:@"alpha\tbeta\u00a0gamma\n" startingAtIndex:0]}
        ];
        NSArray *fonts = @[@{@"name":@"Menlo-Regular",@"size":@12},@{@"name":@"Menlo-Regular",@"size":@18},
            @{@"name":@"Menlo-Regular",@"size":@22},@{@"name":@"Helvetica",@"size":@14}];
        NSMutableArray *results = [NSMutableArray array];
        for (NSDictionary *fontSpec in fonts) {
            NSFont *font = [NSFont fontWithName:fontSpec[@"name"] size:[fontSpec[@"size"] doubleValue]];
            Check(font != nil,@"fixture font exists");
            [[GlobalPrefs defaultPrefs] setNoteBodyFont:font sender:self];
            for (NSNumber *width in @[@480,@560,@700]) {
                [self.window setContentSize:NSMakeSize(width.doubleValue,640)];
                Pump();
                for (NSDictionary *fixture in fixtures) {
                    NSString *source = fixture[@"source"];
                    [note setContentString:[[[NSAttributedString alloc] initWithString:source] autorelease]];
                    Pump();
                    Check([view.string isEqual:source], @"fixture reaches actual editor source");
                    NSArray *lines = NativeLineRecords(view);
                    NSMutableDictionary *record = [NSMutableDictionary dictionaryWithDictionary:@{
                        @"fixture":fixture[@"name"],@"font":fontSpec[@"name"],@"size":fontSpec[@"size"],@"width":width,
                        @"containerWidth":@(view.textContainer.size.width),@"lines":lines}];
                    if ([fixture[@"name"] isEqual:@"arrow-observation"]) {
                        record[@"start"] = MarkerPoint(view,0);
                        record[@"rightArrow"] = MarkerPoint(view,[source rangeOfString:@"→"].location);
                        record[@"leftArrow"] = MarkerPoint(view,[source rangeOfString:@"←"].location);
                    }
                    if ([fontSpec[@"name"] isEqual:@"Menlo-Regular"] && [fontSpec[@"size"] isEqual:@18] && [width isEqual:@560] &&
                        ([fixture[@"name"] isEqual:@"arrow-observation"] || [fixture[@"name"] isEqual:@"spaces-only"])) {
                        [view setSelectedRange:NSMakeRange(0,0)];
                        for (NSUInteger i=0;i<source.length;i++) {
                            [view moveRight:self];
                            Check(NSEqualRanges(view.selectedRange,NSMakeRange(i+1,0)),@"native Right visits every source position");
                        }
                        for (NSUInteger i=source.length;i>0;i--) {
                            [view moveLeft:self];
                            Check(NSEqualRanges(view.selectedRange,NSMakeRange(i-1,0)),@"native Left visits every source position");
                        }
                        NSMutableArray *hitTests = [NSMutableArray array];
                        for (NSDictionary *line in lines) {
                            NSUInteger start = [line[@"location"] unsignedIntegerValue];
                            NSUInteger length = [line[@"length"] unsignedIntegerValue];
                            NSUInteger index = start + MIN((NSUInteger)3,length-1);
                            NSRect rect = [view firstRectForCharacterRange:NSMakeRange(index,0) actualRange:NULL];
                            NSPoint point = [view convertPoint:[self.window convertPointFromScreen:NSMakePoint(NSMinX(rect)+0.1,NSMidY(rect))] fromView:nil];
                            NSUInteger hit = [view characterIndexForInsertionAtPoint:point];
                            [hitTests addObject:@{@"index":@(index),@"hit":@(hit)}];
                        }
                        record[@"hitTests"] = hitTests;
                        Check([view.string isEqual:source] && [[[note contentString] string] isEqual:source],@"native navigation leaves source and model intact");
                    }
                    [results addObject:record];
                }
            }
        }
        [[GlobalPrefs defaultPrefs] setNoteBodyFont:[NSFont fontWithName:@"Menlo-Regular" size:18] sender:self];
        [self.window setContentSize:NSMakeSize(560,640)]; Pump();
        for (NSUInteger count=0;count<=55;count++) {
            NSString *spaces = [@"" stringByPaddingToLength:count withString:@" " startingAtIndex:0];
            NSString *source = [@"alpha beta" stringByAppendingString:spaces];
            [note setContentString:[[[NSAttributedString alloc] initWithString:source] autorelease]]; Pump();
            NSArray *lines = NativeLineRecords(view);
            Check([view.string isEqual:source],@"threshold fixture preserves exact source");
            [results addObject:@{@"fixture":@"appended-space-threshold",@"font":@"Menlo-Regular",@"size":@18,@"width":@560,
                @"spaceCount":@(count),@"lines":lines,@"beta":MarkerPoint(view,6)}];
        }
        NSString *beforeKey = [@"alpha beta" stringByAppendingString:[@"" stringByPaddingToLength:39 withString:@" " startingAtIndex:0]];
        [note setContentString:[[[NSAttributedString alloc] initWithString:beforeKey] autorelease]]; Pump();
        [self.window makeKeyAndOrderFront:self]; [self.window makeFirstResponder:view];
        [view setSelectedRange:NSMakeRange(beforeKey.length,0)];
        NSMutableDictionary *keyRecord = [NSMutableDictionary dictionaryWithDictionary:@{
            @"fixture":@"native-space-key",@"font":@"Menlo-Regular",@"size":@18,@"width":@560,
            @"beforeBeta":MarkerPoint(view,6),@"beforeCaret":NativeCaretPoint(view)}];
        NSEvent *spaceEvent = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
            timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:self.window.windowNumber context:nil
            characters:@" " charactersIgnoringModifiers:@" " isARepeat:NO keyCode:49];
        [NSApp sendEvent:spaceEvent]; Pump();
        Check([view.string isEqual:[beforeKey stringByAppendingString:@" "]] && NSEqualRanges(view.selectedRange,NSMakeRange(50,0)),
            @"native Space appends the 40th trailing space");
        keyRecord[@"afterBeta"] = MarkerPoint(view,6); keyRecord[@"afterCaret"] = NativeCaretPoint(view);
        keyRecord[@"afterLines"] = NativeLineRecords(view);
        [view deleteBackward:self]; Pump();
        Check([view.string isEqual:beforeKey] && NSEqualRanges(view.selectedRange,NSMakeRange(49,0)),@"native Backspace removes only the new space");
        keyRecord[@"deletedBeta"] = MarkerPoint(view,6); keyRecord[@"deletedCaret"] = NativeCaretPoint(view);
        [results addObject:keyRecord];
        NSData *data = [NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted error:NULL];
        Check([data writeToFile:[NSString stringWithUTF8String:getenv("NV_UX_RESULT")] atomically:YES], @"write actual native layout records");
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"CONTRARIAN UX WRAP REVIEW PASSED (%lu checks)",(unsigned long)Checks);
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) {
        NSLog(@"CONTRARIAN UX WRAP REVIEW EXCEPTION %@ %@\n%@",exception.name,exception.reason,exception.callStackSymbols);
        exit(1);
    }
}
@end
