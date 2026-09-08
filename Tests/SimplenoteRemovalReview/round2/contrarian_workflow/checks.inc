- (void)sw_selectStorage:(NSInteger)format controller:(NotationPrefsViewController *)controller {
    NSPopUpButton *popup = [controller valueForKey:@"storageFormatPopupButton"];
    Check([popup target] == controller && [popup action] == @selector(changedFileStorageFormat:), @"native storage popup retains its controller action connection");
    [popup selectItemWithTag:format];
    Check([popup sendAction:[popup action] to:[popup target]], @"selected storage format invokes the native control action");
}
- (void)sw_clickSheetButton:(NSString *)title window:(NSWindow *)parent {
    Check(SWWait(^BOOL { return SWFindView([[parent attachedSheet] contentView], [NSButton class], title) != nil; }),
        [@"actual native sheet offers " stringByAppendingString:title]);
    NSButton *button = (id)SWFindView([[parent attachedSheet] contentView], [NSButton class], title);
    [button performClick:self];
}
- (void)sw_checkSource:(NSString *)source note:(NoteObject *)note peer:(AppController *)peer file:(NSString *)path bytes:(NSData *)bytes {
    Check([[[note contentString] string] isEqual:source] && [[textView string] isEqual:source] && [[[peer valueForKey:@"textView"] string] isEqual:source],
        @"storage and security actions preserve exact model and both native source editors");
    Check([[NSData dataWithContentsOfFile:path] isEqual:bytes], @"disposable individual note file retains exactly its captured bytes");
    Check([[self window] isVisible] && [[peer window] isVisible] && [self sharedNotationController] == [peer sharedNotationController],
        @"both browser windows remain alive over the same local library");
}
- (void)nv_runTests {
    BOOL baseline = getenv("NV_SW_BASELINE") != NULL;
    if (baseline) {
        Method replacement = class_getInstanceMethod([NSPopUpButton class], @selector(sw_removeLegacyItem:));
        Check(class_addMethod([NSPopUpButton class], NSSelectorFromString(@"removeItem:"), method_getImplementation(replacement), method_getTypeEncoding(replacement)), @"baseline-only adapter bypasses the pre-existing unsupported popup removeItem selector");
    }
    Swap([NotationPrefs class], @selector(currentKeychainItem), @selector(sw_noKeychainItem));
    if (getenv("NV_SW_DROP_QUEUED_PICKER")) Swap([NotationPrefsViewController class], @selector(runQueuedStorageFormatChangeInvocation), @selector(sw_dropQueuedPicker));
    NVApplicationController *app = [NVApplicationController sharedController];
    NotationController *library = [self sharedNotationController];
    NotationPrefs *prefs = [[GlobalPrefs defaultPrefs] notationPrefs];
    NSString *source = @"# Local source\n\nA preserved line with café and Ω.\n";
    NoteObject *note = MakeNote(library, @"Workflow source", source);
    [self revealNote:note options:0]; [app newWindow:self];
    AppController *peer = [[app browserControllers] lastObject]; [peer revealNote:note options:0];
    Check(peer != self && ![prefs doesEncryption] && ![prefs storesPasswordInKeychain], @"fixture starts with two local windows and no encryption or stored password");
    prefsWindowController = [[PrefsWindowController alloc] init];
    [self showPreferencesWindow:self];
    PrefsWindowController *preferences = prefsWindowController;
    for (NSToolbarItem *item in [[preferences valueForKey:@"toolbar"] items])
        if ([[item itemIdentifier] isEqual:@"Notes"]) [preferences switchViews:item];
    NSWindow *preferencesWindow = [preferences valueForKey:@"window"];
    NotationPrefsViewController *controller = [preferences notationPrefsViewController];
    NSTabView *tabs = (id)SWFindView([controller view], [NSTabView class], nil);
    Check(tabs && [tabs numberOfTabViewItems] == (baseline ? 3 : 2) && [[controller view] window] == preferencesWindow, @"Notes preferences hosts its expected native tab count in its window");
    [tabs selectTabViewItemAtIndex:0];
    Check([prefs notesStorageFormat] == SingleDatabaseFormat, @"storage history begins in database format");
    [self sw_selectStorage:PlainTextFormat controller:controller];
    Check(SWWait(^BOOL { return [prefs notesStorageFormat] == PlainTextFormat && [[NSFileManager defaultManager] fileExistsAtPath:[note noteFilePath]]; }), @"database-to-file action creates an individual note file");
    NSString *path = [[[note noteFilePath] copy] autorelease];
    Check([[path stringByResolvingSymlinksInPath] hasPrefix:[[TestDirectory stringByResolvingSymlinksInPath] stringByAppendingString:@"/"]], @"all file checks address the runner's disposable directory");
    NSData *bytes = [[NSData dataWithContentsOfFile:path] retain];
    NSString *fileSource = [[[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding] autorelease];
    Check([fileSource isEqual:source], @"individual UTF-8 file preserves all source characters");
    Check([[controller valueForKey:@"allowedExtensionsTable"] isEnabled], @"plain-file format enables its remaining native extension controls");

    [self sw_selectStorage:SingleDatabaseFormat controller:controller];
    [self sw_clickSheetButton:@"Cancel" window:preferencesWindow];
    Check(SWWait(^BOOL { return ![preferencesWindow attachedSheet]; }) && [prefs notesStorageFormat] == PlainTextFormat, @"canceling actual cleanup sheet keeps plain-file storage");
    [self sw_checkSource:source note:note peer:peer file:path bytes:bytes];
    [self sw_selectStorage:SingleDatabaseFormat controller:controller];
    [self sw_clickSheetButton:@"Keep Files" window:preferencesWindow];
    Check(SWWait(^BOOL { return [prefs notesStorageFormat] == SingleDatabaseFormat && ![preferencesWindow attachedSheet]; }), @"Keep Files changes to database storage through the native sheet callback");
    Check(![[controller valueForKey:@"allowedExtensionsTable"] isEnabled], @"database format disables individual-file extension controls");
    [self sw_checkSource:source note:note peer:peer file:path bytes:bytes];

    SWPicker *picker = [[SWPicker alloc] init]; picker->prefs = prefs;
    [controller setValue:picker forKey:@"picker"];
    [tabs selectTabViewItemAtIndex:1];
    NSButton *encryption = [controller valueForKey:@"enableEncryptionButton"];
    Check([encryption target] == controller && [encryption action] == @selector(toggledEncryption:), @"remaining native encryption button retains its controller action");
    [encryption performClick:self];
    Check(picker->calls == 1 && picker->storageWhenShown == SingleDatabaseFormat && picker->shownWindow == preferencesWindow && picker->callback == controller, @"database encryption action invokes picker test double with correct window and delegate");
    [picker cancel];
    Check(![prefs doesEncryption] && ![[controller valueForKey:@"changePasswordButton"] isEnabled], @"picker cancellation leaves encryption and password-change controls off");

    [tabs selectTabViewItemAtIndex:0]; [self sw_selectStorage:PlainTextFormat controller:controller];
    [tabs selectTabViewItemAtIndex:1];
    [encryption performClick:self];
    [self sw_clickSheetButton:@"Cancel" window:preferencesWindow];
    Check(SWWait(^BOOL { return ![preferencesWindow attachedSheet]; }) && picker->calls == 1 && [prefs notesStorageFormat] == PlainTextFormat && ![controller valueForKey:@"postStorageFormatInvocation"], @"canceling actual encryption mismatch sheet queues no picker and leaves file format unchanged");
    [self sw_checkSource:source note:note peer:peer file:path bytes:bytes];

    [encryption performClick:self];
    [self sw_clickSheetButton:@"Use a single database file" window:preferencesWindow];
    Check(SWWait(^BOOL { return SWFindView([[preferencesWindow attachedSheet] contentView], [NSButton class], @"Keep Files") != nil; }), @"accepted encryption mismatch presents the actual file-cleanup sheet next");
    Check(picker->calls == 1 && [controller valueForKey:@"postStorageFormatInvocation"] != nil && [prefs notesStorageFormat] == PlainTextFormat, @"InvocationRecorder defers picker while file-cleanup choice is pending");
    [self sw_clickSheetButton:@"Cancel" window:preferencesWindow];
    Check(SWWait(^BOOL { return ![preferencesWindow attachedSheet]; }) && picker->calls == 1 && [prefs notesStorageFormat] == PlainTextFormat, @"canceling cleanup leaves source files and picker unmodified");
    NSLog(@"OBSERVATION canceled cleanup retains queued invocation=%d", [controller valueForKey:@"postStorageFormatInvocation"] != nil);
    [self sw_checkSource:source note:note peer:peer file:path bytes:bytes];

    [encryption performClick:self];
    [self sw_clickSheetButton:@"Use a single database file" window:preferencesWindow];
    [self sw_clickSheetButton:@"Keep Files" window:preferencesWindow];
    Check(SWWait(^BOOL { return picker->calls == 2; }), @"retained InvocationRecorder invokes picker exactly once after accepted storage conversion");
    Check(picker->storageWhenShown == SingleDatabaseFormat && picker->shownWindow == preferencesWindow && picker->callback == controller && ![controller valueForKey:@"postStorageFormatInvocation"], @"queued invocation runs after database conversion and clears its pending slot");
    [picker cancel];
    Check(![prefs doesEncryption] && ![prefs storesPasswordInKeychain], @"deferred picker cancellation leaves encryption off without storing any password");
    [self sw_checkSource:source note:note peer:peer file:path bytes:bytes];
    Check(SWKeychainLookups > 0, @"all native keychain-item lookups were intercepted with an empty test result");
    [preferencesWindow performClose:self];
    Check(![preferencesWindow isVisible] && [[app browserControllers] count] == 2, @"closing preferences after all workflows leaves both browsers alive");
    [bytes release];
    NSLog(@"CONTRARIAN WORKFLOW ROUND 2 COMPLETE: %lu checks", (unsigned long)Checks);
    [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.1];
}
