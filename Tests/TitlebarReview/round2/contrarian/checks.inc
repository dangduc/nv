- (NSArray *)nv_r2AccessibleDescendants:(id)root {
    NSMutableArray *pending = [NSMutableArray arrayWithObject:root];
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
    Check([seen count] < 300, @"accessibility traversal completes within its bounded descendant limit");
    return seen;
}
- (void)nv_r2CheckAccessibleSearch {
    [window makeFirstResponder:textView]; Pump();
    NSArray *descendants = [self nv_r2AccessibleDescendants:window];
    NSUInteger searches = 0;
    id searchElement = nil;
    for (id element in descendants) if ([element respondsToSelector:@selector(accessibilityAttributeValue:)] &&
        [[element accessibilityAttributeValue:NSAccessibilitySubroleAttribute] isEqual:NSAccessibilitySearchFieldSubrole]) {
        searches++; searchElement = element;
    }
    NSLog(@"ACCESSIBLE_WINDOW titleLength=%lu descendants=%lu searches=%lu", (unsigned long)[[window title] length],
        (unsigned long)[descendants count], (unsigned long)searches);
    Check(searches == 1 && searchElement == [field cell],
        @"the complete window accessibility tree exposes exactly its own native search cell");
    id searchParent = [searchElement accessibilityAttributeValue:NSAccessibilityParentAttribute];
    NSArray *siblings = [searchParent accessibilityAttributeValue:NSAccessibilityChildrenAttribute];
    NSLog(@"ACCESSIBLE_SEARCH parent=%@ siblings=%@ actions=%@", searchParent, siblings,
        [searchElement accessibilityActionNames]);
    Check([siblings indexOfObjectIdenticalTo:searchElement] != NSNotFound,
        @"accessible parent navigation leads back to the same exposed search element");
    Check(![[field superview] isAccessibilityElement] &&
        ![[field superview] acceptsFirstResponder], @"the layout wrapper adds no accessible or keyboard focus stop");
    Check([searchElement accessibilityIsAttributeSettable:NSAccessibilityFocusedAttribute],
        @"the exposed search element supports accessibility focus");
    [searchElement accessibilitySetValue:@YES forAttribute:NSAccessibilityFocusedAttribute]; Pump();
    NSLog(@"ACCESSIBLE_FOCUS responder=%@ field=%@ editor=%@ key=%d active=%d reported=%@", [window firstResponder],
        field, [field currentEditor], [window isKeyWindow], [NSApp isActive],
        [searchElement accessibilityAttributeValue:NSAccessibilityFocusedAttribute]);
    // After AX tree enumeration, direct cell focus writes also fail in the unchanged app
    // and stock NSSearchField. Use the public control accessibility setter for this check.
    [field setAccessibilityFocused:YES]; Pump();
    Check([window firstResponder] == [field currentEditor] && [field currentEditor] != nil,
        @"the native search control's accessibility focus setter reaches its field editor");
    Check([[[self browserSession] searchString] isEqual:[field stringValue]],
        @"accessibility navigation does not change this browser's query");
}
- (void)nv_r2ConfigureQuery:(NSString *)query note:(NoteObject *)note {
    [self nv_activateBrowser];
    [self searchForString:query mode:@"exact"]; [self revealNote:note options:0]; Pump();
    Check([self selectedNoteObject] == note && [[[self browserSession] searchString] isEqual:query] &&
        [[field stringValue] isEqual:query], @"browser fixture retains its distinct query and selected note");
    Check([window titleVisibility] == NSWindowTitleHidden && [[window title] isEqual:titleOfNote(note)],
        @"hidden browser title retains its complete selected note name");
    [self nv_r2CheckAccessibleSearch];
}
- (void)nv_runTests {
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library];
        [self nv_activateBrowser];
        [prefsController setAutoCompleteSearches:NO sender:nil];
        NSString *duplicateTitle = @"Identical note name";
        NSString *longTitle = [[@"Very long note name " stringByPaddingToLength:1024 withString:@"abcdef " startingAtIndex:0]
            stringByAppendingString:@" — 日本語 🪟"];
        NoteObject *alpha = [MakeNote(library, duplicateTitle, @"window corpus alpha") retain];
        NoteObject *beta = [MakeNote(library, duplicateTitle, @"window corpus beta") retain];
        NoteObject *gamma = [MakeNote(library, longTitle, @"window corpus gamma") retain];
        Check([titleOfNote(alpha) isEqual:titleOfNote(beta)] && alpha != beta,
            @"duplicate-title fixture contains two different notes with exactly the same title");
        [self nv_r2ConfigureQuery:@"corpus alpha" note:alpha];
        [app newWindow:self]; Pump();
        AppController *peer = [[app browserControllers] lastObject];
        Check(peer != self, @"second fixture browser is independent");
        [peer nv_r2ConfigureQuery:@"corpus beta" note:beta];
        [app newWindow:self]; Pump();
        AppController *third = [[app browserControllers] lastObject];
        Check(third != self && third != peer, @"third fixture browser is independent");
        [third nv_r2ConfigureQuery:@"corpus gamma" note:gamma];
        NSMenu *menu = [NSApp windowsMenu];
        Check(menu != nil, @"the native application Window menu exists");
        [menu update];
        NSMutableArray *duplicates = [NSMutableArray array];
        NSMenuItem *longItem = nil;
        for (NSMenuItem *item in [menu itemArray]) {
            NSLog(@"WINDOW_MENU titleLength=%lu prefix=%@ action=%@ target=%@ represented=%@",
                (unsigned long)[[item title] length], [[item title] substringToIndex:MIN(40, [[item title] length])],
                NSStringFromSelector([item action]), [item target], [item representedObject]);
            if ([[item title] isEqual:duplicateTitle]) [duplicates addObject:item];
            if ([[item title] isEqual:longTitle]) longItem = item;
        }
        Check([duplicates count] == 2 && longItem != nil,
            @"native Window menu contains both identical names and the complete long Unicode name");
        NSMutableSet *activated = [NSMutableSet set];
        for (NSMenuItem *item in duplicates) {
            if (getenv("NV_CONTRARIAN_R2_NEGATIVE")) {
                [item setTarget:[third window]]; [item setAction:@selector(makeKeyAndOrderFront:)];
            }
            Check([NSApp sendAction:[item action] to:[item target] from:item],
                @"native Window menu accepts an identical-title entry");
            for (NSUInteger spin = 0; spin < 4; spin++) Pump();
            NSWindow *key = [NSApp keyWindow];
            Check(key == window || key == [peer window],
                @"an identical-title Window item activates its corresponding duplicate-title browser");
            [activated addObject:key];
        }
        Check([activated count] == 2, @"the two identical labels route to two distinct browser windows");
        Check([NSApp sendAction:[longItem action] to:[longItem target] from:longItem],
            @"native Window menu accepts the long-title entry");
        for (NSUInteger spin = 0; spin < 4; spin++) Pump();
        Check([NSApp keyWindow] == [third window] && [app activeBrowser] == third,
            @"long-title navigation activates the correct window and command receiver");
        NSArray *browsers = @[self, peer, third];
        NSArray *queries = @[@"corpus alpha", @"corpus beta", @"corpus gamma"];
        NSArray *notes = @[alpha, beta, gamma];
        for (NSUInteger index = 0; index < [browsers count]; index++) {
            AppController *browser = [browsers objectAtIndex:index];
            DualField *search = [browser valueForKey:@"field"];
            Check([browser selectedNoteObject] == [notes objectAtIndex:index] &&
                [[[browser browserSession] searchString] isEqual:[queries objectAtIndex:index]] &&
                [[search stringValue] isEqual:[queries objectAtIndex:index]],
                @"Window-menu navigation preserves each browser's selected note and distinct query");
        }
        [alpha release]; [beta release]; [gamma release];
        NSLog(@"CONTRARIAN_R2_PASS checks=%lu", (unsigned long)Checks);
        [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.2];
    } @catch (NSException *exception) {
        NSLog(@"CONTRARIAN_R2_EXCEPTION %@ %@", [exception name], [exception reason]); exit(2);
    }
}
