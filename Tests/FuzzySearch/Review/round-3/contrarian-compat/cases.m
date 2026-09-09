#import "LegacyExactSession.h"
#import "NVSearchQuery.h"

static NSUInteger ComparisonsWithLegacy;

static void SameExact(NVBrowserSession *current, LegacyExactSession *legacy, NSString *context) {
    NSArray *actual = Visible(current), *expected = Visible((id)legacy);
    if (![actual isEqual:expected]) {
        fprintf(stderr, "Context: %s; query: %s; current=%lu legacy=%lu\n", [context UTF8String],
            [[current searchString] UTF8String], [actual count], [expected count]);
    }
    Check([actual isEqual:expected], "legacy Exact ordered results match");
    Check([current preferredSelectedNoteIndex] == [legacy preferredSelectedNoteIndex], "legacy Exact autocomplete row matches");
    Check([[current searchString] isEqual:[legacy searchString]], "legacy Exact query text matches");
    Check([current searchResultsAreCurrent] && ![current searchPending] && ![current searchError], "Exact publication is synchronous and current");
    Check([current resultCount] == [current distinctResultNoteCount], "Exact result counts contain one occurrence per note");
    ComparisonsWithLegacy++;
}

static void QueryPair(NVBrowserSession *current, LegacyExactSession *legacy, NSString *query, NSUInteger route) {
    if (route == 0) {
        [current filterNotesFromString:query]; [legacy filterNotesFromString:query];
    } else {
        [current filterNotesFromUTF8String:[query UTF8String] forceUncached:route == 2];
        [legacy filterNotesFromUTF8String:[query UTF8String] forceUncached:route == 2];
    }
    SameExact(current, legacy, [NSString stringWithFormat:@"route %lu", route]);
}

static NSArray *Queries(void) {
    return @[@"", @"r", @"ro", @"road", @"ROAD", @"road:copper", @"\"road:copper\"", @"road copper",
        @"\"red blue\"", @"\"red", @"\"red\" blue", @"red\"blue", @"red:blue", @"red::blue", @"red\tblue", @"\"red:blue\"",
        @"'road", @"!road", @"^blue", @"$end", @"|pipe", @"a\"b", @"\"a\"b", @"ab", @"aba", @"ababa", @"a",
        @"café", @"cafe\u0301", @"CAFE", @"résumé", @"re\u0301sume\u0301", @"😀", @"👩🏽‍💻", @"alpha beta",
        @"alpha\nbeta", @"\"alpha\nbeta\"", @"red blue green", @":\t\r\n", @"\"\"", @"\"", @"STRASSE", @"straße"];
}

