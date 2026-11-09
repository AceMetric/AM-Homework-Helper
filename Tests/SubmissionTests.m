#define main LegacyHomeworkTestMain
#import "HomeworkTests.m"
#undef main
#import "../Sources/SSLocalData.h"
#include "SubmissionCompletionTests.inc"
#include "SubmissionPipelineTests.inc"
@interface HistoryBudgetGit:FixtureGit
@property NSTimeInterval observedNetworkBudget;
@property BOOL expireAfterFetch;
@end
@implementation HistoryBudgetGit
- (SSGitResult *)run:(NSArray *)args in:(NSString *)path token:(NSString *)token error:(NSError **)error{BOOL network=[args.firstObject isEqual:@"fetch"];if(network)self.observedNetworkBudget=self.commandTimeout;SSGitResult *result=[super run:args in:path token:token error:error];if(network && self.expireAfterFetch)self.commandDeadline=[NSDate dateWithTimeIntervalSinceNow:-1];return result;}
@end
static void BackgroundFastForwardAssertions(void){
    NSMutableDictionary *fixture=Fixture();FixtureGit *service=Service(fixture);
    NSString *local=fixture[@"path"],*seed=fixture[@"seed"];
    NSString *initial=Git(local,@[@"rev-parse",@"HEAD"]),*remote=Git(fixture[@"forkBare"],@[@"rev-parse",@"main"]);
    Write([seed stringByAppendingPathComponent:@"new-requirements.md"],@"Synthetic teacher update\n");
    Git(seed,@[@"add",@"new-requirements.md"]);Git(seed,@[@"commit",@"-m",@"Add teacher requirements"]);
    NSString *teacher=Git(seed,@[@"rev-parse",@"HEAD"]);
    Git(local,@[@"fetch",@"--no-tags",seed,@"main"]);
    Write([local stringByAppendingPathComponent:@"shared.txt"],@"Keep uncommitted input\n");
    Check([[service fastForwardLocalCourse:fixture teacher:teacher remote:remote error:NULL][@"state"] isEqual:@"dirty"],@"background course update preserves dirty worktree");
    Check([Git(local,@[@"rev-parse",@"HEAD"]) isEqual:initial],@"dirty update leaves the local branch untouched");
    Git(local,@[@"restore",@"--",@"shared.txt"]);
    Check([[service fastForwardLocalCourse:fixture teacher:teacher remote:remote error:NULL][@"state"] isEqual:@"updated"],@"clean branch fast-forwards to verified teacher tip");
    Check([Git(local,@[@"rev-parse",@"HEAD"]) isEqual:teacher] && [Git(fixture[@"forkBare"],@[@"rev-parse",@"main"]) isEqual:remote],@"background update changes only the local branch");
}
static void AssignmentFeedbackAssertions(void){
    NSMutableDictionary *fixture=Fixture();FixtureGit *service=Service(fixture);
    NSString *root=fixture[@"path"];
    for(NSString *directory in @[@"assignment-6",@"assignment-7"]){
        Check([NSFileManager.defaultManager createDirectoryAtPath:[root stringByAppendingPathComponent:directory] withIntermediateDirectories:YES attributes:nil error:NULL],@"feedback fixture directories");
        Write([root stringByAppendingPathComponent:[directory stringByAppendingPathComponent:@"feedback.md"]],@"Synthetic review: check the boundary condition.\n");
    }
    Git(root,@[@"add",@"--",@"assignment-6",@"assignment-7"]);
    Git(root,@[@"-c",@"user.name=Synthetic Reviewer",@"-c",@"user.email=reviewer@example.invalid",@"commit",@"-m",@"Add feedback"]);
    NSString *review=Git(root,@[@"rev-parse",@"HEAD"]);
    Git(root,@[@"update-ref",@"refs/remotes/origin/main",review]);
    fixture[@"teacherCommit"]=fixture[@"teacherCommit"] ?: Git(fixture[@"teacherBare"],@[@"rev-parse",@"main"]);
    Write([root stringByAppendingPathComponent:@"assignment-6/feedback.md"],@"Uncommitted replacement\n");
    NSArray *found=[service assignmentFeedbackForCourse:fixture scope:@"assignment-6" login:@"student" remote:nil error:NULL];
    Check(found.count==1 && [found[0][@"commit"] isEqual:review] && [found[0][@"text"] containsString:@"boundary condition"],@"direct feedback uses the pinned Git object within this assignment");
    Check([service assignmentFeedbackForCourse:fixture scope:@"assignment-6" login:@"reviewer" remote:nil error:NULL].count==0,@"the student's own feedback-like commit is excluded");
}
@interface HistoryCountingGit:FixtureGit
@property NSUInteger diffs;
@property BOOL failPage;
@end
@implementation HistoryCountingGit
- (SSGitResult *)run:(NSArray *)args in:(NSString *)path token:(NSString *)token error:(NSError **)error {
    if([args.firstObject isEqual:@"diff-tree"]){
        self.diffs++;
        if(self.failPage && [args containsObject:@"--stdin"]){if(error)*error=GitError(@"synthetic batch read failure");return nil;}
    }
    return [super run:args in:path token:token error:error];
}
@end
static void HistoryBatchAssertions(void){
    NSMutableDictionary *course=Fixture();NSString *root=course[@"path"];
    NSString *teacher=Git(root,@[@"rev-parse",@"HEAD"]);
    course[@"teacherCommit"]=teacher;
    // The filename equal to a commit ID must be consumed as a path, not a new header.
    NSString *odd=@"spaces 与\t换行\n.txt";
    Write([root stringByAppendingPathComponent:odd],@"Synthetic answer\n");
    Write([root stringByAppendingPathComponent:teacher],@"Synthetic hash-named answer\n");
    Write([root stringByAppendingPathComponent:@".env"],@"synthetic config\n");
    Git(root,@[@"add",@"--force",@"--",odd,teacher,@".env"]);Git(root,@[@"commit",@"-m",@"Answer with unusual paths"]);
    Git(root,@[@"checkout",@"-b",@"second"]);Git(root,@[@"mv",odd,@"renamed.txt"]);Git(root,@[@"commit",@"-m",@"Rename answer"]);
    Git(root,@[@"checkout",@"main"]);Git(root,@[@"rm",@"--",teacher]);Git(root,@[@"commit",@"-m",@"Delete hash path"]);
    Git(root,@[@"merge",@"--no-ff",@"-m",@"Merge fixture",@"second"]);
    for(NSUInteger i=0;i<50;i++)Git(root,@[@"commit",@"--allow-empty",@"-m",[NSString stringWithFormat:@"Synthetic page commit %lu",(unsigned long)i]]);
    HistoryCountingGit *git=HistoryCountingGit.new;git.fixture=course;
    NSError *error=nil;NSTimeInterval start=NSProcessInfo.processInfo.systemUptime;
    NSArray *first=[git externalCommits:course offset:0 error:&error];NSTimeInterval batch=NSProcessInfo.processInfo.systemUptime-start;
    Check(first.count==50 && git.diffs==1,@"one diff-tree process reads a fifty-commit page including empty commits");
    NSDictionary *pinned=git.externalHistorySnapshot;
    Git(root,@[@"commit",@"--allow-empty",@"-m",@"New branch tip after first page"]);
    git.failPage=YES;Check(![git externalCommits:course offset:50 error:&error] && [git.externalHistorySnapshot isEqual:pinned],@"batch failure preserves the pinned cursor");
    git.failPage=NO;NSArray *second=[git externalCommits:course offset:50 error:&error];
    Check(second.count==4 && [second.firstObject[@"kind"] isEqual:@"merge"],@"page two keeps original tip and merges");
    NSUInteger commands=git.diffs;start=NSProcessInfo.processInfo.systemUptime;
    for(NSDictionary *row in [first arrayByAddingObjectsFromArray:second]){
        SSGitResult *legacy=[git checked:@[@"diff-tree",@"--root",@"-m",@"--no-commit-id",@"--name-only",@"-r",@"-z",row[@"commit"],@"--"] in:root token:nil error:&error];
        NSMutableArray *safe=NSMutableArray.array;
        for(NSString *path in [NSOrderedSet orderedSetWithArray:NonemptyParts([git string:legacy],@"\0")])if(!SSSensitivePath(path))[safe addObject:path];
        Check([row[@"files"] isEqual:safe],@"batch matches former read for root-like paths, merges, deletes and renames");
    }
    printf("History page: 1 diff-tree for 50 commits in %.0f ms; %lu individual reads in %.0f ms\n",batch*1000,(unsigned long)(git.diffs-commands),(NSProcessInfo.processInfo.systemUptime-start)*1000);
    NSArray *fresh=[git externalCommits:course offset:0 error:&error];
    Check([fresh.firstObject[@"message"] isEqual:@"New branch tip after first page"],@"refresh establishes a new snapshot");
    [course removeObjectForKey:@"teacherCommit"];Git(root,@[@"update-ref",@"-d",@"refs/remotes/upstream/main"]);
    git.externalHistorySnapshot=nil;NSArray *rootPage=[git externalCommits:course offset:50 error:&error];
    Check(rootPage.count>second.count && ![rootPage.lastObject[@"teacherHistoryKnown"] boolValue],@"root commit remains discoverable when no teacher history is available");
    Cleanup(course);
}
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
    NSDictionary *localPush=[service localPushStateForCourse:f remoteCommit:created error:&error];Check([localPush[@"known"] boolValue] && [localPush[@"ahead"] integerValue]==1 && [localPush[@"behind"] integerValue]==0,@"course status counts an unpushed terminal commit against verified personal tip without fetching");Check(![[service localPushStateForCourse:f remoteCommit:nil error:&error][@"known"] boolValue],@"unknown remote state is not reported as zero pending commits");
    Check([external.firstObject[@"commit"] isEqual:terminal] && [external.firstObject[@"origin"] isEqual:@"external"],@"terminal commit discovered on configured branch");
    Check([external indexOfObjectPassingTest:^BOOL(NSDictionary *r,NSUInteger i,BOOL *stop){return [r[@"commit"] isEqual:before];}]==NSNotFound,@"teacher history excluded using verified cached teacher commit");
    NSMutableDictionary *externalRecord=[external.firstObject mutableCopy];externalRecord[@"id"]=NSUUID.UUID.UUIDString;externalRecord[@"repository"]=f[@"fork"];externalRecord[@"branch"]=f[@"branch"];externalRecord[@"taskIDs"]=@[];externalRecord[@"state"]=@"uncertain";
    NSArray *verified=[service verifyExternalRecords:@[externalRecord] course:f token:@"test" error:&error];Check([verified.firstObject[@"state"] isEqual:@"local"],@"un-pushed terminal commit is local only");
    Git(f[@"path"],@[@"push",f[@"forkBare"],@"HEAD:main"]);verified=[service verifyExternalRecords:verified course:f token:@"test" error:&error];Check([verified.firstObject[@"state"] isEqual:@"confirmed"] && verified.firstObject[@"confirmedAt"],@"terminal push becomes remotely confirmed");
    HistoryBudgetGit *budget=HistoryBudgetGit.new;budget.fixture=f;error=nil;Check([budget verifyExternalRecords:@[] course:f token:@"test" error:&error]!=nil && budget.observedNetworkBudget>30 && budget.observedNetworkBudget<=180,@"history verification uses network budget instead of thirty-second local cap");Check(budget.commandTimeout==0 && !budget.commandDeadline,@"history verification restores caller timeout and deadline");NSDictionary *previousBaseline=AMSubmissionBaseline(f,NULL);budget.expireAfterFetch=YES;error=nil;Check(![budget verifyExternalRecords:@[] course:f token:@"test" error:&error] && error.code==NSURLErrorTimedOut && [AMSubmissionBaseline(f,NULL) isEqual:previousBaseline],@"expired shared history budget returns without erasing baseline or claiming success");Check(budget.commandTimeout==0 && !budget.commandDeadline,@"failed history verification also restores caller budget");
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
    HistoryBatchAssertions();BackgroundFastForwardAssertions();AssignmentFeedbackAssertions();CompletionAssertions();CompletionGitAssertions(f,service);FreshTeacherAssertions();PipelineAssertions();
    Cleanup(f);printf("PASS: %lu submission record and Git safety assertions\n",(unsigned long)assertions);
}return 0;}
