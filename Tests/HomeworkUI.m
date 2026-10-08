// Synthetic UI scenarios only: no account, repository, persistence or notifications.
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
#import "../Sources/SSAssignments.h"
static NSUInteger checks;
static void Check(BOOL condition, NSString *label) { checks++; if (!condition) { fprintf(stderr, "FAIL: %s\n", label.UTF8String); exit(1); } }
static void Capture(NSView *view, NSString *path) {
    [view.window makeKeyAndOrderFront:nil]; [view.window makeFirstResponder:nil]; [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]]; [view.window displayIfNeeded];
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds]; [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES], @"synthetic screenshot saved");
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
    course[@"path"] = @"/synthetic/physics"; course[@"lastScan"] = NSDate.date; [courses refreshCourses];
    Check(courses.syncButton.enabled && courses.commitButton.enabled && [courses.accountLabel.stringValue containsString:@"上次检查"], @"linked course displays readiness and last check");
    Check([courses.emptyLabel.stringValue containsString:@"检查新作业"], @"no-results state gives refresh action");
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
    Check(app.editor.teacherField != nil && app.editor.sourceScroll != nil && [app.editor.task[@"sourceID"] isEqual:candidate[@"id"]], @"review includes teacher date, original text and provenance");
    [app.editor save:nil];
    Check(app.tasks.count == before + 1 && courses.pendingCount == 1 && courses.visible.count == 1, @"save imports and updates inbox count immediately");
    Check(app.tasks.lastObject[@"_reviewCandidate"] == nil && app.tasks.lastObject[@"_existing"] == nil, @"editor-only metadata never persists");
    [courses.reviewFilter selectItemAtIndex:2]; [courses refreshPresentation]; Check(courses.visible.count == 1, @"imported results available through filter");
    [courses.reviewFilter selectItemAtIndex:0];
    NSMutableDictionary *saved = app.tasks.lastObject; saved[@"due"] = [due dateByAddingTimeInterval:-3 * 3600]; saved[@"leadDays"] = @(-1); saved[@"title"] = @"我的自定义标题";
    NSMutableDictionary *updated = candidate.mutableCopy; updated[@"blobSHA"] = @"version2"; updated[@"due"] = [due dateByAddingTimeInterval:86400]; courses.candidates[course[@"fork"]] = @[updated]; [courses refreshPresentation];
    Check(courses.pendingCount == 2 && [[courses stateForCandidate:updated] isEqual:@"有更新"], @"changed original becomes update suggestion");
    [app reviewGitHubCandidate:updated];
    Check([app.editor.task[@"due"] isEqual:saved[@"due"]] && [app.editor.task[@"title"] isEqual:@"我的自定义标题"] && [app.editor.window.title isEqual:@"审核更新"], @"updates preserve manually edited title and deadline");
    Check([saved[@"sourceBlobSHA"] isEqual:@"version1"], @"cancelable review never overwrites source version"); [app closeEditor];
    NSDictionary *weekly = [SSAssignmentsFromDocument(@"# 规则\n- 截止时间：本周日 21:00\n# 任务\n完成附件作业：运动学基础和牛顿定律。", @"teacher/physics", @"assignment-04.md", @"v1", NSDate.date, Cal()) firstObject];
    courses.candidates[course[@"fork"]] = @[weekly]; [courses refreshPresentation]; [app reviewGitHubCandidate:weekly]; before = app.tasks.count;
    Check(app.editor.teacherField.stringValue.length == 0 && [app.editor.candidate[@"snippet"] containsString:@"牛顿定律"], @"relative date stays unresolved with assignment context");
    [app.editor save:nil]; Check(app.tasks.count == before && [app.editor.validation.stringValue containsString:@"完整"], @"relative date cannot save until completed");
    [app.editor.leadMenu selectItemAtIndex:1]; [app.editor leadChanged:app.editor.leadMenu]; Check(app.editor.leadDays == 1, @"lead preference can be chosen before resolving teacher date");
    app.editor.teacherField.stringValue = @"2026-10-11 21:00"; Check([app.editor confirmTeacherDate], @"explicit teacher date accepted inside same sheet"); [app.editor save:nil];
    Check(app.tasks.count == before + 1 && [app.tasks.lastObject[@"announcedDue"] timeIntervalSinceDate:app.tasks.lastObject[@"due"]] == 86400, @"confirmed relative assignment imported with chosen personal lead");
    NSMutableDictionary *suggested = [SSApplyDateReference(weekly, DDLParseDate(@"2026-10-05 09:00", NSDate.date, Cal()), @"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", Cal()) mutableCopy]; suggested[@"id"] = @"suggested-relative-qa";
    [app reviewGitHubCandidate:suggested]; before = app.tasks.count;
    Check(app.editor.teacherField.stringValue.length == 0 && !app.editor.announcedDue, @"suggestion is never silently confirmed when opening review");
    [app.editor save:nil]; Check(app.tasks.count == before, @"saving unresolved suggestion is blocked");
    [app.editor adoptDateSuggestion:nil]; Check([app.editor.teacherField.stringValue isEqual:@"2026-10-11 21:00"] && app.editor.announcedDue, @"explicit adopt action fills teacher date inside same sheet");
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]; [app refreshAppearance];
    Check([app.editor.teacherField.stringValue isEqual:@"2026-10-11 21:00"], @"appearance switch preserves adopted unsaved date"); [app closeEditor];
    Check(app.tasks.count == before, @"canceling adopted suggestion does not import a task");
    NSDictionary *dateOnly = SSAssignmentsFromDocument(@"# 作业五\n截止：2027年4月14日", @"teacher/physics", @"a.md", @"date-only", NSDate.date, Cal()).firstObject;
    [app reviewGitHubCandidate:dateOnly]; Check([app.editor.teacherField.stringValue isEqual:@"2027-04-14"], @"date-only civil date remains visible while time is missing");
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
    Check([courses.statusLabel.stringValue containsString:@"student/physics"] && !courses.commitButton.enabled && courses.courseSnapshots.count == 2, @"browsing another course retains captured operation target and locks writes"); courses.busy = NO;
    SSSubmissionController *submission = [[SSSubmissionController alloc] initWithCourse:course changes:@[@{@"path":@"answers.md", @"status":@" M", @"sensitive":@NO}, @{@"path":@".env", @"status":@"??", @"sensitive":@YES}]];
    Check(submission.checks[0].state == NSControlStateValueOff && !submission.checks[1].enabled, @"submission defaults unchecked and excludes sensitive files");
    __block NSArray *selected; submission.submit = ^(NSArray *paths, NSString *message) { selected = paths; }; [submission save:nil]; Check(selected == nil, @"empty submission is blocked");
    submission.checks[0].state = NSControlStateValueOn; submission.message.stringValue = @"完成作业"; [submission save:nil]; Check([selected isEqual:@[@"answers.md"]], @"only explicit file choices leave submission sheet");
    submission.readPreview = ^(NSString *file, void (^ready)(NSString *)) { ready([@"diff preview: " stringByAppendingString:file]); };
    NSButton *previewButton = NSButton.new; previewButton.tag = 0; [submission showPreview:previewButton]; Check([submission.preview.string containsString:@"answers.md"], @"selected file preview is delivered to sheet");
    courses.preview = NO; courses.selectedFork = course[@"fork"]; __block BOOL finished = NO; __block NSDictionary *captured = course.copy;
    [courses work:@"模拟操作" forCourse:captured operation:^id(NSError **error) { return captured[@"fork"]; } completion:^(NSString *result, NSError *error) { Check([result isEqual:@"student/physics"] && [courses.statusFork isEqual:@"student/physics"], @"completion remains bound to captured course after selection changes"); [courses status:@"模拟完成"]; finished = YES; }];
    courses.selectedFork = other[@"fork"]; [courses refreshCourses];
    Check(courses.busy && !courses.setupButton.enabled && !courses.syncButton.enabled && !courses.commitButton.enabled, @"all mutations locked during work while navigation stays available");
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:3]; while (!finished && limit.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    Check(finished && [courses.statuses[@"student/physics"] isEqual:@"模拟完成"] && !courses.busy, @"result stored against initiating course"); courses.preview = YES;
    courses.preview=YES;Route(app,4);[courses selectCourseID:course[@"fork"]];
    courses.query=@"物理筛选";courses.sections.selectedSegment=2;[courses.typeFilter selectItemAtIndex:2];
    Check([courses selectCourseID:other[@"fork"]] && courses.query.length==0,@"switch course resets only new course view state");
    Check([courses selectCourseID:course[@"fork"]] && [courses.query isEqual:@"物理筛选"] && courses.sections.selectedSegment==2 && courses.typeFilter.indexOfSelectedItem==2,@"course retains its own query, section and type");
    [courses selectCourseID:nil];Check(courses.syncButton.hidden && courses.commitButton.hidden && [courses.scanButton.title isEqual:@"检查所有课程"],@"all-courses view has no ambiguous sync or submit target");
    Check(courses.courseWorkspace.view.superview!=nil && !courses.courseWorkspace.view.hidden && courses.table.enclosingScrollView.hidden,@"SwiftUI course details replace visible legacy table");
    Check([app.navigationScroll.documentView.subviews count]>=7,@"main sidebar expands course entries without second sidebar");
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
    [courses review:nil]; before = app.tasks.count;
    Check(app.editor.reviewQueue.count == 3 && [app.editor.reviewProgress.stringValue containsString:@"3"], @"session captures only pending homework in current course and search");
    [app.editor saveAndReviewNext:nil]; [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    Check(app.tasks.count == before + 1 && [app.editor.candidate[@"id"] isEqual:two[@"id"]], @"save-and-next imports one task and opens the next without a list round trip");
    app.editor.titleField.stringValue = @""; [app.editor saveAndReviewNext:nil];
    Check([app.editor.candidate[@"id"] isEqual:two[@"id"]] && app.tasks.count == before + 1, @"invalid review cannot advance or import another task");
    app.editor.titleField.stringValue = two[@"title"]; [app.editor deferReview:nil]; [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    BOOL deferredStillPending = [courses.pendingReviewCandidates indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) { return [item[@"id"] isEqual:two[@"id"]]; }] != NSNotFound;
    Check([app.editor.candidate[@"id"] isEqual:three[@"id"]] && deferredStillPending, @"defer moves to next and retains unimported homework in inbox");
    [app.editor saveAndReviewNext:nil]; Check(app.editor != nil && app.tasks.count == before + 1, @"continuous review still requires a missing teacher time");
    app.editor.teacherField.stringValue = @"2027-04-14 20:00";
    NSEvent *reviewReturn = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:app.editor.window.windowNumber context:nil characters:@"\r" charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:36];
    Check([app.editor.window performKeyEquivalent:reviewReturn], @"Return invokes save-and-next in review sheet");
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
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
        [submission selectionChanged:nil];
        Capture(submission.window.contentView, [NSString stringWithFormat:@"build/qa/submit-%@.png", name]); [submission.window orderOut:nil];
    }
    [app.window setContentSize:NSMakeSize(960, 640)]; [app layout];
    Check(NSMaxY(courses.table.enclosingScrollView.frame) <= NSMinY(courses.detail.enclosingScrollView.frame) && NSMaxX(courses.search.frame) <= NSWidth(courses.view.bounds), @"minimum window keeps course table and controls separate");
    [app.window orderOut:nil]; [app.ticker invalidate]; [NSStatusBar.systemStatusBar removeStatusItem:app.statusItem]; printf("PASS: %lu homework AppKit assertions\n", (unsigned long)checks);
} return 0; }
