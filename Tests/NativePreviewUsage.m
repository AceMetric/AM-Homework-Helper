#import "QuietUI.h"
#define AM_PREVIEW_NO_MAIN 1
#import "NativeChromePreview.m"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
static void Menu(ChromePreviewApp *app,SEL action){NSInteger index=[NSApp.windowsMenu indexOfItemWithTarget:app andAction:action];Check(index>=0,@"preview action is available through the actual Window menu");[NSApp.windowsMenu performActionForItemAtIndex:index];}
int main(){@autoreleasepool{
    Check(NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"]!=nil,@"preview fixture uses isolated data");
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];ChromePreviewApp *app=ChromePreviewApp.new;NSApp.delegate=app;[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
    Check(app.page==2 && app.nativeTasks.table.numberOfRows>0 && app.courseWindow.courses.count==3,@"preview starts with native task page and three synthetic courses");
    Menu(app,@selector(showGallery:));Check(app.gallery!=nil,@"native control gallery opens from menu");
    Menu(app,@selector(showCourseSample:));Check(app.page==4 && [app.courseWindow.selectedCourseID isEqual:@"demo/physics"],@"course sample is attached to synthetic course only");
    for(NSInteger index=0;index<4;index++){app.courseWindow.sections.selectedSegment=index;[NSApp sendAction:app.courseWindow.sections.action to:app.courseWindow.sections.target from:app.courseWindow.sections];Check(app.courseWindow.sections.selectedSegment==index,@"each actual course segment remains selectable");}
    Menu(app,@selector(showSubmissionSample:));SSSubmissionController *sheet=app.courseWindow.submission;Check(sheet.window.sheetParent==app.window && sheet.checks.count==3,@"submission menu opens the real responsive file-selection sheet with synthetic changes");
    [sheet.checks[0] performClick:nil];Check([sheet.preview.string containsString:@"完整预览结束"] && sheet.preview.string.length>7000,@"file button displays the entire synthetic diff");[sheet.expandPreviewButton performClick:nil];Check(sheet.expandedText.selectable && [sheet.expandedText.string isEqual:sheet.preview.string],@"expand button opens the complete selectable preview");
    sheet.message.stringValue=@"模拟提交草稿";[sheet.filesPrimary performClick:nil];NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:5];while(sheet.checking && limit.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];Check(sheet.report && !sheet.checkPage.hidden,@"check button produces a local report without Git or network");[sheet backToFiles:nil];Check([sheet.message.stringValue isEqual:@"模拟提交草稿"] && sheet.checks[0].state==NSControlStateValueOn,@"returning to file step preserves simulated draft and choices");[sheet cancel:nil];
    Menu(app,@selector(showTasksSample:));Check(app.page==2,@"task page can be restored through the actual menu");
    for(NSDictionary *operation in AMOperations())if([operation[@"state"] isEqual:@"running"])AMOperationCancel(operation[@"id"]);[app.ticker invalidate];[app.window orderOut:nil];[app.gallery.window orderOut:nil];[NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];
    printf("PASS: %lu isolated three-page preview and native gallery assertions; visual appearance awaits user screenshots\n",(unsigned long)checks);
}return 0;}
