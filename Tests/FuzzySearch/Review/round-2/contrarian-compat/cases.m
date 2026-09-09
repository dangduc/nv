static NSString *UUIDString(NoteObject *note) { return [NSString uuidStringWithBytes:*[note uniqueNoteIDBytes]]; }
static NSString *RowKey(NVBrowserSession *session, NoteObject *note, NSString *kind) {
    for (NSUInteger i=0; i<[session resultCount]; i++)
        if ([session noteObjectAtFilteredIndex:i] == note && [[session matchKindAtIndex:i] isEqual:kind]) return [session rowKeyAtIndex:i];
    return nil;
}
@interface UUIDResolver : NSObject { @public NoteObject *note; }
@end
@implementation UUIDResolver
- (NoteObject *)noteWithUUIDBytes:(CFUUIDBytes)bytes { return note && !memcmp(&bytes, [note uniqueNoteIDBytes], sizeof bytes) ? note : nil; }
@end

static void ArchiveCases(NoteObject *note) {
    NSString *uuid = UUIDString(note);
    NSString *titleKey = [@"title:" stringByAppendingString:uuid];
    NSString *fuzzyKey = [@"fuzzy:" stringByAppendingString:uuid];
    NSArray *modes = @[[NSNull null], @0, @[], @{}, @"", @"FUZZY", @"unknown", @"exact", @"fuzzy"];
    for (id mode in modes) {
        NSMutableDictionary *d = [@{@"SearchString":@"road", @"NoteUUIDString":uuid, @"SearchMode":mode} mutableCopy];
        if (mode == [NSNull null]) [d removeObjectForKey:@"SearchMode"];
        NoteBookmark *b = [[[NoteBookmark alloc] initWithDictionary:d] autorelease];
        SavedSearch *s = [[[SavedSearch alloc] initWithDictionary:d] autorelease];
        NSString *expected = [mode isEqual:@"fuzzy"] ? @"fuzzy" : @"exact";
        Check([[b searchMode] isEqual:expected] && [[s searchMode] isEqual:expected], "missing and invalid archive modes normalize to Exact");
        [d release];
    }
    for (id value in @[[NSNull null], @2, @[], @{}, @"not a UUID", @""]) {
        Check([[[NoteBookmark alloc] initWithDictionary:value] autorelease] == nil, "invalid bookmark outer shape rejected");
        Check([[[SavedSearch alloc] initWithDictionary:value] autorelease] == nil, "invalid saved-search outer shape rejected");
        NoteBookmark *invalid = [[[NoteBookmark alloc] initWithDictionary:@{@"NoteUUIDString":value}] autorelease];
        if ([value isKindOfClass:[NSString class]]) {
            CFUUIDRef parsed = CFUUIDCreateFromString(NULL, (CFStringRef)value);
            Check((invalid != nil) == (parsed != NULL), "bookmark UUID validity follows the platform UUID parser");
            if (parsed) CFRelease(parsed);
        } else Check(invalid == nil, "invalid bookmark UUID type rejected");
    }
    NoteBookmark *title = [[[NoteBookmark alloc] initWithNoteObject:note searchString:@"road" searchMode:@"fuzzy" resultRowKey:titleKey] autorelease];
    NoteBookmark *fuzzy = [[[NoteBookmark alloc] initWithNoteObject:note searchString:@"road" searchMode:@"fuzzy" resultRowKey:fuzzyKey] autorelease];
    NoteBookmark *unloaded = [[[NoteBookmark alloc] initWithDictionary:[fuzzy dictionaryRep]] autorelease];
    NSUInteger hash = [fuzzy hash];
    UUIDResolver *resolver = [[[UUIDResolver alloc] init] autorelease]; resolver->note = note;
    [unloaded setDelegate:resolver];
    Check([fuzzy isEqual:unloaded] && [fuzzy hash] == [unloaded hash], "bookmark identity independent of lazy note loading");
    Check([unloaded noteObject] == note, "bookmark resolves the shared model by UUID");
    resolver->note = nil; [unloaded validateNoteObject];
    Check(![unloaded noteObject] && [fuzzy isEqual:unloaded] && hash == [unloaded hash], "deleted model does not change saved identity or hash");
    resolver->note = note; [unloaded validateNoteObject];
    Check([unloaded noteObject] == note && [fuzzy isEqual:unloaded], "reappearing shared model preserves bookmark identity");
    Check(([[NSSet setWithObjects:title, fuzzy, unloaded, nil] count] == 2), "title and fuzzy occurrences remain distinct bookmark identities");
    for (id bad in @[@5, @[], @{}, @""]) {
        NoteBookmark *b = [[[NoteBookmark alloc] initWithDictionary:@{@"NoteUUIDString":uuid, @"ResultRowKey":bad}] autorelease];
        Check(![b resultRowKey], "invalid occurrence metadata falls back to note-only identity");
    }
    SavedSearch *a = [[[SavedSearch alloc] initWithSearchString:@"ROAD" searchMode:@"fuzzy"] autorelease];
    SavedSearch *b = [[[SavedSearch alloc] initWithSearchString:@"road" searchMode:@"fuzzy"] autorelease];
    [a setSelectedNote:note resultRowKey:titleKey]; [b setSelectedNote:note resultRowKey:fuzzyKey];
    Check([a isEqual:b] && [a hash] == [b hash], "saved-search identity remains query and mode despite mutable selected occurrence");
    [a setSelectedNote:nil];
    Check(![a resultRowKey] && [a isEqual:b], "clearing a selected note clears occurrence without breaking saved-search hash membership");
}

