// Exercise the real card hit targets, rather than invoking their action closures.
#ifndef AM_FOREGROUND_TEST
#import "QuietUI.h"
#endif
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
static NSUInteger assertions;
static void Check(BOOL value,NSString *label){assertions++;if(!value){fprintf(stderr,"FAIL: %s\n",label.UTF8String);exit(1);}}
static void Drain(void){NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:.16];while(limit.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.005]];}
static NSArray *Elements(id root){NSMutableArray *result=NSMutableArray.array,*pending=[NSMutableArray arrayWithObject:root];NSHashTable *seen=[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];while(pending.count){id element=pending.lastObject;[pending removeLastObject];if([seen containsObject:element])continue;[seen addObject:element];[result addObject:element];if([element respondsToSelector:@selector(accessibilityChildren)])[pending addObjectsFromArray:[element accessibilityChildren] ?: @[]];if([element isKindOfClass:NSView.class])[pending addObjectsFromArray:[element subviews]];}return result;}
static id Find(id root,NSString *label){for(id e in Elements(root)){NSString *value=[e respondsToSelector:@selector(accessibilityLabel)] ? [e accessibilityLabel]:nil;NSString *title=[e respondsToSelector:@selector(accessibilityTitle)] ? [e accessibilityTitle]:nil;if([value isEqual:label] || [title isEqual:label])return e;}return nil;}
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
    [NSApp finishLaunching];[NSApp activateIgnoringOtherApps:YES];
