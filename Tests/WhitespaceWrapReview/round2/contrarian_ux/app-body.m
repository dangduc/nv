    @try {
        NVApplicationController *app=[NVApplicationController sharedController];
        NotationController *library=app.library;
        [self searchForString:@""]; Pump();
        NoteObject *note=MakeNote(library,@"Native navigation review",@"");
        [self revealNote:note options:0]; Pump();
        LinkingEditor *view=[self valueForKey:@"textView"];
        NSArray *settings=@[
            @{@"font":@"Menlo-Regular",@"size":@12,@"width":@480},
            @{@"font":@"Menlo-Regular",@"size":@22,@"width":@480},
            @{@"font":@"Menlo-Regular",@"size":@18,@"width":@560},
            @{@"font":@"Helvetica",@"size":@14,@"width":@480}];
        NSString *source=[NSString stringWithFormat:@"alpha beta%@tail\nlast line",[@"" stringByPaddingToLength:151 withString:@" " startingAtIndex:0]];
        NSMutableArray *results=[NSMutableArray array];
        for(NSDictionary *setting in settings) {
            [[GlobalPrefs defaultPrefs] setNoteBodyFont:[NSFont fontWithName:setting[@"font"] size:[setting[@"size"] doubleValue]] sender:self];
            [self.window setContentSize:NSMakeSize([setting[@"width"] doubleValue],640)];
            [note setContentString:[[[NSAttributedString alloc] initWithString:source] autorelease]]; Pump();
            [self.window makeKeyAndOrderFront:self]; [self.window makeFirstResponder:view];
            Check(self.window.firstResponder==view,@"actual source editor receives native navigation keys");
            [view setSelectedRange:NSMakeRange(0,0)];
            NSDictionary *previous=NativeCaretPoint(view);
            NSUInteger wraps=0;
            for(NSUInteger index=1;index<=source.length;index++) {
                NavigationKey(view,NSRightArrowFunctionKey,124,0);
                NSDictionary *current=NativeCaretPoint(view);
                Check(NSEqualRanges(view.selectedRange,NSMakeRange(index,0)),@"Right advances exactly one source character");
                Check(MovesForward(previous,current) && CaretInHorizontalBounds(view,current),@"Right caret advances monotonically within editor width");
                if([current[@"y"] doubleValue]>[previous[@"y"] doubleValue]) wraps++;
                previous=current;
            }
            Check(wraps>1,@"native Right crosses several visual wrap boundaries");
            for(NSUInteger index=source.length;index>0;index--) {
                NavigationKey(view,NSLeftArrowFunctionKey,123,0);
                NSDictionary *current=NativeCaretPoint(view);
                Check(NSEqualRanges(view.selectedRange,NSMakeRange(index-1,0)),@"Left retreats exactly one source character");
                Check(MovesForward(current,previous) && CaretInHorizontalBounds(view,current),@"Left caret retreats monotonically within editor width");
                previous=current;
            }
            NSArray *lines=NativeLineRecords(view);
            NSMutableArray *hits=[NSMutableArray array];
            for(NSDictionary *line in lines) {
                NSUInteger start=[line[@"location"] unsignedIntegerValue],end=start+[line[@"length"] unsignedIntegerValue];
                for(NSNumber *position in @[@(start),@(end-1),@(end)]) {
                    NSUInteger index=position.unsignedIntegerValue;
                    if(index>=source.length || [source characterAtIndex:index]!=' ') continue;
                    NSRect screen=[view firstRectForCharacterRange:NSMakeRange(index,0) actualRange:NULL];
                    NSPoint local=[view convertPoint:[self.window convertPointFromScreen:NSMakePoint(NSMinX(screen)+0.1,NSMidY(screen))] fromView:nil];
                    NSUInteger hit=[view characterIndexForInsertionAtPoint:local];
                    Check(hit==index,@"native hit test identifies space at either side of visual wrap");
                    [hits addObject:@{@"index":@(index),@"hit":@(hit),@"x":@(local.x),@"y":@(local.y)}];
                }
            }
            NSUInteger boundary=[lines[0][@"length"] unsignedIntegerValue];
            [view setSelectedRange:NSMakeRange(boundary-1,0)];
            for(NSUInteger n=1;n<=3;n++) {
                NavigationKey(view,NSRightArrowFunctionKey,124,NSEventModifierFlagShift);
                Check(NSEqualRanges(view.selectedRange,NSMakeRange(boundary-1,n)),@"Shift-Right selects spaces across wrap boundary");
            }
            for(NSUInteger n=3;n>0;n--) {
                NavigationKey(view,NSLeftArrowFunctionKey,123,NSEventModifierFlagShift);
                Check(NSEqualRanges(view.selectedRange,NSMakeRange(boundary-1,n-1)),@"Shift-Left contracts selection across wrap boundary");
            }
            [view setSelectedRange:NSMakeRange(boundary+3,0)];
            NavigationKey(view,NSLeftArrowFunctionKey,123,NSEventModifierFlagCommand);
            NSUInteger beginning=view.selectedRange.location;
            Check(beginning==boundary,@"Command-Left moves to visual line beginning");
            NavigationKey(view,NSRightArrowFunctionKey,124,NSEventModifierFlagCommand);
            NSUInteger ending=view.selectedRange.location;
            NSUInteger expectedEnd=boundary+[lines[1][@"length"] unsignedIntegerValue];
            while(expectedEnd>boundary && [[NSCharacterSet newlineCharacterSet] characterIsMember:[source characterAtIndex:expectedEnd-1]]) expectedEnd--;
            Check(ending==expectedEnd,@"Command-Right moves to visual line end before a hard newline");
            NSRange beforeHome=view.selectedRange;
            NavigationKey(view,NSHomeFunctionKey,115,0); NSRange afterHome=view.selectedRange;
            NavigationKey(view,NSEndFunctionKey,119,0); NSRange afterEnd=view.selectedRange;
            Check(NSMaxRange(afterHome)<=source.length && NSMaxRange(afterEnd)<=source.length,@"native Home and End keep logical selection in source bounds");
            Check([view.string isEqual:source] && [[[note contentString] string] isEqual:source],@"all navigation and selection operations preserve exact source and model");
            [results addObject:@{@"setting":setting,@"visualLines":@(lines.count),@"rightLineTransitions":@(wraps),@"hitTests":hits,
                @"lineBeginning":@(beginning),@"lineEnd":@(ending),@"beforeHome":NSStringFromRange(beforeHome),
                @"afterHome":NSStringFromRange(afterHome),@"afterEnd":NSStringFromRange(afterEnd)}];
        }
        Check([[NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted error:NULL]
            writeToFile:[NSString stringWithUTF8String:getenv("NV_NAVIGATION_RESULT")] atomically:YES],@"save observed native navigation results");
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"ROUND2 UX NAVIGATION PASSED (%lu checks)",(unsigned long)Checks);
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];exit(0);
    } @catch(NSException *exception) {
        NSLog(@"ROUND2 UX NAVIGATION EXCEPTION %@ %@\n%@",exception.name,exception.reason,exception.callStackSymbols);exit(1);
    }
}
@end
