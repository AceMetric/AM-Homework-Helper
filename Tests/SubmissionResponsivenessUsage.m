#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
@interface SSGitHub (ScopedCancellationTest)
- (id)requestURL:(NSURL *)url form:(NSDictionary *)form token:(NSString *)token error:(NSError **)error;
@end
static NSUInteger checks;
static void Check(BOOL ok,NSString *reason){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",reason.UTF8String);exit(1);}}
static void Wait(BOOL (^ready)(void)){NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:3];while(!ready() && limit.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];Check(ready(),@"foreground submission responds while history work is blocked");}
@interface LocalChangeSpy:SSGit
@property NSUInteger reads;
@end
@implementation LocalChangeSpy
- (NSArray *)changesForCourse:(NSDictionary *)course error:(NSError **)error{self.reads++;return @[@{@"path":@"assignment-01/assignment.md",@"status":@"??",@"sensitive":@NO}];}
@end
@interface SlowHistorySpy:SSGit
@property dispatch_semaphore_t entered;
@property dispatch_semaphore_t finishGate;
@end
@implementation SlowHistorySpy
- (NSArray *)externalCommits:(NSDictionary *)course offset:(NSUInteger)offset error:(NSError **)error{dispatch_semaphore_signal(self.entered);dispatch_semaphore_wait(self.finishGate,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC));return @[];}
- (NSArray *)classifyExternalRecords:(NSArray *)records course:(NSDictionary *)course{return @[];}
@end
static NSUInteger OperationViews(NSView *root){NSUInteger count=[root isKindOfClass:AMOperationView.class] ? 1:0;for(NSView *child in root.subviews)count+=OperationViews(child);return count;}
static void Git(NSArray *arguments){NSTask *task=NSTask.new;task.executableURL=[NSURL fileURLWithPath:@"/usr/bin/git"];task.arguments=arguments;NSMutableDictionary *environment=NSProcessInfo.processInfo.environment.mutableCopy;environment[@"GIT_CONFIG_GLOBAL"]=@"/dev/null";environment[@"GIT_CONFIG_NOSYSTEM"]=@"1";task.environment=environment;task.standardOutput=NSFileHandle.fileHandleWithNullDevice;task.standardError=NSFileHandle.fileHandleWithNullDevice;Check([task launchAndReturnError:NULL],@"temporary repository command starts");[task waitUntilExit];Check(task.terminationStatus==0,@"temporary repository command succeeds");}
int main(){@autoreleasepool{
    Check(NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"]!=nil,@"isolated synthetic data");[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];AppDelegate *app=AppDelegate.new;NSApp.delegate=app;[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
    SSCourseController *controller=app.courseWindow;NSDictionary *course=@{@"fork":@"student/responsive",@"upstream":@"teacher/responsive",@"path":@"/synthetic/no-real-repository",@"branch":@"main",@"upstreamBranch":@"main"};[controller.courses addObject:course.mutableCopy];[controller selectCourseID:course[@"fork"]];controller.connected=NO;controller.preview=NO;LocalChangeSpy *reader=LocalChangeSpy.new;controller.git=reader;
    SlowHistorySpy *history=SlowHistorySpy.new;history.entered=dispatch_semaphore_create(0);history.finishGate=dispatch_semaphore_create(0);NSMutableArray *targets=NSMutableArray.array;
    controller.externalReaderFactory=^SSGit *(NSDictionary *target){@synchronized(targets){[targets addObject:target[@"fork"]];}return history;};
    [controller.courses addObject:[@{@"fork":@"student/other-course",@"upstream":@"teacher/other-course",@"path":@"/synthetic/other",@"branch":@"main",@"upstreamBranch":@"main"} mutableCopy]];
    [controller discoverExternalSubmissions:NO];Check(dispatch_semaphore_wait(history.entered,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC))==0,@"actual background discovery is held inside the test reader");NSProgress *background=controller.discoveryCancellation;
    NSDate *started=NSDate.date;[controller openSubmissionForCourse:course preserving:nil];Wait(^BOOL{return controller.submission!=nil && !controller.submission.filesPreparing;});Check(reader.reads==1 && -started.timeIntervalSinceNow<3,@"local file selection opens while actual history work is still blocked");Check(!background.cancelled && !history.operationCancelled,@"foreground read leaves independent background work running");Check(targets.count==1 && [targets[0] isEqual:course[@"fork"]],@"selected-course history does not scan unrelated courses");[controller.submission cancel:nil];controller.preview=YES;dispatch_semaphore_signal(history.finishGate);Wait(^BOOL{return !controller.discoveringExternal;});
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"am-local-status-" stringByAppendingString:NSUUID.UUID.UUIDString]];[NSFileManager.defaultManager createDirectoryAtPath:[root stringByAppendingPathComponent:@"answers"] withIntermediateDirectories:YES attributes:nil error:NULL];Git(@[@"init",@"--quiet",@"-b",@"main",root]);Git(@[@"-C",root,@"remote",@"add",@"origin",@"https://github.com/student/status-fixture.git"]);Git(@[@"-C",root,@"remote",@"add",@"upstream",@"https://github.com/teacher/status-fixture.git"]);
    for(NSUInteger i=0;i<500;i++)[@"Synthetic answer\n" writeToFile:[root stringByAppendingPathComponent:[NSString stringWithFormat:@"answers/assignment-%lu.md",(unsigned long)i]] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    SSGit *real=SSGit.new;started=NSDate.date;NSError *error=nil;NSArray *changes=[real changesForCourse:@{@"path":root,@"fork":@"student/status-fixture",@"upstream":@"teacher/status-fixture",@"branch":@"main",@"upstreamBranch":@"main"} error:&error];Check(changes.count==500 && !error,@"actual Git enumerates all 500 local files without remote verification");Check(-started.timeIntervalSinceNow<5 && real.commandTimeout==0,@"local change scan is bounded and restores the caller timeout");[NSFileManager.defaultManager removeItemAtPath:root error:NULL];
    NSProgress *scopeCancellation=[NSProgress progressWithTotalUnitCount:1];__block BOOL observedCancellation=NO;NSError *scopeError=nil;
    id response=AMPerformResourceOperation(@"cancel-auth-fixture",@"模拟授权",@"fixture",@[@"fixture-auth"],100,^BOOL{return scopeCancellation.cancelled;},^id(NSError **problem){[scopeCancellation cancel];id value=[SSGitHub.new requestURL:[NSURL URLWithString:@"https://example.invalid/no-request"] form:nil token:nil error:problem];observedCancellation=!value && [(*problem).localizedDescription containsString:@"终止"];return value;},&scopeError);
    Check(!response && observedCancellation && scopeError.code==NSUserCancelledError,@"background authorization observes scoped cancellation before any network request");
    NSProgress *taskCancellation=[NSProgress progressWithTotalUnitCount:1];NSString *parent=AMOperationBegin(@"核验记录",@"fixture",YES,^{[taskCancellation cancel];});dispatch_semaphore_t childStarted=dispatch_semaphore_create(0),finishChild=dispatch_semaphore_create(0);__block BOOL childFinished=NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{AMPerformResourceOperationInTask(parent,@"child-fixture",@"内部资源协调",@"fixture",@[@"fixture-lease"],0,^BOOL{return taskCancellation.cancelled;},^id(NSError **problem){dispatch_semaphore_signal(childStarted);dispatch_semaphore_wait(finishChild,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC));return @YES;},NULL);childFinished=YES;});
    Check(dispatch_semaphore_wait(childStarted,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC))==0,@"internal resource task starts");BOOL attached=NO;for(NSDictionary *row in AMOperations())if([row[@"parent"] isEqual:parent] && [row[@"resources"] containsObject:@"fixture-lease"])attached=YES;Check(attached,@"child remains tracked by scheduler and safe-exit rules");NSViewController *activity=[NSClassFromString(@"AMActivityController") new];(void)activity.view;NSUInteger activeViews=0;for(NSView *row in [[activity valueForKey:@"body"] arrangedSubviews])if([row isKindOfClass:AMOperationView.class] && [[(AMOperationView *)row operationID] isEqual:parent])activeViews++;Check(activeViews==1 && OperationViews(activity.view)>=1,@"one user operation has one activity indicator even while holding internal resources");AMOperationCancel(parent);Check(taskCancellation.cancelled,@"visible stop controls the parent operation");dispatch_semaphore_signal(finishChild);Wait(^BOOL{return childFinished;});AMOperationFinish(parent,@"cancelled",@"已停止");
    [app.ticker invalidate];[app.quickTimer invalidate];[app.window orderOut:nil];[NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];printf("PASS: %lu submission responsiveness and local Git assertions\n",(unsigned long)checks);
}return 0;}
