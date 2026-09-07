
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        method_setImplementation(class_getInstanceMethod([GlobalPrefs class], @selector(dealloc)), imp_implementationWithBlock(^(id object) {
            NSLog(@"SINGLETON-DEALLOC: a closed browser editor is destroying GlobalPrefs; stack=%@", [NSThread callStackSymbols]);
            _exit(0);
        }));
        __block NSUInteger browserDeallocations=0, editorDeallocations=0;
        IMP oldBrowserDealloc=class_getMethodImplementation([AppController class], @selector(dealloc));
        IMP oldEditorDealloc=class_getMethodImplementation([LinkingEditor class], @selector(dealloc));
        method_setImplementation(class_getInstanceMethod([AppController class], @selector(dealloc)), imp_implementationWithBlock(^(id object) { browserDeallocations++; ((void(*)(id,SEL))oldBrowserDealloc)(object,@selector(dealloc)); }));
        method_setImplementation(class_getInstanceMethod([LinkingEditor class], @selector(dealloc)), imp_implementationWithBlock(^(id object) { editorDeallocations++; ((void(*)(id,SEL))oldEditorDealloc)(object,@selector(dealloc)); }));
        NSLog(@"LIFECYCLE before open=%lu windows=%lu prefs-retain=%lu", (unsigned long)[[app browserControllers] count], (unsigned long)[[NSApp windows] count], (unsigned long)[[GlobalPrefs defaultPrefs] retainCount]);
        NSMutableArray *closed = [NSMutableArray array];
        for (int i=0; i<(getenv("NV_REVIEW_CACHE_ONLY") ? 0 : 8); i++) {
            NSAutoreleasePool *cycle = [[NSAutoreleasePool alloc] init];
            [app newWindow:self]; Pump();
            AppController *browser = [[app browserControllers] lastObject];
            [closed addObject:[NSValue valueWithPointer:browser]];
            [[browser window] close]; Pump();
            [cycle drain]; Pump();
            NSLog(@"LIFECYCLE cycle=%d open=%lu windows=%lu prefs-retain=%lu",i+1,(unsigned long)[[app browserControllers] count], (unsigned long)[[NSApp windows] count],(unsigned long)[[GlobalPrefs defaultPrefs] retainCount]);
        }
        NSLog(@"LIFECYCLE closed=%lu browser-deallocations=%lu editor-deallocations=%lu",(unsigned long)[closed count],(unsigned long)browserDeallocations,(unsigned long)editorDeallocations);
        NotationController *library = [app library];
        for (int i=0; i<12; i++) {
            NoteObject *note=MakeNote(library,[NSString stringWithFormat:@"Deleted %d",i],@"temporary text");
            [self revealNote:note options:0]; Pump();
            [library removeNotes:@[note]]; Pump();
        }
        [[library undoManager] removeAllActions];
        NSLog(@"CACHE live-notes=%lu editing-sessions=%lu",(unsigned long)[[library allNotes] count],(unsigned long)[[app valueForKey:@"editingSessions"] count]);
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] synchronize];
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@",exception,[exception callStackSymbols]); exit(1); }
}
@end
