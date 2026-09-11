
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

static NSString *HistoryUUID(NoteObject *note) {
    return [[NSData dataWithBytes:[note uniqueNoteIDBytes] length:sizeof(CFUUIDBytes)] base64EncodedStringWithOptions:0];
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

static void HistoryObserve(LinkingEditor *editor, NSString *step) {
    NSRange selection = editor.selectedRange;
    NSAttributedString *attributes = [[editor.textStorage copy] autorelease];
    NSDictionary *actual = HistoryGeometry(editor.layoutManager, editor.textContainer);
    BOOL cleared = HistoryCacheIsEmpty(editor.layoutManager.typesetter);
    NSDictionary *cold = HistoryColdGeometry(editor);
    NSUInteger covered = 0;
    BOOL contiguous = YES;
    for (NSDictionary *line in actual[@"lines"]) {
        NSRange range = NSRangeFromString(line[@"characters"]);
        if (range.location != covered || !range.length) contiguous = NO;
        covered = NSMaxRange(range);
    }
    BOOL equal = [actual isEqual:cold];
    NSMutableDictionary *record = [NSMutableDictionary dictionaryWithDictionary:@{
        @"step":step, @"length":@(editor.string.length), @"size":NSStringFromSize(editor.textContainer.containerSize),
        @"contiguous":@(contiguous && covered == editor.string.length), @"matchesCold":@(equal),
        @"lines":actual[@"lines"], @"cacheEmptyAfterLayout":@(cleared)}];
    if (!equal) { record[@"actual"] = actual; record[@"cold"] = cold; }
    [HistoryRecords addObject:record];
    [[NSJSONSerialization dataWithJSONObject:HistoryRecords options:NSJSONWritingPrettyPrinted error:NULL]
        writeToFile:[NSString stringWithUTF8String:getenv("NV_HISTORY_RESULT")] atomically:YES];
    Check(contiguous && covered == editor.string.length,
        [step stringByAppendingString:@": line fragments cover every source character once"]);
    Check(equal, [step stringByAppendingString:@": history layout equals fresh production layout"]);
    Check(cleared,
        [step stringByAppendingString:@": completed production layout retains neither analysis cache"]);
    Check([editor.textStorage isEqualToAttributedString:attributes] && NSEqualRanges(editor.selectedRange, selection),
        [step stringByAppendingString:@": layout preserves source attributes and selection"]);
}

static void HistorySource(NoteObject *note, LinkingEditor *a, LinkingEditor *b, NSString *source, NSString *step) {
    Check([a.string isEqual:source] && [b.string isEqual:source] && [[[note contentString] string] isEqual:source],
        [step stringByAppendingString:@": both editors and the model have exact expected source"]);
    Check(a.textStorage == b.textStorage, [step stringByAppendingString:@": both editors share one storage"]);
    HistoryObserve(a, [step stringByAppendingString:@" / first"]);
    HistoryObserve(b, [step stringByAppendingString:@" / peer"]);
}

static void HistoryReplace(AppController *browser, LinkingEditor *editor, NSRange range, NSString *text) {
    [browser.window makeKeyAndOrderFront:browser];
    [browser.window makeFirstResponder:editor];
    [editor insertText:text replacementRange:range];
    [browser finishEditing];
    Pump();
}
