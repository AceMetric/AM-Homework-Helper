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
    [courses.courses addObjectsFromArray:@[course, other]]; courses.connected = YES; [courses refreshCourses];
    Check([courses.setupButton.title isEqual:@"关联文件夹…"] && !courses.syncButton.enabled && !courses.scanButton.enabled, @"unlinked course provides folder setup and blocks Git actions");
    course[@"path"] = @"/synthetic/physics"; course[@"lastScan"] = NSDate.date; [courses refreshCourses];
    Check(courses.syncButton.enabled && courses.commitButton.enabled && [courses.accountLabel.stringValue containsString:@"上次检查"], @"linked course displays readiness and last check");
    Check([courses.emptyLabel.stringValue containsString:@"检查作业"], @"no-results state gives refresh action");
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
    Route(app, 4); courses.sections.selectedSegment = 1; [courses refreshPresentation]; Check(courses.visible.count == 2 && [courses.visible.firstObject[@"confirmed"] boolValue], @"course shows already-added tasks");
    courses.sections.selectedSegment = 0; course[@"pendingMergeTip"] = @"synthetic-merge"; course[@"pendingConflicts"] = @[@"answers.md"]; [courses refreshPresentation];
    Check(!courses.recoveryButton.hidden && [courses.recoveryButton.title containsString:@"冲突"], @"conflicts expose recovery entry");
    [course removeObjectForKey:@"pendingMergeTip"]; [course removeObjectForKey:@"pendingConflicts"]; course[@"pushFailed"] = @YES; [courses refreshPresentation]; Check([courses.recoveryButton.title isEqual:@"重试推送"], @"failed push exposes retry");
    courses.busy = YES; courses.operationFork = course[@"fork"]; courses.statuses[course[@"fork"]] = @"正在合并老师更新…"; courses.selectedFork = other[@"fork"]; [courses refreshCourses];
    Check([courses.statusLabel.stringValue containsString:@"student/physics"] && !courses.commitButton.enabled && courses.coursePicker.enabled, @"browsing another course retains captured operation target and locks writes"); courses.busy = NO;
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
    // Actual keyboard equivalents on the shared sheet, with no persistence in preview mode.
    [app addTask:nil]; app.editor.titleField.stringValue = @"键盘保存模拟任务"; [app.editor updateDate:DDLParseDate(@"明天 21:00", NSDate.date, Cal())]; before = app.tasks.count;
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]]; [app.editor.window makeKeyWindow];
    NSEvent *returnKey = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:app.editor.window.windowNumber context:nil characters:@"\r" charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:36];
    BOOL handled = [app.editor.window performKeyEquivalent:returnKey];
    Check(handled && app.tasks.count == before + 1, @"Return saves through actual sheet key equivalent");
    [app addTask:nil]; [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]]; [app.editor.window makeKeyWindow]; before = app.tasks.count; NSEvent *escapeKey = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:app.editor.window.windowNumber context:nil characters:@"\033" charactersIgnoringModifiers:@"\033" isARepeat:NO keyCode:53];
    Check([app.editor.window performKeyEquivalent:escapeKey] && !app.editor && app.tasks.count == before, @"Escape cancels without creating a task");
    for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        NSApp.appearance = [NSAppearance appearanceNamed:appearance]; [app refreshAppearance]; NSString *name = [appearance isEqual:NSAppearanceNameAqua] ? @"light" : @"dark";
        Route(app, 0); Capture(app.root, [NSString stringWithFormat:@"build/qa/overview-%@.png", name]);
        Route(app, 3); [courses.reviewFilter selectItemAtIndex:1]; [courses refreshPresentation]; Capture(app.root, [NSString stringWithFormat:@"build/qa/review-%@.png", name]);
        Route(app, 4); Capture(app.root, [NSString stringWithFormat:@"build/qa/courses-%@.png", name]);
        [app reviewGitHubCandidate:weekly]; Capture(app.editor.window.contentView, [NSString stringWithFormat:@"build/qa/review-editor-%@.png", name]); [app closeEditor];
        [submission selectionChanged:nil];
        Capture(submission.window.contentView, [NSString stringWithFormat:@"build/qa/submit-%@.png", name]); [submission.window orderOut:nil];
    }
    [app.window setContentSize:NSMakeSize(960, 640)]; [app layout];
    Check(NSMaxY(courses.table.enclosingScrollView.frame) <= NSMinY(courses.detail.enclosingScrollView.frame) && NSMaxX(courses.search.frame) <= NSWidth(courses.view.bounds), @"minimum window keeps course table and controls separate");
    [app.window orderOut:nil]; [app.ticker invalidate]; [NSStatusBar.systemStatusBar removeStatusItem:app.statusItem]; printf("PASS: %lu homework AppKit assertions\n", (unsigned long)checks);
} return 0; }
