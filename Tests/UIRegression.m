// Exercise the real AppKit views with in-memory preview tasks only.
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#include <stdio.h>
#include <stdlib.h>

static NSInteger assertions;
static void CheckUI(BOOL passed, NSString *message) {
    assertions++;
    if (!passed) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static OverviewGrid *FirstGrid(AppDelegate *app) {
    for (NSView *view in app.calendarDocument.subviews) if ([view isKindOfClass:OverviewGrid.class]) return (OverviewGrid *)view;
    return nil;
}
static void Search(AppDelegate *app, NSString *text) {
    app.search.stringValue = text;
    [app controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:app.search]];
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.arguments containsObject:@"--preview"]) return 2;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        AppDelegate *app = [AppDelegate new]; NSApp.delegate = app;
        [app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
        CheckUI(app.preview && app.tasks.count == 13, @"preview uses synthetic tasks");
        OverviewGrid *initial = FirstGrid(app);
        CheckUI(initial != nil && app.calendarDocument.subviews.count == 26, @"13 calendar sections loaded");
        // Freeze the cache minute for deterministic reuse assertions.
        app.overviewMinute = (NSInteger)floor(NSDate.date.timeIntervalSince1970 / 60);
        [app render];
        CheckUI(FirstGrid(app) == initial, @"unchanged render reuses calendar views");
        app.selectedDay = [Cal() dateByAddingUnit:NSCalendarUnitDay value:1 toDate:app.selectedDay options:0];
        [app renderOverview];
        CheckUI(FirstGrid(app) == initial, @"date selection reuses calendar views");
        CheckUI([Cal() isDate:initial.selection inSameDayAsDate:app.selectedDay], @"reused calendar receives new selection");
        NSPopUpButton *yearPicker = app.yearPicker;
        Search(app, @"英"); NSTimer *first = app.searchTimer;
        Search(app, @"  英语  ");
        CheckUI(!first.valid && app.searchTimer.valid, @"successive searches cancel pending refresh");
        CheckUI([app.query isEqual:@"英语"], @"search trims whitespace");
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
        CheckUI(app.searchTimer == nil && app.overviewSnapshot.count == 3, @"debounced search applies latest query");
        CheckUI(app.yearPicker == yearPicker, @"search preserves month controls");
        Search(app, @"");
        CheckUI(app.searchTimer == nil && app.overviewSnapshot.count == 13, @"clear search restores calendar immediately");
        OverviewGrid *beforeMutation = FirstGrid(app);
        app.tasks[0][@"title"] = @"更新后的演示任务";
        [app renderOverview];
        CheckUI(FirstGrid(app) != beforeMutation, @"mutable task edits invalidate calendar cache");
        CheckUI([app.overviewSnapshot containsObject:app.tasks[0]], @"updated content included in snapshot");
        OverviewGrid *beforeResize = FirstGrid(app);
        NSRect frame = app.calendarScroll.frame; frame.size.width -= 100; app.calendarScroll.frame = frame;
        [app renderOverview];
        CheckUI(FirstGrid(app) != beforeResize, @"resize relays out calendar grid");
        OverviewGrid *beforeTick = FirstGrid(app); app.overviewMinute--;
        [app renderOverview];
        CheckUI(FirstGrid(app) != beforeTick, @"minute change refreshes time-sensitive styling");
        app.calendarStatus.selectedSegment = 2; [app renderOverview];
        CheckUI(app.overviewSnapshot.count == 6, @"completed filter invalidates cached content");
        app.calendarStatus.selectedSegment = 0;
        [app openList:nil]; Search(app, @"  英语  "); [app applySearch];
        CheckUI([app visibleTasks].count == 1, @"list and calendar share whitespace search behavior");
        Search(app, @"设计"); [app openCalendar:nil]; [app applySearch];
        CheckUI(app.query.length == 0 && app.overviewSnapshot.count == 13, @"view switch does not resurrect stale search");
        [app.monthPicker selectItemWithTitle:@"1 月"]; [app jumpCalendar:nil];
        CheckUI([Cal() component:NSCalendarUnitMonth fromDate:app.month] == 1, @"exact month jump rebuilds correct window");
        CheckUI([Cal() isDate:app.overviewBaseMonth equalToDate:app.month toUnitGranularity:NSCalendarUnitMonth], @"cached month matches jump target");
        [app.ticker invalidate]; [app.searchTimer invalidate];
        [app.window orderOut:nil]; [NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];
        printf("PASS: %ld AppKit assertions\n", (long)assertions);
    }
    return 0;
}
