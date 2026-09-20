    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        NVApplicationController *app = [NVApplicationController sharedController];
        NotationController *library = [app library]; AppController *a = self;
        NVBrowserSession *sa = [a browserSession];
        [NSApp activateIgnoringOtherApps:YES]; [[a window] makeKeyAndOrderFront:self];
        Check(FuzzyAwait(^BOOL { return [NSApp isActive] && [[a window] isKeyWindow]; }, 3), @"fuzzy workflow owns active disposable browser");
        NoteObject *road = MakeNote(library, @"Road map", @"road planning committed source");
        NoteObject *body = MakeNote(library, @"Other", @"road and copper lantern\nroad second body line");
        NoteObject *gaps = MakeNote(library, @"Rivet", @"r---o---a---d");
        [a searchForString:@"road" mode:@"fuzzy"];
        Check(FuzzyAwait(^BOOL { return [sa searchResultsAreCurrent]; }, 10), @"actual browser publishes fuzzy result");
        Check([sa resultCount] == 5 && [sa distinctResultNoteCount] == 3, @"line search retains five matching lines in three notes");
        Check([[sa matchKindAtIndex:0] isEqual:@"fuzzy"], @"results contain no strict title group");
        Check(FuzzyRow(sa, body, @"title") == NSNotFound && FuzzyRow(sa, gaps, @"title") == NSNotFound, @"no note enters a strict title group");
        Check(FuzzyRow(sa, body, @"fuzzy") != NSNotFound && FuzzyRow(sa, gaps, @"fuzzy") != NSNotFound, @"complete source contributes native fuzzy matches");
        NSUInteger titleRow = FuzzyFieldRow(sa, road, @"title"), fuzzyRow = FuzzyFieldRow(sa, road, @"source");
        Check(titleRow != NSNotFound && fuzzyRow != NSNotFound, @"title and body matches have separate line rows");
        NotesTableView *resultTable = [a valueForKey:@"notesTableView"];
        Check(FuzzyAwait(^BOOL {
            for (NSUInteger row = 0; row < [sa resultCount]; row++) {
                NSAttributedString *preview = [sa previewForRow:row inTable:resultTable];
                __block BOOL highlighted = NO;
                [preview enumerateAttribute:NSBackgroundColorAttributeName inRange:NSMakeRange(0, [preview length]) options:0
                    usingBlock:^(id color, NSRange range, BOOL *stop) { if (color) highlighted = YES; }];
                if (!highlighted) return NO;
            }
            return YES;
        }, 5), @"all visible title and body result previews receive native match highlights");
        NSUInteger gapsRow = FuzzyFieldRow(sa, gaps, @"source");
        FuzzySelect(a, gapsRow); [[a window] makeFirstResponder:resultTable];
        NSAttributedString *selectedResult = [[resultTable dataSource] tableView:resultTable
            objectValueForTableColumn:[resultTable tableColumnWithIdentifier:NoteTitleColumnString] row:gapsRow];
        Check([selectedResult isKindOfClass:[NSAttributedString class]], @"selected table result preserves attributed match text");
        NSUInteger gapStart = [[selectedResult string] rangeOfString:@"r---o---a---d"].location;
        for (NSUInteger i = 0; i < 13; i++) {
            BOOL matchCharacter = i % 4 == 0;
            Check(([selectedResult attribute:NSBackgroundColorAttributeName atIndex:gapStart + i effectiveRange:NULL] != nil) == matchCharacter,
                @"selected result highlights matching characters and leaves fuzzy gaps clear");
        }
        Check([[selectedResult attribute:NSForegroundColorAttributeName atIndex:gapStart effectiveRange:NULL] isEqual:[NSColor blackColor]],
            @"selected match text remains readable on its highlight background");
        char *artifacts = getenv("NV_UI_ARTIFACTS");
        if (artifacts) {
            NSString *directory = [NSString stringWithUTF8String:artifacts];
            [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
            NSView *frame = [[[a window] contentView] superview];
            [frame layoutSubtreeIfNeeded]; [frame displayIfNeeded];
            NSBitmapImageRep *bitmap = [frame bitmapImageRepForCachingDisplayInRect:[frame bounds]];
            [frame cacheDisplayInRect:[frame bounds] toBitmapImageRep:bitmap];
            Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                writeToFile:[directory stringByAppendingPathComponent:@"fuzzy-line-results.png"] atomically:YES], @"save line-result window screenshot");
        }
        FuzzySelect(a, titleRow);
        LinkingEditor *editor = [a valueForKey:@"textView"];
        NVNoteEditingSession *editing = [a valueForKey:@"editingSession"];
        NSTextStorage *storage = [editor textStorage]; NSUndoManager *undo = [road undoManager];
        [[a window] makeFirstResponder:editor];
        [editor insertText:@"Undoable " replacementRange:NSMakeRange(0, 0)]; [a finishEditing];
        Check(FuzzyAwait(^BOOL { return [sa searchResultsAreCurrent]; }, 10), @"source edit refresh completes");
        titleRow = FuzzyFieldRow(sa, road, @"title"); fuzzyRow = FuzzyFieldRow(sa, road, @"source");
        FuzzySelect(a, titleRow); NSRange caret = NSMakeRange(4, 2); [editor setSelectedRange:caret];
        BOOL canUndo = [undo canUndo]; NSString *undoName = [[[undo undoActionName] copy] autorelease];
        FuzzySelect(a, fuzzyRow);
        Check([a selectedNoteObject] == road && [a valueForKey:@"editingSession"] == editing && [editor textStorage] == storage, @"duplicate occurrence reuses one editing session and text storage");
        Check([road undoManager] == undo && [undo canUndo] == canUndo && [[undo undoActionName] isEqual:undoName] && NSEqualRanges([editor selectedRange], caret), @"duplicate occurrence preserves Undo and caret");
        NSMutableIndexSet *duplicates = [NSMutableIndexSet indexSetWithIndex:titleRow]; [duplicates addIndex:fuzzyRow];
        Check([[sa notesAtIndexes:duplicates] isEqual:@[road]], @"multiple selected occurrences resolve to one document");
        NSString *fuzzyKey = [[[sa rowKeyAtIndex:fuzzyRow] copy] autorelease];
        NSDictionary *saved = [[[a browserWindowState] copy] autorelease];
        Check([saved[@"searchMode"] isEqual:@"fuzzy"] && [saved[@"searchRowKey"] isEqual:fuzzyKey], @"saved state retains fuzzy mode and selected occurrence");
        [app newWindow:self]; AppController *b = [[[app browserControllers] lastObject] retain]; NVBrowserSession *sb = [b browserSession];
        [b restoreBrowserWindowState:saved];
        Check(FuzzyAwait(^BOOL { return [sb searchResultsAreCurrent] && [b selectedNoteObject] == road; }, 10), @"second browser restores note after fuzzy completion");
        Check([[b selectedSearchResultRowKey] isEqual:fuzzyKey] && [b valueForKey:@"editingSession"] == editing, @"restoration preserves duplicate occurrence over shared editing session");
        Check(NSEqualRanges([[b valueForKey:@"textView"] selectedRange], caret), @"restoration applies saved source caret to restored note");
        LinkingEditor *peerEditor = [b valueForKey:@"textView"];
        for (LinkingEditor *view in @[editor, peerEditor]) [view setSearchHighlightRanges:@[[NSValue valueWithRange:NSMakeRange(0, 1)]]];
        [storage replaceCharactersInRange:NSMakeRange([storage length], 0) withString:@"x"];
        for (LinkingEditor *view in @[editor, peerEditor]) {
            NSDictionary *attributes = @{NSBackgroundColorAttributeName: [NSColor yellowColor]};
            NSRange range = NSMakeRange(0, 1);
            NSDictionary *drawing = [view layoutManager:[view layoutManager] shouldUseTemporaryAttributes:attributes
                forDrawingToScreen:NO atCharacterIndex:0 effectiveRange:&range];
            Check(!drawing[NSBackgroundColorAttributeName], @"shared character edit immediately suppresses stale highlight drawing");
        }
        Check(FuzzyAwait(^BOOL {
            return [[editor layoutManager] temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:0 effectiveRange:NULL] == nil &&
                [[peerEditor layoutManager] temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:0 effectiveRange:NULL] == nil;
        }, 3), @"deferred cleanup removes stale highlights from both browsers");
        [editing commitTextChanges];
        Check(FuzzyAwait(^BOOL { return [sa searchResultsAreCurrent] && [sb searchResultsAreCurrent]; }, 10), @"shared character edit reaches both current search results");
        NSMutableDictionary *legacy = [[saved mutableCopy] autorelease]; [legacy removeObjectForKey:@"searchMode"]; [legacy removeObjectForKey:@"searchRowKey"];
        [b restoreBrowserWindowState:legacy];
        Check([[b searchMode] isEqual:@"exact"] && [sb searchResultsAreCurrent] && [sb resultCount] == 2, @"legacy saved state retains exact substring semantics and one row per note");
        [a searchForString:@"copper" mode:@"exact"];
        Check([sa searchResultsAreCurrent] && [sa resultCount] == 1 && [sa noteObjectAtFilteredIndex:0] == body, @"Exact continues matching committed source substrings");

        // Hold only publication. The production service still parses and scores
        // the real snapshots; the actual AppController handles every intent.
        NSMutableArray *deliveries = [NSMutableArray array]; __block BOOL hold = YES;
        Method method = class_getInstanceMethod([NVSearchService class], @selector(requestForOwner:query:completion:));
        IMP original = method_getImplementation(method);
        IMP controlled = imp_implementationWithBlock(^NSUInteger(NVSearchService *service, id owner, NSString *query, NVSearchCompletion completion) {
            return ((NSUInteger(*)(id, SEL, id, id, id))original)(service, @selector(requestForOwner:query:completion:), owner, query, ^(NVSearchResult *result, NSError *error) {
                if (hold) [deliveries addObject:[[^{ completion(result, error); } copy] autorelease]];
                else completion(result, error);
            });
        });
        method_setImplementation(method, controlled);
        void (^releaseDeliveries)(void) = ^{
            NSArray *pending = [[deliveries copy] autorelease]; [deliveries removeAllObjects];
            for (void (^delivery)(void) in pending) delivery();
        };
        [[a window] makeKeyAndOrderFront:self];
        [a searchForString:@"road" mode:@"fuzzy"];
        Check(FuzzyAwait(^BOOL { return [deliveries count] > 0; }, 10) && [sa searchPending], @"publication hold establishes pending browser request");
        NSUInteger notesBeforeReturn = [[library allNotes] count];
        [a fieldAction:self];
        Check([[library allNotes] count] == notesBeforeReturn && [sa searchPending], @"Return during pending search cannot infer permission to create");
        hold = NO; releaseDeliveries();
        Check(FuzzyAwait(^BOOL { return [sa searchResultsAreCurrent] && [a selectedNoteObject] == road; }, 10), @"pending Return opens completed top-ranked result");
        Check([[library allNotes] count] == notesBeforeReturn, @"completed nonempty Return creates no note");

        hold = YES; [a searchForString:@"\"never create this obsolete query\"" mode:@"fuzzy"];
        Check(FuzzyAwait(^BOOL { return [deliveries count] > 0; }, 10), @"obsolete zero result is held before publication");
        [a fieldAction:self]; [a searchForString:@"copper" mode:@"fuzzy"];
        hold = NO; releaseDeliveries();
        Check(FuzzyAwait(^BOOL { return [sa searchResultsAreCurrent] && [[sa searchString] isEqual:@"copper"]; }, 10), @"new query supersedes deferred Return");
        Check([[library allNotes] count] == notesBeforeReturn, @"superseded zero result cannot create its old query");

        hold = YES; [a searchForString:@"\"future marker\"" mode:@"fuzzy"];
        Check(FuzzyAwait(^BOOL { return [deliveries count] > 0; }, 10), @"pre-edit membership completion is held");
        NSUInteger beforeMutation = [sa searchGeneration];
        [body setContentString:[[[NSAttributedString alloc] initWithString:@"road copper lantern future marker"] autorelease]];
        Check(![sa searchResultsAreCurrent] && [sa searchGeneration] > beforeMutation, @"model mutation invalidates browser ownership synchronously");
        hold = NO; releaseDeliveries();
        Check(FuzzyAwait(^BOOL { return [sa searchResultsAreCurrent] && FuzzyRow(sa, body, @"fuzzy") != NSNotFound; }, 10), @"post-edit corpus supersedes held membership without omission");

        hold = YES; [b searchForString:@"copper" mode:@"fuzzy"];
        Check(FuzzyAwait(^BOOL { return [deliveries count] > 0; }, 10), @"Reveal starts with pending membership");
        [b revealNote:road options:0];
        Check([[sb searchString] isEqual:@"copper"], @"Reveal does not clear query based on pending rows");
        hold = NO; releaseDeliveries();
        Check(FuzzyAwait(^BOOL { return [sb searchResultsAreCurrent] && [b selectedNoteObject] == road && ![[sb searchString] length]; }, 10), @"Reveal resolves exclusion after completion and selects target");

        hold = YES; [b searchForString:@"road" mode:@"fuzzy"];
        Check(FuzzyAwait(^BOOL { return [deliveries count] > 0; }, 10), @"closure starts with held result");
        [[b window] close]; NSUInteger browserCount = [[app browserControllers] count];
        hold = NO; releaseDeliveries(); Pump();
        Check([[app browserControllers] count] == browserCount && ![[app browserControllers] containsObject:b], @"closed browser rejects held completion and stays closed");
        method_setImplementation(method, original); imp_removeBlock(controlled); [b release];
        [a searchForString:@"road" mode:@"fuzzy"];
        Check(FuzzyAwait(^BOOL { return [sa searchResultsAreCurrent]; }, 10), @"remaining browser remains usable after peer closure");
        // Each result must reveal its own body match, even when the note is
        // already open or search decoration is disabled.
        NSMutableString *scrollSource = [NSMutableString string];
        NSMutableArray *scrollRanges = [NSMutableArray array];
        for (NSUInteger line = 0; line < 300; ++line) {
            if (line == 70 || line == 160 || line == 250) {
                [scrollRanges addObject:[NSValue valueWithRange:NSMakeRange([scrollSource length], 12)]];
                [scrollSource appendString:@"scrollneedle\n"];
            } else [scrollSource appendFormat:@"Filler line %03lu for editor scrolling.\n", (unsigned long)line];
        }
        NoteObject *scrollNote = MakeNote(library, @"Long scrolling fixture", scrollSource);
        [a searchForString:@"\"scrollneedle\"" mode:@"fuzzy"];
        Check(FuzzyAwait(^BOOL { return [sa searchResultsAreCurrent]; }, 10) && [sa resultCount] == 3, @"three distant body lines become separate candidates");
        [a setViewingNote:NO];
        NSMutableArray *scrollRows = [NSMutableArray array];
        for (NSValue *value in scrollRanges) {
            NSUInteger row = NSNotFound;
            for (NSUInteger i = 0; i < [sa resultCount]; ++i) {
                NVSearchMatch *match = [[sa searchResult] matchForRowKey:[sa rowKeyAtIndex:i]];
                if ([sa noteObjectAtFilteredIndex:i] == scrollNote && [[match line] range].location == [value rangeValue].location) row = i;
            }
            Check(row != NSNotFound, @"each distant line has a selectable row"); [scrollRows addObject:@(row)];
        }
        BOOL savedHighlightPreference = [prefsController highlightSearchTerms];
        for (NSNumber *decorate in @[@YES, @NO]) {
            [prefsController setShouldHighlightSearchTerms:[decorate boolValue] sender:nil];
            for (NSNumber *index in @[@1, @2, @0]) {
                NSUInteger occurrence = [index unsignedIntegerValue];
                NSRange matchRange = [scrollRanges[occurrence] rangeValue];
                [[editor layoutManager] ensureLayoutForCharacterRange:matchRange];
                [editor setSelectedRange:NSMakeRange(3, 0)]; [editor scrollPoint:NSZeroPoint];
                Check(!FuzzyRangeIsVerticallyVisible(editor, matchRange), @"target starts outside the editor viewport");
                NSUndoManager *beforeUndo = [scrollNote undoManager]; BOOL undoable = [beforeUndo canUndo];
                FuzzySelect(a, [scrollRows[occurrence] unsignedIntegerValue]);
                Check(FuzzyAwait(^BOOL { return FuzzyRangeIsVerticallyVisible(editor, matchRange); }, 3),
                    [NSString stringWithFormat:@"selected match %lu is in frame with highlights %@", (unsigned long)occurrence, [decorate boolValue] ? @"on" : @"off"]);
                Check(NSEqualRanges([editor selectedRange], NSMakeRange(3, 0)) && [scrollNote undoManager] == beforeUndo && [beforeUndo canUndo] == undoable,
                    @"revealing a match preserves the source caret and Undo");
            }
        }
        [prefsController setShouldHighlightSearchTerms:YES sender:nil];
        [editor scrollPoint:NSZeroPoint]; [a refreshSearchHighlights];
        NSRange firstScrollMatch = [scrollRanges[0] rangeValue];
        Check(FuzzyAwait(^BOOL { return [[editor layoutManager] temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:firstScrollMatch.location effectiveRange:NULL] != nil; }, 3),
            @"ordinary highlight refresh completes after manual scrolling");
        Check(fabs(NSMinY([editor visibleRect])) < 1, @"highlight refresh does not undo manual scrolling");

        // Hold validated ranges to deliver the newer row before the older row.
        NSMutableArray *scrollDeliveries = [NSMutableArray array];
        SEL validateSelector = @selector(validateSourceRanges:source:matchingSource:owner:completion:);
        Method validateMethod = class_getInstanceMethod([NVSearchService class], validateSelector);
        IMP validateOriginal = method_getImplementation(validateMethod);
        IMP validateHeld = imp_implementationWithBlock(^(NVSearchService *service, NSArray *ranges, NSString *source, NSString *matching, id owner, NVSearchLiteralRangesCompletion completion) {
            ((void(*)(id, SEL, id, id, id, id, id))validateOriginal)(service, validateSelector, ranges, source, matching, owner,
                ^(NSArray *validRanges, NSString *validSource, NSError *error) {
                    if (owner == sa) [scrollDeliveries addObject:[[^{ completion(validRanges, validSource, error); } copy] autorelease]];
                    else completion(validRanges, validSource, error);
                });
        });
        method_setImplementation(validateMethod, validateHeld);
        FuzzySelect(a, [scrollRows[1] unsignedIntegerValue]);
        Check(FuzzyAwait(^BOOL { return [scrollDeliveries count] == 1; }, 3), @"first row scroll completion is held");
        FuzzySelect(a, [scrollRows[2] unsignedIntegerValue]);
        Check(FuzzyAwait(^BOOL { return [scrollDeliveries count] == 2; }, 3), @"newer row scroll completion is held");
        ((void (^)(void))scrollDeliveries[1])();
        NSRange latestMatch = [scrollRanges[2] rangeValue];
        Check(FuzzyRangeIsVerticallyVisible(editor, latestMatch), @"newest row controls the editor viewport");
        NSPoint latestViewport = [editor visibleRect].origin;
        ((void (^)(void))scrollDeliveries[0])();
        Check(NSEqualPoints(latestViewport, [editor visibleRect].origin), @"obsolete completion cannot scroll back to the old row");
        method_setImplementation(validateMethod, validateOriginal); imp_removeBlock(validateHeld);
        [scrollDeliveries removeAllObjects];

        if (artifacts) {
            NSView *frame = [[[a window] contentView] superview];
            [frame layoutSubtreeIfNeeded]; [frame displayIfNeeded];
            NSBitmapImageRep *bitmap = [frame bitmapImageRepForCachingDisplayInRect:[frame bounds]];
            [frame cacheDisplayInRect:[frame bounds] toBitmapImageRep:bitmap];
            Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                writeToFile:[[NSString stringWithUTF8String:artifacts] stringByAppendingPathComponent:@"fuzzy-selected-body-match.png"] atomically:YES], @"save selected body match in frame");
        }

        // A saved viewport remains authoritative until a new row is selected.
        [editor scrollPoint:NSZeroPoint];
        NSDictionary *scrollState = [[[a browserWindowState] copy] autorelease];
        [app newWindow:self]; AppController *restoredBrowser = [[[app browserControllers] lastObject] retain];
        [restoredBrowser restoreBrowserWindowState:scrollState];
        LinkingEditor *restoredEditor = [restoredBrowser valueForKey:@"textView"];
        Check(FuzzyAwait(^BOOL {
            return [[restoredBrowser browserSession] searchResultsAreCurrent] && [restoredBrowser selectedNoteObject] == scrollNote &&
                [[restoredEditor layoutManager] temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:latestMatch.location effectiveRange:NULL] != nil;
        }, 3), @"restored window finishes its occurrence highlights");
        Check(fabs(NSMinY([restoredEditor visibleRect])) < 1, @"restoration preserves saved viewport instead of scrolling to a match");
        [[restoredBrowser window] close]; [restoredBrowser release];

        [editor scrollPoint:NSZeroPoint]; [a setViewingNote:YES];
        FuzzySelect(a, [scrollRows[0] unsignedIntegerValue]);
        Check(FuzzyAwait(^BOOL {
            return [[editor layoutManager] temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:firstScrollMatch.location effectiveRange:NULL] != nil;
        }, 3) && [[a valueForKey:@"viewingNote"] boolValue] && [[a valueForKey:@"searchScrollPending"] boolValue],
            @"selection in Preview defers source scrolling");
        [a setViewingNote:NO];
        Check(FuzzyAwait(^BOOL { return FuzzyRangeIsVerticallyVisible(editor, firstScrollMatch); }, 3),
            @"returning to Source reveals the pending selected match");

        NoteObject *secondScrollNote = MakeNote(library, @"Second long scrolling fixture", scrollSource);
        Check(FuzzyAwait(^BOOL { return [sa searchResultsAreCurrent] && [sa resultCount] == 6; }, 10), @"a second note supplies three more body entries");
        NSUInteger secondRow = NSNotFound;
        for (NSUInteger i = 0; i < [sa resultCount]; ++i) {
            NVSearchMatch *match = [[sa searchResult] matchForRowKey:[sa rowKeyAtIndex:i]];
            if ([sa noteObjectAtFilteredIndex:i] == secondScrollNote && [[match line] range].location == latestMatch.location) secondRow = i;
        }
        Check(secondRow != NSNotFound, @"distant match in another note has its own row");
        FuzzySelect(a, secondRow);
        Check(FuzzyAwait(^BOOL { return [a selectedNoteObject] == secondScrollNote && FuzzyRangeIsVerticallyVisible(editor, latestMatch); }, 3),
            @"selecting a different note also reveals its selected match");
        [prefsController setShouldHighlightSearchTerms:savedHighlightPreference sender:nil];

        NSMutableString *listSource = [NSMutableString string];
        for (NSUInteger i = 0; i < 120; i++) [listSource appendFormat:@"scrollpreview row %03lu\n", (unsigned long)i];
        MakeNote(library, @"List scroll fixture", listSource);
        NSMutableArray *listDeliveries = [NSMutableArray array];
        __block BOOL holdListPositions = YES;
        SEL listSelector = @selector(requestPositionsForRowKey:requestID:owner:positionOwner:completion:);
        Method listMethod = class_getInstanceMethod([NVSearchService class], listSelector);
        IMP listOriginal = method_getImplementation(listMethod);
        __block BOOL dropListRepaints = NO;
        IMP listHeld = imp_implementationWithBlock(^(NVSearchService *service, NSString *key, NSUInteger requestID, id owner, id positionOwner, NVSearchPositionsCompletion completion) {
            ((void(*)(id, SEL, id, NSUInteger, id, id, id))listOriginal)(service, listSelector, key, requestID, owner, positionOwner,
                ^(NVSearchPositions *positions, NSError *error) {
                    if (holdListPositions && owner == sa && positionOwner == [sa valueForKey:@"excerptOwner"])
                        [listDeliveries addObject:[[^{ completion(positions, error); } copy] autorelease]];
                    else completion(positions, error);
                });
        });
        method_setImplementation(listMethod, listHeld);
        if (getenv("NV_FUZZ_DROP_REPAINTS")) {
            SEL rowReloadSelector = @selector(reloadDataForRowIndexes:columnIndexes:);
            Method rowReloadMethod = class_getInstanceMethod([NSTableView class], rowReloadSelector);
            IMP rowReloadOriginal = method_getImplementation(rowReloadMethod);
            IMP rowReloadDropped = imp_implementationWithBlock(^(NSTableView *table, NSIndexSet *rows, NSIndexSet *columns) {
                if (table != resultTable || !dropListRepaints)
                    ((void(*)(id, SEL, id, id))rowReloadOriginal)(table, rowReloadSelector, rows, columns);
            });
            Check(class_addMethod([NotesTableView class], rowReloadSelector, rowReloadDropped, method_getTypeEncoding(rowReloadMethod)),
                @"negative control intercepts row reloads");
            SEL fullReloadSelector = @selector(reloadData);
            Method fullReloadMethod = class_getInstanceMethod([NotesTableView class], fullReloadSelector);
            IMP fullReloadOriginal = method_getImplementation(fullReloadMethod);
            IMP fullReloadDropped = imp_implementationWithBlock(^(NSTableView *table) {
                if (table != resultTable || !dropListRepaints)
                    ((void(*)(id, SEL))fullReloadOriginal)(table, fullReloadSelector);
            });
            method_setImplementation(fullReloadMethod, fullReloadDropped);
            SEL displaySelector = @selector(displayRectIgnoringOpacity:);
            Method displayMethod = class_getInstanceMethod([NSView class], displaySelector);
            IMP displayOriginal = method_getImplementation(displayMethod);
            IMP displayDropped = imp_implementationWithBlock(^(NSView *view, NSRect rect) {
                if (view != resultTable || !dropListRepaints)
                    ((void(*)(id, SEL, NSRect))displayOriginal)(view, displaySelector, rect);
            });
            Check(class_addMethod([NotesTableView class], displaySelector, displayDropped, method_getTypeEncoding(displayMethod)),
                @"negative control intercepts forced visible draws");
        }
        [a searchForString:@"scrollpreview" mode:@"fuzzy"];
        Check(FuzzyAwait(^BOOL { return [sa searchResultsAreCurrent] && [sa resultCount] == 120; }, 10),
            @"long result list supplies multiple viewports of body matches");
        [resultTable scrollRowToVisible:0 withVerticalOffset:0];
        NSRange firstViewport = [resultTable rowsInRect:[resultTable visibleRect]];
        Check(firstViewport.length > 0 && NSMaxRange(firstViewport) < 60, @"scroll fixture spans separate viewports");
        NSInteger titleColumn = [resultTable columnWithIdentifier:NoteTitleColumnString];
        BOOL (^rowsHighlighted)(NSRange) = ^BOOL(NSRange rows) {
            for (NSUInteger row = rows.location; row < NSMaxRange(rows); row++) {
                NSAttributedString *value = [[resultTable preparedCellAtColumn:titleColumn row:row] attributedStringValue];
                NSUInteger at = [[value string] rangeOfString:@"scrollpreview"].location;
                if (at == NSNotFound || ![value attribute:NSBackgroundColorAttributeName atIndex:at effectiveRange:NULL]) return NO;
            }
            return YES;
        };
        Check(!rowsHighlighted(NSMakeRange(60, 1)), @"offscreen native cell is prepared before its highlights arrive");
        Check(FuzzyAwait(^BOOL { return [listDeliveries count] > 0; }, 5), @"position completion waits while the table caches an unhighlighted cell");
        NSUInteger windowPixelsBeforePositions = FuzzyCompositedHighlightPixelsInWindow([resultTable window]);
        Check(windowPixelsBeforePositions != NSNotFound, @"compositor snapshot is available while native positions are held");
        dropListRepaints = getenv("NV_FUZZ_DROP_REPAINTS") != NULL;
        holdListPositions = NO;
        for (void (^delivery)(void) in [[listDeliveries copy] autorelease]) delivery();
        [listDeliveries removeAllObjects];
        Check(FuzzyAwait(^BOOL { return [[sa valueForKey:@"excerptPositions"] count] == [sa resultCount]; }, 10),
            @"held native positions finish before compositor validation");
        NSUInteger windowPixelsAfterPositions = FuzzyCompositedHighlightPixelsInWindow([resultTable window]);
        NSLog(@"COMPOSITOR_HIGHLIGHT before=%lu after_positions=%lu", (unsigned long)windowPixelsBeforePositions,
            (unsigned long)windowPixelsAfterPositions);
        Check(windowPixelsBeforePositions != NSNotFound && windowPixelsAfterPositions > windowPixelsBeforePositions + 100,
            @"completed position pass updates existing compositor pixels without user interaction");
        Check(FuzzyAwait(^BOOL { return rowsHighlighted(firstViewport); }, 5), @"first viewport receives match highlights");
        Check([[sa valueForKey:@"excerptPositions"] count] == [sa resultCount],
            @"idle browser prepares all result highlights without scrolling");
        [resultTable scrollRowToVisible:60 withVerticalOffset:0];
        NSRange distantViewport = [resultTable rowsInRect:[resultTable visibleRect]];
        Check(distantViewport.location >= NSMaxRange(firstViewport), @"native table scroll moves every original row out of view");
        Check(rowsHighlighted(distantViewport), @"previously unseen distant rows highlight on their first draw after idle preparation");
        [resultTable scrollRowToVisible:0 withVerticalOffset:0];
        Check(rowsHighlighted(firstViewport), @"returning native table rows retain highlights without waiting for another lookup");

        if (getenv("NV_FUZZ_LIST_HIGHLIGHTS")) {
            const char *seedText = getenv("NV_FUZZ_SEED");
            const char *iterationText = getenv("NV_FUZZ_ITERATIONS");
            __block uint32_t fuzzState = seedText ? (uint32_t)strtoul(seedText, NULL, 10) : 0x4e56414c;
            NSUInteger fuzzSeed = fuzzState;
            NSUInteger fuzzIterations = iterationText ? strtoul(iterationText, NULL, 10) : 40;
            BOOL naturalTiming = getenv("NV_FUZZ_NATURAL") != NULL;
            uint32_t (^nextRandom)(void) = ^uint32_t {
                fuzzState = fuzzState * 1664525u + 1013904223u;
                return fuzzState;
            };
            [[a window] setContentSize:NSMakeSize(1160, 980)];
            [a setNotesListHeight:760];
            [[a window] makeFirstResponder:[a valueForKey:@"field"]];
            [resultTable deselectAll:self];
            NSLog(@"FUZZ_LIST_HIGHLIGHTS seed=%lu iterations=%lu natural=%d", (unsigned long)fuzzSeed,
                (unsigned long)fuzzIterations, naturalTiming);
            for (NSUInteger iteration = 0; iteration < fuzzIterations; iteration++) {
                holdListPositions = NO;
                for (NSString *prefix in @[@"scl", @"scrlp", @"scrollprev"]) {
                    [a searchForString:prefix mode:@"fuzzy"];
                    if (nextRandom() % 3 == 0)
                        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.002]];
                }
                holdListPositions = !naturalTiming;
                NSString *query = iteration % 2 ? @"SCROLLPREVIEW" : @"scrollpreview";
                [a searchForString:query mode:@"fuzzy"];
                Check(FuzzyAwait(^BOOL { return [sa searchResultsAreCurrent] && [sa resultCount] == 120; }, 10),
                    @"fuzz iteration publishes the complete result list");
                NSMutableArray *trace = [NSMutableArray array];
                NSUInteger initialRow = nextRandom() % [sa resultCount];
                [resultTable scrollRowToVisible:initialRow withVerticalOffset:0];
                [trace addObject:@(initialRow)];
                NSDate *positionDeadline = [NSDate dateWithTimeIntervalSinceNow:10];
                while ([[sa valueForKey:@"excerptPositions"] count] < [sa resultCount]) {
                    if (naturalTiming) {
                        if ([positionDeadline timeIntervalSinceNow] <= 0) {
                            NSLog(@"FUZZ_SCHEDULER_STALL seed=%lu iteration=%lu active=%@ next=%@ positions=%lu trace=%@",
                                (unsigned long)fuzzSeed, (unsigned long)iteration, [sa valueForKey:@"activeExcerptKey"],
                                [sa valueForKey:@"nextExcerptRow"], (unsigned long)[[sa valueForKey:@"excerptPositions"] count], trace);
                            Check(NO, @"natural fuzz scheduler completes every position request");
                        }
                        if (nextRandom() % 4 == 0) {
                            NSUInteger row = nextRandom() % [sa resultCount];
                            [resultTable scrollRowToVisible:row withVerticalOffset:0];
                            [trace addObject:@(row)];
                        }
                        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.001]];
                        continue;
                    }
                    if (!FuzzyAwait(^BOOL { return [listDeliveries count] > 0; }, 5)) {
                        NSLog(@"FUZZ_SCHEDULER_STALL seed=%lu iteration=%lu active=%@ next=%@ positions=%lu trace=%@",
                            (unsigned long)fuzzSeed, (unsigned long)iteration, [sa valueForKey:@"activeExcerptKey"],
                            [sa valueForKey:@"nextExcerptRow"], (unsigned long)[[sa valueForKey:@"excerptPositions"] count], trace);
                        Check(NO, @"fuzz scheduler produces the next held position completion");
                    }
                    NSUInteger actions = nextRandom() % 3;
                    for (NSUInteger action = 0; action < actions; action++) {
                        NSUInteger row = nextRandom() % [sa resultCount];
                        [resultTable scrollRowToVisible:row withVerticalOffset:0];
                        [trace addObject:@(row)];
                        if (nextRandom() % 8 == 0)
                            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.001]];
                    }
                    void (^delivery)(void) = [[[listDeliveries objectAtIndex:0] retain] autorelease];
                    [listDeliveries removeObjectAtIndex:0];
                    delivery();
                    if (nextRandom() % 8 == 0)
                        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.001]];
                }
                holdListPositions = NO;
                Check(![[[sa valueForKey:@"excerptPositions"] allValues] containsObject:[NSNull null]],
                    @"generation churn produces positions for every final result");
                [resultTable scrollRowToVisible:0 withVerticalOffset:0];
                Pump(); [[a window] displayIfNeeded];
                BOOL failed = NO;
                NSUInteger viewportStride = iteration % 10 == 0 ? 7 : 29;
                for (NSUInteger start = 0; start < [sa resultCount] && !failed; start += viewportStride) {
                    [resultTable scrollRowToVisible:start withVerticalOffset:0];
                    Pump(); [[a window] displayIfNeeded];
                    NSRange visible = [resultTable rowsInRect:[resultTable visibleRect]];
                    NSUInteger last = iteration % 10 == 0 ? NSMaxRange(visible) : MIN(NSMaxRange(visible), visible.location + 1);
                    for (NSUInteger row = visible.location; row < last; row++) {
                        NSUInteger pixels = FuzzyDrawnHighlightPixelsForRow(resultTable, row);
                        if (pixels == NSNotFound) continue;
                        if (!pixels) {
                            Pump(); [[a window] displayIfNeeded];
                            NSUInteger repeated = FuzzyDrawnHighlightPixelsForRow(resultTable, row);
                            NSAttributedString *value = [sa previewForRow:row inTable:resultTable];
                            NSUInteger at = [[value string] rangeOfString:@"scrollpreview" options:NSCaseInsensitiveSearch].location;
                            BOOL cached = at != NSNotFound && [value attribute:NSBackgroundColorAttributeName atIndex:at effectiveRange:NULL] != nil;
                            NSLog(@"FUZZ_LIST_FAILURE seed=%lu iteration=%lu row=%lu pixels=%lu repeated=%lu cached=%d positions=%lu trace=%@",
                                (unsigned long)fuzzSeed, (unsigned long)iteration, (unsigned long)row, (unsigned long)pixels,
                                (unsigned long)repeated, cached, (unsigned long)[[sa valueForKey:@"excerptPositions"] count], trace);
                            failed = YES;
                            break;
                        }
                    }
                }
                Check(!failed, @"every fuzzed result row paints its cached match highlight without another user action");
                NSLog(@"FUZZ_LIST_ITERATION seed=%lu iteration=%lu actions=%lu PASSED", (unsigned long)fuzzSeed,
                    (unsigned long)iteration, (unsigned long)[trace count]);
            }
        }
        method_setImplementation(listMethod, listOriginal); imp_removeBlock(listHeld);

        // Switching documents used to lay out every preceding line while restoring
        // the old viewport, before revealing the chosen fuzzy occurrence anyway.
        NSMutableString *longSource = [NSMutableString string];
        for (NSUInteger line = 0; line < 4000; line++)
            [longSource appendFormat:@"line %lu: ordinary words that need to be laid out in the text container to show this note correctly.\n", (unsigned long)line];
        NSRange endMatch = NSMakeRange([longSource length], [@"selectionlatency" length]);
        [longSource appendString:@"selectionlatency near the end\n"];
        NoteObject *longFirst = MakeNote(library, @"Long first", longSource);
        NoteObject *longSecond = MakeNote(library, @"Long second", longSource);
        [a searchForString:@"selectionlatency" mode:@"fuzzy"];
        Check(FuzzyAwait(^BOOL { return [sa searchResultsAreCurrent]; }, 10), @"long-note search completes");
        NSUInteger longRows[] = {FuzzyFieldRow(sa, longFirst, @"source"), FuzzyFieldRow(sa, longSecond, @"source")};
        __block NSUInteger oldViewportRestores = 0;
        Method restoreMethod = class_getInstanceMethod([AppController class], @selector(restoreSourceScroll));
        IMP originalRestore = method_getImplementation(restoreMethod);
        IMP countRestores = imp_implementationWithBlock(^(AppController *browser) {
            if (browser == a) oldViewportRestores++;
            ((void(*)(id, SEL))originalRestore)(browser, @selector(restoreSourceScroll));
        });
        method_setImplementation(restoreMethod, countRestores);
        for (NSUInteger iteration = 0; iteration < 8; iteration++) {
            CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
            FuzzySelect(a, longRows[iteration % 2]);
            Check(FuzzyAwait(^BOOL { return ![[a valueForKey:@"searchScrollPending"] boolValue]; }, 10), @"cross-note match reveal completes");
            NSTimeInterval elapsed = CFAbsoluteTimeGetCurrent() - start;
            Check(FuzzyRangeIsVerticallyVisible(editor, endMatch), @"long-note matched segment is in frame");
            Check([[editor layoutManager] firstUnlaidCharacterIndex] < endMatch.location / 2,
                @"revealing the match leaves the distant preceding text unlaid");
            Check(oldViewportRestores == 0, @"cross-note match selection skips the obsolete saved viewport");
            NSLog(@"FUZZY_SELECTION_LATENCY iteration=%lu milliseconds=%.2f", (unsigned long)iteration, elapsed * 1000);
        }
        method_setImplementation(restoreMethod, originalRestore); imp_removeBlock(countRestores);
        [a searchForString:@"selectionlatency" mode:@"exact"];
        Check(![[editor layoutManager] allowsNonContiguousLayout], @"Exact selection retains contiguous layout for saved scroll restoration");
        NSLog(@"FUZZY APP WORKFLOW PASSED (%lu checks)", (unsigned long)Checks);
        [library flushAllNoteChanges]; [library closeJournal];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] synchronize]; exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: fuzzy workflow exception %@", exception); exit(1); }
}
@end
