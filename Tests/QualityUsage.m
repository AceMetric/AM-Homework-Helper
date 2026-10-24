#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
static NSUInteger checks;
static void Check(BOOL ok,NSString *text){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",text.UTF8String);exit(1);}}
@interface QualityApp:AppDelegate
@property NSUInteger contentRenders;
@end
@implementation QualityApp
- (void)loadPreview {
    for(NSUInteger i=0;i<2000;i++)[self.tasks addObject:[@{@"id":[NSString stringWithFormat:@"task-%lu",(unsigned long)i],@"title":@"模拟任务与长标题",@"due":[NSDate dateWithTimeIntervalSinceNow:3600+i*20],@"subject":@"模拟课程",@"notes":[@"长备注\n" stringByPaddingToLength:4000 withString:@"备注文本\n" startingAtIndex:0],@"completed":@NO,@"archived":@NO,@"reminderOffsets":@[]} mutableCopy]];
}
- (void)renderContent {self.contentRenders++;[super renderContent];}
- (void)refreshReminders {}
@end
int main(void){@autoreleasepool{
    Check(NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"].length>0,@"quality UI isolated storage");
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];NSDate *start=NSDate.date;QualityApp *app=QualityApp.new;[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];NSTimeInterval startup=-start.timeIntervalSinceNow;
    Check(app.tasks.count==2000,@"two thousand task startup fixture");Check(startup<2,@"offline usable startup below two seconds");Check(app.nativeTasks.table.numberOfRows>=2000 && app.nativeTasks.table.subviews.count<80,@"native overview keeps row views bounded for two thousand tasks");
    NSMutableArray *courses=NSMutableArray.array;for(NSUInteger i=0;i<20;i++)[courses addObject:@{@"fork":[NSString stringWithFormat:@"student/course-%lu",(unsigned long)i],@"upstream":[NSString stringWithFormat:@"teacher/course-%lu",(unsigned long)i]}];app.courseWindow.courses=courses;
    NSButton *route=NSButton.new;route.tag=2;[app navigate:route];start=NSDate.date;[app renderContent];NSTimeInterval render=-start.timeIntervalSinceNow;Check(render<0.1,@"task page render below one hundred milliseconds");Check(app.nativeTasks.table.numberOfRows==2000 && app.nativeTasks.table.subviews.count<80,@"native task list row creation bounded");
    [app.nativeTasks.view layoutSubtreeIfNeeded];[app.nativeTasks.scroll.contentView scrollToPoint:NSMakePoint(0,40000)];[app.nativeTasks.scroll reflectScrolledClipView:app.nativeTasks.scroll.contentView];[app.nativeTasks.table layoutSubtreeIfNeeded];NSRange visible=[app.nativeTasks.table rowsInRect:app.nativeTasks.scroll.contentView.bounds];Check(visible.location>100 && visible.length>0 && visible.length<40 && app.nativeTasks.table.numberOfRows==2000,@"native table tracks the scrolled viewport and retains all task identities");
    start=NSDate.date;app.query=@"模拟";[app renderContent];NSTimeInterval search=-start.timeIntervalSinceNow;Check(search<0.1,@"two thousand task search below one hundred milliseconds");
    // First hosting-view creation includes one-time AppKit/SwiftUI setup. Measure
    // it separately from common selection; never benchmark the cached same row.
    NSButton *selection=NSButton.new;selection.identifier=app.tasks[450][@"id"];start=NSDate.date;[app selectTask:selection];NSTimeInterval coldSelect=-start.timeIntervalSinceNow;
    NSUInteger beforeSelections=app.contentRenders;NSMutableArray<NSNumber *> *samples=NSMutableArray.array;
    for(NSUInteger i=1;i<=7;i++){selection.identifier=app.tasks[450+i][@"id"];start=NSDate.date;[app selectTask:selection];[samples addObject:@(-start.timeIntervalSinceNow)];Check([app.selectedTaskID isEqual:selection.identifier],@"consecutive selections preserve stable identity");}
    Check(app.contentRenders==beforeSelections,@"switching existing rows does not rebuild unrelated task presentation");
    NSArray<NSNumber *> *ordered=[samples sortedArrayUsingSelector:@selector(compare:)];NSTimeInterval select=ordered[ordered.count/2].doubleValue;
    printf("TIMING: first detail %.4fs; seven distinct selections median %.4fs, maximum %.4fs\n",coldSelect,select,ordered.lastObject.doubleValue);
    Check(coldSelect<2 && ordered.lastObject.doubleValue<2,@"initial and subsequent detail operations do not stall for two seconds");Check(select<0.1,@"typical long-note selection below one hundred milliseconds");Check([app.selectedTaskID isEqual:selection.identifier],@"stable selected identity");
    for(NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){app.window.appearance=[NSAppearance appearanceNamed:appearance];[app.window setContentSize:NSMakeSize(960,640)];[app layout];Check(app.selectedTaskID.length>0,@"appearance and compact layout preserve selection");}
    [app.window makeFirstResponder:app.search];[app render];Check(app.window.firstResponder!=nil,@"background presentation retains input responder");
    app.taskStoreBlocked=YES;app.preview=NO;NSError *error=nil;Check(![app replaceTasks:@[] action:@"不应覆盖" error:&error] && error,@"corrupt-store state blocks replacement");app.preview=YES;app.taskStoreBlocked=NO;
    SSCourseController *controller=app.courseWindow;[controller showSkillJobs:nil];Check(controller.showingSkillJobs && !controller.skillJobsController.view.hidden,@"Skill status opens embedded page");[controller skillJobAction:@"close" batch:@""];Check(!controller.showingSkillJobs,@"Skill page closes without new window");
    controller.preview=NO;NSString *done=NSUUID.UUID.UUIDString,*pending=NSUUID.UUID.UUIDString;controller.skillJobs[done]=@{@"state":@"已接回",@"date":[NSDate dateWithTimeIntervalSinceNow:-31*86400],@"count":@1};controller.skillJobs[pending]=@{@"state":@"等待助手",@"date":[NSDate dateWithTimeIntervalSinceNow:-31*86400],@"count":@1};controller.skillProgress[@"retained"]=@"version";
    for(NSString *key in @[done,pending])[NSFileManager.defaultManager createDirectoryAtURL:[controller skillFolder:key] withIntermediateDirectories:YES attributes:nil error:NULL];[controller cleanSkillJobs:NO];Check(![NSFileManager.defaultManager fileExistsAtPath:[controller skillFolder:done].path] && [NSFileManager.defaultManager fileExistsAtPath:[controller skillFolder:pending].path],@"cleanup removes only old completed materials");Check([controller.skillProgress[@"retained"] isEqual:@"version"],@"cleanup retains incremental progress");
    __block BOOL finished=NO,cancelledCorrectly=NO;
    [controller work:@"准备中 · 取消测试" forCourse:nil operation:^id(NSError **inner){controller.git.cancelledReads=YES;return @{@"unused":@YES};} completion:^(id value,NSError *inner){cancelledCorrectly=!value && inner.code==NSUserCancelledError;finished=YES;}];
    NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:5];while(!finished && limit.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];Check(finished && cancelledCorrectly,@"cancelled safe read never applies a successful completion payload");
    [app.ticker invalidate];[app.window orderOut:nil];[NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];
    printf("TIMING: offline startup %.4fs; render %.4fs; search %.4fs; selection %.4fs; 2000 tasks, 20 courses\n",startup,render,search,select);
    printf("PASS: %lu quality UI and performance assertions\n",(unsigned long)checks);
}return 0;}
