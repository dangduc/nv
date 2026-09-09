- (void)nv_runTests {
    NSArray *lists = [NSColorList availableColorLists];
    NSLog(@"Native available color lists: %@", [lists valueForKey:@"name"]);
    for (NSColorList *list in lists) {
        for (NSString *key in [list allKeys]) {
            NSColor *color = [list colorWithKey:key];
            if ([color type] == NSColorTypeCatalog && [[color catalogNameComponent] isEqual:@"System"] &&
                [[color colorNameComponent] isEqual:@"selectedTextBackgroundColor"])
                NSLog(@"MATCH: native list=%@ key=%@ color=%@", [list name], key, color);
        }
    }
    NSLog(@"System list: %@", [NSColorList colorListNamed:@"System"]);
    exit(0);
}
