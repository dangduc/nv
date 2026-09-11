// Added to the frozen full-application isolation probe by this review runner.
// The complete app owns snapshot capture, metadata, workers, and publication.
static NSMutableDictionary *CustomResults;

static NSString *CustomParentPath(NSString *stage) {
    return [Root stringByAppendingPathComponent:[@"Custom-" stringByAppendingString:stage]];
}
static NSString *ExpectedCustomDestination(NVBackupController *backup, NSString *stage) {
    NSString *parent = CustomParentPath(stage);
    if (Development()) parent = [parent stringByAppendingPathComponent:@"nvALT Development"];
    return [parent stringByAppendingPathComponent:[backup libraryIdentifier]];
}
static void WaitForBackup(NVBackupController *backup, NSString *stage) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20];
    while ([backup isBusy] && [deadline timeIntervalSinceNow] > 0) Pump();
    Check(![backup isBusy], [stage stringByAppendingString:@" worker finishes"]);
    Check([backup valueForKey:@"latestError"] == nil,
          [NSString stringWithFormat:@"%@ reports no error: %@", stage, [backup statusText]]);
}
static NSString *CheckPublishedPayload(NVBackupController *backup, NSString *stage) {
    NSString *path = [[backup settings] objectForKey:@"lastSnapshot"];
    Check(path != nil, [stage stringByAppendingString:@" saves a snapshot path"]);
    Check([[path stringByDeletingLastPathComponent] isEqualToString:[[backup destinationURL] path]],
          [stage stringByAppendingString:@" snapshot belongs to the selected destination"]);
    NSError *error = nil;
    NSData *data = [(id)NSClassFromString(@"NVBackupStore") archiveDataAtSnapshotURL:[NSURL fileURLWithPath:path] error:&error];
    Check(data != nil && error == nil, [stage stringByAppendingString:@" package passes the real store reader"]);
    FrozenNotation *archive = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    OSStatus status = noErr;
    CheckNotes([archive unpackedNotesReturningError:&status]);
    Check(status == noErr, [stage stringByAppendingString:@" actual snapshot payload decodes"]);
    [CustomResults setObject:path forKey:[stage stringByAppendingString:@"Snapshot"]];
    return path;
}
static void CheckCustomDestination(NVBackupController *backup, NSString *stage) {
    Check([[[backup destinationURL] path] isEqualToString:ExpectedCustomDestination(backup, stage)],
          [stage stringByAppendingString:@" custom destination has the expected flavor namespace"]);
    NSError *error = nil;
    NSData *bookmark = [[backup settings] objectForKey:@"destinationBookmark"];
    Check([bookmark isKindOfClass:[NSData class]] && [bookmark length] > 0,
          [stage stringByAppendingString:@" settings retain the real custom bookmark"]);
    NSURL *parent = [NSURL URLByResolvingBookmarkData:bookmark
                    options:NSURLBookmarkResolutionWithoutUI | NSURLBookmarkResolutionWithoutMounting
                    relativeToURL:nil bookmarkDataIsStale:NULL error:&error];
    Check([[parent path] isEqualToString:CustomParentPath(stage)] && error == nil,
          [stage stringByAppendingString:@" bookmark retains the selected parent"]);
}
static void ExerciseFirstCustomBackup(NVBackupController *backup, NSString *stage, BOOL automatic) {
    NSString *parentPath = CustomParentPath(stage);
    NSFileManager *manager = [NSFileManager defaultManager];
    Check([manager fileExistsAtPath:parentPath], @"the selected custom parent exists");
    Check(![manager fileExistsAtPath:ExpectedCustomDestination(backup, stage)],
          @"the first custom backup starts without a UUID folder");
    if (Development()) Check(![manager fileExistsAtPath:[parentPath stringByAppendingPathComponent:@"nvALT Development"]],
                             @"the first development custom backup starts without its namespace");
    NSError *error = nil;
    NSData *bookmark = [[NSURL fileURLWithPath:parentPath isDirectory:YES]
                       bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark
                       includingResourceValuesForKeys:nil relativeToURL:nil error:&error];
    Check(bookmark != nil && error == nil, @"Foundation creates a real selected-parent bookmark");
    // Match chooseDestination:'s settings update, without presenting a picker.
    NSMutableDictionary *settings = [backup valueForKey:@"librarySettings"];
    [settings setObject:bookmark forKey:@"destinationBookmark"];
    [backup setValue:@YES forKey:@"retentionPending"];
    for (NSString *key in @[@"lastDate", @"lastGeneration", @"lastSnapshot", @"storageBytes"])
        [settings removeObjectForKey:key];
    [backup performSelector:@selector(saveSettings)];
    CheckCustomDestination(backup, stage);
    Check([backup setSettings:@{@"enabled":@(automatic)} error:&error], @"the selected backup mode saves");
    if (automatic) [backup checkForBackupAtDate:[NSDate date]];
    else [backup backupNow:nil];
    WaitForBackup(backup, stage);
    CheckPublishedPayload(backup, stage);
    Check([manager fileExistsAtPath:ExpectedCustomDestination(backup, stage)],
          @"the actual worker creates the custom UUID folder");
    if (Development()) Check([manager fileExistsAtPath:[parentPath stringByAppendingPathComponent:@"nvALT Development"]],
                             @"the actual worker creates the development namespace");
    Check([backup setSettings:@{@"enabled":@NO} error:&error], @"disable further timer work before relaunch");
    Check([[NSUserDefaults standardUserDefaults] synchronize], @"the custom bookmark and snapshot settings persist");
}
