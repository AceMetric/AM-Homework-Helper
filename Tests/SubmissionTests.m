#define main LegacyHomeworkTestMain
#import "HomeworkTests.m"
#undef main
#import "../Sources/SSLocalData.h"
int main(void){@autoreleasepool{
    NSString *data=NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"];Check(data.length>0,@"isolated submission storage");
    NSMutableDictionary *f=Fixture();FixtureGit *service=Service(f);NSError *error=nil;NSString *before=Git(f[@"teacherBare"],@[@"rev-parse",@"main"]);
    Write([f[@"path"] stringByAppendingPathComponent:@"answer.md"],@"An original answer\n");
    NSDictionary *record=[service performRecordedCourse:f kind:@"submission" taskIDs:@[@"task-one",@"task-two"] paths:@[@"answer.md"] message:@"Finish report" token:@"test" login:@"student" userID:@42 error:&error];
    if(![record[@"state"] isEqual:@"confirmed"])fprintf(stderr,"record state=%s, error=%s\n",[record[@"state"] UTF8String],error.localizedDescription.UTF8String);
    Check([record[@"state"] isEqual:@"confirmed"] && [record[@"commit"] length]==40,@"record verified own remote commit");Check([record[@"files"] isEqual:@[@"answer.md"]] && [record[@"taskIDs"] count]==2,@"actual file and stable task association");Check([AMSubmissionRecords(NULL).lastObject[@"commit"] isEqual:record[@"commit"]],@"record reloaded after commit");
    Check([Git(f[@"teacherBare"],@[@"rev-parse",@"main"]) isEqual:before],@"teacher unchanged");
    Write([f[@"path"] stringByAppendingPathComponent:@"answer.md"],@"Revised answer\n");service.rejectPush=YES;
    record=[service performRecordedCourse:f kind:@"submission" taskIDs:@[] paths:@[@"answer.md"] message:@"Revise report" token:@"test" login:@"student" userID:@42 error:&error];NSString *created=record[@"commit"];
    Check(created.length && ![record[@"state"] isEqual:@"confirmed"],@"push failure retains actual local commit");service.rejectPush=NO;
    record=[service verifySubmission:record course:f token:@"test" retry:YES error:&error];Check([record[@"state"] isEqual:@"confirmed"],@"retry verifies and pushes same commit");Check([Git(f[@"path"],@[@"rev-parse",@"HEAD"]) isEqual:created],@"retry creates no duplicate commit");
    NSMutableDictionary *interrupted=record.mutableCopy;interrupted[@"id"]=NSUUID.UUID.UUIDString;interrupted[@"state"]=@"running";[interrupted removeObjectForKey:@"commit"];
    Check(AMStoreSubmission(interrupted,&error),@"persist interrupted intent");record=[service verifySubmission:interrupted course:f token:@"test" retry:NO error:&error];Check([record[@"commit"] isEqual:created] && [record[@"state"] isEqual:@"confirmed"],@"crash after commit recovered by exact parent message and files");
    Check([service recentCommits:f error:&error].count>0,@"bounded recent local history available");
    f[@"teacherCommit"]=before;
    Write([f[@"path"] stringByAppendingPathComponent:@"terminal.md"],@"Synthetic terminal answer\n");Git(f[@"path"],@[@"add",@"terminal.md"]);Git(f[@"path"],@[@"commit",@"-m",@"Terminal work"]);
    NSString *terminal=Git(f[@"path"],@[@"rev-parse",@"HEAD"]);NSArray *external=[service externalCommits:f offset:0 error:&error];
    Check([external.firstObject[@"commit"] isEqual:terminal] && [external.firstObject[@"origin"] isEqual:@"external"],@"terminal commit discovered on configured branch");
    Check([external indexOfObjectPassingTest:^BOOL(NSDictionary *r,NSUInteger i,BOOL *stop){return [r[@"commit"] isEqual:before];}]==NSNotFound,@"teacher history excluded using verified cached teacher commit");
    NSMutableDictionary *externalRecord=[external.firstObject mutableCopy];externalRecord[@"id"]=NSUUID.UUID.UUIDString;externalRecord[@"repository"]=f[@"fork"];externalRecord[@"branch"]=f[@"branch"];externalRecord[@"taskIDs"]=@[];externalRecord[@"state"]=@"uncertain";
    NSArray *verified=[service verifyExternalRecords:@[externalRecord] course:f token:@"test" error:&error];Check([verified.firstObject[@"state"] isEqual:@"local"],@"un-pushed terminal commit is local only");
    Git(f[@"path"],@[@"push",f[@"forkBare"],@"HEAD:main"]);verified=[service verifyExternalRecords:verified course:f token:@"test" error:&error];Check([verified.firstObject[@"state"] isEqual:@"confirmed"] && verified.firstObject[@"confirmedAt"],@"terminal push becomes remotely confirmed");
    Check([Git(f[@"teacherBare"],@[@"rev-parse",@"main"]) isEqual:before],@"external discovery and verification never push teacher");
    Git(f[@"path"],@[@"checkout",@"-b",@"unrelated"]);external=[service externalCommits:f offset:0 error:&error];Check([external.firstObject[@"commit"] isEqual:terminal],@"discovery reads configured branch without switching current branch");Git(f[@"path"],@[@"checkout",@"main"]);
    NSMutableDictionary *malicious=record.mutableCopy;malicious[@"repository"]=@"teacher/course";NSUInteger pushes=service.pushTargets.count;Check(![service verifySubmission:malicious course:f token:@"test" retry:YES error:&error] && service.pushTargets.count==pushes,@"teacher record cannot become push target");
    malicious=record.mutableCopy;malicious[@"files"]=@[@"/private/secret"];Check(!AMStoreSubmission(malicious,&error),@"absolute paths rejected");malicious=record.mutableCopy;malicious[@"token"]=@"synthetic-no-real-token";Check(AMStoreSubmission(malicious,&error) && !AMSubmissionRecords(NULL).lastObject[@"token"],@"nonallowlisted credential fields discarded");
    NSURL *store=[SSDataDirectory() URLByAppendingPathComponent:@"submission-records.plist"];NSData *original=[NSData dataWithContentsOfURL:store];[NSFileManager.defaultManager removeItemAtURL:store error:NULL];[NSFileManager.defaultManager createDirectoryAtURL:store withIntermediateDirectories:NO attributes:nil error:NULL];
    Write([f[@"path"] stringByAppendingPathComponent:@"answer.md"],@"Should remain local only\n");created=Git(f[@"path"],@[@"rev-parse",@"HEAD"]);Check(![service performRecordedCourse:f kind:@"submission" taskIDs:@[] paths:@[@"answer.md"] message:@"Blocked intent" token:@"test" login:@"student" userID:@42 error:&error],@"record write failure blocks initial commit");Check([Git(f[@"path"],@[@"rev-parse",@"HEAD"]) isEqual:created],@"no Git write if intent cannot persist");[NSFileManager.defaultManager removeItemAtURL:store error:NULL];[original writeToURL:store atomically:YES];
    NSArray *savedRecords=AMSubmissionRecords(NULL);NSDictionary *task=@{@"id":@"task-one",@"title":@"Report",@"due":NSDate.date,@"notes":@"",@"subject":@"Course"};
    Check(AMRestoreBackup(@[],@[task],savedRecords,&error),@"task and record backup restores together");Check([AMBackupEnvelope(@[task],NULL)[@"submissions"] count]==savedRecords.count,@"backup contains journal without credential fields");
    Check(SSWritePlist(@"backup-transaction.plist",@{@"tasks":@[],@"submissions":savedRecords},NULL),@"simulate interrupted restore intent");Check(SSLoadTasks(NULL).count==0 && AMSubmissionRecords(NULL).count==savedRecords.count,@"startup completes restore intent without Git writes");
    NSMutableDictionary *tainted=record.mutableCopy;tainted[@"token"]=@"synthetic-not-a-token";Check(!AMDecodeBackup(@{@"format":@"am-helper-backup-v2",@"tasks":@[task],@"submissions":@[tainted]},NULL),@"unknown credential fields rejected in backup");
    Cleanup(f);printf("PASS: %lu submission record and Git safety assertions\n",(unsigned long)assertions);
}return 0;}
