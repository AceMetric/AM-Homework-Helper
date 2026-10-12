// Visible, isolated regression for task inspection while a course scan is still running.
#import <objc/runtime.h>
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
static NSUInteger checks;
static void Check(BOOL value,NSString *message){checks++;if(!value){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
static void Wait(BOOL(^ready)(void)){NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:8];while(!ready() && limit.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];Check(ready(),@"visible operation completes");}
static void Replace(Class cls,SEL selector,IMP imp){Method method=class_getInstanceMethod(cls,selector);class_replaceMethod(cls,selector,imp,method_getTypeEncoding(method));}
int main(void){@autoreleasepool{
    Check([NSProcessInfo.processInfo.arguments containsObject:@"--preview"],@"isolated preview required");
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    AppDelegate *app=AppDelegate.new;NSApp.delegate=app;[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
    SSCourseController *courses=app.courseWindow;
    NSString *root=[NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"] stringByAppendingPathComponent:@"native-check"];
    [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL];
    NSURL *file=[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"report.md"]];
    NSString *text=@"# Synthetic completed report\n![illustration](missing.png)\n";
    [text writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSMutableDictionary *task=[app.tasks.firstObject mutableCopy];task[@"id"]=@"native-completed-check";task[@"title"]=@"Synthetic completed report";task[@"completed"]=@YES;[task removeObjectForKey:@"sourceRepository"];[task removeObjectForKey:@"courseRepository"];
    [app.tasks addObject:task];NSButton *route=NSButton.new;route.tag=2;[app navigate:route];app.filter=3;app.selectedTaskID=task[@"id"];[app render];
    // Display the real native pickers. The test supplies synthetic choices after dismissing them.
    IMP modal=class_getMethodImplementation(NSOpenPanel.class,@selector(runModal));
    IMP urls=class_getMethodImplementation(NSOpenPanel.class,@selector(URLs));
    IMP url=class_getMethodImplementation(NSOpenPanel.class,@selector(URL));
    __block NSUInteger pickers=0;
    Replace(NSOpenPanel.class,@selector(runModal),imp_implementationWithBlock(^NSModalResponse(NSOpenPanel *panel){
        pickers++;panel.directoryURL=[NSURL fileURLWithPath:root];
        NSTimer *dismiss=[NSTimer timerWithTimeInterval:.25 repeats:NO block:^(NSTimer *t){[panel cancel:nil];}];
        [NSRunLoop.mainRunLoop addTimer:dismiss forMode:NSModalPanelRunLoopMode];
        ((NSModalResponse(*)(id,SEL))modal)(panel,@selector(runModal));[dismiss invalidate];return NSModalResponseOK;
    }));
    Replace(NSOpenPanel.class,@selector(URLs),imp_implementationWithBlock(^NSArray *(NSOpenPanel *panel){return @[file];}));
    Replace(NSOpenPanel.class,@selector(URL),imp_implementationWithBlock(^NSURL *(NSOpenPanel *panel){return panel.canChooseDirectories ? [NSURL fileURLWithPath:root]:file;}));
    dispatch_suspend(courses.queue);courses.busy=YES;courses.git.readsCancellable=YES;courses.operationPhase=@"Synthetic teacher scan";
    NSButton *button=(NSButton *)AMFindButton(app.taskDetails,@selector(checkSelectedTask:),0,task[@"id"]);Check(button!=nil,@"real completed-task button present");[button performClick:nil];
    Replace(NSOpenPanel.class,@selector(runModal),modal);Replace(NSOpenPanel.class,@selector(URLs),urls);Replace(NSOpenPanel.class,@selector(URL),url);
    SSSubmissionController *sheet=courses.submission;
    Wait(^BOOL{return sheet.report!=nil && !sheet.checking;});
    Check(pickers==2 && app.page==2 && [app.selectedTaskID isEqual:task[@"id"]],@"native folder and file pickers preserve the task page and selection");
    Check(courses.busy && sheet.checkOnly && sheet.window.sheetParent==app.window && sheet.findings.count>0 && !sheet.submit,@"visible report completes while course queue stays suspended, without submit callback");
    for(NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){
        sheet.window.appearance=[NSAppearance appearanceNamed:appearance];[sheet.window.contentView layoutSubtreeIfNeeded];
        NSView *view=sheet.window.contentView;NSBitmapImageRep *bitmap=[view bitmapImageRepForCachingDisplayInRect:view.bounds];[view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
        NSString *name=[appearance isEqual:NSAppearanceNameAqua] ? @"light":@"dark";
        Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithFormat:@"build/qa/task-check-active-scan-%@.png",name] atomically:YES],@"synthetic visible report screenshot saved");
    }
    [sheet.primary performClick:nil];Wait(^BOOL{return !sheet.window.sheetParent;});
    dispatch_resume(courses.queue);courses.busy=NO;courses.git.readsCancellable=NO;
    Check([[NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:NULL] isEqual:text] && [task[@"completed"] boolValue],@"file and completed status remain unchanged");
    [app.window orderOut:nil];printf("PASS: %lu native task-check and active-scan assertions\n",(unsigned long)checks);
}return 0;}