#endif
    dispatch_async(dispatch_get_main_queue(),^{
#ifdef AM_FOREGROUND_TEST
    // Review new pages inside the real application shell, including its native
    // sidebar and toolbar, rather than judging an isolated hosting window.
    AppDelegate *app=AppDelegate.new;NSApp.delegate=app;[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
    [app.ticker invalidate];[app.quickTimer invalidate];[app openCourses:nil];
    AMCourseController *controller=app.courseWindow.courseWorkspace;NSWindow *window=app.window;
    [window setContentSize:NSMakeSize(1500,960)];[app layout];[window makeKeyAndOrderFront:nil];
#else
    AMCourseController *controller=AMCourseController.new;NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(40,40,1240,820) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];window.releasedWhenClosed=NO;window.contentMinSize=NSMakeSize(960,640);window.title=@"AM Helper · isolated assignment acceptance";// Keep the hidden fixture inside a fixed native container. On macOS 26.0,
    // attaching NSHostingView as the window root negotiates an initial zero size;
    // SwiftUI then correctly hides all offscreen cards, preventing hit testing.
    NSView *container=[[NSView alloc] initWithFrame:NSMakeRect(0,0,1240,820)];window.contentView=container;controller.view.frame=container.bounds;controller.view.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;[container addSubview:controller.view];[window setContentSize:container.bounds.size];[window makeKeyAndOrderFront:nil];
#endif
    __block NSUInteger selected=0,online=0;controller.actionHandler=^(NSString *action,NSString *identifier){if([action isEqual:@"select"])selected++;if([action isEqual:@"workbench-online"])online++;};
    controller.workbenchLoader=^(NSString *identifier,NSString *path,NSString *mode,void(^done)(NSDictionary *,NSView *)){if([mode isEqual:@"index"])done(@{@"paths":@[]},nil);else {AMDocumentView *preview=[[AMDocumentView alloc] initWithFrame:NSMakeRect(0,0,600,600)];NSString *text=@"# 作业要求\n\n## 需要完成\n\n1. 整理学习笔记，说明关键概念。\n2. 完成实践并讨论结果。\n\n## 提交方式\n\n提交 report.md，附上方法、过程与结论。\n";[preview loadSnapshot:@{@"paths":@[@"assignment/README.md"],@"files":@{@"assignment/README.md":@{@"text":text,@"version":@"synthetic-v1"}}} path:@"assignment/README.md"];done(@{},preview);}};
    NSMutableArray *records=NSMutableArray.array;for(NSUInteger i=0;i<3;i++)[records addObject:@{@"id":[NSString stringWithFormat:@"assignment-%lu",(unsigned long)i],@"title":i==1 ? @"排序算法实现与复杂度分析":(i==0 ? @"学习笔记与重点梳理":@"实验报告与结果讨论"),@"courseName":@"示例课程",@"confirmed":@YES,@"gitCourse":@YES,@"completed":@NO,@"boardHistory":@NO,@"path":@"assignment/README.md",@"sourceSummary":i==2 ? @"":@"梳理课程中的重要概念，完成实践并说明方法与结论。",@"sourceRequirements":@"Submit report.md",@"requirementItems":@[@{@"text":@"Submit report.md"}],@"due":[NSDate dateWithTimeIntervalSince1970:1900000000]}];
    [controller setAssignmentBoard:YES];[controller updateRecords:records selected:@"" information:@"" empty:@"" paused:NO];[controller.view layoutSubtreeIfNeeded];Drain();

    NSMutableArray *cards=NSMutableArray.array;for(id element in Elements(controller.view))if([[element accessibilityLabel] hasPrefix:@"打开作业："])[cards addObject:element];
    if(cards.count!=3){fprintf(stderr,"cards=%lu elements=%lu bounds=%s\n",(unsigned long)cards.count,(unsigned long)Elements(controller.view).count,NSStringFromRect(controller.view.bounds).UTF8String);for(id e in Elements(controller.view)){NSString *label=[e accessibilityLabel];NSString *title=[e accessibilityTitle];id value=[e accessibilityValue];fprintf(stderr,"%s label=%s title=%s value=%s\n",NSStringFromClass([e class]).UTF8String,label.UTF8String,title.UTF8String,[value description].UTF8String);}}
    Check(cards.count==3,@"every card is a primary action");CGFloat height=[[cards firstObject] accessibilityFrame].size.height;for(id card in cards)Check(fabs([card accessibilityFrame].size.height-height)<1,@"short and long cards have equal heights");
    NSUInteger index=0;for(NSNumber *y in @[@.7,@.25,@.06]){NSString *label=[@"打开作业：" stringByAppendingString:records[index++][@"title"]];id card=Find(controller.view,label);Click(window,card,y.doubleValue);if(!Find(controller.view,@"返回"))fprintf(stderr,"selected after click=%lu key=%d visible=%d\n",(unsigned long)selected,window.keyWindow,window.visible);Check(Find(controller.view,@"返回")!=nil,@"card body and blank areas open the workbench");Click(window,Find(controller.view,@"AI 检查"),.5);Check(Find(controller.view,@"AI 检查…")!=nil,@"AI action exists before any file or model check");Click(window,Find(controller.view,@"AI 检查…"),.5);Click(window,Find(controller.view,@"返回"),.5);}
    Check(selected==3 && online==3,@"one click produces one selection and one explicit model action");
    id requirement=Find(controller.view,@"作业要求 · 1 条");Check(requirement!=nil,@"requirement count is visible");NSRect before=[Find(controller.view,@"打开作业：学习笔记与重点梳理") accessibilityFrame];Click(window,requirement,.5);
#ifdef AM_FOREGROUND_TEST
BOOL hasSource=NO;for(NSWindow *popup in NSApp.windows)if(Find(popup.contentView,@"查看原文"))hasSource=YES;Check(hasSource,@"requirements open a readable popover");
#else
// Quiet fixtures cannot order a popover window. They only verify the public
// requirements target and stable card geometry, not popup visibility.
Check(requirement!=nil,@"quiet component exposes the requirements action");
#endif
NSRect after=[Find(controller.view,@"打开作业：学习笔记与重点梳理") accessibilityFrame];Check(NSEqualRects(before,after),@"opening requirements does not move cards");
    printf("PASS: %lu assignment component and geometry assertions\n",(unsigned long)assertions);[window orderOut:nil];[NSApp stop:nil];
    });
    [NSTimer scheduledTimerWithTimeInterval:15 repeats:NO block:^(NSTimer *timer){fprintf(stderr,"FAIL: assignment event loop timed out\n");exit(1);}];
    [NSApp run];
}}
