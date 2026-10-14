static BOOL AMValidSubmission(id value) {
    if(![value isKindOfClass:NSDictionary.class])return NO;
    NSDictionary *r=value;
    for(NSString *key in @[@"id",@"repository",@"branch",@"kind",@"state",@"message"])if(![r[key] isKindOfClass:NSString.class])return NO;
    if(![[NSUUID alloc] initWithUUIDString:r[@"id"]] || !SSCanonicalRepository([@"https://github.com/" stringByAppendingString:r[@"repository"]]) || !SSValidBranch(r[@"branch"]) || ![r[@"date"] isKindOfClass:NSDate.class])return NO;
    if(![@[@"submission",@"sync",@"merge",@"existing"] containsObject:r[@"kind"]] || ![@[@"running",@"local",@"uncertain",@"confirmed",@"failed"] containsObject:r[@"state"]])return NO;
    for(NSString *key in @[@"commit",@"before",@"remoteCommit"]){if(r[key] && (![r[key] isKindOfClass:NSString.class] || [r[key] rangeOfString:@"^[a-f0-9]{40,64}$" options:NSRegularExpressionSearch].location==NSNotFound))return NO;}
    for(NSString *key in @[@"taskIDs",@"files"]){if(![r[key] isKindOfClass:NSArray.class])return NO;for(id s in r[key])if(![s isKindOfClass:NSString.class] || ![s length] || ( [key isEqual:@"files"] && ([s hasPrefix:@"/"] || [[s componentsSeparatedByString:@"/"] containsObject:@".."] || SSSensitivePath(s))))return NO;}
    for(NSString *key in @[@"checkedAt",@"confirmedAt"])if(r[key] && ![r[key] isKindOfClass:NSDate.class])return NO;
    if(r[@"review"]){NSDictionary *v=r[@"review"];if(![v isKindOfClass:NSDictionary.class] || ![v[@"date"] isKindOfClass:NSDate.class] || ![v[@"count"] isKindOfClass:NSNumber.class] || [v[@"count"] integerValue]<0 || [v[@"count"] integerValue]>10000 || ![v[@"acknowledged"] isKindOfClass:NSNumber.class] || ![@[@"local",@"assistant",@"partial"] containsObject:v[@"coverage"]] || v.count!=4)return NO;}
    if([r[@"message"] length]>10000 || [r[@"files"] count]>10000 || [r[@"taskIDs"] count]>10000)return NO;
    if(r[@"issue"] && (![r[@"issue"] isKindOfClass:NSString.class] || [r[@"issue"] rangeOfString:@"^[a-z-]{1,64}$" options:NSRegularExpressionSearch].location==NSNotFound))return NO;
    if(r[@"origin"] && ![@[@"app",@"external"] containsObject:r[@"origin"]])return NO;
    for(NSString *key in @[@"teacherHistoryKnown",@"teacherHistoryExcluded"])if(r[key] && ![r[key] isKindOfClass:NSNumber.class])return NO;
    if([r[@"message"] rangeOfString:@"/(Users|private|Volumes|var|home)/" options:NSRegularExpressionSearch].location!=NSNotFound)return NO;
    NSMutableArray *strings=[NSMutableArray arrayWithArray:r[@"files"]];[strings addObjectsFromArray:r[@"taskIDs"]];[strings addObjectsFromArray:@[r[@"repository"],r[@"branch"],r[@"message"]]];if(SSContainsSecret([[strings componentsJoinedByString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]))return NO;
    if(SSContainsSecret([r[@"message"] dataUsingEncoding:NSUTF8StringEncoding]))return NO;
    return YES;
}
static NSDictionary *AMSubmissionPublicFields(NSDictionary *record){NSMutableDictionary *out=NSMutableDictionary.dictionary;for(NSString *key in @[@"id",@"repository",@"branch",@"kind",@"state",@"message",@"date",@"taskIDs",@"files",@"commit",@"before",@"remoteCommit",@"checkedAt",@"confirmedAt",@"issue",@"review",@"origin",@"teacherHistoryKnown",@"teacherHistoryExcluded"])if(record[key])out[key]=record[key];return out;}
NSArray *AMSubmissionRecords(NSError **error) {
    if(!AMRecoverBackup(error))return nil;
    NSURL *url=[SSDataDirectory().URLByResolvingSymlinksInPath URLByAppendingPathComponent:@"submission-records.plist"];
    if(![url.path isEqual:url.URLByResolvingSymlinksInPath.path]){if(error)*error=[NSError errorWithDomain:@"AMSubmissionStore" code:3 userInfo:@{NSLocalizedDescriptionKey:@"记录路径不安全，已停止操作。"}];return nil;}
    id data=SSReadPlist(@"submission-records.plist");
    if(!data && ![NSFileManager.defaultManager fileExistsAtPath:url.path])return @[];
    if([data isKindOfClass:NSArray.class]){BOOL valid=YES;NSMutableArray *clean=NSMutableArray.array;NSMutableSet *ids=NSMutableSet.set;for(id r in data){if(!AMValidSubmission(r) || [ids containsObject:r[@"id"]]){valid=NO;break;}[ids addObject:r[@"id"]];[clean addObject:AMSubmissionPublicFields(r)];}if(valid)return clean;}
    if(error)*error=[NSError errorWithDomain:@"AMSubmissionStore" code:1 userInfo:@{NSLocalizedDescriptionKey:@"提交记录无法读取，原文件已保留。请先从备份恢复，避免丢失记录。"}];return nil;
}
BOOL AMStoreSubmission(NSDictionary *record,NSError **error) {
    if(!AMValidSubmission(record)){if(error)*error=[NSError errorWithDomain:@"AMSubmissionStore" code:2 userInfo:@{NSLocalizedDescriptionKey:@"提交记录字段无效，操作已停止。"}];return NO;}
    @synchronized(NSFileManager.defaultManager){NSArray *old=AMSubmissionRecords(error);if(!old)return NO;NSMutableArray *next=old.mutableCopy;NSUInteger i=[next indexOfObjectPassingTest:^BOOL(NSDictionary *r,NSUInteger idx,BOOL *stop){(void)idx;(void)stop;return [r[@"id"] isEqual:record[@"id"]];}];NSDictionary *copy=AMSubmissionPublicFields(record);if(i==NSNotFound)[next addObject:copy];else next[i]=copy;return SSWritePlist(@"submission-records.plist",next,error);}
}
NSString *AMSubmissionStateLabel(NSDictionary *record){if(record[@"confirmedAt"] && [record[@"state"] isEqual:@"local"])return @"远端历史已变化，需核对";if([record[@"origin"] isEqual:@"external"] && [record[@"state"] isEqual:@"uncertain"])return @"远端状态待核验";return @{@"running":@"正在提交",@"local":@"已本地提交，待推送",@"uncertain":@"推送结果待核验",@"confirmed":@"已确认推送",@"failed":@"提交失败"}[record[@"state"]] ?: @"待核验";}
