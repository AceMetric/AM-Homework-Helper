// Foreground synthetic fixture: exercise Window -> button mouse routing with a real event loop.
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
int main(void){@autoreleasepool{
    if(!NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"])return 2;
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    NSWindow *host=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1050,800) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];host.releasedWhenClosed=NO;host.title=@"AM Helper · 提交按钮验证（模拟数据）";
    SSSubmissionController *sheet=[[SSSubmissionController alloc] initWithCourse:@{@"fork":@"demo/course",@"branch":@"main"} changes:@[@{@"path":@"report.md",@"status":@"??",@"sensitive":@NO}]];
    [sheet configureTasks:@[@{@"id":@"demo-task",@"title":@"模拟作业"}] selected:@[@"demo-task"]];
    __block NSUInteger requests=0,submits=0;__block BOOL passed=NO;
    sheet.performCheck=^NSDictionary *(NSArray *paths,NSArray *ids,NSString *extra,NSMutableDictionary *cache,BOOL(^cancelled)(void),NSError **error){requests++;return @{@"snapshot":@{@"paths":paths,@"files":@{}},@"report":@{@"version":@"synthetic-mouse-report",@"issues":@[],@"coverage":@[]},@"requirements":@""};};
    sheet.submit=^(NSArray *paths,NSString *message){submits++;};
    [host center];[host makeKeyAndOrderFront:nil];[host beginSheet:sheet.window completionHandler:nil];[NSApp activateIgnoringOtherApps:YES];
    NSTimer *click=[NSTimer timerWithTimeInterval:.8 repeats:NO block:^(NSTimer *timer){
        [sheet.checks[0] performClick:nil];[sheet.window makeFirstResponder:sheet.message];NSTextView *editor=(NSTextView *)sheet.message.currentEditor;
        if(!editor){fprintf(stderr,"FAIL: live submission message field editor unavailable\n");exit(1);}
        [editor insertText:@"Synthetic mouse revision" replacementRange:NSMakeRange(0,editor.string.length)];
        NSPoint point=[sheet.filesPrimary convertPoint:NSMakePoint(NSMidX(sheet.filesPrimary.bounds),NSMidY(sheet.filesPrimary.bounds)) toView:nil];NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
        NSEvent *down=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:point modifierFlags:0 timestamp:now windowNumber:sheet.window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1],*up=[NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:point modifierFlags:0 timestamp:now+.01 windowNumber:sheet.window.windowNumber context:nil eventNumber:2 clickCount:1 pressure:0];
        [NSApp postEvent:up atStart:YES];[NSApp sendEvent:down];
    }];[NSRunLoop.mainRunLoop addTimer:click forMode:NSRunLoopCommonModes];
    NSTimer *verify=[NSTimer timerWithTimeInterval:.1 repeats:YES block:^(NSTimer *timer){
        if(!sheet.report)return;
        if(requests!=1 || submits || sheet.checkPage.hidden || ![sheet.message.stringValue isEqual:@"Synthetic mouse revision"]){fprintf(stderr,"FAIL: live Next click failed to preserve input and enter report without submitting\n");exit(1);}
        passed=YES;[timer invalidate];[sheet cancel:nil];[host orderOut:nil];[NSApp stop:nil];
    }];[NSRunLoop.mainRunLoop addTimer:verify forMode:NSRunLoopCommonModes];
    NSTimer *timeout=[NSTimer timerWithTimeInterval:10 repeats:NO block:^(NSTimer *timer){fprintf(stderr,"FAIL: live Next click timed out; calls=%lu checking=%d feedback=%s\n",(unsigned long)requests,sheet.checking,sheet.validation.stringValue.UTF8String);exit(1);}];[NSRunLoop.mainRunLoop addTimer:timeout forMode:NSRunLoopCommonModes];
    [NSApp run];[timeout invalidate];if(!passed)return 1;
    printf("PASS: live mouse routing, active field input and Next report transition; no submission\n");
}return 0;}
