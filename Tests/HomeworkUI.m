// Uses synthetic data only; never logs in, persists settings or starts background scans.
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
#import "../Sources/SSAssignments.h"
static NSUInteger checks;
static void Check(BOOL condition, NSString *label) { checks++; if (!condition) { fprintf(stderr, "FAIL: %s\n", label.UTF8String); exit(1); } }
static void Capture(NSView *view, NSString *path) {
    [view.window makeKeyAndOrderFront:nil];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
    [view.window displayIfNeeded];
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES], @"preview saved");
}
int main(void) { @autoreleasepool {
    if (![NSProcessInfo.processInfo.arguments containsObject:@"--preview"]) return 2;
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    AppDelegate *app = [AppDelegate new]; NSApp.delegate = app;
    [app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
    Check(app.preview && !app.courseWindow, @"preview never starts GitHub checks");
    for (NSView *child in app.header.subviews) if ([child isKindOfClass:ActionButton.class] && [[(ActionButton *)child title] isEqual:@"GitHub 课程与作业"])
        Check(!NSIntersectsRect([app.header convertRect:child.frame toView:app.root], app.themePicker.frame), @"course entry does not overlap theme control");
    SSCourseWindow *courses = SSCourseWindow.new;
    courses.courses = NSMutableArray.array; [courses refreshCourses];
    Check(courses.visible.count == 0, @"empty course list is safe");
    NSMutableDictionary *course = [@{@"fork":@"student/course", @"upstream":@"teacher/course", @"branch":@"main", @"upstreamBranch":@"main", @"enabled":@YES, @"lastScan":NSDate.date} mutableCopy];
    [courses.courses addObject:course];
    NSDate *due = DDLParseDate(@"2026-10-08 23:59", NSDate.date, Cal());
    NSDictionary *candidate = @{@"id":@"teacher/course|README.md|作业一|1", @"title":@"作业一 · 实验报告", @"due":due, @"repository":@"teacher/course", @"path":@"README.md", @"line":@12, @"blobSHA":@"version1", @"needsDate":@NO, @"needsTime":@NO, @"snippet":@"## 作业一 · 实验报告\n截止时间：2026-10-08 23:59\n提交实验报告和源代码。"};
    courses.candidates[course[@"fork"]] = @[candidate];
    courses.tasksProvider = ^NSArray * { return [app snapshot]; };
    __block NSDictionary *reviewed;
    courses.reviewCandidate = ^(NSDictionary *value) { reviewed = value; };
    [courses refreshCourses]; [courses show];
    [courses.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO]; [courses candidateSelected:nil];
    Check([courses.detail.string containsString:@"README.md:12"], @"source snippet and line displayed");
    Check([[courses stateForCandidate:candidate] isEqual:@"待审核"], @"discovery needs review");
    NSUInteger before = app.tasks.count;
    [courses review:nil]; Check(reviewed != nil && app.tasks.count == before, @"review only delivers a draft");
    [app reviewGitHubCandidate:reviewed];
    Check(app.editor && app.tasks.count == before, @"review editor does not silently import");
    Check([app.editor.task[@"announcedDue"] isEqual:due] && [app.editor.task[@"sourceID"] isEqual:candidate[@"id"]], @"teacher deadline and provenance retained");
    [app.editor save:nil];
    Check(app.tasks.count == before + 1, @"explicit save imports task");
    Check([[courses stateForCandidate:candidate] isEqual:@"已导入"], @"same source version does not duplicate");
    NSMutableDictionary *saved = app.tasks.lastObject;
    saved[@"due"] = [due dateByAddingTimeInterval:-3 * 3600]; saved[@"leadDays"] = @(-1); saved[@"title"] = @"我的自定义标题";
    NSMutableDictionary *updated = candidate.mutableCopy; updated[@"blobSHA"] = @"version2"; updated[@"due"] = [due dateByAddingTimeInterval:86400];
    Check([[courses stateForCandidate:updated] isEqual:@"有更新"], @"changed source presents update suggestion");
    [app reviewGitHubCandidate:updated];
    Check([app.editor.task[@"due"] isEqual:saved[@"due"]] && [app.editor.task[@"title"] isEqual:@"我的自定义标题"], @"update draft preserves manually edited task");
    Check([saved[@"sourceBlobSHA"] isEqual:@"version1"], @"review alone never overwrites source state");
    [app closeEditor];
    [courses.window setContentSize:NSMakeSize(1200, 800)];
    Check(NSMaxY(courses.table.enclosingScrollView.frame) <= NSMinY(courses.statusLabel.frame), @"resized table does not overlap controls");
    Check(NSMaxY(courses.detail.enclosingScrollView.frame) < NSMinY(courses.table.enclosingScrollView.frame), @"details remain below table");
    NSDictionary *weekly = [SSAssignmentsFromDocument(@"# 规则\n- 截止时间：本周日 21:00\n# 任务\n完成附件作业：运动学基础和牛顿定律。", @"teacher/course", @"assignment-04.md", @"v1", NSDate.date, Cal()) firstObject];
    courses.candidates[course[@"fork"]] = @[weekly]; [courses refreshCourses];
    NSTextField *dueLabel = (NSTextField *)[courses tableView:courses.table viewForTableColumn:[courses.table tableColumnWithIdentifier:@"due"] row:0];
    Check([dueLabel.stringValue isEqual:@"本周日 21:00 · 待确认"], @"relative deadline displays teacher wording instead of unknown deadline");
    [courses.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO]; [courses candidateSelected:nil];
    Check([courses.detail.string containsString:@"牛顿定律"] && [courses.detail.string containsString:@"本周日 21:00"], @"relative deadline and assignment instructions are visible together");
    Capture(courses.window.contentView, @"build/qa/github-courses.png");
    Capture(app.root, @"build/qa/ddl-calendar.png");
    [courses.window orderOut:nil]; [app.window orderOut:nil]; [app.ticker invalidate]; [NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];
    printf("PASS: %lu homework AppKit assertions\n", (unsigned long)checks);
} return 0; }
