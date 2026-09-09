- (void)nv_runTests {
    @try {
        NSArray *locales = @[@"en", @"de", @"fr", @"it", @"pt-PT", @"zh"];
        NSArray *wellNames = @[@"foregroundColorWell", @"backgroundColorWell", @"searchHighlightColorWell",
            @"darkForegroundColorWell", @"darkBackgroundColorWell", @"darkSearchHighlightColorWell"];
        NSMutableArray *owners = [NSMutableArray array];
        for (NSString *locale in locales) {
            NSUInteger localeIndex = [locales indexOfObject:locale];
            NSLog(@"LOCALE %@", locale);
            PrefsWindowController *settings = [[[PrefsWindowController alloc] init] autorelease];
            [owners addObject:settings];
            NSString *path = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:
                [NSString stringWithFormat:@"%@.lproj/Preferences.nib", locale]];
            NSNib *nib = [[[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]] autorelease];
            NSArray *topLevelObjects = nil;
            Check(nib && [nib instantiateWithOwner:settings topLevelObjects:&topLevelObjects],
                @"the requested localized compiled Preferences nib loads into the real controller");
            [owners addObjectsFromArray:topLevelObjects];
            [settings showWindow:self];
            NSToolbarItem *colorsItem = [[settings valueForKey:@"items"] objectForKey:@"Fonts & Colors"];
            [settings switchViews:colorsItem];
            NSWindow *settingsWindow = [settings valueForKey:@"window"];
            NSView *pane = [settings valueForKey:@"fontsColorsView"];
            for (NSUInteger delay = 0; delay < 10; delay++) Pump();
            Check([settingsWindow isVisible] && [pane window] == settingsWindow,
                @"Fonts & Colors is attached to the visible Settings window");
            NSMutableArray *groups = [NSMutableArray array];
            for (NSView *view in [pane subviews]) {
                if ([view isKindOfClass:[NSBox class]] && [[(NSBox *)view title] hasPrefix:@"User Scheme"])
                    [groups addObject:view];
            }
            Check([groups count] == 2 && !NSIntersectsRect([groups[0] frame], [groups[1] frame]),
                @"the localized pane has exactly two nonoverlapping scheme groups");
            for (NSUInteger index = 0; index < [wellNames count]; index++) {
                NSColorWell *well = [settings valueForKey:wellNames[index]];
                Check(well && [well window] == settingsWindow && ![well isHiddenOrHasHiddenAncestor] &&
                    NSContainsRect([pane bounds], [well convertRect:[well bounds] toView:pane]) &&
                    NSContainsRect([[well superview] bounds], [well frame]),
                    @"each actual color well fits within its group and the visible pane");
                Check([well target] == settings && [settings respondsToSelector:[well action]],
                    @"each nib or generated well routes its action to this Settings controller");
                NSArray *before = ContrarianPalette(prefsController);
                NSColor *replacement = [NSColor colorWithCalibratedRed:.11 + .08 * index + .007 * localeIndex
                    green:.27 blue:.61 - .03 * localeIndex alpha:1];
                Check(!SameContrarianColor(before[index], replacement), @"the intended channel starts with a different color");
                NSColorPanel *panel = [NSColorPanel sharedColorPanel];
                [well activate:YES];
                [panel orderFront:self];
                Pump();
                Check([well isActive], @"exclusive native activation selects the intended color well");
                [panel setColor:replacement];
                for (NSUInteger delay = 0; delay < 4; delay++) Pump();
                NSArray *after = ContrarianPalette(prefsController);
                BOOL onlyIntended = YES;
                for (NSUInteger channel = 0; channel < 6; channel++) {
                    if (!SameContrarianColor(after[channel], channel == index ? replacement : before[channel]))
                        onlyIntended = NO;
                }
                Check(onlyIntended, @"the native shared color panel changes only the active palette channel");
                [well deactivate];
            }
            for (NSBox *group in groups) {
                for (NSView *view in [[group contentView] subviews]) {
                    if (![view isKindOfClass:[NSTextField class]]) continue;
                    NSTextField *label = (NSTextField *)view;
                    NSLog(@"LABEL %@ natural=%.1f frame=%.1f", [label stringValue],
                        [[label cell] cellSize].width, NSWidth([label frame]));
                    Check([[label stringValue] length] && [[label cell] cellSize].width <= NSWidth([label frame]) + 1 &&
                        NSContainsRect([[group contentView] bounds], [label frame]),
                        @"the localized group label fits without clipping");
                }
            }
            NSUInteger childCount = [[pane subviews] count];
            [[NSColorPanel sharedColorPanel] orderOut:self];
            [settingsWindow performClose:self]; Pump();
            [settings showWindow:self]; Pump();
            Check([settingsWindow isVisible] && [[pane subviews] count] == childCount,
                @"reopening Settings reuses its existing groups");
            [settingsWindow orderOut:self];
        }
        NSLog(@"CONTRARIAN LOCALES AND COLOR PANEL PASSED (%lu checks)", (unsigned long)Checks);
        exit(0);
    } @catch (NSException *exception) { NSLog(@"FAIL: %@\n%@", exception, [exception callStackSymbols]); exit(1); }
}
