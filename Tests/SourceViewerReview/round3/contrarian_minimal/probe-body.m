    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        NSAutoreleasePool *firstScope = [[NSAutoreleasePool alloc] init];
        NoteObject *note = [MakeNote(library, @"Residual preview costs", @"# Preview lifetime marker\n\nSource body.") retain];
        [self revealNote:note options:0];
        LinkingEditor *editor = [self valueForKey:@"textView"];
        ChangeMode(self, YES);
        Check(Await(^BOOL { return PreviewShows(self, @"Preview lifetime marker"); }, 15), @"preview loads before residual-cost measurements");
        NSUInteger activeCalls = ScrollJavaScriptCalls;
        Check(Await(^BOOL { return ScrollJavaScriptCalls >= activeCalls + 2; }, 2), @"visible preview control submits periodic DOM reads");
        NSLog(@"VISIBLE CONTROL: DOM reads=%lu", (unsigned long)(ScrollJavaScriptCalls - activeCalls));

        ChangeMode(self, NO);
        Pump();
        NSUInteger sourceCalls = ScrollJavaScriptCalls, sourceRenders = RenderSubmissions, sourceTimers = TimerEntries;
        for (NSUInteger index = 0; index < 20; index++) {
            [editor insertText:[NSString stringWithFormat:@"\nSource edit %lu", (unsigned long)index] replacementRange:NSMakeRange([[editor string] length], 0)];
            [self finishEditing];
            Pump();
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.65]];
        NSLog(@"HIDDEN SOURCE: timer entries=%lu, DOM reads=%lu, render submissions=%lu", (unsigned long)(TimerEntries-sourceTimers), (unsigned long)(ScrollJavaScriptCalls-sourceCalls), (unsigned long)(RenderSubmissions-sourceRenders));
        Check(TimerEntries > sourceTimers, @"hidden-source sample includes live timer callbacks");
        Check(ScrollJavaScriptCalls == sourceCalls, @"hidden Source never submits periodic DOM reads");
        Check(RenderSubmissions == sourceRenders, @"twenty Source edits never enqueue work in the retained renderer");
        Check(![self isViewingNote] && [[[[self selectedNoteObject] contentString] string] hasSuffix:@"Source edit 19"], @"hidden-renderer sample preserves exact committed Source edits");

        ChangeMode(self, YES);
        Check(Await(^BOOL { return PreviewShows(self, @"Source edit 19"); }, 15), @"returning to Preview renders the latest Source");
        Check(ProviderInitializations == 1, @"returning to Preview reuses the window's single provider");
        [[self window] orderOut:self];
        NSUInteger hiddenCalls = ScrollJavaScriptCalls, hiddenTimers = TimerEntries;
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.85]];
        NSLog(@"ORDERED-OUT WINDOW: timer entries=%lu, DOM reads=%lu", (unsigned long)(TimerEntries-hiddenTimers), (unsigned long)(ScrollJavaScriptCalls-hiddenCalls));
        Check(TimerEntries > hiddenTimers, @"ordered-out sample includes live timer callbacks");
        Check(ScrollJavaScriptCalls == hiddenCalls, @"ordered-out Preview never submits periodic DOM reads");
        [[self window] makeKeyAndOrderFront:self];
        Check(Await(^BOOL { return ScrollJavaScriptCalls > hiddenCalls; }, 2), @"reshown Preview resumes periodic DOM reads");

        [self discardViewer];
        ChangeMode(self, NO);
        // The review's KVC reads autorelease provider references. Drain those
        // before measuring application ownership, as a real event turn does.
        [firstScope drain];
        Check(Await(^BOOL { return ProviderDeallocations == ProviderInitializations; }, 3), @"discard releases the first provider after asynchronous callbacks drain");
        for (NSUInteger iteration = 0; iteration < 3; iteration++) {
            NSAutoreleasePool *scope = [[NSAutoreleasePool alloc] init];
            [app newWindow:self]; Pump();
            AppController *peer = [[app browserControllers] lastObject];
            Check(peer != self, @"lifetime sample creates an additional browser");
            [peer revealNote:note options:0];
            ChangeMode(peer, YES);
            Check(Await(^BOOL { return PreviewShows(peer, @"Source edit 19"); }, 15), @"additional browser completes native Preview navigation");
            [[peer window] performClose:self];
            [scope drain];
            Check(Await(^BOOL { return ProviderDeallocations == ProviderInitializations; }, 3), @"closing browser releases its provider and timer ownership");
        }
        NSUInteger afterCloseTimers = TimerEntries, afterCloseCalls = ScrollJavaScriptCalls, afterCloseRenders = RenderSubmissions;
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.8]];
        Check(TimerEntries == afterCloseTimers && ScrollJavaScriptCalls == afterCloseCalls && RenderSubmissions == afterCloseRenders, @"closed providers leave no timer entries, DOM reads, or render submissions");
        Check(ProviderInitializations == 4 && ProviderDeallocations == 4 && ProviderFirstCloses == 4, @"all four provider lifetimes close and deallocate exactly once");
        NSLog(@"LIFETIMES: init=%lu, first close=%lu, dealloc=%lu", (unsigned long)ProviderInitializations, (unsigned long)ProviderFirstCloses, (unsigned long)ProviderDeallocations);
        [note release];
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"ROUND 3 MINIMAL CHECKS PASSED: %lu", (unsigned long)Checks);
        _exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1); }
}
@end
