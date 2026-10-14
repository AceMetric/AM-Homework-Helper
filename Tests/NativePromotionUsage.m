#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
static void Drain(void){[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];}
static NSView *Find(NSView *view,Class kind){if([view isKindOfClass:kind])return view;for(NSView *child in view.subviews){NSView *match=Find(child,kind);if(match)return match;}return nil;}
int main(){@autoreleasepool{
    Check(NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"]!=nil,@"promotion test requires isolated data");[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];AppDelegate *app=AppDelegate.new;NSApp.delegate=app;[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
    NSSegmentedControl *mode=(id)[app.window.toolbar.items.firstObject view];mode.selectedSegment=0;[NSApp sendAction:mode.action to:mode.target from:mode];[app layout];[app.root layoutSubtreeIfNeeded];NSTableView *table=app.nativeTasks.table;
    Check(!app.nativeTasks.view.hidden && table.numberOfRows>0,@"today overview uses the same native task list");Check([table.delegate tableView:table isGroupRow:0],@"overview presents native group headers");Check(![table.delegate tableView:table shouldSelectRow:0],@"group headings do not select a nonexistent task");
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];NSString *selected=app.selectedTaskID;Check(selected.length && !app.taskDetails.hidden,@"overview native row opens task detail");[app render];Check([selected isEqual:app.selectedTaskID],@"overview refresh retains stable selection");
    [app openCalendar:nil];[app layout];[app.root layoutSubtreeIfNeeded];Check(NSHeight(app.calendarStatus.frame)>=app.calendarStatus.intrinsicContentSize.height,@"calendar segments use their system natural height");
    NSButton *route=NSButton.new;route.tag=3;[app navigate:route];Drain();[app.courseWindow.reviewWorkspace.view layoutSubtreeIfNeeded];Check(Find(app.courseWindow.reviewWorkspace.view,NSTableView.class)!=nil,@"review entries use a native list instead of painted selection buttons");
    NSStackView *form=NSStackView.new;form.orientation=NSUserInterfaceLayoutOrientationVertical;form.alignment=NSLayoutAttributeLeading;for(NSUInteger index=0;index<40;index++)[form addArrangedSubview:Text(@"Native long form row",13,NSFontWeightRegular,Ink())];NSScrollView *scroll=AMScrollableForm(form);scroll.frame=NSMakeRect(0,0,400,220);[scroll layoutSubtreeIfNeeded];Check(NSHeight(scroll.documentView.frame)>scroll.contentSize.height,@"long native forms scroll rather than clipping the footer");
    AMOnlineSettings *settings=AMOnlineSettings.new;[settings.window setContentSize:NSMakeSize(720,600)];[settings.window.contentView layoutSubtreeIfNeeded];NSView *footer=settings.window.contentView.subviews.lastObject;Check(NSContainsRect(settings.window.contentView.bounds,footer.frame),@"online settings footer stays inside minimum window");
    NSApp.appearance=nil;[app.ticker invalidate];[app.window orderOut:nil];[settings.window orderOut:nil];[NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];printf("PASS: %lu native promotion, groups, review and scrollable form assertions\n",(unsigned long)checks);
}return 0;}
