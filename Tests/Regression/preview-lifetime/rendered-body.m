
    // The loaded harness must not be injected into the external markup helper.
    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        __block NSUInteger browserDeaths=0, editorDeaths=0, previewDeaths=0, webDeaths=0, setterCalls=0;
        NSMutableSet *webPointers=[NSMutableSet set];
        IMP oldBrowser=class_getMethodImplementation([AppController class],@selector(dealloc));
        IMP oldEditor=class_getMethodImplementation([LinkingEditor class],@selector(dealloc));
        IMP oldPreview=class_getMethodImplementation([PreviewController class],@selector(dealloc));
        IMP oldWeb=class_getMethodImplementation([WebView class],@selector(dealloc));
        IMP oldSetter=class_getMethodImplementation([PreviewController class],@selector(setPreview:));
        method_setImplementation(class_getInstanceMethod([AppController class],@selector(dealloc)),imp_implementationWithBlock(^(id object) { browserDeaths++; ((void(*)(id,SEL))oldBrowser)(object,@selector(dealloc)); }));
        method_setImplementation(class_getInstanceMethod([LinkingEditor class],@selector(dealloc)),imp_implementationWithBlock(^(id object) { editorDeaths++; ((void(*)(id,SEL))oldEditor)(object,@selector(dealloc)); }));
        method_setImplementation(class_getInstanceMethod([PreviewController class],@selector(setPreview:)),imp_implementationWithBlock(^(id object,id value) { if(value) { setterCalls++; [webPointers addObject:[NSValue valueWithPointer:value]]; } ((void(*)(id,SEL,id))oldSetter)(object,@selector(setPreview:),value); }));
        method_setImplementation(class_getInstanceMethod([PreviewController class],@selector(dealloc)),imp_implementationWithBlock(^(id object) { previewDeaths++; ((void(*)(id,SEL))oldPreview)(object,@selector(dealloc)); }));
        method_setImplementation(class_getInstanceMethod([WebView class],@selector(dealloc)),imp_implementationWithBlock(^(id object) { if([webPointers containsObject:[NSValue valueWithPointer:object]]) webDeaths++; ((void(*)(id,SEL))oldWeb)(object,@selector(dealloc)); }));

        NSAutoreleasePool *observationPool=[NSAutoreleasePool new];
        NSAutoreleasePool *batchPool=[NSAutoreleasePool new];
        NotationController *library=[app library];
        NoteObject *alpha=MakeNote(library,@"Preview Alpha",@"# Alpha roundthree marker");
        NoteObject *beta=MakeNote(library,@"Preview Beta",@"# Beta roundthree marker");
        [self revealNote:alpha options:0]; Pump();
        PreviewController *pa=[self valueForKey:@"previewController"];
        if(![pa previewIsVisible]) [self togglePreview:self];
        for(int j=0;j<6;j++) Pump();
        Check([[[pa valueForKey:@"sourceView"] string] rangeOfString:@"Alpha roundthree marker"].location!=NSNotFound,@"initial preview renders its owning browser note");
        [app newWindow:self]; Pump();
        AppController *second=[[app browserControllers] lastObject];
        [second revealNote:beta options:0]; Pump();
        PreviewController *pb=[second valueForKey:@"previewController"];
        if(![pb previewIsVisible]) [second togglePreview:self];
        for(int j=0;j<6;j++) Pump();
        Check([[[pb valueForKey:@"sourceView"] string] rangeOfString:@"Beta roundthree marker"].location!=NSNotFound,@"second preview renders its owning browser note");
        NSDate *scriptDeadline=[NSDate dateWithTimeIntervalSinceNow:3.0];
        while(![[[pb preview] stringByEvaluatingJavaScriptFromString:@"typeof Cocoa !== 'undefined' && typeof Cocoa.log === 'function'"] isEqualToString:@"true"] && [scriptDeadline timeIntervalSinceNow]>0) Pump();
        NSString *logResult=[[pb preview] stringByEvaluatingJavaScriptFromString:@"Cocoa.log('preview-lifetime safe smoke check'); 'bridge-ok'"];
        Check([logResult isEqualToString:@"bridge-ok"], @"rendered preview preserves the callable Cocoa.log API");
        // Close every browser while a rendered preview is present, then reopen repeatedly.
        for(AppController *browser in [app browserControllers]) [[browser window] close];
        Pump();
        [batchPool drain]; Pump();
        Check([[app browserControllers] count]==0,@"all browsers close without closing the shared library");
        for(int cycle=0;cycle<4;cycle++) {
            NSAutoreleasePool *pool=[NSAutoreleasePool new];
            [(id)app applicationShouldHandleReopen:NSApp hasVisibleWindows:NO]; Pump();
            AppController *browser=[[app browserControllers] lastObject];
            Check([[app browserControllers] count]==1 && [browser sharedNotationController]==library,@"reopen keeps exactly one browser on the same library");
            [browser revealNote:cycle%2?beta:alpha options:0]; Pump();
            PreviewController *preview=[browser valueForKey:@"previewController"];
            if(![preview previewIsVisible]) [browser togglePreview:self];
            for(int j=0;j<6;j++) Pump();
            NSString *marker=cycle%2?@"Beta roundthree marker":@"Alpha roundthree marker";
            Check([[[preview valueForKey:@"sourceView"] string] rangeOfString:marker].location!=NSNotFound,@"reopened browser preview renders its current note");
            [[browser window] close]; Pump();
            [pool drain]; Pump();
            Check([[app browserControllers] count]==0,@"closing reopened browser leaves no tracked browser");
        }
        [observationPool drain];
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:8.0];
        while((editorDeaths<5 || webDeaths<5) && [deadline timeIntervalSinceNow]>0) { NSAutoreleasePool *pool=[NSAutoreleasePool new]; Pump(); [pool drain]; }
        NSLog(@"RENDERED LIFETIME browsers=%lu editors=%lu previews=%lu nibSetters=%lu webViews=%lu",(unsigned long)browserDeaths,(unsigned long)editorDeaths,(unsigned long)previewDeaths,(unsigned long)setterCalls,(unsigned long)webDeaths);
        Check(browserDeaths==5 && editorDeaths==5 && previewDeaths==5 && setterCalls==5 && webDeaths==5,@"all five additional rendered browsers and previews deallocate");
        Check([[GlobalPrefs defaultPrefs] noteBodyFont]!=nil && [[library allNotes] count]==2,@"initial service owner and shared library remain usable after all windows close");
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"RENDERED PREVIEW CHECKS PASSED (%lu)",(unsigned long)Checks);
        _exit(0);
    } @catch(NSException *exception) { NSLog(@"FAIL %@\n%@",exception,[exception callStackSymbols]); _exit(1); }
}
@end
