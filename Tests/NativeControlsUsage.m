// Functional checks only. No screen capture or offscreen rendering is performed.
#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
#import "NativeControlGallery.inc"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
static void Await(BOOL (^ready)(void)){NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:3];while(!ready() && limit.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];Check(ready(),@"queued operation state reaches the interface");}
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
    Check(table.allowsMultipleSelection && table.tableColumns[0].width>=44,@"native completion column offers a larger target and standard multi-selection");
    NSButton *completion=(id)[table.delegate tableView:table viewForTableColumn:table.tableColumns[0] row:0];NSButton *options=(id)[table.delegate tableView:table viewForTableColumn:table.tableColumns[3] row:0];
    Check(options.imageScaling==NSImageScaleNone && options.controlSize==NSControlSizeRegular,@"options icon keeps its natural symbol size inside the enlarged click target");
    Check(completion.controlSize==NSControlSizeLarge && NSWidth(completion.frame)>=44 && NSHeight(completion.frame)>=44 && NSHeight(options.frame)>=44,@"completion and options have generous native control bounds");
    AMNativeTaskList *multi=AMNativeTaskList.new;NSMutableArray *toggles=NSMutableArray.array;multi.actionHandler=^(NSString *action,NSString *identifier){if([action isEqual:@"toggle"])[toggles addObject:identifier];};NSArray *rows=@[@{@"id":@"one",@"title":@"One"},@{@"id":@"two",@"title":@"Two"}];[multi updateTasks:rows selected:@"" heading:@""];[multi.table selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,2)] byExtendingSelection:NO];[multi updateTasks:rows selected:@"one" heading:@""];Check(multi.table.selectedRowIndexes.count==2,@"refresh preserves multiple task selections by identity");
    NSEvent *space=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@" " charactersIgnoringModifiers:@" " isARepeat:NO keyCode:49];[multi.table keyDown:space];Check([toggles isEqual:@[@"one",@"two"]],@"Space toggles each selected task exactly once");
    NSString *selected=app.selectedTaskID;[app render];Check(app.nativeTasks.table==table && app.navigationController.outline==outline && [app.selectedTaskID isEqual:selected],@"refresh retains native controls and selection");
    NSEvent *escape=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:app.window.windowNumber context:nil characters:@"\033" charactersIgnoringModifiers:@"\033" isARepeat:NO keyCode:53];[table keyDown:escape];Check(app.taskDetails.hidden && !app.selectedTaskID,@"Escape closes task detail while keeping native list focus");
    app.search.stringValue=@"persistent search";[app.window makeFirstResponder:app.search];[app dismissSearchAtWindowPoint:NSMakePoint(20,20)];Check(app.search.currentEditor==nil && [app.search.stringValue isEqual:@"persistent search"],@"outside click releases search without clearing query");
    [app focusSearch:nil];Check(app.search.currentEditor!=nil,@"search command resumes native search editing");
    Check([app control:app.search textView:(NSTextView *)app.search.currentEditor doCommandBySelector:@selector(cancelOperation:)] && !app.search.currentEditor && [app.search.stringValue isEqual:@"persistent search"],@"Escape exits search and retains its contents");
    NSSearchField *search=app.search;[app render];Check(app.search==search,@"normal refresh retains the search control");app.search.stringValue=@"";
    NSToolbarItem *plus=nil;for(NSToolbarItem *item in app.window.toolbar.items){Check(![@[@"AMOperations",@"AMCheckWorkspace"] containsObject:item.itemIdentifier],@"idle toolbar has no ambiguous progress or checking icons");if([item.itemIdentifier isEqual:@"AMNewTask"])plus=item;}
    Check(plus.action==@selector(addTask:) && ![plus isKindOfClass:NSMenuToolbarItem.class],@"plus is the shared manual new-task action");[NSApp sendAction:plus.action to:plus.target from:plus];Check(app.editor!=nil && app.quickController==nil,@"plus opens manual form directly");[app closeEditor];
    ThemeSegmentedControl *tabs=Segments(@[@"课程内容",@"已加入任务",@"仓库信息",@"提交记录"],nil,NULL);for(NSInteger index=0;index<4;index++){tabs.selectedSegment=index;Check(tabs.selectedSegment==index,@"all navigation segments can be selected");}if(@available(macOS 26.0,*))Check([[tabs valueForKey:@"borderShape"] integerValue]==1,@"capsule shape requested through public system API");
    app.page=1;[app refreshPageToolbar];NSToolbarItem *calendarItem=nil;for(NSToolbarItem *item in app.window.toolbar.items)if([item.itemIdentifier isEqual:@"AMCalendarStatus"])calendarItem=item;
    Check(calendarItem.view==app.calendarStatus && app.calendarStatus.superview!=app.root,@"calendar filter belongs to native toolbar, not stretched body controls");
    for(NSInteger index=0;index<3;index++){NSMenuItem *choice=calendarItem.menuFormRepresentation.submenu.itemArray[index];[NSApp sendAction:choice.action to:choice.target from:choice];Check(app.calendarStatus.selectedSegment==index,@"overflow menu retains every calendar filter");}app.calendarStatus.selectedSegment=0;
    app.page=4;[app refreshPageToolbar];NSToolbarItem *courseItem=nil;for(NSToolbarItem *item in app.window.toolbar.items)if([item.itemIdentifier isEqual:@"AMCourseSections"])courseItem=item;
    Check(courseItem.view==app.courseWindow.sections && app.courseWindow.sections.superview!=app.courseWindow.view,@"course navigation is owned by the page toolbar");
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 270000
    if(@available(macOS 27.0,*)){ThemeSegmentedControl *values=FilterSegments(@[@"低",@"高"],nil,NULL);Check(tabs.role==NSSegmentedControlRoleTabs && app.calendarStatus.role==NSSegmentedControlRoleTabs && values.role==NSSegmentedControlRoleValueSelection,@"calendar content and page navigation use Tabs while form values use ValueSelection");}
