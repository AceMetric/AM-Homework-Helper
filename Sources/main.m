#import <Cocoa/Cocoa.h>
#import <UserNotifications/UserNotifications.h>

static void LogUncaughtException(NSException *exception) {
    fprintf(stderr, "DDLManager exception: %s\n%s\n",
            exception.reason.UTF8String,
            exception.callStackSymbols.description.UTF8String);
}

@interface FlippedView : NSView
@end
@implementation FlippedView
- (BOOL)isFlipped { return YES; }
@end

static NSTextField *Label(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color) {
    NSTextField *label = [NSTextField labelWithString:text ?: @""];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color ?: NSColor.labelColor;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

@interface AppDelegate : NSObject <NSApplicationDelegate, NSPopoverDelegate, UNUserNotificationCenterDelegate>
@property NSStatusItem *statusItem;
@property NSPopover *popover;
@property NSWindow *mainWindow;
@property FlippedView *documentView;
@property NSTextField *summaryLabel;
@property NSMutableArray<NSMutableDictionary *> *tasks;
@property NSTextField *deadlineField;
@property NSDatePicker *calendarPicker;
@property NSDatePicker *timePicker;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self installMainMenu];
    NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:@"ddl-manager.tasks.v1"];
    self.tasks = [NSMutableArray array];
    for (NSDictionary *item in stored ?: @[]) [self.tasks addObject:[item mutableCopy]];

    UNUserNotificationCenter.currentNotificationCenter.delegate = self;
    [UNUserNotificationCenter.currentNotificationCenter
        requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
        completionHandler:^(BOOL granted, NSError *error) {}];

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSButton *button = self.statusItem.button;
    button.image = [NSImage imageWithSystemSymbolName:@"checklist.checked" accessibilityDescription:@"DDL 清单"];
    button.imagePosition = NSImageLeft;
    button.target = self;
    button.action = @selector(toggleMainWindow:);

    NSViewController *content = [self buildContentController];
    self.mainWindow = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 400, 540)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    self.mainWindow.title = @"DDL 清单";
    self.mainWindow.contentViewController = content;
    self.mainWindow.releasedWhenClosed = NO;
    self.mainWindow.level = NSFloatingWindowLevel;
    self.mainWindow.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace;
    [self.mainWindow center];

    [self reloadRows];
    [self refreshNotifications];
    [self showMainWindow];
}

- (void)installMainMenu {
    NSMenu *mainMenu = [NSMenu new];

    NSMenuItem *appMenuItem = [NSMenuItem new];
    [mainMenu addItem:appMenuItem];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"DDL Manager"];
    [appMenu addItemWithTitle:@"关于 DDL Manager" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"退出 DDL Manager" action:@selector(terminate:) keyEquivalent:@"q"];
    [appMenu addItem:quit];
    appMenuItem.submenu = appMenu;

    NSMenuItem *editMenuItem = [NSMenuItem new];
    [mainMenu addItem:editMenuItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"编辑"];
    [editMenu addItemWithTitle:@"撤销" action:@selector(undo:) keyEquivalent:@"z"];
    NSMenuItem *redo = [editMenu addItemWithTitle:@"重做" action:@selector(redo:) keyEquivalent:@"Z"];
    redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"剪切" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"复制" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"粘贴" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"全选" action:@selector(selectAll:) keyEquivalent:@"a"];
    editMenuItem.submenu = editMenu;

    NSApp.mainMenu = mainMenu;
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler {
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound);
}

