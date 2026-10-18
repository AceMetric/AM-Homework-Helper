#ifndef AM_FOREGROUND_TEST
#import "QuietUI.h"
#endif
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
static NSUInteger checks;
static void Check(BOOL ok,NSString *text){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",text.UTF8String);exit(1);}}
static void Drain(void){NSDate *until=[NSDate dateWithTimeIntervalSinceNow:0.2];while(until.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];}
@interface PlanningApp:AppDelegate @end
@implementation PlanningApp
- (void)refreshReminders {}
- (BOOL)applyPlanning:(NSString *)action task:(NSString *)task subtask:(NSString *)sub value:(NSString *)value {BOOL result=[super applyPlanning:action task:task subtask:sub value:value];Drain();return result;}
- (BOOL)replaceTasks:(NSArray *)tasks action:(NSString *)action error:(NSError **)error {self.preview=NO;BOOL result=[super replaceTasks:tasks action:action error:error];self.preview=YES;return result;}
@end
static id Element(NSView *root,NSString *identity){if(NSIsEmptyRect(root.bounds)){root.frame=NSMakeRect(0,0,320,480);[root layoutSubtreeIfNeeded];}NSMutableArray *pending=[NSMutableArray arrayWithObject:root];NSHashTable *seen=[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];while(pending.count){id object=pending.lastObject;[pending removeLastObject];if([seen containsObject:object])continue;[seen addObject:object];if([object respondsToSelector:@selector(accessibilityIdentifier)] && [[object accessibilityIdentifier] isEqual:identity])return object;if([object respondsToSelector:@selector(accessibilityChildren)])[pending addObjectsFromArray:[object accessibilityChildren] ?: @[]];if([object isKindOfClass:NSView.class])[pending addObjectsFromArray:[object subviews]];}return nil;}
// Plan/subtask controls now live in the shared summary popover. Give the
// detached component the same available width before exercising its targets.
static void Capture(NSView *view,NSString *name){(void)name;if(NSIsEmptyRect(view.bounds))view.frame=NSMakeRect(0,0,320,480);[view layoutSubtreeIfNeeded];Check(!NSIsEmptyRect(view.bounds),@"synthetic layout verified without image capture");}
#ifdef AM_FOREGROUND_TEST
static void AnswerModal(NSString *buttonTitle,NSString *input){
    __block NSUInteger attempts=0;
    NSTimer *answerTimer=[NSTimer timerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer){
        if(++attempts>80){fprintf(stderr,"FAIL: isolated modal did not become usable\n");exit(1);}
        NSWindow *window=NSApp.modalWindow;if(!window)return;NSMutableArray *views=[NSMutableArray arrayWithObject:window.contentView];NSButton *button=nil;NSTextField *field=nil;
        while(views.count){NSView *view=views.lastObject;[views removeLastObject];[views addObjectsFromArray:view.subviews];if([view isKindOfClass:NSButton.class] && [[(NSButton *)view title] isEqual:buttonTitle])button=(NSButton *)view;if([view isKindOfClass:NSTextField.class] && [(NSTextField *)view isEditable])field=(NSTextField *)view;}
        if(!button || (input && !field))return;if(input)field.stringValue=input;[timer invalidate];[button performClick:nil];
    }];
    [NSRunLoop.mainRunLoop addTimer:answerTimer forMode:NSRunLoopCommonModes];
    [NSRunLoop.mainRunLoop addTimer:answerTimer forMode:NSModalPanelRunLoopMode];
}
#endif
int main(void){@autoreleasepool{
    Check(NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"].length>0,@"isolated planning data");[NSApplication sharedApplication];
#ifdef AM_FOREGROUND_TEST
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
#else
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
#endif
    PlanningApp *app=PlanningApp.new;NSApp.delegate=app;[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
    NSDate *now=NSDate.date;NSString *today=DDLPlanKey(now,Cal());NSDate *due=[Cal() dateByAddingUnit:NSCalendarUnitDay value:20 toDate:now options:0];
    NSDictionary *task=@{@"id":@"planning-task",@"title":@"模拟物理实验报告",@"subject":@"模拟课程",@"due":due,@"notes":@"作业内容\n整理实验结果并提交报告。",@"subtasks":@[],@"reminderOffsets":@[]};Check([app replaceTasks:DDLNormalizeTasks(@[task]) action:@"样例" error:NULL],@"fixture persisted");
    NSSegmentedControl *mode=[NSSegmentedControl segmentedControlWithLabels:@[@"今日",@"本周"] trackingMode:NSSegmentSwitchTrackingSelectOne target:app action:@selector(changeOverviewMode:)];mode.selectedSegment=1;[app changeOverviewMode:mode];Drain();Check(app.weeklyMode && app.scroll.hidden && !app.weeklyController.view.hidden,@"weekly switch displays embedded planner");
    Check([app applyPlanning:@"set-plan" task:@"planning-task" subtask:@"" value:today],@"plan parent through shared action");Check([app.tasks[0][@"due"] isEqual:due],@"planning never changes assignment deadline");Check([app applyPlanning:@"add" task:@"planning-task" subtask:@"" value:@"整理实验数据"],@"add a step");NSString *first=app.tasks[0][@"subtasks"][0][@"id"];
    Check([app applyPlanning:@"add" task:@"planning-task" subtask:@"" value:@"撰写报告"],@"add another step");NSString *second=app.tasks[0][@"subtasks"][1][@"id"];
    Check([app applyPlanning:@"up" task:@"planning-task" subtask:second value:@""],@"reorder step");Check([app.tasks[0][@"subtasks"][0][@"id"] isEqual:second],@"step order saved");[app undo:nil];Check([app.tasks[0][@"subtasks"][0][@"id"] isEqual:first],@"reorder undo restores stable IDs");
    Check([app applyPlanning:@"set-plan" task:@"planning-task" subtask:first value:today],@"plan child independently");Check([app applyPlanning:@"edit" task:@"planning-task" subtask:first value:@"核对实验数据"],@"rename child");Check([app applyPlanning:@"toggle" task:@"planning-task" subtask:first value:@""],@"complete child");Check(![app.tasks[0][@"completed"] boolValue],@"child completion does not complete parent");
    NSArray *before=app.snapshot;Check([app applyPlanning:@"delete" task:@"planning-task" subtask:second value:@""],@"delete child");[app undo:nil];Check([app.snapshot isEqual:before],@"child delete undo restores complete task");
    Check([SSLoadTasks(NULL) isEqual:app.snapshot],@"all UI changes reload exactly from disk");
    NSURL *store=[SSDataDirectory() URLByAppendingPathComponent:@"tasks.plist"];NSData *saved=[NSData dataWithContentsOfURL:store];[NSFileManager.defaultManager removeItemAtURL:store error:NULL];[NSFileManager.defaultManager createDirectoryAtURL:store withIntermediateDirectories:NO attributes:nil error:NULL];before=app.snapshot;Check(![app applyPlanning:@"edit" task:@"planning-task" subtask:first value:@"不应保存"],@"storage failure blocks step modification");Check([app.snapshot isEqual:before],@"failed save preserves prior task and steps");[NSFileManager.defaultManager removeItemAtURL:store error:NULL];[saved writeToURL:store atomically:YES];Check([app applyPlanning:@"edit" task:@"planning-task" subtask:first value:@"核对实验数据"],@"retry succeeds after storage restoration");
    [app planningAction:@"select" task:@"planning-task" subtask:first value:@""];Drain();Check(app.selectedTaskID.length && app.taskPlanningController,@"weekly item selects parent inspector");
    [app.taskDetailsScroll.contentView scrollToPoint:NSZeroPoint];Drain();Capture(app.taskPlanningController.view,@"build/qa/planning-controls-light.png");Check(Element(app.taskPlanningController.view,@"subtask-add")!=nil && Element(app.taskPlanningController.view,@"task-plan")!=nil,@"planning controls exposed to accessibility");
#ifdef AM_FOREGROUND_TEST
    id add=Element(app.taskPlanningController.view,@"subtask-add");Check([add isKindOfClass:NSButton.class],@"native add-step button present");NSUInteger count=[app.tasks[0][@"subtasks"] count];AnswerModal(@"保存",@"通过原生弹窗添加");[add performClick:nil];Drain();Check([app.tasks[0][@"subtasks"] count]==count+1,@"actual add button and native modal persist input");
    id plan=Element(app.taskPlanningController.view,@"task-plan");AnswerModal(@"保存计划",nil);[plan performClick:nil];Drain();Check([app.tasks[0][@"plannedDate"] isEqual:today],@"native date dialog saves selected plan");
    add=Element(app.taskPlanningController.view,@"subtask-add");count=[app.tasks[0][@"subtasks"] count];AnswerModal(@"取消",@"应取消的输入");[add performClick:nil];Check([app.tasks[0][@"subtasks"] count]==count,@"native cancellation leaves task unchanged");
#endif
    [app closeTaskDetails:nil];for(NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){app.window.appearance=[NSAppearance appearanceNamed:appearance];[app.window setContentSize:NSMakeSize(1280,840)];[app layout];Drain();Capture(app.root,[NSString stringWithFormat:@"build/qa/planning-%@.png",[appearance isEqual:NSAppearanceNameAqua] ? @"light":@"dark"]);Check(app.weeklyMode,@"appearance preserves weekly mode");}
    [app.window setContentSize:NSMakeSize(960,640)];[app layout];Drain();Capture(app.root,@"build/qa/planning-compact.png");Check(NSWidth(app.weeklyController.view.bounds)>=600 && NSContainsRect(app.root.bounds,app.weeklyController.view.frame),@"compact weekly layout remains usable");
    [app planningAction:@"next" task:@"" subtask:@"" value:@""];Check(app.weekOffset==1,@"next week navigation");[app planningAction:@"current" task:@"" subtask:@"" value:@""];Check(app.weekOffset==0,@"return to current week");
#ifndef AM_FOREGROUND_TEST
    NSButton *toggle=NSButton.new;toggle.identifier=@"planning-task";[AMQuietDialogChoices addObject:@(NSAlertFirstButtonReturn)];[app toggleTask:toggle];Check([app.tasks[0][@"completed"] boolValue] && [app.tasks[0][@"subtasks"][1][@"completed"] boolValue],@"confirmed parent completion completes remaining steps");[app undo:nil];Check(![app.tasks[0][@"completed"] boolValue] && ![app.tasks[0][@"subtasks"][1][@"completed"] boolValue],@"single undo restores parent and child completion");
#endif
    [app.ticker invalidate];[app.window orderOut:nil];[NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];printf("PASS: %lu planning UI and persistence assertions\n",(unsigned long)checks);
}return 0;}
