#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
@interface NSViewController(HistoryTest) - (void)refresh; @end
static NSUInteger checks;
static void Check(BOOL ok,NSString *why){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",why.UTF8String);exit(1);}}
static void Wait(BOOL (^ready)(void)){NSDate *end=[NSDate dateWithTimeIntervalSinceNow:4];while(!ready() && end.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];Check(ready(),@"history callback returns without blocking UI");}
@interface PollAPI:SSGitHub @end
@implementation PollAPI
- (NSString *)accessToken:(NSError **)error{return @"synthetic-no-network";}
- (NSDictionary *)authenticationIdentity{return @{@"login":@"student",@"userID":@42};}
@end
@interface PollGit:SSGit
@property NSUInteger reads;
@property NSUInteger verifies;
@property NSString *failureIssue;
@property BOOL succeed;
@property BOOL emptyFailure;
@end
@implementation PollGit
- (NSArray *)externalCommits:(NSDictionary *)course offset:(NSUInteger)offset error:(NSError **)error{self.reads++;return @[];}
- (NSArray *)classifyExternalRecords:(NSArray *)records course:(NSDictionary *)course{return @[];}
- (NSArray *)verifyExternalRecords:(NSArray *)records course:(NSDictionary *)course token:(NSString *)token error:(NSError **)error{self.verifies++;BOOL metadataOnly=NO;for(NSDictionary *row in AMOperations())if([row[@"kind"] isEqual:@"核验提交记录"] && [row[@"state"] isEqual:@"running"] && [row[@"resources"] isEqual:AMRepositoryResources(course,@"fetch")])metadataOnly=YES;Check(metadataOnly,@"background remote verification does not reserve the worktree read barrier");Check(self.commandTimeout==180,@"network verification is not limited to thirty seconds");if(self.succeed)return @[];if(self.emptyFailure)return nil;if(error)*error=AMWorkflowError(self.failureIssue ?: @"timeout",@"Synthetic verification failure",nil);return nil;}
@end
@interface LaunchScanGit : SSGit
@property (atomic) NSUInteger calls;
@property (atomic) BOOL bounded;
@end
@implementation LaunchScanGit
- (NSDictionary *)scanCourse:(NSDictionary *)course cache:(NSMutableDictionary *)cache error:(NSError **)error {
    self.calls++;
    self.bounded=self.commandDeadline && self.commandDeadline.timeIntervalSinceNow<=45;
    if(error)*error=AMWorkflowError(@"network",@"合成网络故障",nil);
    return nil;
}
@end
static NSArray *HistoryViews(NSView *view){NSMutableArray *rows=NSMutableArray.array;if([view isKindOfClass:AMOperationView.class])for(NSDictionary *op in AMOperations())if([op[@"id"] isEqual:[(AMOperationView *)view operationID]] && op[@"presentationKey"])[rows addObject:view];for(NSView *child in view.subviews)[rows addObjectsFromArray:HistoryViews(child)];return rows;}
int main(){@autoreleasepool{
 Check(NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"].length>0,@"synthetic isolated polling storage");NSDate *now=NSDate.date;NSDictionary *state=@{};NSError *timeout=AMWorkflowError(@"timeout",@"fixture",nil);
 for(NSUInteger i=0;i<6;i++){state=AMHistoryPollResult(state,timeout,NO,now);Check([state[@"next"] timeIntervalSinceDate:now]>=300 && [state[@"next"] timeIntervalSinceDate:now]<=1800,@"failures back off between five and thirty minutes");Check(!AMHistoryPollDue(state,[now dateByAddingTimeInterval:60]),@"minute tick does not repeat a failure");}
 state=AMHistoryPollResult(state,nil,NO,now);Check([state[@"failures"] integerValue]==0 && AMHistoryPollDue(state,[now dateByAddingTimeInterval:60]),@"success clears backoff");state=AMHistoryPollResult(@{},[NSError errorWithDomain:@"limit" code:1 userInfo:@{@"AMRetryAt":[now dateByAddingTimeInterval:3600]}],NO,now);Check(!AMHistoryPollDue(state,[now dateByAddingTimeInterval:1800]),@"server retry time is honored");
 [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];AppDelegate *app=AppDelegate.new;[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];[app.ticker invalidate];SSCourseController *c=app.courseWindow;c.connected=YES;c.github=PollAPI.new;c.preview=NO;c.verifiedSubmissionsChanged=nil;
 NSDictionary *course=@{@"fork":@"student/history",@"upstream":@"teacher/history",@"path":@"/synthetic/history",@"branch":@"main",@"upstreamBranch":@"main"};c.courses=[@[course.mutableCopy] mutableCopy];[c selectCourseID:course[@"fork"]];PollGit *git=PollGit.new;c.externalReaderFactory=^SSGit *(NSDictionary *target){return git;};c.externalAPIFactory=^SSGitHub *{return PollAPI.new;};
 NSString *key=AMHistoryPollingKey(course,c.github.authenticationIdentity);NSMutableDictionary *changed=course.mutableCopy;changed[@"branch"]=@"other";Check(![key isEqual:AMHistoryPollingKey(changed,c.github.authenticationIdentity)] && ![key isEqual:AMHistoryPollingKey(course,@{@"login":@"other"})],@"backoff is bound to exact course and account");
 [c discoverExternalSubmissions:NO];Wait(^BOOL{return !c.discoveringExternal;});Check(git.verifies==1 && [c.externalPolling[key][@"failures"] integerValue]==1,@"first timeout records a failed verification");for(NSUInteger i=0;i<20;i++)[c discoverExternalSubmissions:NO];Check(git.verifies==1 && git.reads==1,@"repeated tick and activation do not run again during backoff");
 NSDictionary *persisted=SSReadPlist(@"submission-history-polling.plist");c.externalPolling=nil;[c discoverExternalSubmissions:NO];Check(git.verifies==1 && [c.externalPolling isEqual:persisted],@"restart reloads retry times without replaying failed requests");
 NSViewController *activity=[NSClassFromString(@"AMActivityController") new];(void)activity.view;[activity refresh];Check(HistoryViews(activity.view).count==1,@"one history failure has one activity row");AMOperationView *row=HistoryViews(activity.view)[0];NSButton *close=[row valueForKey:@"cancelButton"];[close performClick:nil];[activity refresh];Check(!HistoryViews(activity.view).count,@"history error can be dismissed");
 [c submissionAction:@"refresh-external" identifier:@""];Wait(^BOOL{return !c.discoveringExternal;});[activity refresh];Check(git.verifies==2 && !HistoryViews(activity.view).count,@"manual retry bypasses backoff but identical dismissed error remains closed");Check([c.workflowFailures.allValues.firstObject.problem[@"effect"] isEqual:@"现有记录保留"],@"read-only failure describes records rather than files");
 git.failureIssue=@"network";[c discoverExternalSubmissions:NO forCourses:@[course] manual:YES];Wait(^BOOL{return !c.discoveringExternal;});[activity refresh];Check(HistoryViews(activity.view).count==1,@"changed error is shown once rather than adding old failures");
 git.emptyFailure=YES;void (^recover)(void)=nil;for(NSDictionary *operation in AMOperations())if(operation[@"presentationKey"] && operation[@"recovery"]){recover=operation[@"recovery"];break;}Check(recover!=nil,@"failed history retains an actionable retry");recover();Wait(^BOOL{return !c.discoveringExternal;});Check([c.externalPolling[key][@"failures"] integerValue]>0 && [c.workflowFailures.allValues.firstObject.problem[@"issue"] isEqual:@"verification-pending"],@"missing result without NSError is still a failed verification");git.emptyFailure=NO;
 NSDictionary *priorState=c.externalPolling[key];c.externalPolling[key]=AMHistoryPollResult(@{},[NSError errorWithDomain:@"rate-limit" code:1 userInfo:@{@"AMRetryAt":[NSDate dateWithTimeIntervalSinceNow:3600]}],NO,NSDate.date);NSUInteger priorCalls=git.verifies;[c submissionAction:@"refresh-external" identifier:@""];Check(!c.discoveringExternal && git.verifies==priorCalls,@"manual retry respects server rate limit while bypassing ordinary backoff");c.externalPolling[key]=priorState;
 git.succeed=YES;[c discoverExternalSubmissions:NO forCourses:@[course] manual:YES];Wait(^BOOL{return !c.discoveringExternal;});[activity refresh];Check([c.externalPolling[key][@"failures"] integerValue]==0 && HistoryViews(activity.view).count==1 && !c.workflowFailures.count && c.workflowNotice.hidden,@"successful retry replaces failed presentation and clears backoff");
 // 升级重启后先完成老师读取，再允许自动提交核验。断网只尝试一门。
 LaunchScanGit *scan=LaunchScanGit.new;
 c.workflowGitFactory=^SSGit *{scan.commandDeadline=nil;return scan;};
 c.workflowAPIFactory=^SSGitHub *{return PollAPI.new;};
 NSMutableDictionary *second=course.mutableCopy;
 second[@"fork"]=@"student/second";
 second[@"upstream"]=@"teacher/second";
 c.courses=[@[course.mutableCopy,second] mutableCopy];
 for(NSUInteger i=3;i<=5;i++){
     NSMutableDictionary *other=course.mutableCopy;
     other[@"fork"]=[NSString stringWithFormat:@"student/course%lu",(unsigned long)i];
     other[@"upstream"]=[NSString stringWithFormat:@"teacher/course%lu",(unsigned long)i];
     [c.courses addObject:other];
 }
 NSUInteger historyBefore=git.reads;
 [c scanAll:nil];
 [c discoverExternalSubmissions:NO];
 Wait(^BOOL{return !c.operationBusy && !c.automaticScanQueue;});
 Check(scan.calls==1 && scan.bounded,@"first launch connection failure stops the remaining teacher reads within a shared deadline");
 [c scanAll:nil];
 [c discoverExternalSubmissions:NO];
 Check(scan.calls==1 && git.reads==historyBefore && [c automaticRemoteWorkDeferred],@"startup and minute polling share the connection backoff");
 [c scanCourses:@[second]];
 Wait(^BOOL{return !c.operationBusy;});
 Check(scan.calls==2,@"explicit course check remains available during background backoff");
 [c.automaticScanRetry invalidate];
 c.workflowAPIFactory=nil;
 c.preview=YES;[app.window orderOut:nil];[NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];printf("PASS: %lu history polling, recovery and activity assertions\n",(unsigned long)checks);
}return 0;}
