    @try {
        NVApplicationController *app=[NVApplicationController sharedController];
        NotationController *library=app.library;
        [self searchForString:@""]; Pump();
        for(NSString *name in @[@"keyDown:",@"insertText:replacementRange:",@"deleteBackward:"]) {
            SEL selector=NSSelectorFromString(name);
            Check(class_getMethodImplementation([LinkingEditor class],selector)==class_getMethodImplementation([NSTextView class],selector),@"the source editor inherits the native key and deletion implementation");
        }
        LinkingEditor *view=[self valueForKey:@"textView"];
        NSArray *settings=@[@{@"font":@"Menlo-Regular",@"size":@18,@"width":@560},
            @{@"font":@"Helvetica",@"size":@14,@"width":@470},
            @{@"font":@"Menlo-Regular",@"size":@26,@"width":@620}];
        NSMutableArray *results=[NSMutableArray array];
        NSUInteger totalKeys=0;
        for(NSDictionary *setting in settings) {
            NSFont *font=[NSFont fontWithName:setting[@"font"] size:[setting[@"size"] doubleValue]];
            [[GlobalPrefs defaultPrefs] setNoteBodyFont:font sender:self];
            NoteObject *note=MakeNote(library,@"Empty source key repeat",@"");
            [note setSourceSyntaxIdentifier:@"plain"];
            [self revealNote:note options:0]; Pump();
            [self.window setContentSize:NSMakeSize([setting[@"width"] doubleValue],640)];
            [self.window makeKeyAndOrderFront:self]; [self.window makeFirstResponder:view];
            [view setSelectedRange:NSMakeRange(0,0)]; Pump();
            Check(self.window.firstResponder==view && !view.hidden && [self.browserSession.searchString length]==0,@"the visible source editor has focus with an empty search field");
            Check([note.sourceSyntaxIdentifier isEqual:@"plain"] && view.string.length==0,@"the repeat sequence starts in an empty plain-text note");
            NSMutableString *expected=[NSMutableString string];
            NSMutableArray *carets=[NSMutableArray arrayWithObject:NativeCaretPoint(view)];
            NSMutableArray *transitions=[NSMutableArray array];
            NSUInteger lastTransition=0;
            for(NSUInteger n=1;n<=600;n++) {
                TypingKey(view,' ',49,n>1); totalKeys++;
                [expected appendString:@" "];
                NSDictionary *current=NativeCaretPoint(view),*previous=carets.lastObject;
                Check([view.string isEqual:expected] && NSEqualRanges(view.selectedRange,NSMakeRange(n,0)),@"repeated native Space appends one ordinary space at the exact logical position");
                Check(MovesForward(previous,current) && CaretInHorizontalBounds(view,current),@"Space advances the queried caret forward within the editor width");
                if([current[@"y"] doubleValue]>[previous[@"y"] doubleValue]+0.01) {
                    Check([current[@"x"] doubleValue]<view.textContainerInset.width+[font advancementForGlyph:[font glyphWithName:@"space"]].width*2+12,@"overflowing Space resumes near the left edge of the next visual line");
                    [transitions addObject:@{@"count":@(n),@"before":previous,@"after":current}];
                    lastTransition=n;
                }
                [carets addObject:current];
                if(transitions.count>=3 && n>=lastTransition+3) break;
            }
            Check(transitions.count>=3,@"empty-note Space repeat crosses three observed wrap thresholds");
            [self finishEditing];
            Check([[[note contentString] string] isEqual:expected],@"repeated spaces commit unchanged to the note model");
            NSUInteger count=expected.length;
            for(NSUInteger n=count;n>0;n--) {
                TypingKey(view,NSDeleteCharacter,51,n<count); totalKeys++;
                [expected deleteCharactersInRange:NSMakeRange(n-1,1)];
                Check([view.string isEqual:expected] && NSEqualRanges(view.selectedRange,NSMakeRange(n-1,0)),@"native Backspace reverses exactly one repeated space");
                Check(SamePoint(NativeCaretPoint(view),carets[n-1]),@"Backspace restores the exact preceding caret point including wrap thresholds");
            }
            [self finishEditing];
            Check(view.string.length==0 && [[[note contentString] string] length]==0,@"reverse repeat restores an empty source and model");
            for(NSUInteger n=0;n<100;n++) {
                unichar character=(n%9==0 || n%9==1 || n%9==5)?'k':' ';
                TypingKey(view,character,character=='k'?40:49,n>0); totalKeys++;
                [expected appendFormat:@"%C",character];
            }
            for(NSUInteger pass=0;pass<12;pass++) {
                NSUInteger position=view.selectedRange.location;
                [self.window setContentSize:NSMakeSize(pass%2?470:650,640)];
                NSDictionary *previous=NativeCaretPoint(view);
                Check([view.string isEqual:expected] && NSEqualRanges(view.selectedRange,NSMakeRange(position,0)),@"resizing preserves source and logical insertion position");
                Check(CaretInHorizontalBounds(view,previous),@"resizing places the queried caret within the new editor width");
                for(NSUInteger key=0;key<3;key++) {
                    unichar character=key==2?'k':' ';
                    TypingKey(view,character,character=='k'?40:49,YES); totalKeys++;
                    [expected appendFormat:@"%C",character];
                    NSDictionary *current=NativeCaretPoint(view);
                    Check([view.string isEqual:expected] && NSEqualRanges(view.selectedRange,NSMakeRange(expected.length,0)),@"mixed Space and k events append to the intended source after resize");
                    Check(MovesForward(previous,current) && CaretInHorizontalBounds(view,current),@"mixed typing after resize advances the caret without an out-of-bounds jump");
                    previous=current;
                }
            }
            NSArray *lines=NativeLineRecords(view);
            Check(lines.count>1,@"mixed fixture supplies a wrapped line for a native mouse click");
            NSUInteger target=[lines[1][@"location"] unsignedIntegerValue]+3;
            NativeMouseClick(view,target);
            Check(NSEqualRanges(view.selectedRange,NSMakeRange(target,0)),@"native mouse down and up place insertion at the intended wrapped-line position");
            Check([view.string isEqual:expected],@"native click leaves all typed source characters unchanged");
            [self finishEditing];
            Check([[[note contentString] string] isEqual:expected],@"mixed typing and resize commit exact source characters to the model");
            [results addObject:@{@"setting":setting,@"repeatSpaces":@(count),@"wrapTransitions":transitions,@"mixedSourceLength":@(expected.length),@"mouseTarget":@(target),@"mouseSelection":NSStringFromRange(view.selectedRange)}];
        }
        Check([[NSJSONSerialization dataWithJSONObject:@{@"totalKeyEvents":@(totalKeys),@"fixtures":results} options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:[NSString stringWithUTF8String:getenv("NV_TYPING_RESULT")] atomically:YES],@"save exact observed key-repeat and wrap-threshold geometry");
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"ROUND3 UX TYPING PASSED (%lu checks)",(unsigned long)Checks);
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];exit(0);
    } @catch(NSException *exception) {
        NSLog(@"ROUND3 UX TYPING EXCEPTION %@ %@\n%@",exception.name,exception.reason,exception.callStackSymbols);exit(1);
    }
}
@end
