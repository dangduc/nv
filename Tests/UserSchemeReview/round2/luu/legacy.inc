- (void)nv_runTests {
    NSColor *raw = [NSColor selectedTextBackgroundColor];
    [prefsController setSearchTermHighlightColor:raw sender:self];
    NSAppearance *dark = nil;
    if (@available(macOS 10.14, *)) dark = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [NSApp setAppearance:dark]; Pump();
    NSColor *legacy = [prefsController searchTermHighlightColorRaw:NO];
    NSColor *unscoped = [raw colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    NSColor *darkExpected = NVDynamicResolvedColor(raw, dark);
    NSLog(@"LEGACY OBSERVATION: retained light accessor=%@ unscoped raw=%@ dark oracle=%@", legacy, unscoped, darkExpected);
    Check(NVDynamicSameColor(legacy, unscoped), @"the unchanged legacy light accessor uses the current unscoped appearance");
    Check(!NVDynamicSameColor(legacy, darkExpected), @"the historical light helper also lacks per-application dark resolution on this host");
    NSLog(@"LEGACY HELPER OBSERVATION PASSED (%lu checks)", (unsigned long)Checks);
    exit(0);
}