static NSDictionary *WindowState(NSString *query, id mode, NoteObject *note, id key) {
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    if (query) state[@"search"] = query;
    if (mode) state[@"searchMode"] = mode;
    if (note) state[@"note"] = UUIDString(note);
    if (key) state[@"searchRowKey"] = key;
    return state;
}
static void SetPreferences(ReviewDefaults *defaults, NSString *query, id mode, NoteObject *note, id key) {
    [defaults->values removeAllObjects];
    if (query) defaults->values[@"LastSearchString"] = query;
    if (mode) defaults->values[@"LastSearchMode"] = mode;
    if (note) defaults->values[@"LastSelectedNoteUUIDBytes"] = UUIDString(note);
    if (key) defaults->values[@"LastSearchResultRowKey"] = key;
}
static void StableSelection(StateController *controller, NoteObject *note, NSString *kind, const char *message) {
    Complete(controller);
    Check(controller->currentNote == note && [[controller->notationController matchKindAtIndex:[controller->notesTableView primarySelectedRow]] isEqual:kind], message);
    NSString *selected = [[controller->selectedSearchRowKey copy] autorelease];
    Check(!controller->pendingSearchRestoration && !controller->pendingSearchReveal, "completion consumes saved selection intent");
    [controller browserSessionSearchDidComplete:controller->notationController];
    Check(controller->currentNote == note && [controller->selectedSearchRowKey isEqual:selected], "duplicate current completion cannot revive older saved selection");
}

