// Visible, isolated regression for task inspection while a course scan is still running.
#import <objc/runtime.h>
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
#import "FixtureButtons.h"
static NSUInteger checks;
static void Check(BOOL value,NSString *message){checks++;if(!value){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
static void Wait(BOOL(^ready)(void)){NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:15];while(!ready() && limit.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];Check(ready(),@"visible operation completes");}
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
    [NSFileManager.defaultManager createDirectoryAtPath:[root stringByAppendingPathComponent:@"assets"] withIntermediateDirectories:YES attributes:nil error:NULL];
    for(NSUInteger i=0;i<17;i++)[[@"# Synthetic section\n\n$x^2+1$\n" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[root stringByAppendingPathComponent:[NSString stringWithFormat:@"section-%02lu.md",(unsigned long)i]] atomically:YES];
    for(NSUInteger i=0;i<19;i++){NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:24 pixelsHigh:24 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];memset(bitmap.bitmapData,255,bitmap.bytesPerRow*24);[[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[root stringByAppendingPathComponent:[NSString stringWithFormat:@"assets/image-%02lu.png",(unsigned long)i]] atomically:YES];}
    NSMutableDictionary *task=[app.tasks.firstObject mutableCopy];task[@"id"]=@"native-completed-check";task[@"title"]=@"Synthetic completed report";task[@"completed"]=@YES;[task removeObjectForKey:@"sourceRepository"];[task removeObjectForKey:@"courseRepository"];
    [app.tasks addObject:task];NSButton *route=NSButton.new;route.tag=2;[app navigate:route];app.filter=3;app.selectedTaskID=task[@"id"];[app render];
    // Display the real native pickers. The test supplies synthetic choices after dismissing them.
    IMP alertModal=class_getMethodImplementation(NSAlert.class,@selector(runModal));
    Replace(NSAlert.class,@selector(runModal),imp_implementationWithBlock(^NSModalResponse(NSAlert *alert){return NSAlertFirstButtonReturn;}));
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
    Replace(NSOpenPanel.class,@selector(URLs),imp_implementationWithBlock(^NSArray *(NSOpenPanel *panel){return @[[NSURL fileURLWithPath:root]];}));
    Replace(NSOpenPanel.class,@selector(URL),imp_implementationWithBlock(^NSURL *(NSOpenPanel *panel){return panel.canChooseDirectories ? [NSURL fileURLWithPath:root]:file;}));
    dispatch_suspend(courses.queue);courses.busy=YES;courses.git.readsCancellable=YES;courses.operationPhase=@"Synthetic teacher scan";
    NSButton *button=(NSButton *)AMFindButton(app.taskDetails,@selector(checkSelectedTask:),0,task[@"id"]);Check(button!=nil,@"real completed-task button present");[button performClick:nil];
    Replace(NSOpenPanel.class,@selector(runModal),modal);Replace(NSOpenPanel.class,@selector(URLs),urls);Replace(NSOpenPanel.class,@selector(URL),url);
    Wait(^BOOL{return courses.checkScope && !courses.checkScope.preparing && courses.checkScope.previewView;});
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.5]];
    for(NSString *name in @[@"light",@"dark",@"compact"]){
        courses.checkScopeWindow.appearance=[NSAppearance appearanceNamed:[name isEqual:@"dark"] ? NSAppearanceNameDarkAqua:NSAppearanceNameAqua];
        [courses.checkScopeWindow setContentSize:[name isEqual:@"compact"] ? NSMakeSize(900,620):NSMakeSize(1120,760)];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.15]];
        NSView *v=courses.checkScopeWindow.contentView;[v layoutSubtreeIfNeeded];NSBitmapImageRep *bmp=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:bmp];
        Check([[bmp representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithFormat:@"build/qa/folder-scope-%@.png",name] atomically:YES],@"scope prototype screenshot");
    }
    Check([courses.checkScopeRecords count]==37 && [[courses.checkScopeRecords filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *row,NSDictionary *bindings){return [row[@"image"] boolValue];}]] count]==19,@"37-file project including 19 images is enumerated intact");
    NSWindow *workspace=courses.checkScopeWindow;[workspace performClose:nil];Check(!workspace.visible && courses.checkScopeWindow==workspace,@"closing only hides the persistent workspace");[courses checkTask:task[@"id"]];Check(workspace.visible && pickers==1,@"repeat task action reuses workspace without picker or duplicate work");
    [courses.checkScope requestCheck];Wait(^BOOL{return courses.submission!=nil && courses.submission.window==courses.checkScopeWindow && courses.submission.window.sheetParent==nil;});
    Replace(NSAlert.class,@selector(runModal),alertModal);
    SSSubmissionController *sheet=courses.submission;
    Wait(^BOOL{return sheet.report!=nil && !sheet.checking;});
    Check(pickers==1 && app.page==2 && [app.selectedTaskID isEqual:task[@"id"]],@"native folder picker and range confirmation preserve the task page and selection");
    Check(courses.busy && sheet.checkOnly && sheet.window.sheetParent==nil && sheet.window==courses.checkScopeWindow && sheet.findings.count>0 && !sheet.submit,@"visible report completes while course queue stays suspended, without submit callback");
    for(NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){
        sheet.window.appearance=[NSAppearance appearanceNamed:appearance];[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.5]];[sheet.window.contentView layoutSubtreeIfNeeded];
        Check(!NSIsEmptyRect(sheet.window.contentView.bounds),@"report geometry remains available without image capture");
    }
    [sheet.window setContentSize:NSMakeSize(900,620)];[sheet layoutReport];
    Check(NSContainsRect(sheet.checkPage.bounds,[sheet.primary convertRect:sheet.primary.bounds toView:sheet.checkPage]) && NSMinX([sheet.findingDetail convertRect:sheet.findingDetail.bounds toView:sheet.checkPage])>=NSMaxX([sheet.findingsTable.enclosingScrollView convertRect:sheet.findingsTable.enclosingScrollView.bounds toView:sheet.checkPage]),@"workspace keeps a wide file and detail area with visible primary action");
    [@"# Changed report\n" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:NULL];[sheet pollReview:nil];Check(sheet.reportStale && !sheet.assistantButton.enabled,@"file modification marks old report stale before assistant export");
    [text writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [sheet backToFiles:nil];Wait(^BOOL{return courses.checkScopeWindow!=nil && courses.checkScopeWindow.sheetParent==nil;});Check(!courses.checkScope.preparing,@"adjust scope preserves completed enumeration and selection");[courses.checkScope requestCheck];Wait(^BOOL{return courses.submission!=nil && courses.submission!=sheet && courses.submission.report!=nil;});sheet=courses.submission;
    [sheet.primary performClick:nil];Wait(^BOOL{return courses.checkScopeWindow==nil;});
    dispatch_resume(courses.queue);courses.busy=NO;courses.git.readsCancellable=NO;
    Check([[NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:NULL] isEqual:text] && [task[@"completed"] boolValue],@"file and completed status remain unchanged");
    [app.window orderOut:nil];printf("PASS: %lu native task-check and active-scan assertions\n",(unsigned long)checks);
}return 0;}