- (NSViewController *)buildContentController {
    NSViewController *controller = [NSViewController new];
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 540)];
    root.wantsLayer = YES;

    NSView *header = [[NSView alloc] initWithFrame:NSMakeRect(0, 474, 400, 66)];
    NSTextField *title = Label(@"DDL 清单", 17, NSFontWeightBold, nil);
    title.frame = NSMakeRect(20, 34, 270, 22);
    [header addSubview:title];

    self.summaryLabel = Label(@"", 12, NSFontWeightRegular, NSColor.secondaryLabelColor);
    self.summaryLabel.frame = NSMakeRect(20, 14, 290, 18);
    [header addSubview:self.summaryLabel];

    NSButton *add = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:@"添加 DDL"] target:self action:@selector(showAddDialog:)];
    add.bezelStyle = NSBezelStyleCircular;
    add.frame = NSMakeRect(345, 17, 36, 36);
    add.toolTip = @"添加 DDL";
    [header addSubview:add];
    [root addSubview:header];

    NSBox *topLine = [[NSBox alloc] initWithFrame:NSMakeRect(0, 473, 400, 1)];
    topLine.boxType = NSBoxSeparator;
    [root addSubview:topLine];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 43, 400, 430)];
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    scroll.autohidesScrollers = YES;
    self.documentView = [[FlippedView alloc] initWithFrame:NSMakeRect(0, 0, 400, 430)];
    scroll.documentView = self.documentView;
    [root addSubview:scroll];

    NSBox *bottomLine = [[NSBox alloc] initWithFrame:NSMakeRect(0, 42, 400, 1)];
    bottomLine.boxType = NSBoxSeparator;
    [root addSubview:bottomLine];

    NSTextField *privacy = Label(@"🔒  数据只保存在本机", 10, NSFontWeightRegular, NSColor.tertiaryLabelColor);
    privacy.frame = NSMakeRect(16, 13, 230, 16);
    [root addSubview:privacy];

    NSButton *quit = [NSButton buttonWithTitle:@"退出" target:self action:@selector(quitApp:)];
    quit.bezelStyle = NSBezelStyleInline;
    quit.font = [NSFont systemFontOfSize:11];
    quit.frame = NSMakeRect(337, 8, 50, 24);
    [root addSubview:quit];

    controller.view = root;
    return controller;
}

- (void)toggleMainWindow:(id)sender {
    if (self.mainWindow.visible && self.mainWindow.keyWindow) {
        [self.mainWindow orderOut:nil];
    } else {
        [self showMainWindow];
    }
}

- (void)showMainWindow {
    [self.mainWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [self showMainWindow];
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return NO; }

- (void)quitApp:(id)sender { [NSApp terminate:nil]; }

- (NSArray<NSMutableDictionary *> *)pendingTasks {
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *task, NSDictionary *bindings) {
        return ![task[@"completed"] boolValue];
    }];
    return [[self.tasks filteredArrayUsingPredicate:predicate]
        sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"due"] compare:b[@"due"]];
        }];
}

- (NSArray<NSMutableDictionary *> *)completedTasks {
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *task, NSDictionary *bindings) {
        return [task[@"completed"] boolValue];
    }];
    return [[self.tasks filteredArrayUsingPredicate:predicate]
        sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [b[@"due"] compare:a[@"due"]];
        }];
}

- (void)reloadRows {
    for (NSView *view in self.documentView.subviews.copy) [view removeFromSuperview];
    NSArray *pending = [self pendingTasks];
    NSArray *completed = [self completedTasks];
    self.summaryLabel.stringValue = pending.count == 0 ? @"今天也很轻松" : [NSString stringWithFormat:@"还有 %ld 项待完成", pending.count];
    self.statusItem.button.title = pending.count == 0 ? @"" : [NSString stringWithFormat:@"%ld", pending.count];

    CGFloat y = 14;
    if (pending.count == 0) {
        NSTextField *icon = Label(@"✓", 40, NSFontWeightBold, NSColor.systemGreenColor);
        icon.alignment = NSTextAlignmentCenter;
        icon.frame = NSMakeRect(20, 88, 360, 52);
        [self.documentView addSubview:icon];
        NSTextField *empty = Label(@"没有待完成的 DDL", 15, NSFontWeightSemibold, nil);
        empty.alignment = NSTextAlignmentCenter;
        empty.frame = NSMakeRect(20, 148, 360, 24);
        [self.documentView addSubview:empty];
        NSTextField *hint = Label(@"点右上角的 +，把下一个截止日期挂起来。", 12, NSFontWeightRegular, NSColor.secondaryLabelColor);
        hint.alignment = NSTextAlignmentCenter;
        hint.frame = NSMakeRect(20, 178, 360, 20);
        [self.documentView addSubview:hint];
        y = 228;
    } else {
        for (NSDictionary *task in pending) {
            NSView *row = [self rowForTask:task y:y];
            [self.documentView addSubview:row];
            y += 92;
        }
    }

    if (completed.count > 0) {
        NSTextField *heading = Label([NSString stringWithFormat:@"已完成 · %ld", completed.count], 12, NSFontWeightSemibold, NSColor.secondaryLabelColor);
        heading.frame = NSMakeRect(18, y + 2, 350, 20);
        [self.documentView addSubview:heading];
        y += 30;
        for (NSDictionary *task in completed) {
            NSView *row = [self rowForTask:task y:y];
            row.alphaValue = 0.62;
            [self.documentView addSubview:row];
            y += 92;
        }
    }
    self.documentView.frame = NSMakeRect(0, 0, 400, MAX(430, y + 14));
}

