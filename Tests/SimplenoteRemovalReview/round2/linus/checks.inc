- (void)nv_linusCheckNote:(NoteObject *)note source:(NSString *)source bytes:(NSData *)bytes peer:(AppController *)peer unrelated:(NoteObject *)unrelated observer:(AppController *)observer {
    LinkingEditor *firstEditor=[self valueForKey:@"textView"], *secondEditor=[peer valueForKey:@"textView"];
    Check([[[note contentString] string] isEqual:source], @"external update commits the exact source in the note model");
    Check([[firstEditor string] isEqual:source] && [[secondEditor string] isEqual:source], @"external update reaches both native source editors");
    Check([firstEditor textStorage]==[secondEditor textStorage], @"both editors retain the same shared source storage");
    Check([self selectedNoteObject]==note && [peer selectedNoteObject]==note, @"external update preserves both selected note identities");
    Check([[[self browserSession] searchString] isEqual:@"External"] && [[[peer browserSession] searchString] isEqual:@"Local"], @"external update preserves each window's title-matching query");
    Check([[note sourceSyntaxIdentifier] isEqual:@"json"], @"external source change preserves locally stored syntax");
    Check([[note valueForKey:@"titleString"] isEqual:@"External Local Note"], @"temporary external filename does not replace the note title");
    Check([observer selectedNoteObject]==unrelated && [[[unrelated contentString] string] isEqual:@"unrelated untouched source"] &&
          [[[[observer valueForKey:@"textView"] textStorage] string] isEqual:@"unrelated untouched source"], @"external update leaves a third window and its other note untouched");
    Check([[note sourceDataReturningError:NULL] isEqual:bytes], @"source export contract retains exact externally supplied bytes and BOM");
    Check(NSMaxRange([firstEditor selectedRange])<=[source length] && NSMaxRange([secondEditor selectedRange])<=[source length], @"both native selections remain within externally changed source");
    Check([[[NVApplicationController sharedController] library] allNotes].count==2, @"external update neither loses nor duplicates notes");
}
- (void)nv_linusExport:(NoteObject *)note bytes:(NSData *)bytes filename:(NSString *)filename {
    FSRef directory;
    Check(FSPathMakeRef((const UInt8 *)[TestDirectory fileSystemRepresentation],&directory,NULL)==noErr, @"export target is inside the disposable test directory");
    Check([note exportToDirectoryRef:&directory withFilename:filename usingFormat:PlainTextFormat overwrite:NO]==noErr, @"source export creates the requested local file");
    NSString *path=[TestDirectory stringByAppendingPathComponent:filename];
    Check([[NSData dataWithContentsOfFile:path] isEqual:bytes], @"actual exported file equals the external source byte for byte");
    Check([note exportToDirectoryRef:&directory withFilename:filename usingFormat:PlainTextFormat overwrite:NO]==dupFNErr, @"source export respects overwrite protection");
    Check([[NSData dataWithContentsOfFile:path] isEqual:bytes], @"refused overwrite leaves the existing export unchanged");
}
- (void)nv_runTests {
    @try {
        NVApplicationController *app=[NVApplicationController sharedController];
        NotationController *library=[app library];
        NoteObject *note=MakeNote(library,@"External Local Note",@"{\"initial\":1}\n");
        NoteObject *unrelated=MakeNote(library,@"Separate Note",@"unrelated untouched source");
        [note setSourceSyntaxIdentifier:@"json"];
        [app newWindow:self]; Pump(); AppController *peer=[[app browserControllers] lastObject];
        [app newWindow:self]; Pump(); AppController *observer=[[app browserControllers] lastObject];
        Check(peer!=self && observer!=self && observer!=peer, @"fixture creates three separate native browser windows");
        [self searchForString:@"External"]; [self revealNote:note options:0];
        [peer searchForString:@"Local"]; [peer revealNote:note options:0];
        [observer searchForString:@"Separate"]; [observer revealNote:unrelated options:0]; Pump();
        LinkingEditor *firstEditor=[self valueForKey:@"textView"], *secondEditor=[peer valueForKey:@"textView"];
        [firstEditor setSelectedRange:NSMakeRange(1,2)]; [secondEditor setSelectedRange:NSMakeRange(6,1)];
        Check([library flushAllNoteChanges], @"initial local notes and syntax reach the database");
        Check([library currentNoteStorageFormat]==SingleDatabaseFormat, @"ODB callback first runs against database storage");
        NSString *temporary=[TestDirectory stringByAppendingPathComponent:@"Temp/external-source.json"];
        NSString *first=@"{\"external\":\"café 😀\",\"line\":2}\r\n";
        NSMutableData *firstBytes=[NSMutableData dataWithBytes:"\xef\xbb\xbf" length:3];
        [firstBytes appendData:[first dataUsingEncoding:NSUTF8StringEncoding]];
        Check([firstBytes writeToFile:temporary atomically:YES], @"disposable UTF-8 BOM file represents an external editor save");
        if(getenv("NV_REVIEW_DROP_ODB_UPDATE")) Swap([NoteObject class],@selector(odbEditor:didModifyFile:newFileLocation:context:),@selector(nv_reviewDropODB:didModifyFile:newFileLocation:context:));
        [note odbEditor:nil didModifyFile:temporary newFileLocation:nil context:@{}]; Pump();
        [self nv_linusCheckNote:note source:first bytes:firstBytes peer:peer unrelated:unrelated observer:observer];
        [self nv_linusExport:note bytes:firstBytes filename:@"database-external-export.txt"];
        Check([library flushAllNoteChanges], @"ODB change flushes to the local database without sync services");

        [[library notationPrefs] setNotesStorageFormat:PlainTextFormat];
        Check([library flushAllNoteChanges], @"switch to separate source files completes");
        [library stopFileNotifications];
        NSString *backing=[[note noteFilePath] copy];
        NSLog(@"Backing source location=%@ fixture root=%@ bytes=%@ expected=%@",backing,TestDirectory,[NSData dataWithContentsOfFile:backing],firstBytes);
        Check([[backing stringByResolvingSymlinksInPath] hasPrefix:[[TestDirectory stringByAppendingPathComponent:@"Notes/"] stringByResolvingSymlinksInPath]] &&
              [[NSData dataWithContentsOfFile:backing] isEqual:firstBytes], @"separate source file contains the prior exact external bytes");
        NSString *second=@"{\"second\":\"Δ 😀\",\"ok\":true}\n";
        NSMutableData *secondBytes=[NSMutableData dataWithBytes:"\xff\xfe" length:2];
        [secondBytes appendData:[second dataUsingEncoding:NSUTF16LittleEndianStringEncoding]];
        Check([secondBytes writeToFile:temporary atomically:YES], @"second external save uses a UTF-16 little-endian BOM");
        [note odbEditor:nil didModifyFile:temporary newFileLocation:nil context:@{}]; Pump();
        [self nv_linusCheckNote:note source:second bytes:secondBytes peer:peer unrelated:unrelated observer:observer];
        Check([library flushAllNoteChanges] && [[NSData dataWithContentsOfFile:backing] isEqual:secondBytes], @"ODB callback writes changed encoding and exact bytes to the backing file");
        [self nv_linusExport:note bytes:secondBytes filename:@"file-external-export.txt"];

        NSString *third=@"{\"directory\":\"separate writer 😀\",\"n\":987654}\r\n";
        NSMutableData *thirdBytes=[NSMutableData dataWithBytes:"\xef\xbb\xbf" length:3];
        [thirdBytes appendData:[third dataUsingEncoding:NSUTF8StringEncoding]];
        Check([thirdBytes writeToFile:backing atomically:NO], @"an independent local writer changes the backing source file");
        Check([library synchronizeNotesFromDirectory], @"explicit directory reconciliation reads the modified file"); Pump();
        [self nv_linusCheckNote:note source:third bytes:thirdBytes peer:peer unrelated:unrelated observer:observer];
        [self nv_linusExport:note bytes:thirdBytes filename:@"reconciled-export.txt"];
        Check([library flushAllNoteChanges], @"reconciled local source reaches the database snapshot");

        [firstEditor insertText:@" " replacementRange:NSMakeRange([[firstEditor string] length],0)]; Pump();
        NSString *edited=[third stringByAppendingString:@" "];
        NSMutableData *editedBytes=[NSMutableData dataWithBytes:"\xef\xbb\xbf" length:3];
        [editedBytes appendData:[edited dataUsingEncoding:NSUTF8StringEncoding]];
        [self nv_linusCheckNote:note source:edited bytes:editedBytes peer:peer unrelated:unrelated observer:observer];
        Check([library flushAllNoteChanges] && [[NSData dataWithContentsOfFile:backing] isEqual:editedBytes], @"native typing after external reconciliation still commits exact local source bytes");
        [self nv_linusExport:note bytes:editedBytes filename:@"native-edit-export.txt"];
        [note odbEditor:nil didClosefile:temporary context:@{}];
        Check(![[NSFileManager defaultManager] fileExistsAtPath:temporary] && [[NSData dataWithContentsOfFile:backing] isEqual:editedBytes], @"ODB close callback removes only its temporary file and preserves the backing file");
        NSData *archive=[NSData dataWithContentsOfFile:[TestDirectory stringByAppendingPathComponent:@"Notes/Notes & Settings"]];
        FrozenNotation *frozen=[NSKeyedUnarchiver unarchiveObjectWithData:archive]; OSStatus error=noErr;
        NSArray *reopened=[frozen unpackedNotesReturningError:&error];
        Check(frozen && error==noErr && [reopened count]==2, @"written local snapshot reopens both notes");
        BOOL exact=NO;
        for(NoteObject *candidate in reopened) if(memcmp([candidate uniqueNoteIDBytes],[note uniqueNoteIDBytes],sizeof(CFUUIDBytes))==0)
            exact=[[[candidate contentString] string] isEqual:edited] && [[candidate sourceDataReturningError:NULL] isEqual:editedBytes];
        Check(exact, @"reopened local snapshot preserves final source characters and encoding bytes");
        [backing release];
        NSLog(@"LINUS ROUND2 PASS: %lu checks, ODB database and plain-file callbacks, native directory reconciliation, shared editors, exports, and archive",(unsigned long)Checks);
        [NSApp terminate:self];
    } @catch(NSException *exception) { NSLog(@"FAIL: unexpected native exception %@",exception); exit(1); }
}
