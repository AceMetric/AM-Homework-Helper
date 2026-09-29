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
static NSData *IconPixels(NSImage *icon) {
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:128 pixelsHigh:128 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState]; [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];
    [icon drawInRect:NSMakeRect(0, 0, 128, 128) fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1];
    [NSGraphicsContext restoreGraphicsState];
    return [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.arguments containsObject:@"--preview"]) return 2;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        AppDelegate *app = [AppDelegate new]; NSApp.delegate = app;
        [app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
        CheckUI(app.preview && app.tasks.count == 13 && CurrentTheme == 1, @"preview uses synthetic tasks and blue theme");
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
        CheckUI(app.themePicker.numberOfItems == 6, @"six named pastel themes available");
        CheckUI(ThemeIndex(@"unknown-theme") == 1 && ThemeIndex(@42) == 1, @"invalid preference falls back to blue");
        CheckUI(app.root.gradientEnd != nil && app.calendarDocument.gradientEnd != nil, @"main and calendar surfaces have gradients");
        NSDateComponents *september = [NSDateComponents new]; september.year = 2026; september.month = 9; september.day = 1;
        NSDate *testMonth = [Cal() dateFromComponents:september];
        NSDate *adjacentDay = DDLMonthGrid(testMonth, Cal()).firstObject;
        OverviewGrid *adjacentGrid = [OverviewGrid new]; adjacentGrid.frame = NSMakeRect(0, 0, 896, 540); adjacentGrid.month = testMonth; adjacentGrid.selection = testMonth;
        adjacentGrid.tasksByDay = @{[Cal() startOfDayForDate:adjacentDay]: @[app.tasks.firstObject]}; [adjacentGrid reload];
        CalendarDayCell *adjacentCell = nil;
        for (NSView *view in adjacentGrid.subviews) if ([view isKindOfClass:CalendarDayCell.class] && [Cal() isDate:((CalendarDayCell *)view).date inSameDayAsDate:adjacentDay]) adjacentCell = (CalendarDayCell *)view;
        NSInteger adjacentEvents = 0;
        for (NSView *view in adjacentCell.subviews) if ([view isKindOfClass:CalendarTaskButton.class]) adjacentEvents++;
        CheckUI(adjacentCell != nil && !adjacentCell.inMonth && adjacentEvents == 0, @"adjacent-month dates hide schedule entries");
        CheckUI([adjacentCell.fill isEqual:[Panel() blendedColorWithFraction:0.48 ofColor:Line()]], @"adjacent-month dates use deeper background");
        NSButton *today = [NSButton new]; today.tag = 0; [app navigateCalendar:today];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
        NSDate *selectedDay = app.selectedDay, *month = app.month;
        NSArray *tasksBeforeTheme = [app.tasks copy];
        NSPoint scrollBeforeTheme = app.calendarScroll.contentView.bounds.origin;
        for (NSInteger i = 0; i < 6; i++) {
            OverviewGrid *oldGrid = FirstGrid(app);
            NSData *oldIcon = IconPixels(NSApp.applicationIconImage);
            [app.themePicker selectItemAtIndex:i]; [app changeTheme:app.themePicker];
            CheckUI(CurrentTheme == i && [app.root.fill isEqual:Canvas()] && [app.root.gradientEnd isEqual:Panel()] && [app.agenda.fill isEqual:Panel()], @"theme recolors persistent gradients");
            CheckUI(![IconPixels(NSApp.applicationIconImage) isEqualToData:oldIcon] && NSEqualSizes(NSApp.applicationIconImage.size, NSMakeSize(512, 512)), @"Dock icon follows theme selection");
            CheckUI(FirstGrid(app) != oldGrid, @"theme invalidates cached calendar colors");
            CheckUI([app.selectedDay isEqual:selectedDay] && [app.month isEqual:month] && [app.tasks isEqual:tasksBeforeTheme], @"theme preserves dates and tasks");
            CheckUI(NSEqualPoints(app.calendarScroll.contentView.bounds.origin, scrollBeforeTheme), @"theme preserves calendar scroll");
            [app.window displayIfNeeded];
            NSBitmapImageRep *bitmap = [app.root bitmapImageRepForCachingDisplayInRect:app.root.bounds];
            [app.root cacheDisplayInRect:app.root.bounds toBitmapImageRep:bitmap];
            NSString *path = [NSString stringWithFormat:@"QA/theme-%@.png", ThemeIDs()[i]];
            CheckUI([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:NO], @"theme preview exported");
        }
        OverviewGrid *hoverGrid = nil;
        for (NSView *view in app.calendarDocument.subviews) {
            if ([view isKindOfClass:OverviewGrid.class] && !NSIsEmptyRect(NSIntersectionRect(view.bounds, view.visibleRect))) { hoverGrid = (OverviewGrid *)view; break; }
        }
        CalendarDayCell *hoverCell = nil;
        for (NSView *view in hoverGrid.subviews) {
            if ([view isKindOfClass:CalendarDayCell.class] && !NSIsEmptyRect(NSIntersectionRect(view.bounds, view.visibleRect))) { hoverCell = (CalendarDayCell *)view; break; }
        }
        CheckUI(hoverCell != nil, @"visible calendar day exists for hover regression");
        CallbackButton *dayHit = nil;
        for (NSView *view in hoverCell.subviews) if ([view isKindOfClass:CallbackButton.class] && NSEqualRects(view.frame, hoverCell.bounds)) dayHit = (CallbackButton *)view;
        CheckUI(dayHit != nil && !dayHit.allowsHoverFill, @"transparent day hit area never paints stale hover fill");
        NSRect visibleDay = NSIntersectionRect(hoverCell.bounds, hoverCell.visibleRect);
        NSPoint pointer = [hoverCell convertPoint:NSMakePoint(NSMidX(visibleDay), NSMidY(visibleDay)) toView:nil];
        NSInteger staleCount = 0;
        for (NSView *view in hoverGrid.subviews) if ([view isKindOfClass:CalendarDayCell.class]) { ((CalendarDayCell *)view).hovered = YES; staleCount++; }
        CheckUI(staleCount > 1, @"regression setup contains multiple stale hovered days");
        [hoverGrid refreshHoverAtWindowPoint:pointer];
        NSInteger activeCount = 0;
        for (NSView *view in hoverGrid.subviews) if ([view isKindOfClass:CalendarDayCell.class] && ((CalendarDayCell *)view).hovered) activeCount++;
        CheckUI(activeCount == 1 && hoverCell.hovered, @"pointer highlights only its visible day");
        NSPoint shifted = app.calendarScroll.contentView.bounds.origin; shifted.y += NSHeight(hoverCell.bounds);
        [app.calendarScroll.contentView scrollToPoint:shifted]; [app.calendarScroll reflectScrolledClipView:app.calendarScroll.contentView];
        [hoverGrid refreshHoverAtWindowPoint:pointer];
        activeCount = 0;
        for (NSView *view in hoverGrid.subviews) if ([view isKindOfClass:CalendarDayCell.class] && ((CalendarDayCell *)view).hovered) activeCount++;
        CheckUI(activeCount <= 1, @"scrolling does not leave a dark calendar column");
        [app openList:nil];
        [app.themePicker selectItemAtIndex:1]; [app changeTheme:app.themePicker];
        CheckUI([app.sidebar.fill isEqual:Panel()] && !app.themePicker.hidden, @"list shares theme and picker");
        [app.window setContentSize:NSMakeSize(1100, 760)]; [app layout];
        CheckUI(NSMaxX(app.themePicker.frame) <= NSWidth(app.root.bounds), @"theme picker fits compact window");
        [app.window displayIfNeeded];
        NSBitmapImageRep *listBitmap = [app.root bitmapImageRepForCachingDisplayInRect:app.root.bounds];
        [app.root cacheDisplayInRect:app.root.bounds toBitmapImageRep:listBitmap];
        [[listBitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"QA/theme-list-compact.png" atomically:NO];
        [app.ticker invalidate]; [app.searchTimer invalidate];
        [app.window orderOut:nil]; [NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];
        printf("PASS: %ld AppKit assertions\n", (long)assertions);
    }
    return 0;
}
