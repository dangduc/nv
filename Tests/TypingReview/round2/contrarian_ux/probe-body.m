    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        LinkingEditor *ea = [self valueForKey:@"textView"];
        id ca = [self valueForKey:@"wordCounter"];
        [[GlobalPrefs defaultPrefs] setShowWordCount:YES];
        NoteObject *alpha = MakeNote(library, @"Popup count", @"one two three");
        NoteObject *beta = MakeNote(library, @"Switch count", @"one two three four five six seven");
        [self searchForString:@"" mode:@"fuzzy"]; [self revealNote:alpha options:0];
        Check([ca isHidden], @"word count begins hidden under popup preference");
        Popup(self, YES);
        Check(![ca isHidden], @"event-qualified production popup exposes native count control");
        Check(Await(^BOOL { return [[ca stringValue] isEqual:@"3 words"]; }, 3), @"popup alone requests and publishes three-word count");
        Popup(self, NO);
        Check([ca isHidden] && ![[ca stringValue] length], @"popup hide clears native label");
        [ea insertText:@" four" replacementRange:NSMakeRange(ea.string.length, 0)];
        Popup(self, YES); Popup(self, NO);
        Check(Await(^BOOL { return NVSourceLinksAreCurrent(ea.textStorage); }, 3), @"analysis settles after show-then-hide during pending count");
        Check([ca isHidden] && ![[ca stringValue] length], @"late completion does not repaint hidden popup");
        Popup(self, YES);
        Check(Await(^BOOL { return [[ca stringValue] isEqual:@"4 words"]; }, 3), @"showing popup again obtains latest count after canceled demand");
        Popup(self, NO);

        [[GlobalPrefs defaultPrefs] setShowWordCount:NO];
        [app newWindow:self]; Pump();
        AppController *b = [[app browserControllers] lastObject];
        [b searchForString:@"" mode:@"fuzzy"]; [b revealNote:alpha options:0];
        LinkingEditor *eb = [b valueForKey:@"textView"];
        id cb = [b valueForKey:@"wordCounter"];
        Check(ea.textStorage == eb.textStorage, @"two native windows share count source storage");
        Check(Await(^BOOL { return [[ca stringValue] isEqual:@"4 words"] && [[cb stringValue] isEqual:@"4 words"]; }, 3), @"both visible controls obtain shared cached count");
        [ea insertText:@" five" replacementRange:NSMakeRange(ea.string.length, 0)];
        Check(Await(^BOOL { return [[ca stringValue] isEqual:@"5 words"] && [[cb stringValue] isEqual:@"5 words"]; }, 3), @"peer edit refreshes both native count controls");
        [ea insertText:@" six" replacementRange:NSMakeRange(ea.string.length, 0)];
        [self revealNote:beta options:0];
        Check(Await(^BOOL { return [self selectedNoteObject] == beta; }, 3), @"note switch completes while old count is pending");
        Check(Await(^BOOL { return [[ca stringValue] isEqual:@"7 words"] && [[cb stringValue] isEqual:@"6 words"]; }, 3), @"pending old-note count updates peer without contaminating replacement note");
        [eb insertText:@" seven eight" replacementRange:NSMakeRange(eb.string.length, 0)];
        [[b window] close];
        Check(Await(^BOOL { return [[app browserControllers] count] == 1; }, 3), @"last old-note browser closes while analysis is pending");
        [self revealNote:alpha options:0];
        Check(Await(^BOOL { return [[ca stringValue] isEqual:@"8 words"]; }, 3), @"reattaching closed-window note computes complete latest count");
        Check([library flushAllNoteChanges], @"disposable library checkpoint succeeds");
        [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"TYPING UX PASSED (%lu checks)", (unsigned long)Checks); exit(0);
    } @catch (NSException *exception) {
        NSLog(@"TYPING UX EXCEPTION %@ %@", [exception name], [exception reason]); exit(1);
    }
}
@end
