// A durable transaction makes task + submission-record restore recoverable across a crash.
static BOOL AMValidRecords(id rows){if(![rows isKindOfClass:NSArray.class])return NO;NSMutableSet *ids=NSMutableSet.set;for(id row in rows){if(!AMValidSubmission(row) || ![AMSubmissionPublicFields(row) isEqual:row] || [ids containsObject:row[@"id"]])return NO;[ids addObject:row[@"id"]];}return YES;}
BOOL AMRecoverBackup(NSError **error){
    NSURL *url=[SSDataDirectory().URLByResolvingSymlinksInPath URLByAppendingPathComponent:@"backup-transaction.plist"];if(![url.path isEqual:url.URLByResolvingSymlinksInPath.path]){if(error)*error=StoreError(@"恢复记录路径不安全，未修改数据。");return NO;}if(![NSFileManager.defaultManager fileExistsAtPath:url.path])return YES;
    NSDictionary *pending=SSReadPlist(@"backup-transaction.plist");if(![pending isKindOfClass:NSDictionary.class] || !ValidTasks(pending[@"tasks"]) || !AMValidRecords(pending[@"submissions"])){if(error)*error=StoreError(@"备份恢复记录损坏，已停止写入并保留原文件。");return NO;}
    return SSWritePlist(@"tasks.plist",pending[@"tasks"],error) && SSWritePlist(@"submission-records.plist",pending[@"submissions"],error) && [NSFileManager.defaultManager removeItemAtURL:url error:error];
}
NSDictionary *AMBackupEnvelope(NSArray *tasks,NSError **error){NSArray *records=AMSubmissionRecords(error);if(!records || !ValidTasks(tasks))return nil;return @{@"format":@"am-helper-backup-v2",@"tasks":tasks,@"submissions":records};}
NSDictionary *AMDecodeBackup(id value,NSError **error){
    if([value isKindOfClass:NSArray.class]){NSArray *normalized=DDLNormalizeTasks(value);if(normalized.count==[value count] && ValidTasks(normalized))return @{@"tasks":normalized,@"submissions":@[]};}
    if([value isKindOfClass:NSDictionary.class] && [value[@"format"] isEqual:@"am-helper-backup-v2"] && ValidTasks(value[@"tasks"]) && AMValidRecords(value[@"submissions"]))return @{@"tasks":value[@"tasks"],@"submissions":value[@"submissions"]};
    if(error)*error=StoreError(@"备份格式无效或含异常记录，未修改现有数据。");return nil;
}
BOOL AMRestoreBackup(NSArray *previous,NSArray *tasks,NSArray *records,NSError **error){
    @synchronized(NSFileManager.defaultManager){if(!AMRecoverBackup(error) || !ValidTasks(tasks) || !AMValidRecords(records))return NO;
        NSArray *oldRecords=AMSubmissionRecords(error);if(!oldRecords)return NO;
        // Create the same rolling recovery points as ordinary edits before starting the transaction.
        if(!SSSaveTasks(previous,previous,error))return NO;
        NSDictionary *intent=@{@"tasks":tasks,@"submissions":records};if(!SSWritePlist(@"backup-transaction.plist",intent,error))return NO;
        if(AMRecoverBackup(error))return YES;
        // A failed restore must not publish partial success; retain a recoverable rollback intent.
        if(SSWritePlist(@"backup-transaction.plist",@{@"tasks":previous,@"submissions":oldRecords},NULL))AMRecoverBackup(NULL);return NO;
    }
}
