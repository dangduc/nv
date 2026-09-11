
// This support follows the copied-app startup category and precedes its test method.
static NSMutableArray *HistoryRecords;
static void *HistoryCachePointer(id typesetter, const char *name) {
    Ivar ivar = class_getInstanceVariable(NSClassFromString(@"NVSourceTypesetter"), name);
    void *pointer = NULL;
    memcpy(&pointer, (const char *)(void *)typesetter + ivar_getOffset(ivar), sizeof(pointer));
    return pointer;
}

static BOOL HistoryCacheIsEmpty(id typesetter) {
    return !HistoryCachePointer(typesetter, "paragraphMeasure") && !HistoryCachePointer(typesetter, "lineBreaks");
}

static BOOL HistoryExactSource(LinkingEditor *editor, NoteObject *note, NSString *source) {
    NSData *expected = [source dataUsingEncoding:NSUTF8StringEncoding];
    return [[editor.string dataUsingEncoding:NSUTF8StringEncoding] isEqual:expected] &&
        [[[[note contentString] string] dataUsingEncoding:NSUTF8StringEncoding] isEqual:expected];
}

static NSDictionary *HistoryGeometry(NSLayoutManager *layout, NSTextContainer *container) {
    [layout ensureLayoutForTextContainer:container];
    NSMutableArray *lines = [NSMutableArray array], *positions = [NSMutableArray array];
    [layout enumerateLineFragmentsForGlyphRange:NSMakeRange(0, layout.numberOfGlyphs)
        usingBlock:^(NSRect rect, NSRect used, NSTextContainer *item, NSRange glyphs, BOOL *stop) {
            NSRange characters = [layout characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];
            [lines addObject:@{@"characters":NSStringFromRange(characters), @"glyphs":NSStringFromRange(glyphs),
                @"rect":NSStringFromRect(rect), @"used":NSStringFromRect(used),
                @"text":[layout.textStorage.string substringWithRange:characters]}];
        }];
    for (NSUInteger glyph = 0; glyph < layout.numberOfGlyphs; glyph++) {
        [positions addObject:NSStringFromPoint([layout locationForGlyphAtIndex:glyph])];
    }
    // TextKit retains an irrelevant origin for an absent extra line fragment.
    BOOL hasExtra = layout.extraLineFragmentTextContainer == container;
    return @{@"lines":lines, @"positions":positions,
        @"extraRect":NSStringFromRect(hasExtra ? layout.extraLineFragmentRect : NSZeroRect),
        @"extraUsed":NSStringFromRect(hasExtra ? layout.extraLineFragmentUsedRect : NSZeroRect)};
}

// The oracle runs the app's linked typesetter and glyph delegate, with no old
// paragraph or TextKit cache. It does not implement word-break rules.
static NSDictionary *HistoryColdGeometry(LinkingEditor *editor) {
    NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:editor.textStorage];
    NSLayoutManager *layout = [[[editor.layoutManager class] alloc] init];
    layout.delegate = editor;
    layout.usesFontLeading = editor.layoutManager.usesFontLeading;
    layout.typesetterBehavior = editor.layoutManager.typesetterBehavior;
    layout.hyphenationFactor = editor.layoutManager.hyphenationFactor;
    layout.typesetter = [[[NSClassFromString(@"NVSourceTypesetter") alloc] init] autorelease];
    NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:editor.textContainer.containerSize];
    container.lineFragmentPadding = editor.textContainer.lineFragmentPadding;
    [layout addTextContainer:container];
    [storage addLayoutManager:layout];
    NSTextView *view = [[NSTextView alloc] initWithFrame:editor.frame textContainer:container];
    view.typingAttributes = editor.typingAttributes;
    container.widthTracksTextView = NO;
    container.heightTracksTextView = NO;
    container.containerSize = editor.textContainer.containerSize;
    container.lineFragmentPadding = editor.textContainer.lineFragmentPadding;
    NSDictionary *geometry = [[HistoryGeometry(layout, container) retain] autorelease];
    [storage removeLayoutManager:layout];
    layout.delegate = nil;
    [view release]; [container release]; [layout release]; [storage release];
    return geometry;
}

static NSArray *LineRanges(NSDictionary *geometry) {
    return [geometry[@"lines"] valueForKey:@"characters"];
}

static BOOL CoversSource(NSDictionary *geometry, NSUInteger length) {
    NSUInteger covered=0;
    for (NSString *value in LineRanges(geometry)) {
        NSRange range=NSRangeFromString(value);
        if (range.location!=covered || !range.length) return NO;
        covered=NSMaxRange(range);
    }
    return covered==length;
}

static void ObserveCommand(NoteObject *note, LinkingEditor *first, LinkingEditor *second,
                           NSString *expected, NSString *label, NSUInteger command) {
    BOOL exact=HistoryExactSource(first,note,expected) && HistoryExactSource(second,note,expected);
    NSDictionary *a=HistoryGeometry(first.layoutManager,first.textContainer), *b=HistoryGeometry(second.layoutManager,second.textContainer);
    NSDictionary *freshA=HistoryColdGeometry(first), *freshB=HistoryColdGeometry(second);
    BOOL matchesA=[a isEqual:freshA], matchesB=[b isEqual:freshB];
    NSMutableDictionary *record=[NSMutableDictionary dictionaryWithDictionary:@{@"command":@(command),@"label":label,
        @"expectedSource":expected,@"sourceMatches":@(exact),@"firstMatchesFresh":@(matchesA),@"peerMatchesFresh":@(matchesB),
        @"firstRanges":LineRanges(a),@"peerRanges":LineRanges(b)}];
    if (!matchesA) { record[@"firstActual"]=a; record[@"firstFresh"]=freshA; }
    if (!matchesB) { record[@"peerActual"]=b; record[@"peerFresh"]=freshB; }
    [HistoryRecords addObject:record];
    [[NSJSONSerialization dataWithJSONObject:HistoryRecords options:NSJSONWritingPrettyPrinted error:NULL]
        writeToFile:[NSString stringWithUTF8String:getenv("NV_HISTORY_RESULT")] atomically:YES];
    Check(exact,[label stringByAppendingString:@": both editors and model match independent UTF-8 source"]);
    Check(matchesA && matchesB,[label stringByAppendingString:@": both native layouts match fresh production layouts"]);
    Check(CoversSource(a,expected.length) && CoversSource(b,expected.length),
        [label stringByAppendingString:@": both layouts cover every character exactly once"]);
}
