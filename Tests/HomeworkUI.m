#import "QuietUI.h"
// Synthetic UI scenarios only: no account, repository, persistence or notifications.
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
#import "../Sources/SSAssignments.h"
static NSUInteger checks;
static void Check(BOOL condition, NSString *label) { checks++; if (!condition) { fprintf(stderr, "FAIL: %s\n", label.UTF8String); exit(1); } }
static void Await(BOOL (^finished)(void)) {
    // A cold WebKit process can use the renderer's 12-second timeout on CI.
    NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:20];while(!finished() && limit.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    Check(finished(),@"asynchronous UI operation completes within its renderer allowance");
}
static void Capture(NSView *view, NSString *path) {
    (void)path;[view layoutSubtreeIfNeeded];Check(!NSIsEmptyRect(view.bounds),@"synthetic form lays out without image capture");
}
static void Route(AppDelegate *app, NSInteger page) { NSButton *button = NSButton.new; button.tag = page; [app navigate:button]; }
@interface FailedReviewApp : AppDelegate @end
@implementation FailedReviewApp
- (BOOL)replaceTasks:(NSArray *)tasks action:(NSString *)action error:(NSError **)error {if(error)*error=[NSError errorWithDomain:@"Fixture" code:1 userInfo:@{NSLocalizedDescriptionKey:@"模拟存储失败"}];return NO; }
@end
int main(void) { @autoreleasepool {
    if (![NSProcessInfo.processInfo.arguments containsObject:@"--preview"]) return 2;
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    AppDelegate *app = AppDelegate.new; NSApp.delegate = app; [app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
    SSCourseController *courses = app.courseWindow;
    Check(app.preview && courses.preview && !courses.timer && !courses.connected, @"preview never reads Keychain or starts real checks");
    Route(app, 4); Check(courses.view.window == app.window && courses.visible.count == 0, @"empty courses are embedded in main window");
    Check([courses.setupButton.title isEqual:@"连接 GitHub"] && [courses.emptyLabel.stringValue containsString:@"添加"], @"first use has explanation and next step");
    NSMutableDictionary *course = [@{@"fork":@"student/physics", @"upstream":@"teacher/physics", @"branch":@"main", @"upstreamBranch":@"main", @"enabled":@YES} mutableCopy];
    NSMutableDictionary *other = [@{@"fork":@"student/math", @"upstream":@"teacher/math", @"branch":@"main", @"upstreamBranch":@"main", @"enabled":@YES, @"path":@"/synthetic/math"} mutableCopy];
    [courses.courses addObjectsFromArray:@[course, other]]; [courses selectCourseID:course[@"fork"]]; courses.connected = YES; [courses refreshCourses];
    Check([courses.setupButton.title isEqual:@"关联文件夹…"] && !courses.syncButton.enabled && !courses.scanButton.enabled, @"unlinked course provides folder setup and blocks Git actions");
    // Exercise the real task-detail button, not only the course controller method.
    NSArray *tasksBeforeCheck=app.snapshot;NSUInteger pageBeforeCheck=app.page;
    NSMutableDictionary *checkTask=[tasksBeforeCheck.firstObject mutableCopy];
    checkTask[@"id"]=@"task-check-route";checkTask[@"courseRepository"]=course[@"fork"];
    [app.tasks addObject:checkTask];Route(app,2);app.selectedTaskID=checkTask[@"id"];[app render];
    NSButton *checkButton=NSButton.new;checkButton.identifier=checkTask[@"id"];checkButton.target=app;checkButton.action=@selector(checkSelectedTask:);
    Check(app.editor.sharedForm.actionHandler!=nil,@"shared task form exposes its contextual file check action");
    courses.busy=YES;courses.operationPhase=@"正在推送个人仓库";Check([courses taskCheckBlockReason]==nil,@"Git writes no longer block opening a check workspace; reads queue at the write barrier");courses.busy=NO;
    // File chooser adapter supplies only synthetic files; the production check service still runs.
    NSString *checkRoot=[NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"] stringByAppendingPathComponent:@"task-check-fixture"];
    [NSFileManager.defaultManager createDirectoryAtPath:checkRoot withIntermediateDirectories:YES attributes:nil error:NULL];
    NSURL *reportURL=[NSURL fileURLWithPath:[checkRoot stringByAppendingPathComponent:@"report.md"]];
    NSString *reportText=@"# Report\n![missing illustration](missing.png)\n";
    [reportText writeToURL:reportURL atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    IMP modalBefore=class_getMethodImplementation(NSOpenPanel.class,@selector(runModal));
    IMP urlsBefore=class_getMethodImplementation(NSOpenPanel.class,@selector(URLs));
    IMP urlBefore=class_getMethodImplementation(NSOpenPanel.class,@selector(URL));
    __block NSUInteger foldersPicked=0,filesPicked=0;__block BOOL cancelPicker=NO;
    AMQuietReplace(NSOpenPanel.class,@selector(runModal),imp_implementationWithBlock(^NSModalResponse(NSOpenPanel *panel){if(panel.canChooseDirectories)foldersPicked++;else filesPicked++;return cancelPicker ? NSModalResponseCancel:NSModalResponseOK;}));
    AMQuietReplace(NSOpenPanel.class,@selector(URLs),imp_implementationWithBlock(^NSArray *(NSOpenPanel *panel){return @[reportURL];}));
    AMQuietReplace(NSOpenPanel.class,@selector(URL),imp_implementationWithBlock(^NSURL *(NSOpenPanel *panel){return panel.canChooseDirectories ? [NSURL fileURLWithPath:checkRoot]:reportURL;}));
    [checkTask removeObjectForKey:@"courseRepository"];[checkTask removeObjectForKey:@"sourceRepository"];
    Route(app,2);app.selectedTaskID=checkTask[@"id"];[app render];
    // Reproduce a long automatic scan: its course queue remains occupied throughout the check.
    dispatch_suspend(courses.queue);courses.busy=YES;courses.git.readsCancellable=YES;courses.operationPhase=@"正在扫描老师文档";
    checkTask[@"completed"]=@YES;app.filter=3;[app render];
    checkButton.identifier=checkTask[@"id"];if(app.editor.sharedForm)app.editor.sharedForm.actionHandler(@"check",app.editor.sharedForm.snapshot);else [checkButton performClick:nil];
    Await(^BOOL{return courses.checkScope && !courses.checkScope.preparing;});
    [courses.checkScope requestCheck];Await(^BOOL{return courses.submission && courses.submission.window==courses.checkScopeWindow && !courses.submission.window.sheetParent;});
    SSSubmissionController *taskCheckSheet=courses.submission;
    Check(foldersPicked==1 && filesPicked==0 && taskCheckSheet.checkOnly && !app.window.attachedSheet && courses.checkScopeWindow==taskCheckSheet.window && !taskCheckSheet.submit,@"task detail opens independent check-only workspace with no submit callback");
    Await(^BOOL{return !taskCheckSheet.checking && taskCheckSheet.report!=nil;});
    Check(app.page==2 && [app.selectedTaskID isEqual:checkTask[@"id"]] && courses.busy && [checkTask[@"completed"] boolValue],@"completed task opens its report in place during an ongoing teacher scan");
    Check(!taskCheckSheet.hasUnsavedChanges,@"preselected scope and associated task do not create an unsaved draft warning");
    Check(taskCheckSheet.report && !taskCheckSheet.checkPage.hidden && taskCheckSheet.findings.count>0 && [taskCheckSheet.snapshot[@"paths"] isEqual:@[@"report.md"]],@"actual task button through file selection produces the real missing-image report");
    NSDictionary *localCourse=@{@"fork":@"student/fixture",@"branch":@"main",@"path":checkRoot,@"preflightMode":@"working",@"preflightLocal":@YES};
    SSSubmissionController *parallel=[[SSSubmissionController alloc] initWithCourse:localCourse changes:@[@{@"path":@"report.md",@"status":@"M",@"sensitive":@NO}]];[courses configurePreflight:parallel course:localCourse tasks:@[]];parallel.message.stringValue=@"Synthetic submission check";[parallel.checks[0] performClick:nil];[parallel.filesPrimary performClick:nil];Await(^BOOL{return !parallel.checking && parallel.report!=nil;});Check(parallel.report && !parallel.checkPage.hidden && courses.busy,@"submission Next reaches real local report while the teacher scan queue remains suspended");[parallel cancel:nil];
    courses.git.readsCancellable=NO;dispatch_semaphore_t writeStarted=dispatch_semaphore_create(0),writeReleased=dispatch_semaphore_create(0);
    AMOperationEnqueue(@"synthetic-write",@"模拟写入",@"fixture",@[@"git-write"],100,^(NSString *identifier){dispatch_semaphore_signal(writeStarted);dispatch_semaphore_wait(writeReleased,DISPATCH_TIME_FOREVER);AMOperationFinish(identifier,@"success",@"");},nil);
    Check(dispatch_semaphore_wait(writeStarted,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC))==0,@"synthetic Git write owns the shared barrier");
    SSSubmissionController *writing=[[SSSubmissionController alloc] initWithCourse:localCourse changes:@[@{@"path":@"report.md",@"status":@"M",@"sensitive":@NO}]];[courses configurePreflight:writing course:localCourse tasks:@[]];writing.message.stringValue=@"Keep while writing";[writing.checks[0] performClick:nil];[writing.filesPrimary performClick:nil];
    Await(^BOOL{return AMQueuedOperationCount()>0;});Check(writing.checking && !writing.report && [writing.message.stringValue isEqual:@"Keep while writing"],@"concurrent write queues inspection and preserves inputs");
    dispatch_semaphore_signal(writeReleased);Await(^BOOL{return !writing.checking;});Check(writing.report!=nil,@"queued local inspection resumes when the write completes");[writing cancel:nil];courses.git.readsCancellable=YES;

    [taskCheckSheet.primary performClick:nil];Check(!app.window.attachedSheet && taskCheckSheet.closed,@"check-only completion closes without committing or pushing");
    Check([[NSString stringWithContentsOfURL:reportURL encoding:NSUTF8StringEncoding error:NULL] isEqual:reportText],@"task check leaves the selected file unchanged");
    courses.submission=nil;dispatch_resume(courses.queue);courses.busy=NO;courses.git.readsCancellable=NO;
    courses.operationsPaused=YES;
    checkButton.identifier=checkTask[@"id"];Check(checkButton!=nil,@"task check remains available for an actionable pause explanation");[AMQuietDialogChoices addObject:@(NSAlertFirstButtonReturn)];if(app.editor.sharedForm)app.editor.sharedForm.actionHandler(@"check",app.editor.sharedForm.snapshot);else [checkButton performClick:nil];
    Check(!courses.submission && [[courses taskCheckBlockReason] containsString:@"更新"] && AMQuietDialogChoices.count==0,@"exit or update still prevents a new check and explains why");courses.operationsPaused=NO;
    cancelPicker=YES;Route(app,2);app.selectedTaskID=checkTask[@"id"];[app render];
    checkButton.identifier=checkTask[@"id"];if(app.editor.sharedForm)app.editor.sharedForm.actionHandler(@"check",app.editor.sharedForm.snapshot);else [checkButton performClick:nil];
    Check(!courses.submission && !app.window.attachedSheet,@"cancelled task file selection opens no check or submission");
    AMQuietReplace(NSOpenPanel.class,@selector(runModal),modalBefore);AMQuietReplace(NSOpenPanel.class,@selector(URLs),urlsBefore);AMQuietReplace(NSOpenPanel.class,@selector(URL),urlBefore);
    app.tasks=tasksBeforeCheck.mutableCopy;app.filter=0;Route(app,pageBeforeCheck);[courses selectCourseID:course[@"fork"]];
    course[@"path"] = @"/synthetic/physics"; course[@"lastScan"] = NSDate.date; [courses refreshCourses];
    Check(courses.syncButton.enabled && courses.commitButton.enabled && [courses.accountLabel.stringValue containsString:@"上次成功检查"], @"linked course displays readiness and last check");
    Check([courses.emptyLabel.stringValue isEqual:@"暂无待审核作业"] && courses.scanButton.enabled && !courses.scanButton.hidden && courses.scanButton.action==@selector(scan:), @"empty result keeps a direct working check action without a tutorial sentence");
    NSDate *due = DDLParseDate(@"2026-10-08 23:59", NSDate.date, Cal());
    NSDictionary *candidate = @{@"id":@"teacher/physics|README.md|作业一|1", @"title":@"作业一 · 实验报告", @"due":due, @"repository":@"teacher/physics", @"path":@"README.md", @"line":@12, @"blobSHA":@"version1", @"timeZone":@"Asia/Shanghai", @"needsDate":@NO, @"needsTime":@NO, @"snippet":@"## 作业一 · 实验报告\n截止时间：2026-10-08 23:59\n提交实验报告和源代码。"};
    NSMutableDictionary *math = candidate.mutableCopy; math[@"id"] = @"math-homework"; math[@"repository"] = @"teacher/math"; math[@"title"] = @"数学 · 习题练习";
    courses.candidates[course[@"fork"]] = @[candidate]; courses.candidates[other[@"fork"]] = @[math]; [courses refreshCourses];
    Route(app, 3); Check(courses.visible.count == 2 && courses.pendingCount == 2, @"inbox aggregates all courses and pending count");
    [courses.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    Check([courses.detail.string containsString:@"README.md:12"], @"selection previews original wording and file location");
    courses.query = @"数学"; [courses refreshPresentation]; Check(courses.visible.count == 1 && courses.table.selectedRow == -1, @"search filters without moving selection onto another assignment");
    courses.query = @""; [courses refreshPresentation]; NSUInteger before = app.tasks.count;
    [app reviewGitHubCandidate:candidate];
    Check(app.editor && app.tasks.count == before && [app.editor.window.title isEqual:@"审核作业"], @"review opens unified sheet without silent import");
    Check(app.editor.deadlineField != nil && app.editor.sourceScroll != nil && [app.editor.task[@"sourceID"] isEqual:candidate[@"id"]], @"review includes one deadline, original text and provenance");
    [app.editor save:nil];
    Check(app.tasks.count == before + 1 && courses.pendingCount == 1 && courses.visible.count == 1, @"save imports and updates inbox count immediately");
    Check(app.tasks.lastObject[@"_reviewCandidate"] == nil && app.tasks.lastObject[@"_existing"] == nil, @"editor-only metadata never persists");
    [courses.reviewFilter selectItemAtIndex:2]; [courses refreshPresentation]; Check(courses.visible.count == 0, @"reviewed results are excluded even from update filter");
    [courses.reviewFilter selectItemAtIndex:0];
    NSMutableDictionary *saved = app.tasks.lastObject; saved[@"due"] = [due dateByAddingTimeInterval:-3 * 3600]; saved[@"leadDays"] = @(-1); saved[@"title"] = @"我的自定义标题";
    NSMutableDictionary *updated = candidate.mutableCopy; updated[@"blobSHA"] = @"version2"; updated[@"due"] = [due dateByAddingTimeInterval:86400]; courses.candidates[course[@"fork"]] = @[updated]; [courses refreshPresentation];
    Check(courses.pendingCount == 2 && [[courses stateForCandidate:updated] isEqual:@"有更新"], @"changed original becomes update suggestion");
    [app reviewGitHubCandidate:updated];
    Check([app.editor.task[@"due"] isEqual:saved[@"due"]] && [app.editor.task[@"title"] isEqual:@"我的自定义标题"] && [app.editor.window.title isEqual:@"审核更新"], @"updates preserve manually edited title and deadline");
    Check([saved[@"sourceBlobSHA"] isEqual:@"version1"], @"cancelable review never overwrites source version"); [app closeEditor];
    NSDictionary *weekly = [SSAssignmentsFromDocument(@"# 规则\n- 截止时间：本周日 21:00\n# 任务\n完成附件作业：运动学基础和牛顿定律。", @"teacher/physics", @"assignment-04.md", @"v1", NSDate.date, Cal()) firstObject];
    courses.candidates[course[@"fork"]] = @[weekly]; [courses refreshPresentation]; [app reviewGitHubCandidate:weekly]; before = app.tasks.count;
    Check(app.editor.deadlineField.stringValue.length == 0 && [app.editor.candidate[@"snippet"] containsString:@"牛顿定律"], @"relative date stays unresolved with assignment context");
    [app.editor save:nil]; Check(app.tasks.count == before && [app.editor.validation.stringValue containsString:@"完整"], @"relative date cannot save until completed");
    [app.editor updateDate:DDLParseDate(@"2026-10-11 21:00",NSDate.date,Cal())]; Check([app.editor validateAssignmentDate], @"explicit teacher date accepted inside same sheet"); [app.editor save:nil];
    Check(app.tasks.count == before + 1 && [app.tasks.lastObject[@"due"] isEqual:DDLParseDate(@"2026-10-11 21:00", NSDate.date, Cal())], @"confirmed relative assignment uses one explicit deadline");
    NSMutableDictionary *suggested = [SSApplyDateReference(weekly, DDLParseDate(@"2026-10-05 09:00", NSDate.date, Cal()), @"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", Cal()) mutableCopy]; suggested[@"id"] = @"suggested-relative-qa";
    courses.candidates[course[@"fork"]] = @[suggested]; [app reviewGitHubCandidate:suggested]; before = app.tasks.count;
    Check([app.editor.deadlineField.stringValue isEqual:@"2026-10-11 21:00"] && [app.editor validateAssignmentDate], @"verified suggestion automatically prefills single deadline");
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]; [app refreshAppearance];
    Check([app.editor.deadlineField.stringValue isEqual:@"2026-10-11 21:00"], @"appearance switch preserves automatically filled date"); [app closeEditor];
    Check(app.tasks.count == before, @"canceling prefilled suggestion does not import a task");
    courses.candidates[course[@"fork"]] = @[weekly]; [courses refreshPresentation];
    NSDictionary *dateOnly = SSAssignmentsFromDocument(@"# 作业五\n截止：2027年4月14日", @"teacher/physics", @"a.md", @"date-only", NSDate.date, Cal()).firstObject;
    [app reviewGitHubCandidate:dateOnly]; Check([app.editor.deadlineField.stringValue isEqual:@"2027-04-14"], @"date-only civil date remains visible while time is missing");
    [app.editor save:nil]; Check(app.tasks.count == before && app.editor != nil, @"date-only cannot silently save as 23:59"); [app closeEditor];
    NSArray *exams = SSGroupMaterials(SSDiscoveriesFromDocument(@"# 问题一\n请分析并解答。", @"teacher/physics", @"intro_exam/Q1_assignment.md", @"exam-v1", NSDate.date, Cal()));
    courses.materials[course[@"fork"]] = exams; NSUInteger pending = courses.pendingCount;
    Route(app, 4); courses.sections.selectedSegment = 0; [courses.typeFilter selectItemAtIndex:3]; [courses refreshPresentation];
    Check(courses.visible.count == 1 && [courses.visible[0][@"kind"] isEqual:@"exam"], @"course type filter shows exam materials");
    [courses.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    Check(!courses.reviewButton.enabled && courses.typeButton.enabled && [courses.detail.string containsString:@"考试"], @"exam preview has classification but no homework import action");
    [courses review:nil]; [app reviewGitHubCandidate:exams.firstObject]; Check(!app.editor && app.tasks.count == before, @"both review entry points refuse exam import");
    Route(app, 3); Check(courses.pendingCount == pending && courses.visible.count == 1, @"exam adds no pending homework or DDL tasks");
    Check([courses setKind:@"assignment" forDiscovery:exams.firstObject error:nil] && courses.pendingCount == pending + 1, @"manual classification to homework enters review immediately");
    NSMutableDictionary *revisedExam = [exams.firstObject mutableCopy]; revisedExam[@"blobSHA"] = @"exam-v2"; courses.materials[course[@"fork"]] = @[revisedExam]; [courses refreshPresentation];
    Check([[[courses discoveriesForFork:course[@"fork"]] lastObject][@"kind"] isEqual:@"assignment"], @"manual type correction survives changed source version");
    [courses setKind:@"exam" forDiscovery:revisedExam error:nil]; [courses.typeFilter selectItemAtIndex:0];
    Route(app, 4); courses.sections.selectedSegment = 1; [courses refreshPresentation]; Check(courses.visible.count == 2 && [courses.visible.firstObject[@"confirmed"] boolValue], @"course shows already-added tasks");
    courses.sections.selectedSegment = 0; course[@"pendingMergeTip"] = @"synthetic-merge"; course[@"pendingConflicts"] = @[@"answers.md"]; [courses refreshPresentation];
    Check(!courses.recoveryButton.hidden && [courses.recoveryButton.title containsString:@"冲突"], @"conflicts expose recovery entry");
    [course removeObjectForKey:@"pendingMergeTip"]; [course removeObjectForKey:@"pendingConflicts"]; course[@"pushFailed"] = @YES; [courses refreshPresentation]; Check([courses.recoveryButton.title isEqual:@"重试推送"], @"failed push exposes retry");
    courses.busy = YES; courses.operationFork = course[@"fork"]; courses.statuses[course[@"fork"]] = @"正在合并老师更新…"; courses.selectedFork = other[@"fork"]; [courses refreshCourses];
    Check([courses.statusLabel.stringValue containsString:@"student/physics"] && courses.commitButton.enabled && courses.courseSnapshots.count == 2, @"browsing another course retains operation target and permits queued actions"); courses.busy = NO;
    SSSubmissionController *submission = [[SSSubmissionController alloc] initWithCourse:course changes:@[@{@"path":@"answers.md", @"status":@" M", @"sensitive":@NO}, @{@"path":@".env", @"status":@"??", @"sensitive":@YES}]];
    [submission configureTasks:@[@{@"id":@"related-task",@"title":@"关联模拟作业"},@{@"id":@"other-task",@"title":@"另一份模拟作业"}] selected:@[@"related-task"]];
    Check(submission.taskChecks[0].state==NSControlStateValueOn && submission.taskChecks[1].state==NSControlStateValueOff && NSMinY([submission.fileListScroll convertRect:submission.fileListScroll.bounds toView:submission.filesPage])>=NSMaxY(submission.taskSection.frame),@"task association does not overlap file controls or select files");
    Check(submission.checks[0].state == NSControlStateValueOff && !submission.checks[1].enabled, @"submission defaults unchecked and excludes sensitive files");
    __block NSArray *selected; submission.submit = ^(NSArray *paths, NSString *message) { selected = paths; }; [submission save:nil]; Check(selected == nil, @"empty submission is blocked");
    submission.performCheck=^NSDictionary *(NSArray *paths,NSArray *ids,NSString *extra,NSMutableDictionary *cache,BOOL(^cancelled)(void),NSError **error){return @{@"snapshot":@{},@"requirements":@"",@"report":@{@"version":@"fixture",@"issues":@[],@"coverage":@[],@"images":@[]}};};
    submission.checks[0].state=NSControlStateValueOn;submission.message.stringValue=@"完成作业";[submission save:nil];NSDate *reviewLimit=[NSDate dateWithTimeIntervalSinceNow:5];while(submission.checking && reviewLimit.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];Check(submission.report && !selected,@"file selection proceeds to check, not implicit submission");submission.acknowledge.state=NSControlStateValueOn;[submission save:nil];reviewLimit=[NSDate dateWithTimeIntervalSinceNow:5];while(submission.checking && reviewLimit.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];Check([selected isEqual:@[@"answers.md"]],@"only explicitly selected and checked files leave submission sheet");
    Check([submission.taskIDs isEqual:@[@"related-task"]],@"explicit task association accompanies submission");
    submission.readPreview = ^(NSString *file, void (^ready)(NSString *)) { ready([@"diff preview: " stringByAppendingString:file]); };
    NSButton *previewButton = NSButton.new; previewButton.tag = 0; [submission showPreview:previewButton]; Check([submission.preview.string containsString:@"answers.md"], @"selected file preview is delivered to sheet");
    courses.preview = NO; courses.selectedFork = course[@"fork"]; __block BOOL finished = NO; __block NSDictionary *captured = course.copy;
    dispatch_semaphore_t capturedRelease=dispatch_semaphore_create(0);
    [courses work:@"模拟操作" forCourse:captured operation:^id(NSError **error) {dispatch_semaphore_wait(capturedRelease,DISPATCH_TIME_FOREVER);return captured[@"fork"]; } completion:^(NSString *result, NSError *error) { Check([result isEqual:@"student/physics"] && [courses.statusFork isEqual:@"student/physics"], @"completion remains bound to captured course after selection changes"); [courses status:@"模拟完成"]; finished = YES; }];
    courses.selectedFork = other[@"fork"]; [courses refreshCourses];
    Await(^BOOL{return courses.busy;});Check(courses.setupButton.enabled && courses.syncButton.enabled && courses.commitButton.enabled,@"background work keeps user actions available for queueing");dispatch_semaphore_signal(capturedRelease);
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:3]; while (!finished && limit.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    Check(finished && [courses.statuses[@"student/physics"] isEqual:@"模拟完成"] && !courses.busy, @"result stored against initiating course"); courses.preview = YES;
    courses.preview=YES;Route(app,4);[courses selectCourseID:course[@"fork"]];
    courses.query=@"物理筛选";courses.sections.selectedSegment=2;[courses.typeFilter selectItemAtIndex:2];
    Check([courses selectCourseID:other[@"fork"]] && courses.query.length==0,@"switch course resets only new course view state");
    Check([courses selectCourseID:course[@"fork"]] && [courses.query isEqual:@"物理筛选"] && courses.sections.selectedSegment==2 && courses.typeFilter.indexOfSelectedItem==2,@"course retains its own query, section and type");
    [courses selectCourseID:nil];Check(courses.syncButton.hidden && courses.commitButton.hidden && [courses.scanButton.title isEqual:@"检查所有课程"],@"all-courses view has no ambiguous sync or submit target");
    Check(courses.courseWorkspace.view.superview!=nil && !courses.courseWorkspace.view.hidden && courses.table.enclosingScrollView.hidden,@"SwiftUI course details replace visible legacy table");
    Check(app.navigationController.outline.numberOfRows>=7,@"main sidebar expands course entries without second sidebar");
    courses.query=@"";courses.sections.selectedSegment=0;[courses.typeFilter selectItemAtIndex:0];[courses selectCourseID:course[@"fork"]];
    // Actual keyboard equivalents on the shared sheet, with no persistence in preview mode.
    [app addTask:nil]; app.editor.titleField.stringValue = @"键盘保存模拟任务"; [app.editor updateDate:DDLParseDate(@"明天 21:00", NSDate.date, Cal())]; before = app.tasks.count;
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]]; [app.editor.window makeKeyWindow];
    NSEvent *returnKey = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:app.editor.window.windowNumber context:nil characters:@"\r" charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:36];
    BOOL handled = [app.editor.window performKeyEquivalent:returnKey];
    Check(handled && app.tasks.count == before + 1, @"Return saves through actual sheet key equivalent");
    [app addTask:nil]; [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]]; [app.editor.window makeKeyWindow]; before = app.tasks.count; NSEvent *escapeKey = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:app.editor.window.windowNumber context:nil characters:@"\033" charactersIgnoringModifiers:@"\033" isARepeat:NO keyCode:53];
    Check([app.editor.window performKeyEquivalent:escapeKey] && !app.editor && app.tasks.count == before, @"Escape cancels without creating a task");
    // One session follows the current filter, saves individually and never loops over deferred items.
    NSDictionary *originalCandidates = courses.candidates.copy; NSArray *originalTasks = app.snapshot;
    NSMutableDictionary *one = candidate.mutableCopy, *two = candidate.mutableCopy, *three = dateOnly.mutableCopy;
    one[@"id"] = @"queue-one"; one[@"title"] = @"连续审核一"; two[@"id"] = @"queue-two"; two[@"title"] = @"连续审核二"; three[@"id"] = @"queue-three"; three[@"title"] = @"连续审核三";
    courses.candidates[course[@"fork"]] = @[one, two, three]; courses.candidates[other[@"fork"]] = @[math];
    Route(app, 3); courses.selectedFork = course[@"fork"]; courses.query = @"连续"; [courses.reviewFilter selectItemAtIndex:0]; [courses refreshPresentation];
    [courses.table deselectAll:nil]; [courses candidateSelected:nil];
    Check([courses.reviewButton.title isEqual:@"开始审核…"] && courses.reviewButton.enabled, @"start-review action does not require selecting each row");
    [courses review:nil]; Check(!app.editor && !app.window.attachedSheet, @"review entry selects inline details without sheet");
    [app reviewGitHubCandidate:courses.pendingReviewCandidates.firstObject]; before = app.tasks.count;
    Check(app.editor.reviewQueue.count == 3 && [app.editor.reviewProgress.stringValue containsString:@"3"], @"session captures only pending homework in current course and search");
    [app.editor saveAndReviewNext:nil]; Await(^BOOL{return app.tasks.count==before+1 && [app.editor.candidate[@"id"] isEqual:two[@"id"]];});
    if(app.tasks.count != before+1 || ![app.editor.candidate[@"id"] isEqual:two[@"id"]])fprintf(stderr,"queue diagnostic: before=%lu after=%lu next=%s validation=%s\n",(unsigned long)before,(unsigned long)app.tasks.count,[app.editor.candidate[@"id"] UTF8String],app.editor.validation.stringValue.UTF8String);
    Check(app.tasks.count == before + 1 && [app.editor.candidate[@"id"] isEqual:two[@"id"]], @"save-and-next imports one task and opens the next without a list round trip");
    app.editor.titleField.stringValue = @""; [app.editor saveAndReviewNext:nil];
    Check([app.editor.candidate[@"id"] isEqual:two[@"id"]] && app.tasks.count == before + 1, @"invalid review cannot advance or import another task");
    app.editor.titleField.stringValue = two[@"title"]; [app.editor deferReview:nil]; Await(^BOOL{return [app.editor.candidate[@"id"] isEqual:three[@"id"]];});
    BOOL deferredStillPending = [courses.pendingReviewCandidates indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) { return [item[@"id"] isEqual:two[@"id"]]; }] != NSNotFound;
    Check([app.editor.candidate[@"id"] isEqual:three[@"id"]] && deferredStillPending, @"defer moves to next and retains unimported homework in inbox");
    [app.editor saveAndReviewNext:nil]; Check(app.editor != nil && app.tasks.count == before + 1, @"continuous review still requires a missing teacher time");
    [app.editor updateDate:DDLParseDate(@"2027-04-14 20:00",NSDate.date,Cal())];
    NSEvent *reviewReturn = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:app.editor.window.windowNumber context:nil characters:@"\r" charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:36];
    Check([app.editor.window performKeyEquivalent:reviewReturn], @"Return invokes save-and-next in review sheet");
    Await(^BOOL{return !app.editor && [app.notice containsString:@"本轮审核已结束"];});
    Check(!app.editor && app.tasks.count == before + 2 && [app.notice containsString:@"本轮审核已结束"], @"session ends without immediately reopening deferred homework");
    Check(courses.pendingReviewCandidates.count == 1 && [courses.pendingReviewCandidates.firstObject[@"id"] isEqual:two[@"id"]], @"other-course homework and exams never enter the filtered session");
    [app reviewGitHubCandidate:two]; NSUInteger pendingBeforeCancel = courses.pendingReviewCandidates.count; [app.editor cancel:nil];
    Check(!app.editor && courses.pendingReviewCandidates.count == pendingBeforeCancel, @"cancel ends session without marking the pending item imported");
    FailedReviewApp *failed = FailedReviewApp.new; failed.preview = YES; failed.courseWindow = courses; failed.window = app.window;failed.tasks=app.tasks.mutableCopy;
    failed.editor = [[EditorController alloc] initWithTask:@{@"_reviewCandidate":two, @"title":two[@"title"], @"due":due, @"announcedDue":due, @"leadDays":@0} owner:failed];
    failed.editor.reviewQueue = @[one[@"id"], two[@"id"]]; EditorController *failedSheet = failed.editor; [failedSheet saveAndReviewNext:nil];
    Check(failed.editor == failedSheet && [failedSheet.validation.stringValue containsString:@"存储失败"], @"persistence failure leaves current input and queue intact");
    [failedSheet.window orderOut:nil]; failed.editor = nil;
    courses.operationsPaused = YES; [app continueReviewQueue:@[one[@"id"], two[@"id"]] after:one[@"id"]];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    Check(!app.editor, @"pending exit or update cannot reopen the next review sheet"); courses.operationsPaused = NO;
    app.tasks = [originalTasks mutableCopy]; courses.candidates = [originalCandidates mutableCopy]; courses.query = @""; courses.selectedFork = nil; [courses refreshPresentation];
    for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        NSApp.appearance = [NSAppearance appearanceNamed:appearance]; [app refreshAppearance]; NSString *name = [appearance isEqual:NSAppearanceNameAqua] ? @"light" : @"dark";
        Route(app, 0); Capture(app.root, [NSString stringWithFormat:@"build/qa/overview-%@.png", name]);
        Route(app, 3); [courses.reviewFilter selectItemAtIndex:1]; [courses refreshPresentation]; Capture(app.root, [NSString stringWithFormat:@"build/qa/review-%@.png", name]);
        Route(app, 4); [courses selectCourseID:course[@"fork"]]; courses.query=@"";courses.search.stringValue=@"";courses.sections.selectedSegment=0;[courses.typeFilter selectItemAtIndex:0];courses.selectedCandidateID=exams.firstObject[@"id"];[courses refreshPresentation];
        Capture(app.root, [NSString stringWithFormat:@"build/qa/courses-%@.png", name]);
        [courses.typeFilter selectItemAtIndex:3]; [courses refreshPresentation]; Capture(app.root, [NSString stringWithFormat:@"build/qa/materials-%@.png", name]);
        [app.window setContentSize:NSMakeSize(960,640)];[app layout];Capture(app.root,[NSString stringWithFormat:@"build/qa/course-compact-%@.png",name]);[app.window setContentSize:NSMakeSize(1280,840)];[app layout];[courses.typeFilter selectItemAtIndex:0];
        [app reviewGitHubCandidate:suggested]; Capture(app.editor.window.contentView, [NSString stringWithFormat:@"build/qa/review-editor-%@.png", name]); [app closeEditor];
        courses.setupRecords=[@[[ @{@"fork":@"student/physics",@"existing":@YES} mutableCopy],[ @{@"fork":@"student/mathematics",@"existing":@NO} mutableCopy],[ @{@"fork":@"student/computing",@"existing":@NO} mutableCopy]] mutableCopy];
        courses.github.authType=@"githubCLI";courses.setupStep=0;[courses presentCourseSetup];courses.loginChallenge=@{@"user_code":@"ABCD-EFGH"};[courses updateCourseSetup:@"模拟验证码：不会进行实际登录。"];Capture(courses.setupWindow.contentView,[NSString stringWithFormat:@"build/qa/setup-login-%@.png",name]);courses.loginChallenge=nil;courses.setupStep=1;[courses updateCourseSetup:@"选择课程后逐门核验。"];Capture(courses.setupWindow.contentView,[NSString stringWithFormat:@"build/qa/setup-selection-%@.png",name]);Check(!courses.hasUnsavedReview,@"opening prefilled configuration is window state, not an unsaved edit");
        courses.setupStep=2;courses.setupRecords=[@[[ @{@"fork":@"student/physics",@"path":@"课程目录/物理",@"ready":@YES,@"status":@"已关联，老师仓库读取正常。"} mutableCopy],[ @{@"fork":@"student/mathematics",@"matches":@[@"课程目录/数学",@"备份目录/数学"],@"status":@"找到多个仓库，请选择使用的目录。"} mutableCopy],[ @{@"fork":@"student/computing",@"invalid":@YES,@"status":@"当前账户没有该课程的读取权限，请核对课程或完成学校 SSO。",@"helpURL":@"https://github.com/orgs/example-school/sso"} mutableCopy]] mutableCopy];
        [courses updateCourseSetup:@"成功结果已保留，未完成课程可稍后继续。"];Capture(courses.setupWindow.contentView,[NSString stringWithFormat:@"build/qa/setup-folders-%@.png",name]);courses.setupStep=3;[courses updateCourseSetup:@"首次检查完成，失败课程可以单独处理。"];Capture(courses.setupWindow.contentView,[NSString stringWithFormat:@"build/qa/setup-results-%@.png",name]);courses.setupStep=4;[courses updateCourseSetup:@""];Capture(courses.setupWindow.contentView,[NSString stringWithFormat:@"build/qa/setup-tips-%@.png",name]);[courses closeCourseSetup];Check(!courses.setupWindow,@"cancelling setup closes only configuration sheet");
        [submission selectionChanged:nil];
        Capture(submission.window.contentView, [NSString stringWithFormat:@"build/qa/submit-%@.png", name]); [submission.window orderOut:nil];
    }
    [app.window setContentSize:NSMakeSize(960, 640)]; [app layout];
    Check(NSMaxY(courses.table.enclosingScrollView.frame) <= NSMinY(courses.detail.enclosingScrollView.frame) && NSMaxX(courses.search.frame) <= NSWidth(courses.view.bounds), @"minimum window keeps course table and controls separate");
    [app.window orderOut:nil]; [app.ticker invalidate]; [NSStatusBar.systemStatusBar removeStatusItem:app.statusItem]; printf("PASS: %lu homework AppKit assertions\n", (unsigned long)checks);
} return 0; }
