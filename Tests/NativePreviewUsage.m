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
    NSPredicate *weekly=[NSPredicate predicateWithFormat:@"seriesID == %@",@"preview-weekly-review"];
    Check([app.tasks filteredArrayUsingPredicate:weekly].count==8 && [[app visibleTasks] filteredArrayUsingPredicate:weekly].count==2,@"preview presents two of eight real materialized synthetic recurring tasks");
    Menu(app,@selector(showGallery:));Check(app.gallery!=nil,@"native control gallery opens from menu");
    Menu(app,@selector(showCourseSample:));Check(app.page==4 && [app.courseWindow.selectedCourseID isEqual:@"demo/physics"],@"course sample is attached to synthetic course only");
    for(NSInteger index=0;index<4;index++){app.courseWindow.sections.selectedSegment=index;[NSApp sendAction:app.courseWindow.sections.action to:app.courseWindow.sections.target from:app.courseWindow.sections];Check(app.courseWindow.sections.selectedSegment==index,@"each actual course segment remains selectable");}
    Menu(app,@selector(showSubmissionSample:));SSSubmissionController *sheet=app.courseWindow.submission;Check(sheet.window.sheetParent==app.window && sheet.checks.count==3,@"submission menu opens the real responsive file-selection sheet with synthetic changes");
    [sheet.checks[0] performClick:nil];Check([sheet.preview.string containsString:@"完整预览结束"] && sheet.preview.string.length>7000,@"file button displays the entire synthetic diff");[sheet.expandPreviewButton performClick:nil];Check(sheet.expandedText.selectable && [sheet.expandedText.string isEqual:sheet.preview.string],@"expand button opens the complete selectable preview");
    sheet.message.stringValue=@"模拟提交草稿";[sheet.filesPrimary performClick:nil];NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:5];while(sheet.checking && limit.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];Check(sheet.report && !sheet.checkPage.hidden,@"check button produces a local report without Git or network");[sheet backToFiles:nil];Check([sheet.message.stringValue isEqual:@"模拟提交草稿"] && sheet.checks[0].state==NSControlStateValueOn,@"returning to file step preserves simulated draft and choices");[sheet cancel:nil];Check(!app.courseWindow.hasUnsavedSubmission,@"explicitly cancelled draft does not produce another quit warning");
    Menu(app,@selector(showAnnotatedSample:));SSSubmissionController *annotated=app.courseWindow.submission;Check(annotated.checkOnly && annotated.findings.count==2 && annotated.documentPreview==annotated.findingDetail && [[annotated.documentPreview valueForKey:@"payload"][@"annotations"] count]==1,@"isolated annotation sample opens one reader with a version-bound image finding");[annotated cancel:nil];
    Menu(app,@selector(showTasksSample:));Check(app.page==2,@"task page can be restored through the actual menu");
    Check([app applicationShouldTerminateAfterLastWindowClosed:NSApp],@"closing the last preview window requests exit instead of leaving a hidden app");
    Menu(app,@selector(showCourseProgressSample:));Menu(app,@selector(showEditorSample:));app.editor.notesField.string=@"保留尚未保存的模拟备注";
    Check(app.exitCoordinator.operationBusy() && [(ChromePreviewCourse *)app.courseWindow showingProgressSample],@"exit regression starts with both indefinitely running preview samples");
    __block NSUInteger replies=0;__block BOOL ready=NO;
    AMQuietReplace(NSApplication.class,@selector(replyToApplicationShouldTerminate:),imp_implementationWithBlock(^(id sender,BOOL value){replies++;ready=value;}));
    [AMQuietDialogChoices addObject:@(NSAlertThirdButtonReturn)];
    Check([app applicationShouldTerminate:NSApp]==NSTerminateLater,@"preview still coordinates unsaved drafts asynchronously");
    limit=[NSDate dateWithTimeIntervalSinceNow:3];while(!replies && limit.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    Check(replies==1 && !ready && !app.exitCoordinator.pending && app.editor && [app.editor.notesField.string isEqual:@"保留尚未保存的模拟备注"],@"preview exits the simulated wait but preserves an unsaved draft when exit is cancelled");
    Check(!app.exitCoordinator.operationBusy() && ![(ChromePreviewCourse *)app.courseWindow showingProgressSample],@"both simulated progress samples are stopped without bypassing normal exit protection");
    [AMQuietDialogChoices addObject:@(NSAlertSecondButtonReturn)];
    Check([app applicationShouldTerminate:NSApp]==NSTerminateLater,@"retrying preview quit uses the normal exit coordinator");
    limit=[NSDate dateWithTimeIntervalSinceNow:3];while(replies<2 && limit.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    Check(replies==2 && ready && !app.editor,@"explicitly discarded preview draft permits quit without waiting forever");
    for(NSDictionary *operation in AMOperations())if([operation[@"state"] isEqual:@"running"])AMOperationCancel(operation[@"id"]);[app.ticker invalidate];[app.window orderOut:nil];[app.gallery.window orderOut:nil];[NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];
    printf("PASS: %lu isolated three-page preview and native gallery assertions; visual appearance awaits user screenshots\n",(unsigned long)checks);
}return 0;}
