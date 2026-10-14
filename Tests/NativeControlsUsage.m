// Functional checks only. No screen capture or offscreen rendering is performed.
#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
#import "NativeControlGallery.inc"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
static void Drain(void){[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];}
static NSRect In(NSView *view,NSView *root){return [view convertRect:view.bounds toView:root];}
int main(){@autoreleasepool{
    Check(NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"]!=nil,@"isolated storage is required");
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];AppDelegate *app=AppDelegate.new;NSApp.delegate=app;[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
    Check(app.preview && NSApp.appearance==nil && app.window.appearance==nil,@"isolated preview follows system appearance");
    [app openList:nil];NSOutlineView *outline=app.navigationController.outline;NSTableView *table=app.nativeTasks.table;
    Check(outline.numberOfRows>=5 && table.numberOfRows>0,@"system sidebar and task table present synthetic content");
    Check(app.navigationItem.minimumThickness==192 && app.navigationItem.maximumThickness==280,@"native sidebar is adjustable within supported widths");
    for(NSValue *size in @[[NSValue valueWithSize:NSMakeSize(960,640)],[NSValue valueWithSize:NSMakeSize(1500,1000)],[NSValue valueWithSize:NSMakeSize(1280,840)]]){
        [app.window setContentSize:size.sizeValue];[app layout];[app.mainSplit.view layoutSubtreeIfNeeded];
        Check(NSContainsRect(app.mainSplit.view.bounds,In(app.sidebar,app.mainSplit.view)),@"sidebar remains inside native split at every size");
        if(!NSContainsRect(app.root.bounds,app.nativeTasks.view.frame))fprintf(stderr,"Task geometry: window=%s root=%s list=%s\n",NSStringFromSize(size.sizeValue).UTF8String,NSStringFromRect(app.root.bounds).UTF8String,NSStringFromRect(app.nativeTasks.view.frame).UTF8String);
        Check(NSContainsRect(app.root.bounds,app.nativeTasks.view.frame),@"native task list remains inside its content pane");
    }
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];Check(app.selectedTaskID.length && !app.taskDetails.hidden,@"table selection opens task detail by stable identity");
    NSString *selected=app.selectedTaskID;[app render];Check(app.nativeTasks.table==table && app.navigationController.outline==outline && [app.selectedTaskID isEqual:selected],@"refresh retains native controls and selection");
    NSEvent *escape=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:app.window.windowNumber context:nil characters:@"\033" charactersIgnoringModifiers:@"\033" isARepeat:NO keyCode:53];[table keyDown:escape];Check(app.taskDetails.hidden && !app.selectedTaskID,@"Escape closes task detail while keeping native list focus");
    app.search.stringValue=@"persistent search";[app.window makeFirstResponder:app.search];[app dismissSearchAtWindowPoint:NSMakePoint(20,20)];Check(app.search.currentEditor==nil && [app.search.stringValue isEqual:@"persistent search"],@"outside click releases search without clearing query");
    [app focusSearch:nil];Check(app.search.currentEditor!=nil,@"search command resumes native search editing");
    Check([app control:app.search textView:(NSTextView *)app.search.currentEditor doCommandBySelector:@selector(cancelOperation:)] && !app.search.currentEditor && [app.search.stringValue isEqual:@"persistent search"],@"Escape exits search and retains its contents");
    NSSearchField *search=app.search;[app render];Check(app.search==search,@"normal refresh retains the search control");app.search.stringValue=@"";
    NSToolbarItem *plus=nil;for(NSToolbarItem *item in app.window.toolbar.items){Check(![@[@"AMOperations",@"AMCheckWorkspace"] containsObject:item.itemIdentifier],@"idle toolbar has no ambiguous progress or checking icons");if([item.itemIdentifier isEqual:@"AMNewTask"])plus=item;}
    Check(plus.action==@selector(quickEntry:) && ![plus isKindOfClass:NSMenuToolbarItem.class],@"plus is a direct quick-entry action");[NSApp sendAction:plus.action to:plus.target from:plus];Check(app.quickController!=nil,@"plus opens quick entry directly");[app closeQuick];
    ThemeSegmentedControl *tabs=Segments(@[@"课程内容",@"已加入任务",@"仓库信息",@"提交记录"],nil,NULL);for(NSInteger index=0;index<4;index++){tabs.selectedSegment=index;Check(tabs.selectedSegment==index,@"all navigation segments can be selected");}if(@available(macOS 26.0,*))Check([[tabs valueForKey:@"borderShape"] integerValue]==1,@"capsule shape requested through public system API");
    [app.courseWindow selectCourseID:@""];app.courseWindow.inbox=NO;[app.courseWindow.view setFrameSize:NSMakeSize(692,520)];[app.courseWindow layoutContent];[app.courseWindow.view layoutSubtreeIfNeeded];Check(NSHeight(app.courseWindow.sections.frame)>=app.courseWindow.sections.intrinsicContentSize.height && NSContainsRect(app.courseWindow.view.bounds,In(app.courseWindow.sections,app.courseWindow.view)),@"course navigation uses intrinsic size without clipping");
    NSString *operation=AMOperationBegin(@"检查文件",@"模拟项目",NO,nil);AMOperationProgress(operation,@"检查文件与图片",12,37);Drain();[app.root layoutSubtreeIfNeeded];Check(!app.operationStrip.hidden && NSContainsRect(app.root.bounds,app.operationStrip.frame),@"active progress is visible inside content bounds");
    AMShowOperations(app.window);NSWindow *panel=nil;for(NSWindow *window in NSApp.windows)if([window.title isEqual:@"后台任务"])panel=window;Check(panel!=nil,@"Window menu progress action opens compact history");AMOperationFinish(operation,@"success",@"完成");Drain();Check(app.operationStrip.hidden,@"idle progress strip collapses");Check([[(NSScrollView *)[panel valueForKey:@"operationScroll"] documentView] subviews].count==1,@"completed operations are initially collapsed");
    AMNativeControlGallery *gallery=AMNativeControlGallery.new;[gallery.window.contentView layoutSubtreeIfNeeded];Check(gallery.window.contentMinSize.width==680,@"interactive native gallery is resizable");
    [app.ticker invalidate];[app.searchTimer invalidate];[app.window orderOut:nil];[panel orderOut:nil];[gallery.window orderOut:nil];[NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];
    printf("PASS: %lu native control, search, navigation and layout assertions; real glass appearance remains pending user screenshots\n",(unsigned long)checks);
}return 0;}
