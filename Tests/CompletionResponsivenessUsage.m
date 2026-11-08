#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
static NSUInteger checks;
static void Check(BOOL ok,NSString *why){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",why.UTF8String);exit(1);}}
static void Pump(NSTimeInterval seconds){NSDate *end=[NSDate dateWithTimeIntervalSinceNow:seconds];while(end.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];}
int main(){@autoreleasepool{
    Check(NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"].length>0,@"isolated storage");
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    AppDelegate *app=AppDelegate.new;[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];[app.ticker invalidate];
    NSMutableArray *tasks=NSMutableArray.array,*records=NSMutableArray.array,*courses=NSMutableArray.array;
    NSDate *now=NSDate.date;
    for(NSUInteger c=0;c<5;c++)[courses addObject:@{@"fork":[NSString stringWithFormat:@"student/course%lu",(unsigned long)c],@"upstream":[NSString stringWithFormat:@"teacher/course%lu",(unsigned long)c],@"branch":@"main"}];
    for(NSUInteger i=0;i<82;i++){NSDictionary *course=courses[i%5];[tasks addObject:@{@"id":[NSString stringWithFormat:@"task-%lu",(unsigned long)i],@"title":@"Synthetic assignment",@"due":[now dateByAddingTimeInterval:86400],@"courseID":AMRepositoryCourseID(course[@"fork"]),@"sourcePath":@"assignment-1/README.md",@"completed":@NO}];}
    for(NSUInteger i=0;i<107;i++){NSDictionary *course=courses[i%5];[records addObject:@{@"id":NSUUID.UUID.UUIDString,@"repository":course[@"fork"],@"branch":@"main",@"commit":[@"a" stringByPaddingToLength:40 withString:@"a" startingAtIndex:0],@"remoteCommit":[@"a" stringByPaddingToLength:40 withString:@"a" startingAtIndex:0],@"kind":@"submission",@"origin":@"app",@"state":@"confirmed",@"message":@"Synthetic",@"date":now,@"checkedAt":now,@"files":@[@"assignment-1/answer.md"],@"completionFiles":@[@"assignment-1/answer.md"],@"taskIDs":@[],@"completionEligibility":@"new"}];}
    Check(SSWritePlist(@"submission-records.plist",records,NULL),@"synthetic submission history");
    app.tasks=[DDLNormalizeTasks(tasks) mutableCopy];app.courseWindow.courses=courses.mutableCopy;app.courseWindow.preview=NO;app.preview=NO;__weak AppDelegate *owner=app;app.courseWindow.verifiedSubmissionsChanged=^{[owner applyVerifiedSubmissions];};
    // Hold the store snapshot lock on a worker until the UI processes an event.
    // The main event loop must stay usable even while persistence is contended.
    dispatch_semaphore_t held=dispatch_semaphore_create(0),release=dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        @synchronized(NSFileManager.defaultManager){
            dispatch_semaphore_signal(held);
            dispatch_semaphore_wait(release,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC));
        }
    });
    Check(dispatch_semaphore_wait(held,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC))==0,@"synthetic storage contention established");
    CFAbsoluteTime start=CFAbsoluteTimeGetCurrent();app.courseWindow.verifiedSubmissionsChanged();
    Check(CFAbsoluteTimeGetCurrent()-start<.1,@"verification callback returns within 100ms before calculation completes");
    for(NSUInteger i=0;i<30;i++)app.courseWindow.verifiedSubmissionsChanged();
    __block BOOL heartbeat=NO;
    CFRunLoopPerformBlock(CFRunLoopGetMain(),kCFRunLoopDefaultMode,^{heartbeat=app.applyingSubmissionCompletions;});
    NSDate *eventDeadline=[NSDate dateWithTimeIntervalSinceNow:2];
    while(!heartbeat && eventDeadline.timeIntervalSinceNow>0)Pump(.01);
    dispatch_semaphore_signal(release);
    Check(heartbeat,@"main event loop processes an event while completion is waiting for storage");
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];while(app.applyingSubmissionCompletions && deadline.timeIntervalSinceNow>0)Pump(.01);
    Check(!app.applyingSubmissionCompletions && !app.submissionCompletionsPending,@"coalesced calculation settles without an unbounded callback loop");
    Check(app.tasks.count==82,@"background calculation preserves the task inventory");
    printf("PASS: %lu completion responsiveness assertions\n",(unsigned long)checks);
    app.preview=YES;app.courseWindow.preview=YES;
}return 0;}
