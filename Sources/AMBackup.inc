// A durable transaction makes task + submission-record restore recoverable across a crash.
static BOOL AMValidRecords(id rows){if(![rows isKindOfClass:NSArray.class])return NO;NSMutableSet *ids=NSMutableSet.set;for(id row in rows){if(!AMValidSubmission(row) || ![AMSubmissionPublicFields(row) isEqual:row] || [ids containsObject:row[@"id"]])return NO;[ids addObject:row[@"id"]];}return YES;}
static BOOL AMValidSeries(id rows){if(![rows isKindOfClass:NSArray.class])return NO;NSMutableSet *ids=NSMutableSet.set;for(id s in rows){if(![s isKindOfClass:NSDictionary.class] || ![s[@"id"] isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:s[@"id"]] || [ids containsObject:s[@"id"]] || !DDLRecurrenceValid(s[@"rule"]) || s[@"rule"][@"allowUnknownCalendar"] || !ValidTasks(@[s[@"template"] ?: @{}]))return NO;for(NSString *key in s)if(![@[@"id",@"rule",@"template",@"stopped",@"skippedKeys",@"excludedDates"] containsObject:key])return NO;if(s[@"stopped"] && ![s[@"stopped"] isKindOfClass:NSNumber.class])return NO;if(s[@"excludedDates"]){if(![s[@"excludedDates"] isKindOfClass:NSArray.class])return NO;for(id date in s[@"excludedDates"])if(![date isKindOfClass:NSString.class] || !DDLPlanDate(date,[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]))return NO;}if(s[@"skippedKeys"]){if(![s[@"skippedKeys"] isKindOfClass:NSArray.class])return NO;for(id key in s[@"skippedKeys"])if(![key isKindOfClass:NSString.class])return NO;}[ids addObject:s[@"id"]];}return YES;}
static BOOL AMValidCalendar(id value){if(![value isKindOfClass:NSDictionary.class])return NO;for(id key in value){NSDictionary *v=value[key];if(![key isKindOfClass:NSString.class] || !DDLPlanDate(key,[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]) || ![v isKindOfClass:NSDictionary.class] || ![v[@"rest"] isKindOfClass:NSNumber.class] || ![v[@"name"] isKindOfClass:NSString.class] || ![v[@"reason"] isKindOfClass:NSString.class])return NO;}return YES;}
BOOL AMRecoverBackup(NSError **error){
    NSURL *url=[SSDataDirectory().URLByResolvingSymlinksInPath URLByAppendingPathComponent:@"backup-transaction.plist"];if(![url.path isEqual:url.URLByResolvingSymlinksInPath.path]){if(error)*error=StoreError(@"恢复记录路径不安全，未修改数据。");return NO;}if(![NSFileManager.defaultManager fileExistsAtPath:url.path])return YES;
    NSDictionary *pending=SSReadPlist(@"backup-transaction.plist");if(![pending isKindOfClass:NSDictionary.class] || !ValidTasks(pending[@"tasks"]) || !AMValidRecords(pending[@"submissions"])){if(error)*error=StoreError(@"备份恢复记录损坏，已停止写入并保留原文件。");return NO;}
    if((pending[@"series"] && !AMValidSeries(pending[@"series"])) || (pending[@"calendarOverrides"] && !AMValidCalendar(pending[@"calendarOverrides"]))){if(error)*error=StoreError(@"周期或日历恢复记录无效，原数据保留。");return NO;}
    return SSWritePlist(@"tasks.plist",pending[@"tasks"],error) && SSWritePlist(@"submission-records.plist",pending[@"submissions"],error) && (!pending[@"series"] || SSWritePlist(@"recurrence-series.plist",pending[@"series"],error)) && (!pending[@"calendarOverrides"] || SSWritePlist(@"calendar-overrides.plist",pending[@"calendarOverrides"],error)) && [NSFileManager.defaultManager removeItemAtURL:url error:error];
}
NSArray *SSRecurrenceSeries(NSError **error){if(!AMRecoverBackup(error))return nil;id data=SSReadPlist(@"recurrence-series.plist");if(!data && ![NSFileManager.defaultManager fileExistsAtPath:[[SSDataDirectory() URLByAppendingPathComponent:@"recurrence-series.plist"] path]])return @[];if(AMValidSeries(data))return data;if(error)*error=StoreError(@"周期系列无法完整读取，已停止生成并保留原任务。");return nil;}
NSDictionary *SSCalendarOverrides(void){id data=SSReadPlist(@"calendar-overrides.plist");return AMValidCalendar(data) ? data:@{};}
static BOOL AMExistingCalendarValid(NSError **error){NSURL *url=[SSDataDirectory() URLByAppendingPathComponent:@"calendar-overrides.plist"];if([NSFileManager.defaultManager fileExistsAtPath:url.path] && !AMValidCalendar(SSReadPlist(@"calendar-overrides.plist"))){if(error)*error=StoreError(@"本机日历覆盖记录无法完整读取，原文件已保留；未保存或导出缺失数据。");return NO;}return YES;}
NSDictionary *AMBackupEnvelope(NSArray *tasks,NSError **error){if(!AMExistingCalendarValid(error))return nil;NSArray *records=AMSubmissionRecords(error),*series=SSRecurrenceSeries(error);if(!records || !series || !ValidTasks(tasks))return nil;return @{@"format":@"am-helper-backup-v3",@"tasks":tasks,@"submissions":records,@"series":series,@"calendarOverrides":SSCalendarOverrides()};}
NSDictionary *AMDecodeBackup(id value,NSError **error){
    if([value isKindOfClass:NSArray.class]){NSArray *normalized=DDLNormalizeTasks(value);if(normalized.count==[value count] && ValidTasks(normalized))return @{@"tasks":normalized,@"submissions":@[]};}
    if([value isKindOfClass:NSDictionary.class] && [value[@"format"] isEqual:@"am-helper-backup-v2"] && ValidTasks(value[@"tasks"]) && AMValidRecords(value[@"submissions"]))return @{@"tasks":value[@"tasks"],@"submissions":value[@"submissions"]};
    if([value isKindOfClass:NSDictionary.class] && [value[@"format"] isEqual:@"am-helper-backup-v3"] && ValidTasks(value[@"tasks"]) && AMValidRecords(value[@"submissions"]) && AMValidSeries(value[@"series"]) && AMValidCalendar(value[@"calendarOverrides"]))return value;
    if(error)*error=StoreError(@"备份格式无效或含异常记录，未修改现有数据。");return nil;
}
static BOOL AMStoreSchedule(NSArray *previous,NSArray *tasks,NSArray *records,NSArray *series,NSDictionary *overrides,NSError **error){
    @synchronized(NSFileManager.defaultManager){if(!AMRecoverBackup(error) || !AMExistingCalendarValid(error) || !ValidTasks(tasks) || !AMValidRecords(records) || !AMValidSeries(series) || !AMValidCalendar(overrides))return NO;
        NSArray *oldSeries=SSRecurrenceSeries(error),*oldRecords=AMSubmissionRecords(error);NSDictionary *oldOverrides=SSCalendarOverrides();if(!oldSeries || !oldRecords || !SSSaveTasks(previous,previous,error))return NO;
        NSDictionary *intent=@{@"tasks":tasks,@"submissions":records,@"series":series,@"calendarOverrides":overrides};if(!SSWritePlist(@"backup-transaction.plist",intent,error))return NO;if(AMRecoverBackup(error))return YES;
        if(SSWritePlist(@"backup-transaction.plist",@{@"tasks":previous,@"submissions":oldRecords,@"series":oldSeries,@"calendarOverrides":oldOverrides},NULL))AMRecoverBackup(NULL);return NO;
    }
}
BOOL SSSaveScheduledTasks(NSArray *previous,NSArray *tasks,NSArray *series,NSDictionary *overrides,NSError **error){NSArray *records=AMSubmissionRecords(error);return records && AMStoreSchedule(previous,tasks,records,series,overrides,error);}
BOOL AMRestoreScheduledBackup(NSArray *previous,NSDictionary *decoded,NSError **error){return AMStoreSchedule(previous,decoded[@"tasks"],decoded[@"submissions"],decoded[@"series"] ?: @[],decoded[@"calendarOverrides"] ?: @{},error);}
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
