#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
static NSUInteger checks;
static void Check(BOOL value,NSString *message){checks++;if(!value){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
int main(){@autoreleasepool{
    Check(NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"]!=nil,@"isolated storage");
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];AppDelegate *app=AppDelegate.new;NSApp.delegate=app;@try {[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];} @catch(NSException *exception){fprintf(stderr,"UX exception: %s\n%s\n",exception.reason.UTF8String,exception.callStackSymbols.description.UTF8String);exit(1);}
    [app openList:nil];[app render];CGFloat top=app.headerHeight.constant;NSRect list=app.nativeTasks.view.frame;
    for(NSUInteger i=0;i<100;i++){app.notice=[NSString stringWithFormat:@"后台状态 %lu",(unsigned long)i];[app render];Check(app.headerHeight.constant==top && NSEqualRects(list,app.nativeTasks.view.frame),@"status updates do not move task content");}
    BOOL create=NO,activity=NO;for(NSToolbarItem *item in app.window.toolbar.items){if([item.itemIdentifier isEqual:@"AMNewTask"]){create=item.action==@selector(addTask:) && [item.label isEqual:@"新建任务"];}if([item.itemIdentifier isEqual:@"AMActivity"])activity=YES;}
    Check(create && activity,@"toolbar uses manual create and exposes activity");
    AMPostUIMessage(@"test",@"one",@"保存失败",AMUIMessageError,nil,nil);AMDismissUIMessage(@"test",@"one");AMPostUIMessage(@"test",@"one",@"保存失败",AMUIMessageError,nil,nil);
    NSDictionary *message=nil;for(NSDictionary *row in AMUIMessages())if([row[@"scope"] isEqual:@"test"])message=row;
    Check([message[@"dismissed"] boolValue],@"dismissed unchanged events do not revive");
    AMPostUIMessage(@"test",@"one",@"保存失败：磁盘已满",AMUIMessageError,nil,nil);for(NSDictionary *row in AMUIMessages())if([row[@"scope"] isEqual:@"test"])message=row;
    Check(![message[@"dismissed"] boolValue],@"new revision is actionable again");
    NSString *op=AMOperationBegin(@"测试",@"模拟材料",YES,^{});AMPostUIMessage(@"operation",op,@"检查中",AMUIMessageInformation,nil,nil);AMDismissUIMessage(@"operation",op);
    BOOL stillRunning=NO;for(NSDictionary *row in AMOperations())if([row[@"id"] isEqual:op])stillRunning=[row[@"state"] isEqual:@"running"];Check(stillRunning,@"dismissing feedback never cancels work");AMOperationFinish(op,@"success",@"完成");
    [app addTask:nil];Check(app.editor && !app.quickWindow,@"manual create opens without recognition");[app closeEditor];
    [app.ticker invalidate];[app.quickTimer invalidate];[app.window orderOut:nil];[NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];printf("PASS: %lu unified interaction assertions\n",(unsigned long)checks);
}return 0;}
