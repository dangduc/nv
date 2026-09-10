    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NoteObject *target = [MakeNote(library, @"Typing benchmark", @"short source") retain];
        while (library.allNotes.count < 20) MakeNote(library, @"Corpus note", @"A short corpus note.");
        LinkingEditor *editor = [self valueForKey:@"textView"];
        [[GlobalPrefs defaultPrefs] setNoteBodyFont:[NSFont fontWithName:@"Menlo" size:12] sender:self];
        [target setSourceSyntaxIdentifier:@"plain"];
        [self.window setContentSize:NSMakeSize(800, 600)];
        // These hooks count calls without suppressing or altering production work.
        Swap([NVApplicationController class], @selector(refreshBrowsers), @selector(nv_countRefresh));
        Swap([AppController class], @selector(updateNoteHeader), @selector(nv_countHeader));
        Swap([AppController class], @selector(refreshSearchHighlights), @selector(nv_countHighlights));
        NSArray *cases = @[@[@"short hidden count", @100, @NO, @NO, @200],
                           @[@"100KB visible count", @100000, @NO, @YES, @80],
                           @[@"100KB single line", @100000, @YES, @NO, @80]];
        NSMutableArray *results = [NSMutableArray array];
        for (NSUInteger trial = 0; trial < 3; trial++) {
            for (NSUInteger step = 0; step < cases.count; step++) {
                NSArray *test = cases[(step + trial) % cases.count];
                [[GlobalPrefs defaultPrefs] setShowWordCount:![test[3] boolValue]];
                [target setContentString:[[[NSAttributedString alloc] initWithString:Fixture([test[1] unsignedIntegerValue], [test[2] boolValue])] autorelease]];
                [self searchForString:@""]; [self revealNote:target options:0];
                [editor setSelectedRange:NSMakeRange(editor.string.length, 0)];
                [NSApp activateIgnoringOtherApps:YES]; [self.window makeKeyAndOrderFront:self]; [self focusNoteBody];
                WaitForUI(.5);
                Require([self selectedNoteObject] == target && library.allNotes.count == 20, @"20-note fixture owns selection");
                Require(self.window.firstResponder == editor, @"source editor owns keyboard focus");
                NSUInteger keys = [test[4] unsignedIntegerValue], length = editor.string.length;
                FullRefreshes = HeaderWrites = HighlightRequests = 0;
                double maximum = 0, total = 0; NSUInteger over16 = 0;
                Measuring = YES;
                double cpu = MainCPU(), started = TimeNow();
                for (NSUInteger i = 0; i < keys; i++) {
                    @autoreleasepool {
                        NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
                            timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:editor.window.windowNumber context:nil
                            characters:@"k" charactersIgnoringModifiers:@"k" isARepeat:i > 0 keyCode:40];
                        double begin = TimeNow(); [NSApp sendEvent:event]; double duration = (TimeNow() - begin) * 1000;
                        total += duration; maximum = MAX(maximum, duration); over16 += duration > 16;
                        WaitForUI(.025);
                        Require(editor.string.length == length + i + 1, @"each repeat inserts one character");
                        Require(NSEqualRanges(editor.selectedRange, NSMakeRange(length + i + 1, 0)), @"each repeat preserves insertion offset");
                        Require([[[target contentString] string] isEqualToString:editor.string], @"each repeat immediately reaches model");
                    }
                }
                WaitForUI(.3);
                double elapsed = (TimeNow() - started) * 1000; cpu = (MainCPU() - cpu) * 1000;
                Measuring = NO;
                Require([[self browserSession] resultCount] == 20, @"list retains all notes after final refresh");
                [results addObject:@{@"case":test[0], @"trial":@(trial+1), @"keys":@(keys), @"cpu_ms":@(cpu),
                    @"elapsed_ms":@(elapsed), @"key_mean_ms":@(total/keys), @"key_max_ms":@(maximum), @"key_over_16ms":@(over16),
                    @"full_refresh_calls":@(FullRefreshes), @"header_calls":@(HeaderWrites), @"highlight_calls":@(HighlightRequests)}];
                NSLog(@"TYPING %@ trial %lu main CPU %.1f ms, key mean %.3f ms", test[0], trial+1, cpu, total/keys);
            }
        }
        NSString *path = [NSString stringWithUTF8String:getenv("NV_TYPING_REPORT")];
        Require([[NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:path atomically:YES], @"results saved");
        Require([library flushAllNoteChanges], @"final checkpoint succeeds");
        [library closeJournal]; [target release];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"TYPING BENCHMARK PASSED (1080 checked edits)");
        exit(0);
    } @catch (NSException *exception) {
        NSLog(@"TYPING BENCHMARK EXCEPTION %@ %@\n%@", exception.name, exception.reason, exception.callStackSymbols);
        exit(1);
    }
}
- (void)nv_countHeader { if (Measuring) HeaderWrites++; [self nv_countHeader]; }
- (void)nv_countHighlights { if (Measuring) HighlightRequests++; [self nv_countHighlights]; }
@end
@implementation NVApplicationController (NVTypingBenchmark)
- (void)nv_countRefresh { if (Measuring) FullRefreshes++; [self nv_countRefresh]; }
@end