- (NSView *)rowForTask:(NSDictionary *)task y:(CGFloat)y {
    NSView *row = [[NSView alloc] initWithFrame:NSMakeRect(12, y, 376, 80)];
    row.wantsLayer = YES;
    row.layer.cornerRadius = 11;
    row.layer.backgroundColor = [NSColor.controlBackgroundColor colorWithAlphaComponent:0.72].CGColor;

    NSButton *check = [NSButton checkboxWithTitle:@"" target:self action:@selector(toggleTask:)];
    check.identifier = task[@"id"];
    check.state = [task[@"completed"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    check.frame = NSMakeRect(12, 43, 22, 22);
    [row addSubview:check];

    NSColor *color = [self urgencyColorForDate:task[@"due"] completed:[task[@"completed"] boolValue]];
    NSTextField *subject = Label(task[@"subject"], 11, NSFontWeightSemibold, color);
    subject.frame = NSMakeRect(42, 53, 205, 18);
    [row addSubview:subject];

    NSTextField *remaining = Label([self remainingTextForTask:task], 10, NSFontWeightMedium, color);
    remaining.alignment = NSTextAlignmentRight;
    remaining.frame = NSMakeRect(245, 53, 118, 18);
    [row addSubview:remaining];

    NSTextField *name = Label(task[@"title"], 14, NSFontWeightMedium, [task[@"completed"] boolValue] ? NSColor.secondaryLabelColor : NSColor.labelColor);
    name.frame = NSMakeRect(42, 29, 320, 20);
    [row addSubview:name];

    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.dateFormat = @"M月d日 E HH:mm";
    NSTextField *date = Label([formatter stringFromDate:task[@"due"]], 10, NSFontWeightRegular, NSColor.tertiaryLabelColor);
    date.frame = NSMakeRect(42, 10, 250, 16);
    [row addSubview:date];
    return row;
}

- (NSColor *)urgencyColorForDate:(NSDate *)date completed:(BOOL)completed {
    if (completed) return NSColor.systemGreenColor;
    NSTimeInterval interval = date.timeIntervalSinceNow;
    if (interval < 0) return NSColor.systemRedColor;
    if (interval < 86400) return NSColor.systemOrangeColor;
    if (interval < 3 * 86400) return NSColor.systemYellowColor;
    return NSColor.systemBlueColor;
}

- (NSString *)remainingTextForTask:(NSDictionary *)task {
    if ([task[@"completed"] boolValue]) return @"已完成";
    NSTimeInterval interval = [task[@"due"] timeIntervalSinceNow];
    if (interval < 0) return [NSString stringWithFormat:@"已逾期 %ld 天", MAX(1, (NSInteger)(fabs(interval) / 86400))];
    NSInteger days = interval / 86400;
    NSInteger hours = ((NSInteger)interval % 86400) / 3600;
    if (days > 0) return [NSString stringWithFormat:@"还剩 %ld 天", days];
    if (hours > 0) return [NSString stringWithFormat:@"还剩 %ld 小时", hours];
    return @"不到 1 小时";
}

- (void)showAddDialog:(id)sender {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"添加 DDL";
    alert.informativeText = @"可直接输入，也可以从日历和常用时间中选择。";
    [alert addButtonWithTitle:@"加入清单"];
    [alert addButtonWithTitle:@"取消"];

    NSView *form = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 382)];
    NSTextField *subjectLabel = Label(@"学科", 11, NSFontWeightMedium, NSColor.secondaryLabelColor);
    subjectLabel.frame = NSMakeRect(0, 361, 360, 16);
    [form addSubview:subjectLabel];
    NSTextField *subject = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 332, 360, 26)];
    subject.placeholderString = @"例如：数据结构";
    [form addSubview:subject];

    NSTextField *taskLabel = Label(@"任务", 11, NSFontWeightMedium, NSColor.secondaryLabelColor);
    taskLabel.frame = NSMakeRect(0, 312, 360, 16);
    [form addSubview:taskLabel];
    NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 283, 360, 26)];
    title.placeholderString = @"例如：完成实验报告";
    [form addSubview:title];

    NSTextField *deadlineLabel = Label(@"截止时间", 11, NSFontWeightMedium, NSColor.secondaryLabelColor);
    deadlineLabel.frame = NSMakeRect(0, 263, 360, 16);
    [form addSubview:deadlineLabel];
    self.deadlineField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 233, 215, 26)];
    self.deadlineField.stringValue = @"一周后 23:59";
    [form addSubview:self.deadlineField];

    NSPopUpButton *quick = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(225, 232, 135, 28) pullsDown:NO];
    [quick addItemsWithTitles:@[@"常用日期", @"今晚", @"明天 23:59", @"后天 23:59", @"3天后 23:59", @"一周后 23:59", @"两周后 23:59"]];
    quick.target = self;
    quick.action = @selector(selectQuickDeadline:);
    [form addSubview:quick];

    NSTextField *calendarLabel = Label(@"选择日期", 11, NSFontWeightMedium, NSColor.secondaryLabelColor);
    calendarLabel.frame = NSMakeRect(0, 207, 220, 16);
    [form addSubview:calendarLabel];

    NSDate *initialDate = [self parseDeadline:self.deadlineField.stringValue] ?: NSDate.date;
    self.calendarPicker = [[NSDatePicker alloc] initWithFrame:NSMakeRect(0, 42, 222, 160)];
    self.calendarPicker.datePickerStyle = NSDatePickerStyleClockAndCalendar;
    self.calendarPicker.datePickerElements = NSDatePickerElementFlagYearMonthDay;
    self.calendarPicker.dateValue = initialDate;
    self.calendarPicker.target = self;
    self.calendarPicker.action = @selector(syncDeadlineFromPickers:);
    [form addSubview:self.calendarPicker];

    NSTextField *timeLabel = Label(@"选择时间", 11, NSFontWeightMedium, NSColor.secondaryLabelColor);
    timeLabel.frame = NSMakeRect(235, 207, 125, 16);
    [form addSubview:timeLabel];

    self.timePicker = [[NSDatePicker alloc] initWithFrame:NSMakeRect(235, 176, 125, 26)];
    self.timePicker.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
    self.timePicker.datePickerElements = NSDatePickerElementFlagHourMinute;
    self.timePicker.dateValue = initialDate;
    self.timePicker.target = self;
    self.timePicker.action = @selector(syncDeadlineFromPickers:);
    [form addSubview:self.timePicker];

    NSPopUpButton *commonTime = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(235, 140, 125, 28) pullsDown:NO];
    [commonTime addItemsWithTitles:@[@"常用时间", @"09:00", @"12:00", @"18:00", @"20:00", @"22:00", @"23:59"]];
    commonTime.target = self;
    commonTime.action = @selector(selectCommonTime:);
    [form addSubview:commonTime];

    NSTextField *reminderHint = Label(@"🔔 提醒：提前 3 天、1 天、1 小时，以及到期时", 10, NSFontWeightRegular, NSColor.secondaryLabelColor);
    reminderHint.frame = NSMakeRect(0, 12, 360, 18);
    [form addSubview:reminderHint];
    alert.accessoryView = form;

    [alert.window setInitialFirstResponder:subject];
    while (true) {
        NSModalResponse response = [alert runModal];
        if (response != NSAlertFirstButtonReturn) return;
        NSString *subjectText = [subject.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *titleText = [title.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSDate *due = [self parseDeadline:self.deadlineField.stringValue];
        if (subjectText.length && titleText.length && due && due.timeIntervalSinceNow > 0) {
            NSMutableDictionary *task = [@{
                @"id": NSUUID.UUID.UUIDString,
                @"subject": subjectText,
                @"title": titleText,
                @"due": due,
                @"completed": @NO
            } mutableCopy];
            [self.tasks addObject:task];
            [self save];
            [self reloadRows];
            [self scheduleNotificationsForTask:task];
            return;
        }
        alert.informativeText = @"请填写学科、任务和未来的有效时间。";
    }
}

- (void)selectQuickDeadline:(NSPopUpButton *)sender {
    if (sender.indexOfSelectedItem == 0) return;
    self.deadlineField.stringValue = sender.titleOfSelectedItem;
    NSDate *date = [self parseDeadline:self.deadlineField.stringValue];
    if (date) {
        self.calendarPicker.dateValue = date;
        self.timePicker.dateValue = date;
    }
}

- (void)selectCommonTime:(NSPopUpButton *)sender {
    if (sender.indexOfSelectedItem == 0) return;
    NSArray<NSString *> *parts = [sender.titleOfSelectedItem componentsSeparatedByString:@":"];
    if (parts.count != 2) return;
    NSDate *time = [NSCalendar.currentCalendar dateBySettingHour:parts[0].integerValue
                                                          minute:parts[1].integerValue
                                                          second:0
                                                          ofDate:self.timePicker.dateValue
                                                         options:0];
    if (time) self.timePicker.dateValue = time;
    [self syncDeadlineFromPickers:sender];
}

- (void)syncDeadlineFromPickers:(id)sender {
    NSDateComponents *dateParts = [NSCalendar.currentCalendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay)
                                                                 fromDate:self.calendarPicker.dateValue];
    NSDateComponents *timeParts = [NSCalendar.currentCalendar components:(NSCalendarUnitHour | NSCalendarUnitMinute)
                                                                 fromDate:self.timePicker.dateValue];
    dateParts.hour = timeParts.hour;
    dateParts.minute = timeParts.minute;
    dateParts.second = 0;
    NSDate *combined = [NSCalendar.currentCalendar dateFromComponents:dateParts];
    if (!combined) return;
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm";
    self.deadlineField.stringValue = [formatter stringFromDate:combined];
}

