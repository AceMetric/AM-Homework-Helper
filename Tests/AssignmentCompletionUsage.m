#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
static NSUInteger checks;
static void Check(BOOL value,NSString *label){checks++;if(!value){fprintf(stderr,"FAIL: %s\n",label.UTF8String);exit(1);}}
static void Drain(void){[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.2]];}
static id Find(id root,NSString *label){NSMutableArray *pending=[NSMutableArray arrayWithObject:root];NSHashTable *seen=[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];while(pending.count){id e=pending.lastObject;[pending removeLastObject];if([seen containsObject:e])continue;[seen addObject:e];if(([e respondsToSelector:@selector(accessibilityLabel)] && [[e accessibilityLabel] isEqual:label]) || ([e respondsToSelector:@selector(accessibilityTitle)] && [[e accessibilityTitle] isEqual:label]))return e;if([e respondsToSelector:@selector(accessibilityChildren)])[pending addObjectsFromArray:[e accessibilityChildren] ?: @[]];if([e isKindOfClass:NSView.class])[pending addObjectsFromArray:[e subviews]];}return nil;}
static void Tab(AMCourseController *controller,NSString *name){
    id element=Find(controller.view,name);Check(element!=nil,@"board state tab exists");
    // Hidden test windows cannot use AXPress. Drive the actual native control's
    // target/action; no task or board model method is invoked by this helper.
    NSMutableArray *pending=[NSMutableArray arrayWithObject:controller.view];NSSegmentedControl *control=nil;
    while(pending.count){NSView *view=pending.lastObject;[pending removeLastObject];if([view isKindOfClass:NSSegmentedControl.class] && [(NSSegmentedControl *)view segmentCount]==2){control=(id)view;break;}[pending addObjectsFromArray:view.subviews];}
    Check(control!=nil,@"native board state picker exists");control.selectedSegment=[name isEqual:@"历史"] ? 1:0;Check([NSApp sendAction:control.action to:control.target from:control],@"native board picker dispatches its action");Drain();
}
static void ToggleFromTaskList(AppDelegate *app){[app openList:nil];[app.taskFilter selectItemAtIndex:[app.tasks[0][@"completed"] boolValue] ? 3:0];[NSApp sendAction:app.taskFilter.action to:app.taskFilter.target from:app.taskFilter];[app.nativeTasks.view layoutSubtreeIfNeeded];NSTableView *table=app.nativeTasks.table;Check(table.numberOfRows==1,@"one synthetic task is displayed");NSButton *completion=(id)[table.delegate tableView:table viewForTableColumn:table.tableColumns[0] row:0];Check([completion isKindOfClass:NSButton.class],@"real completion checkbox exists");[completion performClick:nil];Drain();}
int main(){@autoreleasepool{
    Check(NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"]!=nil,@"isolated data required");[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];AppDelegate *app=AppDelegate.new;NSApp.delegate=app;[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];[app.ticker invalidate];
    NSMutableDictionary *course=[@{@"fork":@"student/state",@"upstream":@"teacher/state",@"branch":@"main",@"upstreamBranch":@"main",@"path":@"/synthetic/state",@"enabled":@YES} mutableCopy];[app.courseWindow.courses addObject:course];
    NSDictionary *task=@{@"id":@"completion-fixture",@"title":@"同步验收作业",@"subject":@"state",@"sourceRepository":@"teacher/state",@"sourcePath":@"assignment-1/README.md",@"due":[NSDate dateWithTimeIntervalSinceNow:3600],@"completed":@NO};Check([app replaceTasks:@[task] action:@"Seed synthetic data" error:NULL],@"synthetic task fixture installed");
    [app openCourses:nil];[app.courseWindow refreshPresentation];Drain();AMCourseController *board=app.courseWindow.courseWorkspace;
    Check(Find(board.view,@"打开作业：同步验收作业")!=nil,@"incomplete assignment appears in active board");
    ToggleFromTaskList(app);Check([app.tasks[0][@"completed"] boolValue],@"task checkbox records completion");[app openCourses:nil];[app.courseWindow refreshPresentation];Drain();
    Check(!Find(board.view,@"打开作业：同步验收作业"),@"completed assignment immediately leaves active board without push verification");Tab(board,@"历史");Check(Find(board.view,@"打开作业：同步验收作业")!=nil,@"completed Git assignment appears in history without a fabricated pushed status");
    app.courseWindow.assignmentProgress=[NSMutableDictionary dictionaryWithObject:@{@"working":[NSSet setWithObject:@"assignment-1"],@"pending":NSSet.set,@"pendingKnown":@YES,@"failed":@NO,@"date":NSDate.date} forKey:@[@"student/state",@"main",@"/synthetic/state"]];[app.courseWindow refreshPresentation];Drain();
    Check([app.tasks[0][@"completed"] boolValue] && Find(board.view,@"打开作业：同步验收作业")!=nil,@"later local changes preserve manual completion and history membership");
    ToggleFromTaskList(app);Check(![app.tasks[0][@"completed"] boolValue],@"same checkbox can undo completion");[app openCourses:nil];[app.courseWindow refreshPresentation];Drain();Check(!Find(board.view,@"打开作业：同步验收作业"),@"undo removes assignment from history");Tab(board,@"进行中");Check(Find(board.view,@"打开作业：同步验收作业")!=nil,@"undo restores the same assignment to active board");
    [app.quickTimer invalidate];[NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];printf("PASS: %lu task-to-board completion synchronization assertions\n",(unsigned long)checks);
}}