int main(void) {
    @autoreleasepool {
        Autocomplete = YES;
        NSArray *records = @[
            @[@"Road map", @"planning copper", @"work"], @[@"Road", @"untitled plan", @""],
            @[@"Other", @"r---o---a---d", @""], @[@"Copper tag", @"misc", @"road copper"],
            @[@"Quoted", @"red blue sequence", @""], @[@"Split", @"red small blue", @""],
            @[@"Colon", @"red:blue exactly", @""], @[@"Literal operators", @"!road ^blue $end |pipe 'apostrophe", @""],
            @[@"NFC résumé", @"café naïve", @"étiquette"], @[@"NFD re\u0301sume\u0301", @"cafe\u0301 nai\u0308ve", @"e\u0301tiquette"],
            @[@"Emoji 😀", @"👩🏽‍💻", @"todo"], @[@"Line boundaries", @"alpha\nbeta\tgamma", @"delta"],
            @[@"Quote characters", @"a\"b road", @""], @[@"Across fields red", @"blue body", @"green tags"],
            @[@"Whitespace", @" \t: \r\n", @""], @[@"Empty", @"", @""],
            @[@"Turkish İstan", @"STRASSE Straße", @"istanbul"], @[@"Dense", @"ababa aaaa A", @"x"]];
        NSMutableArray *notes = [NSMutableArray array];
        for (NSArray *record in records) {
            NoteObject *note = Note(record[0], record[1]); [note setLabelString:record[2]]; [notes addObject:note];
        }
        TestLibrary *library = [[[TestLibrary alloc] initWithNotes:notes] autorelease];
        TestOwner *owner = [[[TestOwner alloc] init] autorelease];
        NVBrowserSession *current = [[[NVBrowserSession alloc] initWithLibrary:(id)library] autorelease];
        LegacyExactSession *legacy = [[[LegacyExactSession alloc] initWithLibrary:(id)library] autorelease];
        [current setDelegate:owner]; [legacy setDelegate:owner]; [current setSearchMode:@"exact"];
        TestColumn *column = [[[TestColumn alloc] init] autorelease];

        for (NSUInteger reverse = 0; reverse < 2; reverse++) {
            [current setSortColumn:(id)column reversed:reverse]; [legacy setSortColumn:(id)column reversed:reverse];
            for (NSUInteger route = 0; route < 3; route++) for (NSString *query in Queries()) QueryPair(current, legacy, query, route);
        }
        QueryPair(current, legacy, nil, 0);
        QueryPair(current, legacy, nil, 1);
        QueryPair(current, legacy, @"road:copper", 0);
        Check([Visible(current) count] == 2 && [Visible(current) containsObject:notes[0]] && [Visible(current) containsObject:notes[3]],
              "literal colon separates requirements across title, body, and tags");
        QueryPair(current, legacy, @"\"red blue\"", 0);
        Check([Visible(current) count] == 1 && Visible(current)[0] == notes[4], "quoted phrase requires adjacent text within one field");
        QueryPair(current, legacy, @"red blue green", 0);
        Check([Visible(current) count] == 1 && Visible(current)[0] == notes[13], "unquoted requirements can span all three note fields");
        QueryPair(current, legacy, @"!road", 0);
        Check([Visible(current) count] == 1 && Visible(current)[0] == notes[7], "fzf punctuation remains literal in Exact mode");
        QueryPair(current, legacy, @"road", 0);
        Check(![Visible(current) containsObject:notes[2]], "gapped source match remains outside Exact mode");

        // Mutating the existing models invalidates both sessions. The old session
        // remains the behavioral oracle, including retained editor rows.
        owner->selected = notes[0];
        [notes[0] setTitleString:@"Changed title"];
        [notes[0] setContentString:[[[NSAttributedString alloc] initWithString:@"unrelated"] autorelease]];
        [notes[0] setLabelString:@""];
        [current libraryDidChange]; [legacy libraryDidChange]; SameExact(current, legacy, @"retained edited note");
        Check([Visible(current) containsObject:notes[0]], "edited open note survives as a retained row");
        NSUInteger row = [current indexInFilteredListForNoteIdenticalTo:notes[0]];
        Check([[current matchKindAtIndex:row] isEqual:@"retained"], "retained note is outside Exact match membership");
        QueryPair(current, legacy, @"road copper", 0);
        Check(![Visible(current) containsObject:notes[0]], "next refinement excludes the retained editor from search candidates");
        owner->selected = nil;
        NoteObject *added = Note(@"Road later", @"copper"); [library addNote:added];
        [current libraryDidChange]; [legacy libraryDidChange]; SameExact(current, legacy, @"insert during refined query");
        Check([Visible(current) containsObject:added], "library invalidation adds new matches to a refined search");
        [library removeNote:added]; [current libraryDidChange]; [legacy libraryDidChange];
        SameExact(current, legacy, @"delete during refined query");
        Check(![Visible(current) containsObject:added], "deleted match leaves both Exact projections");

        // A second browser remains Exact while the first browser uses a real
        // asynchronous Fuzzy request, then returns to legacy Exact behavior.
        NVSearchService *service = [[[NVSearchService alloc] init] autorelease]; Capture(service, library);
        [current setSearchService:service];
        NVBrowserSession *other = [[[NVBrowserSession alloc] initWithLibrary:(id)library] autorelease];
        TestOwner *otherOwner = [[[TestOwner alloc] init] autorelease]; [other setDelegate:otherOwner];
        [other setSearchService:service]; [other setSearchMode:@"exact"];
        [other setSortColumn:(id)column reversed:YES]; [other filterNotesFromString:@"red blue"];
        NSArray *otherRows = [[Visible(other) copy] autorelease]; NSUInteger otherGeneration = [other searchGeneration];
        for (NSString *query in @[@"road", @"red:blue", @"résumé", @"!road"]) {
            [current setSearchMode:@"fuzzy"]; Search(current, query);
            Check([FuzzyUUIDs(current) isEqual:[[current searchResult] fuzzyNoteUUIDs]], "mode transition preserves the complete native Fuzzy tail");
            Check([[other searchMode] isEqual:@"exact"] && [Visible(other) isEqual:otherRows] && [other searchGeneration] == otherGeneration,
                  "another browser's Exact mode, rows, and generation survive Fuzzy searches");
            [current setSearchMode:@"exact"]; [legacy filterNotesFromString:query];
            SameExact(current, legacy, @"return from Fuzzy to Exact");
        }
        Autocomplete = NO;
        QueryPair(current, legacy, @"Road", 0);
        Check([current preferredSelectedNoteIndex] == NSNotFound, "disabled autocomplete remains disabled after mode changes");
        [current setDelegate:nil]; [other setDelegate:nil]; [legacy setDelegate:nil];
        printf("PASS: %lu assertions across %lu legacy Exact comparisons; %lu queries, three entry routes, two sort directions\n",
               Checks, ComparisonsWithLegacy, [Queries() count]);
    }
    return 0;
}