- (NSDate *)parseDeadline:(NSString *)raw {
    NSString *text = [[raw stringByReplacingOccurrencesOfString:@" " withString:@""] stringByReplacingOccurrencesOfString:@"：" withString:@":"];
    if (!text.length) return nil;
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDate *now = NSDate.date;
    NSInteger hour = 23, minute = 59;
    NSRegularExpression *timeRegex = [NSRegularExpression regularExpressionWithPattern:@"(\\d{1,2}):(\\d{2})" options:0 error:nil];
    NSTextCheckingResult *timeMatch = [timeRegex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (timeMatch.numberOfRanges == 3) {
        hour = [[text substringWithRange:[timeMatch rangeAtIndex:1]] integerValue];
        minute = [[text substringWithRange:[timeMatch rangeAtIndex:2]] integerValue];
        if (hour > 23 || minute > 59) return nil;
    }
    NSDate *day = nil;
    if ([text containsString:@"今天"] || [text containsString:@"今晚"]) day = now;
    else if ([text containsString:@"明天"]) day = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:now options:0];
    else if ([text containsString:@"后天"]) day = [calendar dateByAddingUnit:NSCalendarUnitDay value:2 toDate:now options:0];
    else if ([text containsString:@"一周后"] || [text containsString:@"下周"]) day = [calendar dateByAddingUnit:NSCalendarUnitDay value:7 toDate:now options:0];
    else if ([text containsString:@"两周后"] || [text containsString:@"二周后"]) day = [calendar dateByAddingUnit:NSCalendarUnitDay value:14 toDate:now options:0];
    else {
        NSRegularExpression *relative = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)(天|周)后" options:0 error:nil];
        NSTextCheckingResult *match = [relative firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
        if (match.numberOfRanges == 3) {
            NSInteger value = [[text substringWithRange:[match rangeAtIndex:1]] integerValue];
            if ([[text substringWithRange:[match rangeAtIndex:2]] isEqualToString:@"周"]) value *= 7;
            day = [calendar dateByAddingUnit:NSCalendarUnitDay value:value toDate:now options:0];
        }
    }
    if (day) return [calendar dateBySettingHour:hour minute:minute second:0 ofDate:day options:0];

    for (NSString *format in @[@"yyyy-MM-ddHH:mm", @"yyyy/M/dHH:mm", @"yyyy-MM-dd", @"yyyy/M/d"]) {
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
        formatter.dateFormat = format;
        NSDate *date = [formatter dateFromString:text];
        if (date) {
            if ([format containsString:@"HH:mm"]) return date;
            return [calendar dateBySettingHour:23 minute:59 second:0 ofDate:date options:0];
        }
    }
    return nil;
}

