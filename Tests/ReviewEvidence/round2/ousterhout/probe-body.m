
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
        method_setImplementation(class_getInstanceMethod([PreviewController class],@selector(dealloc)),imp_implementationWithBlock(^(id object) { previewDeaths++; if(getenv("NV_PREVIEW_OWNERSHIP_CONTROL")) [object setPreview:nil]; ((void(*)(id,SEL))oldPreview)(object,@selector(dealloc)); }));
        method_setImplementation(class_getInstanceMethod([WebView class],@selector(dealloc)),imp_implementationWithBlock(^(id object) { if([webPointers containsObject:[NSValue valueWithPointer:object]]) webDeaths++; ((void(*)(id,SEL))oldWeb)(object,@selector(dealloc)); }));
        NotationController *library = [app library];
        NoteObject *note=MakeNote(library,@"Ownership fixture",@"alpha beta gamma");
        for(int i=0;i<8;i++) {
            NSAutoreleasePool *pool=[NSAutoreleasePool new];
            [app newWindow:self]; Pump();
            AppController *browser=[[app browserControllers] lastObject];
            [browser revealNote:note options:0]; Pump();
            LinkingEditor *editor=[browser valueForKey:@"textView"];
            [editor setSelectedRange:NSMakeRange(5,0)];
            [editor beforeString]; [editor afterString];
            [[browser window] close]; Pump();
            [pool drain]; Pump();
        }
        // Earlier Cocoa deallocation occurred after several subsequent note operations.
        for(int i=0;i<12;i++) { [note setTitleString:[NSString stringWithFormat:@"Ownership fixture %d",i]]; Pump(); }
        for(int i=0;i<60;i++) Pump();
        NSLog(@"ROUND2 mode=%s browsers=%lu editors=%lu previewControllers=%lu nibSetters=%lu webViews=%lu prefs-retain=%lu",getenv("NV_PREVIEW_OWNERSHIP_CONTROL")?"release-control":"production",(unsigned long)browserDeaths,(unsigned long)editorDeaths,(unsigned long)previewDeaths,(unsigned long)setterCalls,(unsigned long)webDeaths,(unsigned long)[[GlobalPrefs defaultPrefs] retainCount]);
        Check(browserDeaths==8, @"all eight closed browser controllers deallocate");
        Check(editorDeaths>0, @"real delayed editor deallocation was exercised");
        Check([GlobalPrefs defaultPrefs]!=nil && [[GlobalPrefs defaultPrefs] noteBodyFont]!=nil, @"shared preferences remain usable after editor deallocation");
        Check([[[note contentString] string] isEqualToString:@"alpha beta gamma"], @"shared note survives browser teardown");
        [library flushAllNoteChanges]; [library closeJournal];
        NSLog(@"ROUND2 OWNERSHIP CHECKS PASSED");
        _exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL %@\n%@",exception,[exception callStackSymbols]); _exit(1); }
}
@end
