- (void)nv_runTests {
    NoteObject *note = MakeNote([self sharedNotationController], @"Search display control", @"# Stable heading\n\nTyping: ");
    [self revealNote:note options:0]; [self nv_activateBrowser]; [window makeFirstResponder:textView];
    for (NSUInteger i=0; i<5; i++) Pump();
    NSUInteger token = [[textView string] rangeOfString:@"Stable"].location;
    [[textView layoutManager] addTemporaryAttribute:NSBackgroundColorAttributeName value:[NSColor yellowColor] forCharacterRange:NSMakeRange(token,2)];
    id before = [[textView layoutManager] temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:token effectiveRange:NULL];
    Check([before isEqual:[NSColor yellowColor]], @"control installs a manual highlight without any search query");
    [textView insertText:@" " replacementRange:NSMakeRange([[textView string] length],0)];
    id after = [[textView layoutManager] temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:token effectiveRange:NULL];
    NSLog(@"OBSERVATION manual background before=%@ after=%@",before,after);
    Check([[textView string] isEqual:@"# Stable heading\n\nTyping:  "], @"control insertion preserves exact source");
    [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.1];
}
