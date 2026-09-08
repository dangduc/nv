- (void)nv_runTests {
    const char *manifestPath = getenv("NV_REVIEW_INTEGRATION_MANIFEST");
    Check(manifestPath != NULL, @"explicit review manifest provided");
    NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:manifestPath]];
    NSArray *manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    Check([manifest count] == 6, @"native validation has six locales");
    for (NSDictionary *entry in manifest) {
        NSString *locale = [entry objectForKey:@"locale"];
        NSString *path = [[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:locale]
            stringByAppendingPathComponent:@"NotationPrefsView.nib"];
        NSNib *nib = [[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]];
        Check(nib != nil, [NSString stringWithFormat:@"%@ compiled nib exists", locale]);
        NotationPrefsViewController *owner = [[NotationPrefsViewController alloc] init];
        NSArray *topLevel = nil;
        Check([nib instantiateWithOwner:owner topLevelObjects:&topLevel],
            [NSString stringWithFormat:@"%@ production owner instantiates compiled nib", locale]);
        for (NSString *outlet in [entry objectForKey:@"outlets"]) {
            Check([owner valueForKey:outlet] != nil,
                [NSString stringWithFormat:@"%@ %@ outlet connected", locale, outlet]);
        }
        for (NSString *selector in [entry objectForKey:@"selectors"]) {
            Check([owner respondsToSelector:NSSelectorFromString(selector)],
                [NSString stringWithFormat:@"%@ owner implements %@", locale, selector]);
        }
        NSMutableArray *views = [NSMutableArray array];
        NVCollectViews([owner view], views);
        NSUInteger tabViews = 0, ownerActions = 0;
        for (NSView *view in views) {
            if ([view isKindOfClass:[NSTabView class]]) {
                tabViews++;
                NSTabView *tabs = (NSTabView *)view;
                Check([tabs numberOfTabViewItems] == 2, [NSString stringWithFormat:@"%@ native tab count is two", locale]);
                Check([[[tabs tabViewItemAtIndex:0] identifier] isEqual:@"storage"] &&
                      [[[tabs tabViewItemAtIndex:1] identifier] isEqual:@"security"],
                    [NSString stringWithFormat:@"%@ native tab identifiers survived compilation", locale]);
            }
            if ([view isKindOfClass:[NSControl class]]) {
                NSControl *control = (NSControl *)view;
                if ([control action] && [control target] == owner) {
                    ownerActions++;
                    Check([owner respondsToSelector:[control action]],
                        [NSString stringWithFormat:@"%@ native control action resolves %@", locale, NSStringFromSelector([control action])]);
                }
            }
        }
        Check(tabViews == 1 && ownerActions > 0, [NSString stringWithFormat:@"%@ native view hierarchy exposes prefs actions", locale]);
        NSPopUpButton *formats = [owner valueForKey:@"storageFormatPopupButton"];
        Check([formats numberOfItems] == 2, [NSString stringWithFormat:@"%@ current storage formats initialized", locale]);
        [nib release];
        // The short-lived probe keeps owners and nib top-level objects alive until process exit.
        // Real app preference ownership is outside this connection/build-closure probe.
    }
    NSLog(@"PASS: %lu native integration assertions across six locales", (unsigned long)Checks);
    [self performSelector:@selector(nv_finishTests) withObject:nil afterDelay:0.1];
}
