- (void)nv_runTests {
    [self nv_activateBrowser];
    [window setFrame:NSMakeRect(160, 160, 820, 680) display:YES];
    NSString *source = @"# Colors stay visible while typing\n\nA **bold phrase**, some *emphasis*, and `inline code`.\n\n## Edit this source\n\nThe heading and existing syntax keep their colors.\n\nTyping here: ";
    NoteObject *note = MakeNote([[NVApplicationController sharedController] library], @"Source syntax colors", source);
    [self revealNote:note options:0];
    NSMenuItem *syntax = [[[NSMenuItem alloc] initWithTitle:@"Markdown" action:@selector(selectSourceSyntax:) keyEquivalent:@""] autorelease];
    [syntax setRepresentedObject:@"markdown"]; [self selectSourceSyntax:syntax];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!NVSourceCapturesAreCurrent([textView layoutManager]) && [deadline timeIntervalSinceNow] > 0) Pump();
    Check(NVSourceCapturesAreCurrent([textView layoutManager]), @"visual fixture begins with completed syntax analysis");
    [window makeFirstResponder:textView];
    // Hold analysis only after the initial result, to capture the pending state
    // without depending on WindowServer completing a frame within 60 ms.
    Method method = class_getInstanceMethod([NVSourceHighlighter class], NSSelectorFromString(@"analyze"));
    IMP original = method_setImplementation(method, imp_implementationWithBlock(^(id highlighter) {}));
    [textView insertText:@"a" replacementRange:NSMakeRange([[textView string] length], 0)];
    for (NSUInteger i = 0; i < 6; i++) Pump();
    Check(!NVSourceCapturesAreCurrent([textView layoutManager]), @"visual fixture captures the pending parse after a native edit");
    [[window contentView] layoutSubtreeIfNeeded]; [window displayIfNeeded];
    CGImageRef frame = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow,
        (CGWindowID)[window windowNumber], kCGWindowImageBoundsIgnoreFraming);
    Check(frame != NULL, @"native window screenshot exists");
    NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithCGImage:frame] autorelease];
    NSData *png = [bitmap representationUsingType:NSPNGFileType properties:@{}];
    NSString *path = [NSString stringWithUTF8String:getenv("NV_FLICKER_SCREENSHOT")];
    Check([png writeToFile:path atomically:YES], @"native screenshot saved");
    CGImageRelease(frame);
    method_setImplementation(method, original);
    NSLog(@"VISUAL CHECKS PASSED: %lu", (unsigned long)Checks);
    [self nv_finishTests];
}
