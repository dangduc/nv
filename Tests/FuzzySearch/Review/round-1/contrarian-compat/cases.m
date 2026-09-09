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

int main(void) {
    @autoreleasepool {
        Autocomplete = YES;
        NoteObject *road = Note(@"Road map", @"road planning"), *other = Note(@"Other", @"road copper"), *gaps = Note(@"Rivet", @"r---o---a---d");
        TestLibrary *library = [[[TestLibrary alloc] initWithNotes:@[road, other, gaps]] autorelease];
        NVSearchService *service = [[[NVSearchService alloc] init] autorelease]; Capture(service, library); ActiveSearchService = service;
        ArchiveCases(road);
        ReviewDefaults *defaults = [ReviewDefaults standardUserDefaults];
        [[GlobalPrefs defaultPrefs] setValue:defaults forKey:@"defaults"];
        StateController *fresh = Controller(library, service);
        [fresh restoreListStateUsingPreferences];
        Check([[fresh searchMode] isEqual:@"fuzzy"], "absent last-search defaults preserve fresh Fuzzy session");
        defaults->values[@"LastSearchString"] = @"";
        StateController *legacy = Controller(library, service);
        [legacy restoreListStateUsingPreferences];
        printf("LEGACY EMPTY: stored_query=present-empty stored_mode=absent restored_mode=%s\n", [[legacy searchMode] UTF8String]);
#ifdef EXPECT_LEGACY_EMPTY
        Check([[legacy searchMode] isEqual:@"exact"], "a present legacy empty search restores Exact");
#else
        Check([[legacy searchMode] isEqual:@"fuzzy"], "witness: a present legacy empty search incorrectly retains Fuzzy");
#endif
        defaults->values[@"LastSearchString"] = @"road";
        StateController *nonempty = Controller(library, service);
        [nonempty restoreListStateUsingPreferences];
        Check([[nonempty searchMode] isEqual:@"exact"], "present legacy nonempty search restores Exact");
        defaults->values[@"LastSearchString"] = @""; defaults->values[@"LastSearchMode"] = @"exact";
        StateController *explicit = Controller(library, service); [explicit restoreListStateUsingPreferences];
        Check([[explicit searchMode] isEqual:@"exact"], "explicit Exact with empty search restores Exact");
        [defaults->values removeAllObjects];

        StateController *controller = Controller(library, service);
        Pending(controller, @"road"); Complete(controller);
        Check(controller->currentNote == road, "production autocomplete selects first title occurrence");
        [controller->notesTableView deselectAll:nil];
        Check(controller->currentNote == nil && [[controller searchMode] isEqual:@"fuzzy"] && [controller->notationController preferredSelectedNoteIndex] != NSNotFound,
              "production selection callback leaves a reachable deselected Fuzzy query");
        BOOL handled = [controller control:(id)controller->field textView:(id)controller->field->editor doCommandBySelector:@selector(insertTab:)];
        printf("TAB: handled=%d query=%s restored_mode=%s rows=%lu\n", handled, [[controller fieldSearchString] UTF8String], [[controller searchMode] UTF8String], (unsigned long)[controller->notationController resultCount]);
#ifdef EXPECT_TAB_MODE
        Check([[controller searchMode] isEqual:@"fuzzy"], "Tab autocomplete preserves the active Fuzzy mode");
#else
        Check(handled && [[controller searchMode] isEqual:@"exact"], "witness: Tab autocomplete changes an existing Fuzzy query to Exact");
#endif
        [controller searchForString:@"road" mode:@"fuzzy"]; Complete(controller);
        NSString *fuzzyKey = [[RowKey(controller->notationController, road, @"fuzzy") copy] autorelease];
        NSUInteger fuzzyRow = [controller->notationController indexForRowKey:fuzzyKey];
        [controller->notesTableView selectRowAndScroll:fuzzyRow];
        NoteBookmark *bookmark = [[[NoteBookmark alloc] initWithNoteObject:road searchString:@"road" searchMode:@"fuzzy" resultRowKey:fuzzyKey] autorelease];
        Check([controller interpretNVURL:[NSURL URLWithString:@"nv://find/road"]], "production nv find route accepts legacy search URL");
        Check([[controller searchMode] isEqual:@"exact"], "legacy nv find URL remains Exact");
        NoteBookmark *back = [controller->field popLastFollowedLink]; Complete(controller);
        Check([[back resultRowKey] isEqual:fuzzyKey] && [[controller searchMode] isEqual:@"fuzzy"] && [[controller selectedSearchResultRowKey] isEqual:fuzzyKey],
              "followed-link stack restores Fuzzy mode and original occurrence through production completion");
        [controller searchForString:@"road"];
        Check([[controller searchMode] isEqual:@"exact"], "legacy direct search selector remains Exact");
        [controller bookmarksController:nil restoreNoteBookmark:bookmark inBackground:YES]; Complete(controller);
        Check([[controller selectedSearchResultRowKey] isEqual:fuzzyKey], "bookmark command restores saved fuzzy occurrence");
        NSDictionary *mismatch = @{@"search":@"road", @"searchMode":@"fuzzy", @"note":UUIDString(road), @"searchRowKey":RowKey(controller->notationController, other, @"fuzzy")};
        [controller restoreBrowserWindowState:mismatch]; Complete(controller);
        Check(controller->currentNote == road && [[controller->notationController matchKindAtIndex:[controller->notesTableView primarySelectedRow]] isEqual:@"title"],
              "restoration rejects another note's row key and chooses this note's title occurrence");
        [controller restoreBrowserWindowState:@{@"search":@"road", @"note":UUIDString(road)}];
        Check([[controller searchMode] isEqual:@"exact"] && controller->currentNote == road, "mode-less browser window restores Exact and same note");
        [controller restoreBrowserWindowState:@{@"search":@"road", @"searchMode":@5, @"note":UUIDString(road), @"searchRowKey":@5}];
        Check([[controller searchMode] isEqual:@"exact"] && controller->currentNote == road, "invalid window mode and occurrence preserve legacy Exact fallback");
        printf("PASS: %lu compatibility checks with production methods and real native search.\n", (unsigned long)Checks);
    }
    return 0;
}
