#define main LegacyHomeworkMain
#import "HomeworkTests.m"
#undef main
@interface WorkflowProtocol:NSURLProtocol @end
static NSArray *HTTPResponses;static NSUInteger HTTPCalls;
@implementation WorkflowProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request{return [request.URL.host isEqual:@"api.github.com"];}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request{return request;}
- (void)startLoading{NSDictionary *next=HTTPResponses[MIN(HTTPCalls++,HTTPResponses.count-1)];NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:[next[@"status"] integerValue] HTTPVersion:@"HTTP/1.1" headerFields:next[@"headers"] ?: @{}];[self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];[self.client URLProtocol:self didLoadData:[NSJSONSerialization dataWithJSONObject:next[@"body"] ?: @{@"message":@"synthetic failure"} options:0 error:NULL]];[self.client URLProtocolDidFinishLoading:self];}
- (void)stopLoading{}
@end
@interface DeadlineAPI:SSGitHub
@property NSUInteger calls;
@property NSDate *firstDeadline;
@property BOOL commonDeadline;
@end
@implementation DeadlineAPI
- (id)workflowRequestURL:(NSURL *)url form:(NSDictionary *)form token:(NSString *)token error:(NSError **)error{self.calls++;if(!self.firstDeadline)self.firstDeadline=self.workflowDeadline;else self.commonDeadline=self.firstDeadline==self.workflowDeadline;if(self.calls==1){if(error)*error=AMWorkflowError(@"network",@"offline",nil);return nil;}return @{@"ok":@YES};}
@end
@interface StorageAfterPushGit:FixtureGit
@property BOOL failStore;
@property NSData *oldStore;
@end
@implementation StorageAfterPushGit
- (BOOL)pushCourse:(NSDictionary *)course token:(NSString *)token error:(NSError **)error{BOOL result=[super pushCourse:course token:token error:error];if(result && self.failStore){self.failStore=NO;NSURL *url=[SSDataDirectory() URLByAppendingPathComponent:@"submission-records.plist"];self.oldStore=[NSData dataWithContentsOfURL:url];[NSFileManager.defaultManager removeItemAtURL:url error:NULL];[NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:NO attributes:nil error:NULL];}return result;}
@end
@interface RetryGit:SSGit
@property NSUInteger calls;
@property NSTimeInterval firstBudget;
@property BOOL budgetShared;
@end
@implementation RetryGit
- (SSGitResult *)run:(NSArray *)args in:(NSString *)path token:(NSString *)token error:(NSError **)error{self.calls++;if(self.calls==1)self.firstBudget=self.commandTimeout;else self.budgetShared=self.commandTimeout<self.firstBudget;SSGitResult *result=SSGitResult.new;result.status=self.calls==1 ? 128:0;result.data=NSData.data;result.diagnostic=self.calls==1 ? @"Failed to connect to GitHub":@"";return result;}
@end
@interface LostPushGit:FixtureGit @end
@implementation LostPushGit
- (BOOL)pushCourse:(NSDictionary *)course token:(NSString *)token error:(NSError **)error {BOOL ok=[super pushCourse:course token:token error:error];if(ok && self.pushTargets.count==1){if(error)*error=AMWorkflowError(@"network",@"response lost after push",nil);return NO;}return ok;}
@end
int main(){@autoreleasepool{
    Check(NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"].length>0,@"workflow fixtures isolated");NSError *error=nil;NSDictionary *environment=NSProcessInfo.processInfo.environment;
    NSDate *started=NSDate.date;SSGitResult *result=AMRunGitProcess(@[@"-c",@"alias.amprobe=!/bin/sh -c 'sleep 30 & exit 0'",@"amprobe"],environment,NSTemporaryDirectory(),nil,5,nil,nil,&error);Check(!result && [AMWorkflowIssue(error) isEqual:@"timeout"] && -started.timeIntervalSinceNow<3.5,@"escaped descendant cannot hold output forever");
    __block BOOL stopped=NO;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,150*NSEC_PER_MSEC),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{stopped=YES;});started=NSDate.date;result=AMRunGitProcess(@[@"-c",@"alias.amprobe=!sleep 30",@"amprobe"],environment,NSTemporaryDirectory(),nil,5,^BOOL{return stopped;},nil,&error);Check(!result && [AMWorkflowIssue(error) isEqual:@"cancelled"] && -started.timeIntervalSinceNow<2.5,@"cancel interrupts real process group and pipe readers");
    started=NSDate.date;result=AMRunGitProcess(@[@"-c",@"alias.amprobe=!sleep 30",@"amprobe"],environment,NSTemporaryDirectory(),nil,.15,nil,nil,&error);Check(!result && [AMWorkflowIssue(error) isEqual:@"timeout"] && -started.timeIntervalSinceNow<2.5,@"process budget returns even when child still runs");
    SSGitHub *api=SSGitHub.new;api.workflowProtocolClasses=@[WorkflowProtocol.class];NSURL *url=[NSURL URLWithString:@"https://api.github.com/repos/student/example"];
    for(NSArray *pair in @[@[@401,@"login"],@[@403,@"permission"],@[@404,@"permission"],@[@429,@"rate-limit"],@[@500,@"service"],@[@422,@"response"]]){HTTPCalls=0;HTTPResponses=@[@{@"status":pair[0]}];error=nil;Check(![api requestURL:url form:nil token:nil error:&error] && [AMWorkflowIssue(error) isEqual:pair[1]],@"HTTP status maps to correct recoverable category");Check([error.userInfo[@"SSRepository"] isEqual:@"student/example"],@"repository context survives API error");Check(HTTPCalls==([pair[0] integerValue]==500 ? 2:1),@"only transient reads retry once");}
    HTTPCalls=0;HTTPResponses=@[@{@"status":@403,@"headers":@{@"Retry-After":@"120"},@"body":@{@"message":@"secondary rate limit"}}];error=nil;[api requestURL:url form:nil token:nil error:&error];Check([AMWorkflowIssue(error) isEqual:@"rate-limit"] && HTTPCalls==1 && [error.userInfo[@"AMRetryAt"] timeIntervalSinceNow]>110,@"long rate limit is shown without blocking or permission misclassification");
    HTTPCalls=0;HTTPResponses=@[@{@"status":@503},@{@"status":@200,@"body":@{@"ok":@YES}}];Check([[api requestURL:url form:nil token:nil error:&error][@"ok"] boolValue] && HTTPCalls==2,@"read service error recovers once");
    HTTPCalls=0;HTTPResponses=@[@{@"status":@503}];Check(![api requestURL:url form:@{@"code":@"synthetic"} token:nil error:&error] && HTTPCalls==1,@"authentication POST is never replayed");
    DeadlineAPI *deadline=DeadlineAPI.new;started=NSDate.date;Check([deadline requestURL:url form:nil token:nil error:&error] && deadline.calls==2 && deadline.commonDeadline && -started.timeIntervalSinceNow>=.9,@"retry waits one second and shares original API deadline");
    deadline=DeadlineAPI.new;deadline.requestsCancelled=YES;Check(![deadline requestURL:url form:nil token:nil error:&error] && deadline.calls==1,@"cancel prevents automatic retry");
    NSError *underlying=AMWorkflowError(@"permission",@"access denied",nil),*pending=PendingPushError(underlying);Check([AMWorkflowIssue(pending) isEqual:@"permission"] && pending.userInfo[NSUnderlyingErrorKey]==underlying && [pending.userInfo[@"SSDetail"] length],@"pending push retains classification and cause");
    NSDictionary *checkpoint=@{@"commit":[@"a" stringByPaddingToLength:40 withString:@"a" startingAtIndex:0],@"state":@"local"};Check([AMWorkflowProblem(pending,@"push",checkpoint)[@"command"] isEqual:@"access"],@"access must be repaired before checkpoint resumes");Check([AMWorkflowProblem(AMWorkflowError(@"network",@"offline",nil),@"push",checkpoint)[@"command"] isEqual:@"verify"],@"post-commit network failure verifies instead of replaying commit");
    for(NSArray *pair in @[@[@"login",@"login"],@[@"directory",@"relink"],@[@"dirty",@"changes"],@[@"merge-conflict",@"conflicts"],@[@"diverged",@"difference"],@[@"files-changed",@"refresh"],@[@"storage",@"save"],@[@"recognition",@"recognition"]])Check([AMWorkflowProblem(AMWorkflowError(pair[0],@"fixture",nil),@"test",nil)[@"command"] isEqual:pair[1]],@"problem routes to its specific recovery");
    NSMutableDictionary *fixture=Fixture();StorageAfterPushGit *git=StorageAfterPushGit.new;git.fixture=fixture;git.identityVerifier=Service(fixture).identityVerifier;git.failStore=YES;Write([fixture[@"path"] stringByAppendingPathComponent:@"answer.md"],@"Synthetic answer\n");error=nil;
    NSDictionary *record=[git performRecordedCourse:fixture kind:@"submission" taskIDs:@[] paths:@[@"answer.md"] message:@"Store recovery fixture" token:@"test" login:@"student" userID:@42 error:&error];Check([record[@"state"] isEqual:@"confirmed"] && error && [git.lastWorkflowRecord[@"state"] isEqual:@"confirmed"],@"remote success and persistence failure remain distinct");NSString *commit=Git(fixture[@"path"],@[@"rev-parse",@"HEAD"]);NSUInteger pushes=git.pushTargets.count;
    NSURL *store=[SSDataDirectory() URLByAppendingPathComponent:@"submission-records.plist"];[NSFileManager.defaultManager removeItemAtURL:store error:NULL];[git.oldStore writeToURL:store atomically:YES];Check(AMStoreSubmission(git.lastWorkflowRecord,&error) && git.pushTargets.count==pushes && [Git(fixture[@"path"],@[@"rev-parse",@"HEAD"]) isEqual:commit],@"save-only recovery creates no new commit or push");
    Cleanup(fixture);
    for(NSString *command in @[@"fetch",@"ls-remote",@"push",@"merge",@"commit"]){RetryGit *retry=RetryGit.new;NSError *failure=nil;BOOL read=[@[@"fetch",@"ls-remote"] containsObject:command];SSGitResult *value=[retry checked:@[command] in:nil token:nil error:&failure];Check(read ? (value && retry.calls==2 && retry.budgetShared):(!value && failure && retry.calls==1),@"read-only Git retry shares budget; writes never replay");}
    RetryGit *expired=RetryGit.new;expired.commandDeadline=[NSDate dateWithTimeIntervalSinceNow:-1];error=nil;Check(![expired checked:@[@"fetch"] in:nil token:nil error:&error] && error.code==NSURLErrorTimedOut && expired.calls==0,@"expired Git stage cannot start another attempt");expired.operationCancelled=YES;error=nil;Check(![expired checked:@[@"fetch"] in:nil token:nil error:&error] && error.code==NSUserCancelledError && expired.calls==0,@"cancellation remains terminal when deadline also expired");
    fixture=Fixture();LostPushGit *lost=LostPushGit.new;lost.fixture=fixture;Write([fixture[@"path"] stringByAppendingPathComponent:@"answer.md"],@"Lost response fixture\n");error=nil;record=[lost performRecordedCourse:fixture kind:@"submission" taskIDs:@[] paths:@[@"answer.md"] message:@"Response loss" token:@"test" login:@"student" userID:@42 error:&error];Check(record[@"commit"] && error && lost.pushTargets.count==1,@"push response loss preserves checkpoint");NSString *savedCommit=record[@"commit"];error=nil;record=[lost verifySubmission:record course:fixture token:@"test" retry:YES error:&error];Check([record[@"state"] isEqual:@"confirmed"] && [record[@"commit"] isEqual:savedCommit] && lost.pushTargets.count==1,@"retry first checks remote and never repeats already successful push");Cleanup(fixture);
    printf("PASS: %lu workflow recovery, HTTP and process assertions\n",(unsigned long)assertions);
}return 0;}
