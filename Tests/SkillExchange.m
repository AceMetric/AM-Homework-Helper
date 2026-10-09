#import "QuietUI.h"
#import <sys/stat.h>
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
static NSUInteger checks;
static void Check(BOOL value,NSString *label){checks++;if(!value){fprintf(stderr,"FAIL: %s\n",label.UTF8String);exit(1);}}
static void Finish(SSCourseController *controller){NSDate *until=[NSDate dateWithTimeIntervalSinceNow:5];while(controller.busy && until.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];Check(!controller.busy,@"background receive completes");}
@interface ExchangeGit:SSGit
@property NSMutableDictionary *reads;
@property NSDictionary *sources;
@end
@implementation ExchangeGit
- (NSDictionary *)readCourseDocuments:(NSDictionary *)course paths:(NSArray *)paths fetch:(BOOL)fetch cache:(NSMutableDictionary *)cache error:(NSError **)error {
    NSString *fork=course[@"fork"];self.reads[fork]=@([self.reads[fork] unsignedIntegerValue]+1);Check(fetch && paths.count==1,@"receive fetches only returned document paths");
    return @{@"documents":self.sources[fork] ?: @[],@"commit":@"fixed",@"date":NSDate.date};
}
@end
int main(int argc,const char *argv[]){@autoreleasepool{
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    SSCourseController *controller=[[SSCourseController alloc] initWithPreview:YES];controller.preview=NO;
    ExchangeGit *git=ExchangeGit.new;git.reads=NSMutableDictionary.dictionary;controller.git=git;
    NSArray *courses=@[@{@"fork":@"student/physics",@"upstream":@"teacher/physics",@"path":@"/synthetic/physics"},@{@"fork":@"student/math",@"upstream":@"teacher/math",@"path":@"/synthetic/math"},@{@"fork":@"student/computing",@"upstream":@"teacher/computing",@"path":@"/synthetic/computing"}];
    controller.courses=[NSMutableArray arrayWithArray:courses];
    NSMutableDictionary *scans=NSMutableDictionary.dictionary,*sources=NSMutableDictionary.dictionary;NSMutableArray *answers=NSMutableArray.array;
    for(NSDictionary *course in courses){NSDictionary *document=@{@"repository":course[@"upstream"],@"path":@"assignment.md",@"blobSHA":@"version-1",@"timeZone":@"Asia/Shanghai",@"text":@"# 作业\n提交实验报告。截止时间：2027年1月2日 18:00。"};sources[course[@"fork"]]=@[document];scans[course[@"fork"]]=@{@"documents":@[document]};NSMutableDictionary *answer=document.mutableCopy;[answer removeObjectForKey:@"text"];answer[@"courseID"]=course[@"fork"];answer[@"activities"]=@[];[answers addObject:answer];}
    git.sources=sources;NSDictionary *exported=SSSkillExport(courses,scans,@{},NO);NSString *batch=exported[@"context"][@"batchID"];
    controller.skillBatches[batch]=exported[@"manifest"];controller.skillJobs[batch]=@{@"state":@"等待助手",@"date":NSDate.date,@"count":@3};
    NSURL *folder=[controller skillFolder:batch];Check(folder!=nil && [controller skillFolder:@"../outside"]==nil,@"only UUID child job paths are allowed");
    [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL];
    NSMutableDictionary *result=[@{@"format":@"am-course-results-v2",@"batchID":batch,@"documents":answers} mutableCopy];
    NSURL *url=[folder URLByAppendingPathComponent:@"results.local.json"],*tmp=[folder URLByAppendingPathComponent:@"results.local.json.tmp"];
    [@"{" writeToURL:tmp atomically:YES encoding:NSUTF8StringEncoding error:NULL];[controller pollSkillResults:nil];Check(!controller.busy && !git.reads.count,@"incomplete temporary output is never consumed");
    [@"{" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:NULL];Check(!SSSkillReadResult(url,NULL),@"partial JSON rejected before any network work");
    NSData *data=[NSJSONSerialization dataWithJSONObject:result options:0 error:NULL];[data writeToURL:tmp atomically:YES];[NSFileManager.defaultManager removeItemAtURL:url error:NULL];[NSFileManager.defaultManager moveItemAtURL:tmp toURL:url error:NULL];
    [controller pollSkillResults:nil];Finish(controller);
    Check([controller.skillJobs[batch][@"state"] isEqual:@"已接回"] && controller.skillProgress.count==3,@"three courses received without import dialog");Check(git.reads.count==3,@"only each involved course is read once");
    Check([SSReadPlist(@"discoveries.plist")[@"skillProgress"] count]==3,@"progress and job state persist atomically");
    [controller pollSkillResults:nil];Check([git.reads[courses[0][@"fork"]] intValue]==1,@"completed result cannot trigger repeated reads");
    SSCourseController *restored=[[SSCourseController alloc] initWithPreview:NO];Check([restored.skillJobs[batch][@"state"] isEqual:@"已接回"],@"restart restores completed jobs");
    NSString *second=NSUUID.UUID.UUIDString;NSMutableDictionary *partial=[SSSkillExport(courses,scans,@{},NO) mutableCopy];second=partial[@"context"][@"batchID"];controller.skillBatches[second]=partial[@"manifest"];controller.skillJobs[second]=@{@"state":@"等待助手",@"date":NSDate.date,@"count":@3};
    NSDictionary *one=@{@"format":@"am-course-results-v2",@"batchID":second,@"documents":@[answers[0]]};[controller receiveSkillResult:one batch:second fingerprint:@"one" legacy:nil automatic:YES];Finish(controller);
    Check([git.reads[courses[1][@"fork"]] intValue]==1 && [git.reads[courses[2][@"fork"]] intValue]==1,@"partial response does not scan unrelated courses");
    NSMutableDictionary *recent=NSMutableDictionary.dictionary;for(NSString *fork in scans){NSMutableDictionary *snapshot=[scans[fork] mutableCopy];snapshot[@"date"]=NSDate.date;snapshot[@"commit"]=@"fixed";recent[fork]=snapshot;}controller.reports=recent;
    NSUInteger reads=[[git.reads.allValues valueForKeyPath:@"@sum.self"] unsignedIntegerValue];NSDate *start=NSDate.date;
    NSDictionary *warm=[controller readSkillCourses:courses result:nil];
    Check(warm.count==3 && [[git.reads.allValues valueForKeyPath:@"@sum.self"] unsignedIntegerValue]==reads,@"warm preparation reuses completed snapshots without a fetch");
    printf("TIMING: warm preparation %.6f seconds; baseline full reads 3, warm reads 0\n",-start.timeIntervalSinceNow);
    NSDictionary *skillRecord=@{@"id":@"stable",@"recognizer":@"skill-v1",@"summary":@"保留概括",@"path":@"assignment.md",@"repository":@"teacher/physics",@"blobSHA":@"version-1"};
    Check([[controller retainingSkill:@[skillRecord] current:@[] documents:sources[@"student/physics"]] count]==1,@"unchanged scan retains assistant summaries");
    Check([[controller retainingSkill:@[skillRecord] current:@[] documents:@[]] count]==0,@"removed or changed document cannot retain stale suggestions");
    Check([SSSkillExport(courses,scans,controller.skillProgress,NO)[@"context"][@"documents"] count]==0,@"successful receives consume incremental materials");
    NSURL *link=[folder URLByAppendingPathComponent:@"link.json"];[NSFileManager.defaultManager createSymbolicLinkAtURL:link withDestinationURL:url error:NULL];Check(!SSSkillReadResult(link,NULL),@"result symlinks cannot redirect reads");
    NSURL *fifo=[folder URLByAppendingPathComponent:@"pipe.json"];mkfifo(fifo.fileSystemRepresentation,0600);Check(!SSSkillReadResult(fifo,NULL),@"named pipe cannot block result watcher");
    result[@"documents"]=@"invalid";[[NSJSONSerialization dataWithJSONObject:result options:0 error:NULL] writeToURL:url atomically:YES];Check(!SSSkillReadResult(url,NULL),@"invalid document collection rejected");
    // Replace only the test data file with a directory to inject a storage failure.
    NSURL *store=[SSDataDirectory() URLByAppendingPathComponent:@"discoveries.plist"];[NSFileManager.defaultManager removeItemAtURL:store error:NULL];[NSFileManager.defaultManager createDirectoryAtURL:store withIntermediateDirectories:NO attributes:nil error:NULL];
    NSUInteger before=controller.skillProgress.count;NSMutableDictionary *changed=[answers[0] mutableCopy];changed[@"blobSHA"]=@"version-2";NSMutableDictionary *live=[sources[courses[0][@"fork"]][0] mutableCopy];live[@"blobSHA"]=@"version-2";sources[courses[0][@"fork"]]=@[live];git.sources=sources;
    NSString *failureBatch=NSUUID.UUID.UUIDString;NSDictionary *failureExport=SSSkillExport(@[courses[0]],@{courses[0][@"fork"]:@{@"documents":@[live]}},@{},NO);failureBatch=failureExport[@"context"][@"batchID"];controller.skillBatches[failureBatch]=failureExport[@"manifest"];controller.skillJobs[failureBatch]=@{@"state":@"等待助手",@"date":NSDate.date,@"count":@1};
    [controller receiveSkillResult:@{@"format":@"am-course-results-v2",@"batchID":failureBatch,@"documents":@[changed]} batch:failureBatch fingerprint:@"fail" legacy:nil automatic:YES];Finish(controller);
    Check(controller.skillProgress.count==before && ![controller.skillProgress.allValues containsObject:SSSkillVersion(live)],@"failed save neither partially merges nor advances progress");
    printf("PASS: %lu Skill exchange assertions\n",(unsigned long)checks);
}return 0;}