- (void)toggleTask:(NSButton *)sender {
    for (NSMutableDictionary *task in self.tasks) {
        if ([task[@"id"] isEqualToString:sender.identifier]) {
            BOOL completed = ![task[@"completed"] boolValue];
            task[@"completed"] = @(completed);
            completed ? [self removeNotificationsForTask:task] : [self scheduleNotificationsForTask:task];
            break;
        }
    }
    [self save];
    [self reloadRows];
}

- (void)save {
    [[NSUserDefaults standardUserDefaults] setObject:self.tasks forKey:@"ddl-manager.tasks.v1"];
}

- (void)refreshNotifications {
    for (NSDictionary *task in [self pendingTasks]) [self scheduleNotificationsForTask:task];
}

- (void)removeNotificationsForTask:(NSDictionary *)task {
    NSString *base = task[@"id"];
    [UNUserNotificationCenter.currentNotificationCenter removePendingNotificationRequestsWithIdentifiers:@[
        [base stringByAppendingString:@".early"],
        [base stringByAppendingString:@".threeDays"],
        [base stringByAppendingString:@".oneDay"],
        [base stringByAppendingString:@".oneHour"],
        [base stringByAppendingString:@".due"]
    ]];
}

- (void)scheduleNotificationsForTask:(NSDictionary *)task {
    [self removeNotificationsForTask:task];
    NSDate *due = task[@"due"];
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDate *threeDays = [calendar dateByAddingUnit:NSCalendarUnitDay value:-3 toDate:due options:0];
    NSDate *oneDay = [calendar dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:due options:0];
    NSDate *oneHour = [due dateByAddingTimeInterval:-3600];
    NSArray *dates = @[threeDays, oneDay, oneHour, due];
    NSArray *suffixes = @[@".threeDays", @".oneDay", @".oneHour", @".due"];
    NSArray *messages = @[
        [NSString stringWithFormat:@"3 天后截止：%@", task[@"title"]],
        [NSString stringWithFormat:@"明天截止：%@", task[@"title"]],
        [NSString stringWithFormat:@"1 小时后截止：%@", task[@"title"]],
        [NSString stringWithFormat:@"DDL 到时间了：%@", task[@"title"]]
    ];
    for (NSInteger i = 0; i < dates.count; i++) {
        if ([dates[i] timeIntervalSinceNow] <= 0) continue;
        UNMutableNotificationContent *content = [UNMutableNotificationContent new];
        content.title = task[@"subject"];
        content.body = messages[i];
        content.sound = UNNotificationSound.defaultSound;
        NSDateComponents *components = [NSCalendar.currentCalendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:dates[i]];
        UNCalendarNotificationTrigger *trigger = [UNCalendarNotificationTrigger triggerWithDateMatchingComponents:components repeats:NO];
        NSString *identifier = [task[@"id"] stringByAppendingString:suffixes[i]];
        UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger];
        [UNUserNotificationCenter.currentNotificationCenter addNotificationRequest:request withCompletionHandler:nil];
    }
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSSetUncaughtExceptionHandler(&LogUncaughtException);
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
