    unsetenv("DYLD_INSERT_LIBRARIES");
    @try {
        NotationController *library = [[NVApplicationController sharedController] library];
        if (getenv("NV_REVIEW_MUTATE_UNDO_LINE_ENDINGS")) {
            Method method = class_getInstanceMethod([NVNoteEditingSession class], @selector(restoreContents:));
            IMP original = method_getImplementation(method);
            method_setImplementation(method, imp_implementationWithBlock(^(id object, NSAttributedString *contents) {
                NSString *normalized = [[contents string] stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
                NSAttributedString *replacement = [[[NSAttributedString alloc] initWithString:normalized] autorelease];
                ((void(*)(id, SEL, id))original)(object, @selector(restoreContents:), replacement);
            }));
            NSLog(@"NEGATIVE CONTROL: Undo restoration normalizes CRLF");
        }
        AlienNoteImporter *importer = [[[AlienNoteImporter alloc] init] autorelease];
        NSString *unicode = @" \t# Source\r\nA e\u0301 é 😀 👩‍💻\rB\n\u2028C\u2029https://example.invalid/x\r\n\n";
        NSString *legacy = @" \t# Source\r\nA café £ –\rB\nhttps://example.invalid/x\r\n\n";
        const unsigned char utf8[] = {0xEF, 0xBB, 0xBF}, utf16le[] = {0xFF, 0xFE}, utf32be[] = {0, 0, 0xFE, 0xFF};
        NSArray *fixtures = @[
            @{ @"text": unicode, @"encoding": @(NSUTF8StringEncoding), @"bom": [NSData data] },
            @{ @"text": unicode, @"encoding": @(NSUTF8StringEncoding), @"bom": [NSData dataWithBytes:utf8 length:3] },
            @{ @"text": unicode, @"encoding": @(NSUTF16LittleEndianStringEncoding), @"bom": [NSData dataWithBytes:utf16le length:2] },
            @{ @"text": unicode, @"encoding": @(NSUTF32BigEndianStringEncoding), @"bom": [NSData dataWithBytes:utf32be length:4] },
            @{ @"text": legacy, @"encoding": @(NSWindowsCP1252StringEncoding), @"bom": [NSData data] },
            @{ @"text": @" \t\r\n\r\n", @"encoding": @(NSUTF8StringEncoding), @"bom": [NSData data] },
            @{ @"text": @"", @"encoding": @(NSUTF8StringEncoding), @"bom": [NSData dataWithBytes:utf8 length:3] }
        ];
        NSUInteger histories = 0;
        for (NSDictionary *fixture in fixtures) {
            NSString *source = fixture[@"text"];
            NSStringEncoding encoding = [fixture[@"encoding"] unsignedIntegerValue];
            NSData *originalBytes = SourceBytes(source, encoding, fixture[@"bom"]);
            NSString *path = [TestDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"history-%lu.md", (unsigned long)histories]];
            Check([originalBytes writeToFile:path atomically:YES], @"history source fixture writes");
            [[NSFileManager defaultManager] setTextEncodingAttribute:encoding atFSPath:[path fileSystemRepresentation]];
            NoteObject *note = [importer noteWithFile:path];
            Check(note && [[[note contentString] string] isEqual:source], @"import retains each Unicode unit and newline boundary");
            [library addNewNote:note];
            NVNoteEditingSession *session = [[[NVNoteEditingSession alloc] initWithNote:note] autorelease];
            NSTextStorage *storage = [session textStorage];
            NSMutableArray *layouts = [NSMutableArray array];
            for (NSUInteger index = 0; index < 2; index++) {
                NSLayoutManager *layout = [[[NSLayoutManager alloc] init] autorelease];
                NSTextContainer *container = [[[NSTextContainer alloc] initWithContainerSize:NSMakeSize(600, CGFLOAT_MAX)] autorelease];
                [layout addTextContainer:container];
                [storage addLayoutManager:layout];
                [layouts addObject:layout];
            }
            [session sourceLayoutDidAttach];
            Check([[storage string] isEqual:source] && [[note sourceDataReturningError:NULL] isEqual:originalBytes], @"shared editable storage starts with original source and bytes");
            [[note undoManager] removeAllActions];
            NSMutableString *first = [NSMutableString stringWithString:source];
            NSRange firstNewline = [first rangeOfString:@"\r\n"];
            if (firstNewline.location != NSNotFound) [first replaceCharactersInRange:firstNewline withString:@"\n"];
            else [first appendString:@"\n"];
            [storage replaceCharactersInRange:NSMakeRange(0, [storage length]) withString:first];
            [session commitTextChanges];
            Check([session canUndo] && [[[note contentString] string] isEqual:first], @"first edit commits an intentional newline change");
            NSString *second = [first stringByAppendingString:@" edited\r\n"];
            [storage replaceCharactersInRange:NSMakeRange([storage length], 0) withString:@" edited\r\n"];
            [session commitTextChanges];
            Check([[[note contentString] string] isEqual:second] && [[note sourceDataReturningError:NULL] isEqual:SourceBytes(second, encoding, fixture[@"bom"])], @"second edit keeps the remaining original boundaries and encoding");
            CFAbsoluteTime modified = modifiedDateOfNote(note);
            uint64_t generation = [session sourceGeneration];
            for (NSString *syntax in @[@"json", @"html", @"textile", @"plain", @"markdown"]) [note setSourceSyntaxIdentifier:syntax];
            [session commitPendingTextChanges];
            Check([session sourceGeneration] == generation && modifiedDateOfNote(note) == modified && [[[note contentString] string] isEqual:second], @"syntax changes and display refresh do not commit a source edit");
            [session undo];
            Check([[storage string] isEqual:first] && [[[note contentString] string] isEqual:first], @"first Undo removes only the second edit after five syntax changes");
            [session undo];
            Check([[storage string] isEqual:source] && [[[note contentString] string] isEqual:source], @"second Undo restores every original Unicode unit and newline boundary");
            Check([[note sourceDataReturningError:NULL] isEqual:originalBytes] && ![session canUndo] && [session canRedo], @"complete Undo recovers exact original bytes and exactly two history entries");
            Check([[note sourceSyntaxIdentifier] isEqual:@"markdown"], @"source Undo does not revert local syntax metadata");
            [session redo]; [session redo];
            Check([[storage string] isEqual:second] && [[note sourceDataReturningError:NULL] isEqual:SourceBytes(second, encoding, fixture[@"bom"])], @"Redo restores both edits without normalizing untouched source");
            [session undo]; [session undo];
            NSData *prefsArchive = [NSKeyedArchiver archivedDataWithRootObject:[library notationPrefs]];
            NVReviewSourceOwner *owner = [[[NVReviewSourceOwner alloc] init] autorelease];
            owner->prefs = [NSKeyedUnarchiver unarchiveObjectWithData:prefsArchive];
            NoteObject *restored = [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:note]];
            [restored setDelegate:owner];
            Check([[[restored contentString] string] isEqual:source] && [[restored sourceDataReturningError:NULL] isEqual:originalBytes] && [[restored sourceSyntaxIdentifier] isEqual:@"markdown"], @"post-Undo archive restores exact source bytes and local syntax together");
            for (NSLayoutManager *layout in layouts) [storage removeLayoutManager:layout];
            [session sourceLayoutDidDetach]; [session close];
            Check([[note sourceDataReturningError:NULL] isEqual:originalBytes], @"last layout detach and editing-session closure retain source bytes");
            NSLog(@"EVIDENCE history=%lu source_units=%lu original_bytes=%lu encoding=%llu edits=2 undos=4 redos=2 layouts=2", (unsigned long)histories, (unsigned long)[source length], (unsigned long)[originalBytes length], (unsigned long long)encoding);
            histories++;
        }
        NSLog(@"ROUND 3 CONTRARIAN DATA PASSED: %lu checks, %lu histories", (unsigned long)Checks, (unsigned long)histories);
        _exit(0);
    } @catch (NSException *exception) {
        NSLog(@"FAIL %@\n%@", exception, [exception callStackSymbols]); _exit(1);
    }
}
@end