#endif
    [app openCalendar:nil];NSSegmentedControl *calendar=app.calendarStatus;NSStackView *header=app.calendarHeader;
    Check(calendar.controlSize==NSControlSizeRegular && calendar.segmentDistribution==NSSegmentDistributionFit,@"toolbar calendar uses standard sizing and natural segment widths");
    for(NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua,NSAppearanceNameAccessibilityHighContrastAqua,NSAppearanceNameAccessibilityHighContrastDarkAqua])for(NSValue *size in @[[NSValue valueWithSize:NSMakeSize(960,640)],[NSValue valueWithSize:NSMakeSize(1180,790)],[NSValue valueWithSize:NSMakeSize(1500,1000)]]){
        app.window.appearance=[NSAppearance appearanceNamed:appearance];[app.window setContentSize:size.sizeValue];[app layout];
        for(NSInteger index=0;index<3;index++){calendar.selectedSegment=index;[app changeCalendarStatus:calendar];[app layout];
            NSRect safe=app.root.safeAreaRect;
            Check(NSMinY(app.header.frame)>=NSMinY(safe)+15,@"calendar title stays below toolbar safe area");
            Check(NSHeight(app.header.frame)>=header.fittingSize.height && NSMinY(app.calendarScroll.frame)>=NSMaxY(app.header.frame)+15,@"grid follows actual header height without clipping or overlap");
            Check(NSContainsRect(app.root.bounds,app.calendarScroll.frame) && NSContainsRect(app.root.bounds,app.agenda.frame),@"calendar and agenda fit at minimum and intermediate widths");
            Check(app.calendarStatus==calendar && app.calendarHeader==header && calendar.selectedSegment==index,@"appearance, layout and filtering retain native controls and selected value");
        }
    }
    app.window.appearance=nil;calendar.selectedSegment=0;[app changeCalendarStatus:calendar];[app.window setContentSize:NSMakeSize(1280,840)];[app layout];
    app.page=4;[app refreshPageToolbar];
    NSSegmentedControl *sameSections=app.courseWindow.sections;[app refreshPageToolbar];Check(sameSections==app.courseWindow.navigationControl,@"refresh reuses navigation and current selection");
    [app.courseWindow selectCourseID:@""];app.courseWindow.inbox=NO;[app.courseWindow.view setFrameSize:NSMakeSize(692,520)];[app.courseWindow layoutContent];

    SSCourseController *course=app.courseWindow;course.busy=YES;course.git.readsCancellable=YES;course.cancelReadButton.enabled=YES;
    course.statusLabel.stringValue=@"example/physics：本地模型正在分析课程材料和附件，保留完整路径与当前阶段以便查看进度";
    for(NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua])for(NSNumber *width in @[@692,@1120])for(NSNumber *recovery in @[@NO,@YES]){
        course.view.appearance=[NSAppearance appearanceNamed:appearance];course.recoveryButton.hidden=!recovery.boolValue;course.recoveryButton.title=@"处理冲突…";
        [course.view setFrameSize:NSMakeSize(width.doubleValue,520)];[course layoutContent];[course.view layoutSubtreeIfNeeded];
        Check(course.operationStatus.hidden && NSMinY(course.courseWorkspace.view.frame)==NSMaxY(course.nativeHeader.frame)+8,@"running, recovery and completed feedback never push course content down");
        Check(course.cancelReadButton.enabled && course.cancelReadButton.action==@selector(cancelReadOperation:),@"activity cancellation retains the same operation target");
    }
    [course cancelReadOperation:nil];Check(course.git.cancelledReads && !course.cancelReadButton.enabled && [course.statusLabel.stringValue containsString:@"正在停止"],@"cancel remains connected to the active read after layout changes");
    course.busy=NO;course.git.readsCancellable=NO;course.git.cancelledReads=NO;course.git.operationCancelled=NO;course.github.requestsCancelled=NO;[course refreshPresentation];
    Check(course.cancelReadButton.hidden && course.progress.hidden,@"finished course check removes the cancel action and progress bar");
    course.statusLabel.stringValue=@"";course.recoveryButton.hidden=YES;[course layoutContent];
    Check(course.operationStatus.hidden && NSMinY(course.courseWorkspace.view.frame)==NSMaxY(course.nativeHeader.frame)+8,@"idle course has no empty progress area");course.view.appearance=nil;
    // A real scheduler path with synthetic work only; no repository or network access.
    [course.courses addObject:[@{@"fork":@"student/scheduled-fixture",@"upstream":@"teacher/fixture",@"path":@"/synthetic/no-git-operations"} mutableCopy]];course.preview=NO;__block BOOL firstStarted=NO,firstFinished=NO,secondFinished=NO;__block NSUInteger invocations=0;
    dispatch_semaphore_t release=dispatch_semaphore_create(0);
    [course work:@"读取模拟排队材料" forCourse:course.courses.lastObject operation:^id(NSError **error){firstStarted=YES;dispatch_semaphore_wait(release,DISPATCH_TIME_FOREVER);return @YES;} completion:^(id value,NSError *error){firstFinished=YES;}];Await(^BOOL{return firstStarted && course.busy;});
    [course refreshPresentation];Check(course.scanButton.enabled && course.moreButton.enabled && !course.courseWorkspace.paused,@"model or read activity does not disable navigation, review, and new requests");
    for(NSUInteger i=0;i<2;i++)[course work:@"读取第二份模拟材料" forCourse:course.courses.lastObject operation:^id(NSError **error){invocations++;return @YES;} completion:^(id value,NSError *error){secondFinished=YES;}];
    Check(AMQueuedOperationCount()==1,@"duplicate course clicks merge into one pending operation");dispatch_semaphore_signal(release);Await(^BOOL{return firstFinished && secondFinished && !course.busy;});Check(invocations==1,@"queued course request executes once after current work");course.preview=YES;
    AMReviewController *clean=AMReviewController.new;NSDictionary *proposal=@{@"id":@"clean-source",@"title":@"Prefilled",@"due":NSDate.date,@"kind":@"assignment"};[clean updateRecords:@[proposal]];Check(!clean.hasUnsavedChanges,@"prefilled review can close without a false unsaved warning");
    SSSubmissionController *submission=[[SSSubmissionController alloc] initWithCourse:@{@"fork":@"student/fixture",@"branch":@"main"} changes:@[@{@"path":@"answer.md",@"status":@" M"}]];[submission configureTasks:@[@{@"id":@"prefilled-task",@"title":@"Assignment"}] selected:@[@"prefilled-task"]];Check(!submission.hasUnsavedChanges,@"default task association is not an unsaved edit");submission.message.stringValue=@"draft";Check(submission.hasUnsavedChanges,@"typed submission description remains protected");submission.message.stringValue=@"";Check(!submission.hasUnsavedChanges,@"reverted description clears unsaved state");
    NSString *operation=AMOperationBegin(@"检查文件",@"模拟项目",NO,nil);AMOperationProgress(operation,@"检查文件与图片",12,37);Check([AMOperations() filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *row,id bindings){return [row[@"id"] isEqual:operation];}]].count==1,@"background operation is recorded once without a duplicate progress view");
    AMShowOperations(app.window);NSWindow *panel=nil;for(NSWindow *window in NSApp.windows)if([window.title isEqual:@"后台任务"])panel=window;Check(panel!=nil,@"Window menu progress action opens compact history");AMOperationFinish(operation,@"success",@"完成");Await(^BOOL{return [[(NSScrollView *)[panel valueForKey:@"operationScroll"] documentView] subviews].count==1;});Check([[(NSScrollView *)[panel valueForKey:@"operationScroll"] documentView] subviews].count==1,@"completed operations are initially collapsed");
    course.preview=NO;__block BOOL writeStarted=NO,writeEnded=NO;dispatch_semaphore_t finishWrite=dispatch_semaphore_create(0);
    [course work:@"提交模拟文件" forCourse:nil operation:^id(NSError **error){writeStarted=YES;dispatch_semaphore_wait(finishWrite,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC));return @NO;} completion:^(id value,NSError *error){writeEnded=error.code==NSUserCancelledError;}];Await(^BOOL{return writeStarted && course.busy;});[course refreshPresentation];Check(!course.cancelReadButton.hidden && course.cancelReadButton.enabled,@"write steps expose force termination too");[course.cancelReadButton performClick:nil];Check(course.busy && !course.cancelReadButton.enabled,@"termination keeps the writer barrier until the running step has ended");dispatch_semaphore_signal(finishWrite);Await(^BOOL{return writeEnded && !course.busy;});course.preview=YES;
    AMNativeControlGallery *gallery=AMNativeControlGallery.new;[gallery.window.contentView layoutSubtreeIfNeeded];Check(gallery.window.contentMinSize.width==680,@"interactive native gallery is resizable");
    [app.ticker invalidate];[app.searchTimer invalidate];[app.window orderOut:nil];[panel orderOut:nil];[gallery.window orderOut:nil];[NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];
    printf("PASS: %lu native control, search, navigation and layout assertions; real glass appearance remains pending user screenshots\n",(unsigned long)checks);
}return 0;}
