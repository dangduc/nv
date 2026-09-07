// Reuse only the in-memory fixture definitions. This file supplies a new trace.
#define main ExistingSearchRegressionMain
#include "../../../Regression/search/search_regression.m"
#undef main

static uint32_t Seed = 0xD4A1C002;
static uint32_t Next(void) { Seed = Seed * 1664525U + 1013904223U; return Seed; }
static id Pick(NSArray *values) { return [values objectAtIndex:Next() % [values count]]; }
static void Verify(NVBrowserSession *session, TestLibrary *library, TestOwner *owner, BOOL pinned, NSUInteger step) {
    NVBrowserSession *fresh = [[[NVBrowserSession alloc] initWithLibrary:(id)library] autorelease];
    [fresh filterNotesFromString:[session searchString]];
    [fresh setSortColumn:[session sortColumn] reversed:[session reverseSorted]];
    if (pinned) { [fresh setDelegate:owner]; [fresh libraryDidChange]; }
    NSArray *actual = Visible(session), *expected = Visible(fresh);
    if (![actual isEqualToArray:expected]) {
        NSLog(@"MISMATCH step=%lu query=%@ actual=%@ expected=%@", (unsigned long)step, [session searchString], actual, expected);
        exit(1);
    }
    Checks++;
    [fresh setDelegate:nil];
}

int main(void) {
    @autoreleasepool {
        NSArray *words = @[@"alpha", @"beta", @"gamma", @"Straße", @"STRASSE", @"İ", @"i", @"i\u0307",
            @"café", @"cafe\u0301", @"Σ", @"ς", @"σ", @"Tiếng Việt", @"🙂", @"a:b", @"absent"];
        NSMutableArray *queries = [NSMutableArray arrayWithObjects:@"", @"\"", @"alpha beta", @"\"alpha beta\"",
            @"alpha:\"beta\"", @"\"alpha beta", @"\"alpha:beta\"", @"alpha:beta", @"absentxyz", nil];
        [queries addObjectsFromArray:words];
        for (NSString *word in words) {
            [queries addObject:[word uppercaseString]];
            [queries addObject:[word substringToIndex:1]];
            [queries addObject:[NSString stringWithFormat:@"\"%@\"", word]];
        }
        NSMutableArray *initial = [NSMutableArray array];
        for (NSUInteger i = 0; i < 32; i++) {
            [initial addObject:Note([NSString stringWithFormat:@"N%04lu", (unsigned long)i],
                [NSString stringWithFormat:@"%@ %@", Pick(words), Pick(words)])];
        }
        TestLibrary *library = [[[TestLibrary alloc] initWithNotes:initial] autorelease];
        NSMutableArray *retainedNotes = [NSMutableArray arrayWithArray:initial];
        NVBrowserSession *sessions[2] = {
            [[[NVBrowserSession alloc] initWithLibrary:(id)library] autorelease],
            [[[NVBrowserSession alloc] initWithLibrary:(id)library] autorelease]
        };
        TestOwner *owners[2] = { [[[TestOwner alloc] init] autorelease], [[[TestOwner alloc] init] autorelease] };
        BOOL pinned[2] = { NO, NO };
        for (NSUInteger i = 0; i < 2; i++) [sessions[i] setDelegate:owners[i]];
        NSUInteger actions[9] = { 0 };
        for (NSUInteger step = 0; step < 4000; step++) {
            @autoreleasepool {
                NSUInteger which = (Next() >> 8) % 2, action = (Next() >> 8) % 9;
                actions[action]++;
                NSArray *notes = [library allNotes];
                NoteObject *note = [notes count] ? Pick(notes) : nil;
                BOOL changed = NO;
                switch (action) {
                    case 0: case 1:
                        [sessions[which] filterNotesFromString:Pick(queries)]; pinned[which] = NO; break;
                    case 2:
                        if (note) [note setContentString:[[[NSAttributedString alloc] initWithString:
                            [NSString stringWithFormat:@"%@ %@", Pick(words), Pick(words)]] autorelease]];
                        changed = YES; break;
                    case 3:
                        if (note) { [note->titleString release]; note->titleString = [Pick(words) copy]; }
                        changed = YES; break;
                    case 4:
                        if (note) { [note->labelString release]; note->labelString = [Pick(words) copy]; }
                        changed = YES; break;
                    case 5: {
                        NoteObject *added = Note([NSString stringWithFormat:@"Added%04lu", (unsigned long)step], Pick(words));
                        [library addNote:added]; [retainedNotes addObject:added]; changed = YES; break;
                    }
                    case 6:
                        if (note) [library removeNote:note]; changed = YES; break;
                    case 7:
                        [sessions[which] setSortColumn:nil reversed:![sessions[which] reverseSorted]]; break;
                    case 8:
                        owners[which]->selected = note;
                        [sessions[which] libraryDidChange]; pinned[which] = YES; break;
                }
                if (changed) {
                    for (NSUInteger i = 0; i < 2; i++) {
                        // Every 17th mutation defers the UI callback, then searches
                        // before that callback can run. The cache must be invalid.
                        owners[i]->allowsChange = step % 17 != 0;
                        [sessions[i] libraryDidChange];
                        pinned[i] = owners[i]->allowsChange;
                        if (!owners[i]->allowsChange) {
                            [sessions[i] filterNotesFromString:[sessions[i] searchString]];
                            [NSObject cancelPreviousPerformRequestsWithTarget:sessions[i]];
                            owners[i]->allowsChange = YES;
                        }
                    }
                }
                for (NSUInteger i = 0; i < 2; i++) Verify(sessions[i], library, owners[i], pinned[i], step);
            }
        }
        // Confirm the original performance fix after a long mutable trace.
        for (NSUInteger i = 0; i < 2; i++) {
            [sessions[i] filterNotesFromString:@"certainlymissing123"];
            ContentsReads = LibraryReads = 0;
            [sessions[i] filterNotesFromString:@"certainlymissing1234"];
            Check(ContentsReads == 0 && LibraryReads == 0, "zero-result refinement stays constant after mutation trace");
            [sessions[i] setDelegate:nil];
        }
        printf("DIFFERENTIAL TRACE PASSED: seed=0xD4A1C002 steps=4000 comparisons=%lu queries=%lu\n",
            (unsigned long)Checks, (unsigned long)[queries count]);
        for (NSUInteger i = 0; i < 9; i++) printf("action_%lu=%lu\n", (unsigned long)i, (unsigned long)actions[i]);
    }
    return 0;
}
