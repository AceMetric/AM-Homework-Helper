#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
static NSUInteger assertions;
static void Check(BOOL pass,NSString *label){assertions++;if(!pass){fprintf(stderr,"FAIL: %s\n",label.UTF8String);exit(1);}}
@interface FailedBatchApp:AppDelegate @end
@implementation FailedBatchApp
- (BOOL)replaceTasks:(NSArray *)tasks action:(NSString *)action error:(NSError **)error {if(error)*error=[NSError errorWithDomain:@"Fixture" code:1 userInfo:@{NSLocalizedDescriptionKey:@"模拟存储失败"}];return NO;}
@end
static void Capture(NSView *view,NSString *name){[view.window makeKeyAndOrderFront:nil];[view layoutSubtreeIfNeeded];[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];[view.window displayIfNeeded];NSBitmapImageRep *image=[view bitmapImageRepForCachingDisplayInRect:view.bounds];[view cacheDisplayInRect:view.bounds toBitmapImageRep:image];Check([[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[@"build/qa/" stringByAppendingString:name] atomically:YES],@"synthetic hybrid screenshot");}
int main(int argc,const char *argv[]){@autoreleasepool{
    if(![NSProcessInfo.processInfo.arguments containsObject:@"--preview"])return 2;[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];AppDelegate *app=AppDelegate.new;NSApp.delegate=app;[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
    SSCourseController *courses=app.courseWindow;[courses.courses addObject:[@{@"fork":@"student/physics",@"upstream":@"teacher/physics",@"enabled":@YES,@"path":@"/synthetic/course"} mutableCopy]];
    NSCalendar *calendar=Cal();NSArray *found=SSRecognizeDocument(@"# 运动分析与实验报告作业\n截止：2027 年 4 月 14 日（星期三）21:00 UTC+8\n## 任务\n分析时间步长对实验结果的影响。\n提交单个 Markdown 报告，附完整计算过程。",@"teacher/physics",@"assignment-06/README.md",@"v1",calendar,@{@"mode":@"rules"},NSMutableDictionary.dictionary,NULL);NSDictionary *record=found.firstObject;Check(record!=nil,@"synthetic source recognized");
    NSMutableDictionary *missing=record.mutableCopy;missing[@"id"]=@"missing-time";missing[@"title"]=@"阅读与学习笔记";missing[@"suggestedTitle"]=missing[@"title"];missing[@"needsTime"]=@YES;[missing removeObjectForKey:@"due"];missing[@"warnings"]=@[@"老师仅写明日期，请补全时间"];
    courses.candidates[@"student/physics"]=@[record,missing];[courses refreshCourses];NSButton *route=NSButton.new;route.tag=3;[app navigate:route];
    Check([courses.reviewWorkspace.view isKindOfClass:NSView.class] && !courses.reviewWorkspace.view.hidden && courses.table.enclosingScrollView.hidden,@"SwiftUI inbox is embedded and replaces visible legacy table");
    Check(app.window.titleVisibility==NSWindowTitleHidden,@"redundant window title hidden");
    for(NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){NSApp.appearance=[NSAppearance appearanceNamed:appearance];[app refreshAppearance];Capture(app.window.contentView,[NSString stringWithFormat:@"hybrid-review-%@.png",[appearance isEqual:NSAppearanceNameAqua] ? @"light" : @"dark"]);}
    [app.window setContentSize:NSMakeSize(960,640)];[app layout];Check(NSWidth(courses.reviewWorkspace.view.frame)>500 && NSHeight(courses.reviewWorkspace.view.frame)>200,@"minimum window keeps usable split review");Capture(app.window.contentView,@"hybrid-review-compact.png");
    NSUInteger before=app.tasks.count;NSString *result=[app saveReviewItems:@[@{@"record":record,@"draft":@{}},@{@"record":missing,@"draft":@{}}] automatic:NO];Check(result.length && app.tasks.count==before,@"invalid batch saves no partial tasks");
    result=[app saveReviewItems:@[@{@"record":record,@"draft":@{}}] automatic:YES];Check(!result.length && app.tasks.count==before+1 && courses.pendingCount==1,@"automatic eligible task updates calendar source and inbox");
    Check(![app saveReviewItems:@[@{@"record":record,@"draft":@{}}] automatic:YES].length || app.tasks.count==before+1,@"repeated automatic candidate cannot duplicate task");
    [app undoAutomaticImport:nil];Check(app.tasks.count==before,@"automatic import has exact-batch undo");
    Check(!SSCanAutomaticallyImport([courses discoveriesForFork:@"student/physics"].firstObject,@[],NSDate.date),@"automatic undo keeps unchanged source for manual review on next scan");
    [app saveReviewItems:@[@{@"record":record,@"draft":@{}}] automatic:YES];Check(app.tasks.count==before,@"old callback cannot bypass deferred live source state");
    NSMutableDictionary *stale=record.mutableCopy;stale[@"blobSHA"]=@"changed";Check([app saveReviewItems:@[@{@"record":stale,@"draft":@{}}] automatic:NO].length && app.tasks.count==before,@"stale source draft cannot save");
    FailedBatchApp *failed=FailedBatchApp.new;failed.preview=YES;failed.tasks=app.tasks.mutableCopy;failed.courseWindow=courses;Check([failed saveReviewItems:@[@{@"record":record,@"draft":@{}}] automatic:NO].length && failed.tasks.count==before,@"disk failure retains entire previous batch");
    [app showSettings:nil];Check(app.settingsController && app.settingsWindow.sheetParent==app.window,@"SwiftUI settings uses main window sheet");Capture(app.settingsWindow.contentView,@"hybrid-settings-dark.png");NSApp.appearance=[NSAppearance appearanceNamed:NSAppearanceNameAqua];[app refreshAppearance];Capture(app.settingsWindow.contentView,@"hybrid-settings-light.png");Check([app resolveEditsForExit:NO] && !app.settingsController,@"clean settings participate in exit coordination");
    [app.window orderOut:nil];[app.ticker invalidate];[NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];printf("PASS: %lu hybrid UI assertions\n",(unsigned long)assertions);
}return 0;}
