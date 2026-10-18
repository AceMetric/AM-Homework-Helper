#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
@interface NSViewController (ActivityTest)
- (void)refresh;
- (void)hideOperation:(NSButton *)sender;
@end
static NSUInteger checks;
static void Check(BOOL ok,NSString *reason){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",reason.UTF8String);exit(1);}}
static NSToolbarItem *Item(AppDelegate *app,NSString *identifier){for(NSToolbarItem *item in app.window.toolbar.items)if([item.itemIdentifier isEqual:identifier])return item;return nil;}
static void Layout(NSView *view){[view layoutSubtreeIfNeeded];for(NSView *child in view.subviews)Layout(child);}
int main(){@autoreleasepool{
    Check(NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"]!=nil,@"isolated synthetic data");
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];AppDelegate *app=AppDelegate.new;NSApp.delegate=app;[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
    app.page=4;[app.courseWindow selectCourseID:nil];[app refreshPageToolbar];
    Check(!Item(app,@"AMCourseSync") && !Item(app,@"AMCourseSubmit"),@"all courses removes unavailable toolbar items instead of leaving empty capsules");
    [app.courseWindow.courses addObject:[@{@"fork":@"student/toolbar-fixture",@"upstream":@"teacher/fixture",@"path":@"/synthetic/no-git-operations"} mutableCopy]];
    Check([app.courseWindow selectCourseID:@"student/toolbar-fixture"],@"select synthetic course");
    for(NSInteger section=0;section<4;section++){
        app.courseWindow.sections.selectedSegment=section;[app.courseWindow layoutContent];[app refreshPageToolbar];
        for(NSString *identifier in @[@"AMCourseSync",@"AMCourseSubmit"]){NSToolbarItem *item=Item(app,identifier);NSButton *button=(id)item.view;Check(item && !button.hidden && button.title.length && NSWidth(button.frame)>30,@"selected course exposes named, visible actions in every section");}
        Check([Item(app,@"AMCourseScan").menuFormRepresentation.title isEqual:app.courseWindow.scanButton.title],@"overflow action name follows the selected course");
        Check((Item(app,@"AMCourseFilter")!=nil)==(section==0),@"filter item exists only in its content section");
    }
    [app.courseWindow selectCourseID:nil];[app refreshPageToolbar];Check(!Item(app,@"AMCourseSync") && !Item(app,@"AMCourseSubmit"),@"returning to all courses removes items again");Check([Item(app,@"AMCourseScan").menuFormRepresentation.title isEqual:@"检查所有课程"],@"overflow action resets to all courses");
    for(NSDictionary *row in AMUIMessages())AMDismissUIMessage(row[@"scope"],row[@"id"]);
    NSViewController *activity=[NSClassFromString(@"AMActivityController") new];NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,440,200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];window.contentViewController=activity;
    (void)activity.view;Layout(activity.view);Check(NSHeight(activity.view.frame)<150,@"empty activity fits its content");
    __block BOOL cancelled=NO;NSString *operation=AMOperationBegin(@"检查材料",@"模拟课程",YES,^{cancelled=YES;});AMOperationProgress(operation,@"读取作业与附件",12,37);[activity refresh];Layout(activity.view);
    NSStackView *body=[activity valueForKey:@"body"];NSStackView *row=(id)body.arrangedSubviews.firstObject;AMOperationView *progress=(id)row.arrangedSubviews.firstObject;
    for(NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua,NSAppearanceNameAccessibilityHighContrastAqua,NSAppearanceNameAccessibilityHighContrastDarkAqua]){
        activity.view.appearance=[NSAppearance appearanceNamed:appearance];Layout(activity.view);
        NSTextField *stage=[progress valueForKey:@"stage"];NSButton *cancel=[progress valueForKey:@"cancelButton"];NSProgressIndicator *bar=[progress valueForKey:@"bar"];
        Check(NSHeight(activity.view.frame)<200 && NSWidth(progress.frame)>340,@"single activity is compact without compressing its content");
        Check(stage.stringValue.length && NSWidth(stage.frame)>180 && NSContainsRect(progress.bounds,[stage alignmentRectForFrame:stage.frame]),@"stage text has a readable, contained frame");
        Check(!cancel.hidden && NSContainsRect(progress.bounds,cancel.frame) && !NSIntersectsRect(stage.frame,cancel.frame),@"terminate action fits without covering the stage");
        Check(NSWidth(bar.frame)>340 && NSContainsRect(progress.bounds,bar.frame),@"progress fills the row and stays within bounds");
    }
    NSButton *hide=(id)row.arrangedSubviews.lastObject;[hide performClick:nil];Check(!cancelled,@"hiding progress never terminates the operation");AMOperationFinish(operation,@"success",@"完成");
    NSString *cancellable=AMOperationBegin(@"再次检查",@"模拟课程",YES,^{cancelled=YES;});[activity refresh];Layout(activity.view);row=(id)body.arrangedSubviews.firstObject;progress=(id)row.arrangedSubviews.firstObject;
    NSButton *terminate=[progress valueForKey:@"cancelButton"];[terminate performClick:nil];Check(cancelled,@"terminate button still reaches the scheduler cancellation action");AMOperationFinish(cancellable,@"cancelled",@"已取消");
    NSPopover *popover=NSPopover.new;popover.contentViewController=activity;[activity setValue:popover forKey:@"popover"];Check(popover.contentSize.height<200,@"native popover receives the compact controller size");
    for(NSUInteger i=0;i<12;i++)AMPostUIMessage(@"layout",[NSString stringWithFormat:@"%lu",(unsigned long)i],@"这是一条需要显示完整内容的模拟错误消息，请重试当前操作。",AMUIMessageError,nil,nil);
    [activity refresh];Layout(activity.view);NSScrollView *scroll=[activity valueForKey:@"scroll"];
    Check(popover.contentSize.height<=400 && fabs(popover.contentSize.height-NSHeight(activity.view.frame))<1 && popover.contentSize.height>250,@"native popover grows with many messages within its limit");
    Check(NSHeight(activity.view.frame)<=400 && NSHeight(scroll.documentView.frame)>NSHeight(scroll.contentView.bounds),@"many messages scroll within a bounded popover");
    for(NSView *message in body.arrangedSubviews)Check(NSWidth(message.frame)>380 && NSHeight(message.frame)>=32,@"message rows retain readable dimensions");
    for(NSDictionary *message in AMUIMessages())AMDismissUIMessage(message[@"scope"],message[@"id"]);[activity refresh];Layout(activity.view);Check(popover.contentSize.height<150,@"native popover shrinks when activities are dismissed");
    Check(NSHeight(activity.view.frame)<150,@"dismissal shrinks the activity instead of leaving blank space");
    [app.ticker invalidate];[app.quickTimer invalidate];[app.window orderOut:nil];[window orderOut:nil];[NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];printf("PASS: %lu toolbar and activity geometry and interaction assertions\n",(unsigned long)checks);
}return 0;}