int main(void) {
    @autoreleasepool {
        Autocomplete = YES;
        NoteObject *road = Note(@"Road map", @"road planning"), *body = Note(@"Other", @"road copper"), *gaps = Note(@"Rivet", @"r---o---a---d");
        TestLibrary *library = [[[TestLibrary alloc] initWithNotes:@[road, body, gaps]] autorelease];
        NVSearchService *service = [[[NVSearchService alloc] init] autorelease]; Capture(service, library); ActiveSearchService = service;
        ReviewDefaults *defaults = [ReviewDefaults standardUserDefaults];
        [[GlobalPrefs defaultPrefs] setValue:defaults forKey:@"defaults"];
        ArchiveCases(road);

        NSArray *emptyModes = @[[NSNull null], @"exact", @"fuzzy", @5, @[], @{}, @"unknown"];
        for (id mode in emptyModes) {
            id savedMode = mode == [NSNull null] ? nil : mode;
            NSString *expected = [mode isEqual:@"fuzzy"] ? @"fuzzy" : @"exact";
            SetPreferences(defaults, @"", savedMode, road, nil);
            StateController *controller = Controller(library, service);
            [controller restoreListStateUsingPreferences];
            Check([[controller searchMode] isEqual:expected] && [[controller fieldSearchString] isEqual:@""], "present empty preference query restores explicit mode or legacy Exact");
            StableSelection(controller, road, @"exact", "empty query selects one ordinary occurrence of the saved note");
            [controller restoreBrowserWindowState:WindowState(@"", savedMode, road, nil)];
            Check([[controller searchMode] isEqual:expected], "empty window state applies its own mode or legacy Exact");
            StableSelection(controller, road, @"exact", "empty window restoration selects one ordinary occurrence");
        }
        SetPreferences(defaults, nil, nil, nil, nil);
        StateController *fresh = Controller(library, service); [fresh restoreListStateUsingPreferences];
        Check([[fresh searchMode] isEqual:@"fuzzy"] && [[fresh fieldSearchString] isEqual:@""], "completely absent preferences keep fresh Fuzzy session");
        SetPreferences(defaults, nil, @"fuzzy", nil, nil);
        StateController *modeOnly = Controller(library, service); [modeOnly restoreListStateUsingPreferences];
        Check([[modeOnly searchMode] isEqual:@"fuzzy"], "explicit Fuzzy survives a missing query");
        SetPreferences(defaults, nil, nil, nil, nil);

        StateController *reference = Controller(library, service); Pending(reference, @"road"); Complete(reference);
        NSString *titleKey = [[RowKey(reference->notationController, road, @"title") copy] autorelease];
        NSString *fuzzyKey = [[RowKey(reference->notationController, road, @"fuzzy") copy] autorelease];
        NSString *bodyKey = [[RowKey(reference->notationController, body, @"fuzzy") copy] autorelease];
        Check([reference->notationController resultCount] == 4 && [reference->notationController distinctResultNoteCount] == 3,
              "Fuzzy query retains title overlap and gapped body match");
        NSMutableArray *tail = [NSMutableArray array];
        for (NSUInteger i=1; i<[reference->notationController resultCount]; i++) {
            Check([[reference->notationController matchKindAtIndex:i] isEqual:@"fuzzy"], "title group precedes the complete native group");
            [tail addObject:UUID([reference->notationController noteObjectAtFilteredIndex:i])];
        }
        Check([tail isEqual:[reference->notationController.searchResult fuzzyNoteUUIDs]], "fuzzy tail exactly equals complete native result order");

        NSArray *keys = @[[NSNull null], @5, @[], @{}, @"", @"obsolete-format", @"retained:missing", bodyKey, titleKey, fuzzyKey];
        for (id key in keys) {
            id savedKey = key == [NSNull null] ? nil : key;
            NSString *expectedKind = [key isEqual:fuzzyKey] ? @"fuzzy" : @"title";
            StateController *controller = Controller(library, service);
            SetPreferences(defaults, @"road", @"fuzzy", road, savedKey);
            [controller restoreListStateUsingPreferences];
            StableSelection(controller, road, expectedKind, "preferences resolve only a matching occurrence of the saved UUID");
            [controller restoreBrowserWindowState:WindowState(@"road", @"fuzzy", road, savedKey)];
            StableSelection(controller, road, expectedKind, "window restoration rejects stale, malformed, and foreign row keys");
            NoteBookmark *bookmark = [[[NoteBookmark alloc] initWithNoteObject:road searchString:@"road" searchMode:@"fuzzy" resultRowKey:savedKey] autorelease];
            [controller bookmarksController:nil restoreNoteBookmark:bookmark inBackground:YES];
            // Note-only Reveal can preserve a valid selected occurrence. This
            // fresh controller sequence starts each invalid-key case on title.
            StableSelection(controller, road, expectedKind, "bookmark restoration keeps the intended note and available occurrence");
        }
        StateController *bodyOnly = Controller(library, service);
        [bodyOnly restoreBrowserWindowState:WindowState(@"road", @"fuzzy", body, [bodyKey stringByReplacingOccurrencesOfString:@"fuzzy:" withString:@"title:"])];
        StableSelection(bodyOnly, body, @"fuzzy", "obsolete title occurrence falls back to an available fuzzy occurrence");
        [bodyOnly restoreBrowserWindowState:WindowState(@"", @"fuzzy", body, bodyKey)];
        StableSelection(bodyOnly, body, @"exact", "empty explicit Fuzzy query ignores obsolete fuzzy occurrence key");
        Check([[bodyOnly searchMode] isEqual:@"fuzzy"] && [bodyOnly->notationController resultCount] == 3, "empty Fuzzy query retains mode and one row per note");

        [reference->notesTableView selectRowAndScroll:[reference->notationController indexForRowKey:fuzzyKey]];
        [reference->prefsController setLastSearchString:[reference fieldSearchString] selectedNote:road scrollOffsetForTableView:(id)reference->notesTableView sender:reference];
        Check([[reference->prefsController lastSearchMode] isEqual:@"fuzzy"] && [[reference->prefsController lastSearchResultRowKey] isEqual:fuzzyKey], "production preference writer stores selected occurrence and mode");
        StateController *roundtrip = Controller(library, service); [roundtrip restoreListStateUsingPreferences];
        StableSelection(roundtrip, road, @"fuzzy", "production preference write/read restores the exact saved occurrence");

        StateController *precedence = Controller(library, service);
        SetPreferences(defaults, @"road", @"fuzzy", road, fuzzyKey); [precedence restoreListStateUsingPreferences];
        Check(precedence->pendingSearchReveal != nil, "preference restoration has a pending selection before completion");
        [precedence restoreBrowserWindowState:WindowState(@"road", nil, body, nil)];
        StableSelection(precedence, body, @"exact", "newer mode-less window state supersedes pending Fuzzy preferences");
        Check([[precedence searchMode] isEqual:@"exact"], "newer legacy window mode overrides explicit preference mode");

        StateController *windowThenBookmark = Controller(library, service);
        [windowThenBookmark restoreBrowserWindowState:WindowState(@"road", @"fuzzy", road, fuzzyKey)];
        Check(windowThenBookmark->pendingSearchRestoration != nil, "window selection is pending before newer bookmark");
        NoteBookmark *bodyBookmark = [[[NoteBookmark alloc] initWithNoteObject:body searchString:@"road" searchMode:@"fuzzy" resultRowKey:bodyKey] autorelease];
        [windowThenBookmark bookmarksController:nil restoreNoteBookmark:bodyBookmark inBackground:YES];
        StableSelection(windowThenBookmark, body, @"fuzzy", "newer bookmark supersedes older pending window occurrence");

        StateController *windowThenPreferences = Controller(library, service);
        [windowThenPreferences restoreBrowserWindowState:WindowState(@"road", @"fuzzy", road, fuzzyKey)];
        SetPreferences(defaults, @"road", @"fuzzy", body, bodyKey); [windowThenPreferences restoreListStateUsingPreferences];
        StableSelection(windowThenPreferences, body, @"fuzzy", "explicit newer preference restoration supersedes pending window selection");

        StateController *bookmarkThenWindow = Controller(library, service);
        [bookmarkThenWindow bookmarksController:nil restoreNoteBookmark:bodyBookmark inBackground:YES];
        [bookmarkThenWindow restoreBrowserWindowState:WindowState(@"road", @"fuzzy", road, fuzzyKey)];
        StableSelection(bookmarkThenWindow, road, @"fuzzy", "newer window restoration supersedes older bookmark selection");

        StateController *external = Controller(library, service);
        [external restoreBrowserWindowState:WindowState(@"road", @"fuzzy", road, fuzzyKey)];
        [external searchForString:@"Rivet"];
        StableSelection(external, gaps, @"exact", "legacy external search supersedes pending saved selection");
        Check([[external searchMode] isEqual:@"exact"] && [[external fieldSearchString] isEqual:@"Rivet"], "legacy external selector keeps Exact semantics");

        [reference->notesTableView deselectAll:nil];
        Check(reference->currentNote == nil && [[reference searchMode] isEqual:@"fuzzy"], "deselected query remains Fuzzy before Tab");
        Check([reference control:(id)reference->field textView:(id)reference->field->editor doCommandBySelector:@selector(insertTab:)], "production Tab path handles its current query");
        Complete(reference);
        Check([[reference searchMode] isEqual:@"fuzzy"] && [reference->notationController resultCount] == 4, "repaired Tab preserves Fuzzy mode and complete overlap");
        printf("PASS: %lu round-two compatibility checks. No failure witness assertions.\n", (unsigned long)Checks);
    }
    return 0;
}
