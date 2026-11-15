// Exercise the real card hit targets, rather than invoking their action closures.
#ifndef AM_FOREGROUND_TEST
#import "QuietUI.h"
#endif
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
#import <WebKit/WebKit.h>
// NSApplication.delegate and toolbar delegates are not ownership roots.
static AppDelegate *FixtureApplication;
static NSUInteger FixtureLaunches;
@interface AssignmentFixtureDelegate:AppDelegate @end
@implementation AssignmentFixtureDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)note{FixtureLaunches++;[super applicationDidFinishLaunching:note];}
@end
static NSUInteger assertions;
static void Check(BOOL value,NSString *label){assertions++;if(!value){fprintf(stderr,"FAIL: %s\n",label.UTF8String);exit(1);}}
static void Drain(void){NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:.16];while(limit.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.005]];}
static void CheckRendered(AMDocumentView *preview){
    WKWebView *web=[preview valueForKey:@"web"];__block BOOL rendered=NO;NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:8];
    while(!rendered && deadline.timeIntervalSinceNow>0){[web evaluateJavaScript:@"document.querySelector('#content h1')?.textContent==='作业要求' && document.querySelectorAll('#content li').length===2" completionHandler:^(id value,NSError *error){rendered=[value boolValue];}];Drain();}
    if(!rendered || ![[preview valueForKey:@"sourceScroll"] isHidden]){fprintf(stderr,"renderer readiness=%d url=%s sourceHidden=%d bundle=%s\n",[[preview valueForKey:@"ready"] boolValue],web.URL.absoluteString.UTF8String,[[preview valueForKey:@"sourceScroll"] isHidden],NSBundle.mainBundle.resourcePath.UTF8String);__block BOOL inspected=NO;[web evaluateJavaScript:@"({render:typeof AMRender,markdown:typeof markdownit,content:document.getElementById('content')?.innerHTML})" completionHandler:^(id value,NSError *error){fprintf(stderr,"renderer state=%s error=%s sourceHidden=%d bundle=%s\n",[value description].UTF8String,error.localizedDescription.UTF8String,[[preview valueForKey:@"sourceScroll"] isHidden],NSBundle.mainBundle.resourcePath.UTF8String);inspected=YES;}];while(!inspected && deadline.timeIntervalSinceNow>-1)Drain();}
    Check(rendered && [[preview valueForKey:@"sourceScroll"] isHidden],@"actual Markdown headings and list render without source fallback");
}
static NSArray *Elements(id root){if(!root)return @[];NSMutableArray *result=NSMutableArray.array,*pending=[NSMutableArray arrayWithObject:root];NSHashTable *seen=[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];while(pending.count){id element=pending.lastObject;[pending removeLastObject];if([seen containsObject:element])continue;[seen addObject:element];[result addObject:element];if([element respondsToSelector:@selector(accessibilityChildren)])[pending addObjectsFromArray:[element accessibilityChildren] ?: @[]];if([element isKindOfClass:NSView.class])[pending addObjectsFromArray:[element subviews]];}return result;}
static id Find(id root,NSString *label){if(!root)return nil;if([root isKindOfClass:NSWindow.class]){for(NSToolbarItem *item in [(NSWindow *)root toolbar].items){id result=Find(item.view,label);if(result)return result;}root=[(NSWindow *)root contentView];}for(id e in Elements(root)){NSString *value=[e respondsToSelector:@selector(accessibilityLabel)] ? [e accessibilityLabel]:nil;NSString *title=[e respondsToSelector:@selector(accessibilityTitle)] ? [e accessibilityTitle]:nil;if([value isEqual:label] || [title isEqual:label])return e;}return nil;}
static void Click(NSWindow *window,id element,CGFloat relativeY){Check(element!=nil,@"click target is present");NSRect rect=[element accessibilityFrame];Check(rect.size.width>10 && rect.size.height>10,@"click target has real geometry");NSPoint screen=NSMakePoint(NSMidX(rect),NSMinY(rect)+rect.size.height*relativeY);NSPoint location=[window convertPointFromScreen:screen];if([element isKindOfClass:NSView.class]){NSView *view=element;location=[view convertPoint:NSMakePoint(NSMidX(view.bounds),NSMinY(view.bounds)+NSHeight(view.bounds)*relativeY) toView:nil];}// AX segment frames use screen coordinates; resolve the native segmented
// control to obtain the same window coordinates used by its mouse handler.
if(![element isKindOfClass:NSView.class]){
    id parent=element;
    for(NSUInteger i=0;i<8 && parent;i++){
        if([parent isKindOfClass:NSSegmentedControl.class]){NSSegmentedControl *control=parent;NSString *label=[element accessibilityLabel];NSInteger segment=-1;for(NSInteger n=0;n<control.segmentCount;n++)if([[control labelForSegment:n] isEqual:label])segment=n;
            if(segment>=0)location=[control convertPoint:NSMakePoint(NSWidth(control.bounds)*(segment+.5)/control.segmentCount,NSMidY(control.bounds)) toView:nil];break;}
        parent=[parent respondsToSelector:@selector(accessibilityParent)] ? [parent accessibilityParent]:nil;
    }
}
if(![element isKindOfClass:NSView.class] && [[element accessibilityLabel] isEqual:@"AI 检查"]){
    for(id view in Elements(window.contentView))if([view isKindOfClass:NSSegmentedControl.class] && [(NSSegmentedControl *)view segmentCount]==3){NSSegmentedControl *control=view;location=[control convertPoint:NSMakePoint(NSMidX(control.bounds),NSMidY(control.bounds)) toView:nil];break;}
}
NSView *hit=nil;
#ifdef AM_FOREGROUND_TEST
hit=[window.contentView hitTest:[window.contentView.superview convertPoint:location fromView:nil]];
Check(hit!=nil,@"window hit test resolves a visible control");
#else
// A quiet window may not have a themed window-server container on CI. Test
// native component hit regions in their own parent coordinates instead. The
// foreground lane above remains the full-window routing gate.
if([element isKindOfClass:NSView.class]){NSView *view=element;NSPoint parentPoint=[view.superview convertPoint:location fromView:nil];hit=[view hitTest:parentPoint];
    if(!hit){fprintf(stderr,"quiet hit failure: class=%s label=%s bounds=%s frame=%s parentPoint=%s hidden=%d ancestorHidden=%d\n",NSStringFromClass(view.class).UTF8String,[[element accessibilityLabel] UTF8String],NSStringFromRect(view.bounds).UTF8String,NSStringFromRect(view.frame).UTF8String,NSStringFromPoint(parentPoint).UTF8String,view.hidden,view.hiddenOrHasHiddenAncestor);for(NSView *ancestor=view.superview;ancestor;ancestor=ancestor.superview)fprintf(stderr,"ancestor: %s frame=%s bounds=%s hidden=%d\n",NSStringFromClass(ancestor.class).UTF8String,NSStringFromRect(ancestor.frame).UTF8String,NSStringFromRect(ancestor.bounds).UTF8String,ancestor.hidden);}
    Check(hit!=nil,@"native component hit region resolves its target");}
#endif
NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;NSEvent *up=[NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:location modifierFlags:0 timestamp:now+.02 windowNumber:window.windowNumber context:nil eventNumber:2 clickCount:1 pressure:0];[NSApp postEvent:up atStart:YES];NSEvent *down=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:location modifierFlags:0 timestamp:now windowNumber:window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];[window makeKeyWindow];
#ifdef AM_FOREGROUND_TEST
NSPoint original=NSEvent.mouseLocation;
NSPoint actual=[window convertPointToScreen:location];
CGFloat displayHeight=CGDisplayBounds(CGMainDisplayID()).size.height;
CGWarpMouseCursorPosition(CGPointMake(actual.x,displayHeight-actual.y));
@try {
    [window sendEvent:down];
    // Some Tahoe controls finish tracking asynchronously. Dispatch an unconsumed
    // release before inspecting the result; synchronous tracking consumes it itself.
    NSEvent *release=[NSApp nextEventMatchingMask:NSEventMaskLeftMouseUp untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES];
    if(release)[window sendEvent:release];
} @finally {CGWarpMouseCursorPosition(CGPointMake(original.x,displayHeight-original.y));}
#else
// The quiet lane verifies hit testing and native event handling separately.
// Only the visible application lane is an end-to-end window-dispatch gate.
if([element isKindOfClass:NSButton.class] && [[element accessibilityLabel] hasPrefix:@"打开作业："]){[hit mouseDown:down];}else if([element isKindOfClass:NSButton.class]){[(NSButton *)element performClick:nil];}else if([element respondsToSelector:@selector(accessibilityPerformPress)]){[element accessibilityPerformPress];}else{[hit mouseDown:down];}
#endif
Drain();}
int main(){@autoreleasepool{
    NSString *log=[NSBundle.mainBundle objectForInfoDictionaryKey:@"AMFixtureLog"];
    if(log.length){freopen(log.fileSystemRepresentation,"w",stdout);freopen(log.fileSystemRepresentation,"a",stderr);}

    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
#ifdef AM_FOREGROUND_TEST
    FixtureApplication=AssignmentFixtureDelegate.new;NSApp.delegate=FixtureApplication;
#endif
    dispatch_block_t runFixture=^{
#ifdef AM_FOREGROUND_TEST
    AppDelegate *app=FixtureApplication;Check(FixtureLaunches==1 && app.window!=nil,@"visible fixture uses exactly one real application launch");
    [app.ticker invalidate];[app.quickTimer invalidate];[app openCourses:nil];
    AMCourseController *controller=app.courseWindow.courseWorkspace;NSWindow *window=app.window;
    window.title=@"AM Helper · 1.20 修复验收（合成作业）";window.titleVisibility=NSWindowTitleHidden;[window setContentSize:NSMakeSize(1180,760)];[app layout];[window center];[window makeKeyAndOrderFront:nil];
#else
    // The quiet lane creates the real toolbar delegate without launching global
    // application services. Its fixed native container also avoids zero-size hosting roots.
    AppDelegate *app=AppDelegate.new;FixtureApplication=app;app.page=4;app.courseWindow=[[SSCourseController alloc] initWithPreview:YES];
    AMCourseController *controller=app.courseWindow.courseWorkspace;
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(40,40,1500,960) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];window.releasedWhenClosed=NO;app.window=window;
    NSView *container=[[NSView alloc] initWithFrame:NSMakeRect(0,0,1500,960)];window.contentView=container;controller.view.frame=container.bounds;controller.view.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;[container addSubview:controller.view];
    NSToolbar *toolbar=[[NSToolbar alloc] initWithIdentifier:@"AMIsolatedToolbar"];toolbar.delegate=app;window.toolbar=toolbar;[app refreshPageToolbar];[window setContentSize:NSMakeSize(1500,960)];
#endif
    __block NSUInteger selected=0,online=0;void(^applicationAction)(NSString *,NSString *)=[controller.actionHandler copy];controller.actionHandler=^(NSString *action,NSString *identifier){if([action isEqual:@"select"])selected++;if([action isEqual:@"workbench-online"])online++;
        // Keep ordinary editing and navigation real, while synthetic fixtures
        // never start a model request or a Git operation against fake courses.
        if([@[@"new-assignment",@"edit-task",@"workbench-back",@"workbench-navigation",@"course-result"] containsObject:action] && applicationAction)applicationAction(action,identifier);
        if(![action isEqual:@"select"])[app refreshPageToolbar];};
    controller.workbenchLoader=^(NSString *identifier,NSString *path,NSString *mode,void(^done)(NSDictionary *,NSView *)){if([mode isEqual:@"index"])done(@{@"paths":@[]},nil);else {AMDocumentView *preview=[[AMDocumentView alloc] initWithFrame:NSMakeRect(0,0,600,600)];NSString *text=@"# 作业要求\n\n## 需要完成\n\n1. 整理学习笔记，说明关键概念。\n2. 完成实践并讨论结果。\n\n## 提交方式\n\n提交 report.md，附上方法、过程与结论。\n";[preview loadSnapshot:@{@"paths":@[@"assignment/README.md"],@"files":@{@"assignment/README.md":@{@"text":text,@"version":@"synthetic-v1"}}} path:@"assignment/README.md"];done(@{},preview);}};
    NSMutableArray *records=NSMutableArray.array;for(NSUInteger i=0;i<3;i++)[records addObject:@{@"id":[NSString stringWithFormat:@"assignment-%lu",(unsigned long)i],@"title":i==1 ? @"排序算法实现与复杂度分析":(i==0 ? @"学习笔记与重点梳理":@"实验报告与结果讨论"),@"courseName":@"示例课程",@"confirmed":@YES,@"gitCourse":@YES,@"completed":@NO,@"boardHistory":@NO,@"path":@"assignment/README.md",@"sourceSummary":i==2 ? @"":@"梳理课程中的重要概念，完成实践并说明方法与结论。",@"sourceRequirements":@"Submit report.md",@"requirementItems":@[@{@"text":@"Submit report.md"}],@"due":[NSDate dateWithTimeIntervalSince1970:1900000000]}];
    // Seed the application's real task projection too: navigation and refresh
    // must not replace the injected board with unrelated overview demo tasks.
    [app.courseWindow.courses addObject:[@{@"fork":@"student/synthetic",@"upstream":@"teacher/synthetic",@"branch":@"main",@"enabled":@YES} mutableCopy]];
    NSMutableArray *tasks=NSMutableArray.array;for(NSDictionary *record in records){NSMutableDictionary *task=record.mutableCopy;task[@"subject"]=@"示例课程";task[@"sourceRepository"]=@"teacher/synthetic";task[@"sourcePath"]=@"assignment/README.md";[tasks addObject:task];}app.tasks=tasks;app.courseWindow.tasksProvider=^NSArray *{return [FixtureApplication snapshot];};
    Check(Elements(nil).count==0 && Find(nil,@"missing")==nil,@"empty roots are safe");
    [controller setAssignmentBoard:YES];[controller updateRecords:records selected:@"" information:@"" empty:@"" paused:NO];[controller.view layoutSubtreeIfNeeded];Drain();

    NSMutableArray *cards=NSMutableArray.array;for(id element in Elements(controller.view))if([[element accessibilityLabel] hasPrefix:@"打开作业："])[cards addObject:element];
    if(cards.count!=3){fprintf(stderr,"cards=%lu elements=%lu bounds=%s\n",(unsigned long)cards.count,(unsigned long)Elements(controller.view).count,NSStringFromRect(controller.view.bounds).UTF8String);for(id e in Elements(controller.view)){NSString *label=[e accessibilityLabel];NSString *title=[e accessibilityTitle];id value=[e accessibilityValue];fprintf(stderr,"%s label=%s title=%s value=%s\n",NSStringFromClass([e class]).UTF8String,label.UTF8String,title.UTF8String,[value description].UTF8String);}}
    Check(cards.count==3,@"every card is a primary action");CGFloat height=[[cards firstObject] accessibilityFrame].size.height;for(id card in cards)Check(fabs([card accessibilityFrame].size.height-height)<1,@"short and long cards have equal heights");
    NSUInteger index=0;for(NSNumber *y in @[@.7,@.25,@.06]){NSString *label=[@"打开作业：" stringByAppendingString:records[index++][@"title"]];id card=Find(controller.view,label);Click(window,card,y.doubleValue);if(!Find(window,@"返回作业看板")){fprintf(stderr,"selected=%lu showing=%d page=%ld toolbar=%s\n",(unsigned long)selected,app.courseWindow.showingWorkbench,(long)app.page,[[window.toolbar.items valueForKey:@"itemIdentifier"] description].UTF8String);for(NSToolbarItem *item in window.toolbar.items)fprintf(stderr,"item=%s view=%s label=%s\n",item.itemIdentifier.UTF8String,NSStringFromClass(item.view.class).UTF8String,item.view.accessibilityLabel.UTF8String);}Check(Find(window,@"返回作业看板")!=nil,@"card body and blank areas open the workbench");Check([window.toolbar.items.firstObject.itemIdentifier isEqual:@"AMCourseBack"],@"workbench Back is the leading toolbar item");
#ifdef AM_FOREGROUND_TEST
    for(NSNumber *visibility in @[@(NSWindowTitleVisible),@(NSWindowTitleHidden)]){window.titleVisibility=visibility.integerValue;[window layoutIfNeeded];Drain();NSView *backView=Find(window,@"返回作业看板");NSRect position=[backView convertRect:backView.bounds toView:nil];if(NSMinX(position)>=320)fprintf(stderr,"Back physical frame=%s window=%s\n",NSStringFromRect(position).UTF8String,NSStringFromRect(window.frame).UTF8String);Check(NSMinX(position)<320,@"Back stays physically at the leading edge with a visible or hidden window title");}
#endif
Click(window,Find(controller.view,@"AI 检查"),.5);Check(Find(controller.view,@"AI 检查…")!=nil,@"AI action exists before any file or model check");Click(window,Find(controller.view,@"AI 检查…"),.5);
    NSView *preview=nil,*tabs=nil;for(id view in Elements(controller.view)){if([view isKindOfClass:AMDocumentView.class])preview=view;if([view isKindOfClass:NSSegmentedControl.class] && [(NSSegmentedControl *)view segmentCount]==3)tabs=view;}
    Check(preview && tabs,@"preview and native inspector tabs exist");CheckRendered((AMDocumentView *)preview);
    Check(tabs.frame.size.width<260 && tabs.frame.size.width>120,@"inspector tabs keep a compact native width");
    NSSegmentedControl *previewTabs=[preview valueForKey:@"mode"];Check(previewTabs.frame.size.width>=previewTabs.fittingSize.width && previewTabs.frame.size.width<200,@"preview selector contains its native fitting width");
    NSRect previewFrame=[preview convertRect:preview.bounds toView:nil],tabFrame=[tabs convertRect:tabs.bounds toView:nil];
    for(NSString *label in @[@"提交",@"历史",@"AI 检查"]){Click(window,Find(controller.view,label),.5);[controller.view layoutSubtreeIfNeeded];Check(NSEqualRects(previewFrame,[preview convertRect:preview.bounds toView:nil]) && NSEqualRects(tabFrame,[tabs convertRect:tabs.bounds toView:nil]),@"tab switching does not move preview or inspector header");}
#ifdef AM_FOREGROUND_TEST
    if(index==1){[window setContentSize:NSMakeSize(960,640)];[app layout];Drain();[controller.view layoutSubtreeIfNeeded];NSRect reading=[preview convertRect:preview.bounds toView:controller.view];Check(NSContainsRect(controller.view.bounds,reading) && reading.size.width>500,@"minimum window preserves the preview instead of squeezing three panes");CheckRendered((AMDocumentView *)preview);[window setContentSize:NSMakeSize(1180,760)];[app layout];Drain();}
#endif
    Click(window,Find(window,@"返回作业看板"),.5);}
    Check(selected==3 && online==3,@"one click produces one selection and one explicit model action");
    Click(window,Find(controller.view,@"课程管理"),.5);id back=Find(window,@"返回作业看板");Check([window.toolbar.items.firstObject.itemIdentifier isEqual:@"AMCourseBack"],@"course management Back uses the same leading toolbar position");
#ifdef AM_FOREGROUND_TEST
    NSView *managementBack=back;NSRect managementPosition=[managementBack convertRect:managementBack.bounds toView:nil];Check(NSMinX(managementPosition)<320,@"management Back is physically at the same leading edge");
#endif
Check([back isKindOfClass:NSButton.class] && [(NSButton *)back image]!=nil && ![(NSButton *)back title].length,@"course management returns through an image-only toolbar arrow");Click(window,back,.5);
    id requirement=Find(controller.view,@"查看老师要求");Check(requirement!=nil,@"requirement count is visible");NSRect before=[Find(controller.view,@"打开作业：学习笔记与重点梳理") accessibilityFrame];Click(window,requirement,.5);
#ifdef AM_FOREGROUND_TEST
BOOL hasSource=NO;for(NSWindow *popup in NSApp.windows)if(Find(popup.contentView,@"查看原文"))hasSource=YES;Check(hasSource,@"requirements open a readable popover");
#else
// Quiet fixtures cannot order a popover window. They only verify the public
// requirements target and stable card geometry, not popup visibility.
Check(requirement!=nil,@"quiet component exposes the requirements action");
#endif
NSRect after=[Find(controller.view,@"打开作业：学习笔记与重点梳理") accessibilityFrame];Check(NSEqualRects(before,after),@"opening requirements does not move cards");
    // Let the current click callback return before checking the deferred native
    // toolbar layout. Immediate assertions previously missed a viewer-engine crash.
    NSTimeInterval deferredDelay=.35;
#ifdef AM_FOREGROUND_TEST
    // The reported native toolbar crash arrived after the initial click assertions.
    // Keep the real event loop running long enough to exercise deferred viewer layout.
    deferredDelay=6;
#endif
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(deferredDelay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[app.courseWindow refreshPresentation];[window layoutIfNeeded];Drain();NSUInteger refreshed=0;for(id item in Elements(controller.view))if([[item accessibilityLabel] hasPrefix:@"打开作业："])refreshed++;Check(refreshed==3,@"normal navigation refresh keeps the same three task-backed cards");Check(FixtureApplication.window==window,@"application owner survives deferred toolbar layout");printf("PASS: %lu assignment component and geometry assertions\n",(unsigned long)assertions);
#ifdef AM_HOLD_REVIEW
    fflush(stdout);
#else
    [window orderOut:nil];[NSApp stop:nil];[NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0] atStart:NO];
#endif
    });
    };
#ifdef AM_FOREGROUND_TEST
    // Use NSApplication's lifecycle rather than invoking its delegate manually.
    // Otherwise run-loop startup can initialize a second window over old controls.
    [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidFinishLaunchingNotification object:NSApp queue:nil usingBlock:^(NSNotification *note){[NSTimer scheduledTimerWithTimeInterval:.05 repeats:NO block:^(NSTimer *timer){runFixture();}];}];
#else
    // A run-loop timer permits WebKit's main-queue navigation callbacks while
    // the fixture pumps the loop. A main-queue block would starve those callbacks.
    [NSTimer scheduledTimerWithTimeInterval:.05 repeats:NO block:^(NSTimer *timer){runFixture();}];
#endif
#ifndef AM_HOLD_REVIEW
    [NSTimer scheduledTimerWithTimeInterval:25 repeats:NO block:^(NSTimer *timer){fprintf(stderr,"FAIL: assignment event loop timed out\n");exit(1);}];
#endif
    [NSApp run];
}}
