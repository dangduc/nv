- (NSMenuItem *)nv_findCommand:(SEL)action {
  NSMutableArray *menus = [NSMutableArray arrayWithObject:[NSApp mainMenu]];
  for (NSUInteger i=0;i<[menus count];i++) for(NSMenuItem *item in [[menus objectAtIndex:i] itemArray]) {
    if ([item action]==action) return item;
    if ([item submenu]) [menus addObject:[item submenu]];
  }
  return nil;
}
- (void)nv_dispatch:(SEL)action {
  NSMenuItem *item=[self nv_findCommand:action]; Check(item!=nil,@"requested native menu command exists");
  [[item menu] update]; Check([item isEnabled],@"requested native menu command is enabled");
  Check([NSApp sendAction:action to:[item target] from:item],@"native application dispatch accepts command"); Pump();
}
- (void)nv_hideAllRows {
  if ([prefsController showTitleInTopSection]) [self nv_dispatch:@selector(toggleTitleInTopSection:)];
  if ([prefsController showTagsInTopSection]) [self nv_dispatch:@selector(toggleTagsInTopSection:)];
  if ([prefsController showBodyControlsInTopSection]) [self nv_dispatch:@selector(toggleBodyControlsInTopSection:)];
  if ([prefsController showNotesList]) [self nv_dispatch:@selector(toggleNotesList:)];
}
- (void)nv_runTests {
 @try {
  NVApplicationController *app=[NVApplicationController sharedController]; NotationController *library=[app library];
  [self nv_activateBrowser]; [window setContentSize:NSMakeSize(480,420)]; Pump();
  Check(NSWidth([[window contentView] bounds])==480,@"fixture uses stock 480-point content width");
  NSLog(@"FIXTURE preferred localization %@",[[NSBundle mainBundle] preferredLocalizations]);
  [prefsController setShowWordCount:YES];
  NoteObject *alpha=[MakeNote(library,@"Alpha",@"alpha body") retain];
  NoteObject *beta=[MakeNote(library,@"Beta",@"beta body") retain];
  NSMenuItem *count=[self nv_findCommand:@selector(toggleWordCount:)];
  Check(count!=nil && [count infoForBinding:NSValueBinding]==nil,@"localized Word Count menu has no obsolete value binding");
  for(NSUInteger fixture=0;fixture<3;fixture++) {
    NSLog(@"HISTORY %lu: Search customization runs before View commands",fixture);
    [self setViewingNote:NO]; [self searchForString:@""]; [self revealNote:alpha options:0]; Pump();
    if (fixture==1) {
      NSUInteger index=[[[toolbar items] valueForKey:@"itemIdentifier"] indexOfObject:@"Search"];
      Check(index!=NSNotFound,@"customization can find native Search item"); [toolbar removeItemAtIndex:index]; Pump();
    } else if (fixture==2) [self setDualFieldIsVisible:NO];
    [self nv_dispatch:@selector(bringFocusToControlField:)]; for(NSUInteger i=0;i<6;i++) Pump();
    NSLog(@"SEARCH fixture toolbar=%d fieldWindow=%@ hidden=%d width=%.1f editor=%@ responder=%@ key=%d",[toolbar isVisible],[field window],[field isHiddenOrHasHiddenAncestor],NSWidth([field bounds]),[field currentEditor],[window firstResponder],[window isKeyWindow]);
    Check([toolbar isVisible] && [field currentEditor] && ![field isHiddenOrHasHiddenAncestor],@"Search restores a visible native field after customization");
    NSUInteger searchCount=0;for(NSToolbarItem *item in [toolbar items]) if([[item itemIdentifier] isEqual:@"Search"]) searchCount++;
    Check(searchCount==1,@"Search restoration has exactly one toolbar item");
    [self nv_hideAllRows];
    Check([field currentEditor]!=nil,@"hiding every note row and list leaves active Search editing intact");
    NSTextView *searchEditor=(id)[field currentEditor];
    [searchEditor insertText:@"Alpha" replacementRange:NSMakeRange(0,[[searchEditor string] length])]; Pump();
    Check([[[self browserSession] searchString] isEqual:@"Alpha"],@"native Search continues filtering with every note row hidden");
    [self revealNote:alpha options:0];
    [searchEditor doCommandBySelector:@selector(insertTab:)]; Pump();
    Check([window firstResponder]==textView,@"Tab reaches Source from customized Search with every note row hidden");
    // Actual menu actions remain usable after Search changed the toolbar.
    [self nv_dispatch:@selector(toggleSourcePreview:)];
    Check([self isViewingNote] && [window firstResponder]==[[self valueForKey:@"previewController"] webView],@"hidden-row View command reaches and focuses Preview");
    [self nv_dispatch:@selector(toggleSourcePreview:)];
    Check(![self isViewingNote] && [window firstResponder]==textView,@"hidden-row View command restores focused editable Source");
    [self nv_dispatch:@selector(renameNote:)];
    Check(![noteTitleField isHidden] && [noteTitleField currentEditor]!=nil,@"Rename reveals its row after Search customization");
    [(id)[noteTitleField currentEditor] doCommandBySelector:@selector(cancelOperation:)]; Pump();
    [self nv_dispatch:@selector(tagNote:)];
    Check(![noteTagsField isHidden] && [noteTagsField currentEditor]!=nil,@"Tags reveals its row after Search customization");
    [(id)[noteTagsField currentEditor] doCommandBySelector:@selector(cancelOperation:)]; Pump();
    [self nv_hideAllRows];
    for(NSUInteger i=0;i<2;i++) {
      BOOL before=[prefsController showWordCount]; [self nv_dispatch:@selector(toggleWordCount:)];
      Check([prefsController showWordCount]!=before,@"native Word Count action changes preference exactly once");
      Check([wordCounter isHidden]==[prefsController showWordCount],@"Word Count visibility matches the changed preference");
      [[count menu] update];
      Check([count state]==([prefsController showWordCount]?NSControlStateValueOff:NSControlStateValueOn),@"Word Count menu check matches current visibility");
    }
    [self nv_dispatch:@selector(newNote:)]; NoteObject *created=[[self selectedNoteObject] retain];
    Check(created && created!=alpha && created!=beta && ![self isViewingNote] && [window firstResponder]==textView,
      @"New Note focuses editable Source with title and list hidden after Search customization");
    [textView insertText:@"created from hidden interface" replacementRange:NSMakeRange(0,0)]; [self finishEditing];
    Check([[[created contentString] string] isEqual:@"created from hidden interface"],@"new hidden-interface note accepts and commits native body input");
    [library removeNote:created];[created release];Pump();
    [prefsController setShowTitleInTopSection:YES sender:nil]; [prefsController setShowTagsInTopSection:YES sender:nil];
    [prefsController setShowBodyControlsInTopSection:YES sender:nil]; [prefsController setShowNotesList:YES sender:nil]; Pump();
  }
  Check([[[alpha contentString] string] isEqual:@"alpha body"] && [[[beta contentString] string] isEqual:@"beta body"],@"the original notes retain exact source characters across all histories");
  [alpha release];[beta release]; [library flushAllNoteChanges]; [library closeJournal];
  NSLog(@"CONTRARIAN REVIEW PASSED: %lu checks",Checks); exit(0);
 } @catch(NSException *exception) { NSLog(@"FAIL exception %@",exception); exit(1); }
}
