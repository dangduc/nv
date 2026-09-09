- (void)nv_r2FocusDiagnostic:(NSSearchField *)search label:(NSString *)label {
    [window makeFirstResponder:textView]; Pump();
    id cell = [search cell];
    [cell accessibilitySetValue:@YES forAttribute:NSAccessibilityFocusedAttribute]; Pump();
    NSLog(@"FOCUS_CONTROL label=%@ path=cell-old-api fieldEditor=%d reported=%@ responder=%@", label,
        [search currentEditor] != nil, [cell accessibilityAttributeValue:NSAccessibilityFocusedAttribute],
        NSStringFromClass([[window firstResponder] class]));
    [window makeFirstResponder:textView]; Pump();
    if ([cell respondsToSelector:@selector(setAccessibilityFocused:)]) {
        [cell setAccessibilityFocused:YES]; Pump();
        NSLog(@"FOCUS_CONTROL label=%@ path=cell-protocol-api fieldEditor=%d responder=%@", label,
            [search currentEditor] != nil, NSStringFromClass([[window firstResponder] class]));
    }
    [window makeFirstResponder:textView]; Pump();
    [search setAccessibilityFocused:YES]; Pump();
    NSLog(@"FOCUS_CONTROL label=%@ path=view-protocol-api fieldEditor=%d responder=%@", label,
        [search currentEditor] != nil, NSStringFromClass([[window firstResponder] class]));
    [window makeFirstResponder:search]; Pump();
    Check([search currentEditor] != nil, [NSString stringWithFormat:@"%@ direct focus positive control opens native editor", label]);
}
- (void)nv_runTests {
    @try {
        [self nv_activateBrowser];
        NotationController *library = [[NVApplicationController sharedController] library];
        NoteObject *note = MakeNote(library, @"Control note", @"control body");
        [self searchForString:@"Control" mode:@"exact"]; [self revealNote:note options:0]; Pump();
        // Mirror the complete accessibility traversal from the main probe.
        NSMutableArray *pending = [NSMutableArray arrayWithObject:window];
        NSMutableArray *seen = [NSMutableArray array];
        for (NSUInteger i = 0; i < [pending count] && [seen count] < 300; i++) {
            id item = [pending objectAtIndex:i];
            if ([seen indexOfObjectIdenticalTo:item] != NSNotFound) continue;
            [seen addObject:item];
            if ([item respondsToSelector:@selector(accessibilityAttributeValue:)]) {
                id children = [item accessibilityAttributeValue:NSAccessibilityChildrenAttribute];
                if ([children isKindOfClass:[NSArray class]]) [pending addObjectsFromArray:children];
            }
        }
        NSLog(@"FOCUS_CONTROL accessibleDescendants=%lu", (unsigned long)[seen count]);
        [self nv_r2FocusDiagnostic:field label:@"production"];
        NSSearchField *stock = [[[NSSearchField alloc] initWithFrame:NSMakeRect(20, 20, 240, 24)] autorelease];
        [[window contentView] addSubview:stock];
        [self nv_r2FocusDiagnostic:stock label:@"stock"];
        NSLog(@"FOCUS_CONTROL_PASS checks=%lu", (unsigned long)Checks);
        [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.2];
    } @catch (NSException *exception) { NSLog(@"FOCUS_CONTROL_EXCEPTION %@", exception); exit(2); }
}
