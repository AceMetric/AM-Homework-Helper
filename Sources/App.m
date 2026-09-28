#import <Cocoa/Cocoa.h>
#import <UserNotifications/UserNotifications.h>
#import "DDLCore.h"

static NSColor *RGB(unsigned value) { return [NSColor colorWithSRGBRed:((value >> 16) & 255) / 255.0 green:((value >> 8) & 255) / 255.0 blue:(value & 255) / 255.0 alpha:1]; }
// Every palette keeps light surfaces, including when macOS uses dark appearance.
static NSColor *Adaptive(unsigned light, unsigned dark) { return RGB(light); }
typedef struct { unsigned canvas, panel, tint, emphasis, line, ink, muted, accent; } PastelPalette;
static const PastelPalette Palettes[] = {
    {0xF8FAF7, 0xEFF4EC, 0xE5EFE1, 0xD3E5CB, 0xDCE5D7, 0x2E3C30, 0x5E6D60, 0x3D6245},
    {0xF7FAFC, 0xEDF3F8, 0xE1EDF7, 0xCDDFEF, 0xD8E3EC, 0x2D3C49, 0x596E7E, 0x385F7D},
    {0xFAF8FC, 0xF2EEF8, 0xEAE3F4, 0xDED2ED, 0xE3DCED, 0x3D344A, 0x6D617B, 0x665080},
    {0xFCF8FA, 0xF8EEF2, 0xF5E2EA, 0xEED0DD, 0xEEDCE4, 0x4A3540, 0x7B606D, 0x7C4B63},
    {0xFCF9F6, 0xF8F0E9, 0xF6E6D9, 0xEFD7C2, 0xECDDCE, 0x48392E, 0x796555, 0x795334},
    {0xFCFBF6, 0xF7F3E5, 0xF2ECD3, 0xE9DFAF, 0xE8E1CA, 0x423E2E, 0x726B50, 0x726032}
};
static NSInteger CurrentTheme = 0;
static NSString * const ThemePreferenceKey = @"ddl-manager.theme.v1";
static NSArray<NSString *> *ThemeIDs(void) { return @[@"sage", @"blue", @"lavender", @"rose", @"peach", @"cream"]; }
static NSArray<NSString *> *ThemeNames(void) { return @[@"鼠尾草", @"雾蓝", @"薰衣草", @"樱花", @"蜜桃", @"奶油"]; }
static NSInteger ThemeIndex(id identifier) {
    NSUInteger index = [ThemeIDs() indexOfObject:identifier ?: @""];
    return index == NSNotFound ? 0 : (NSInteger)index;
}
static NSColor *Ink(void) { return RGB(Palettes[CurrentTheme].ink); }
static NSColor *Muted(void) { return RGB(Palettes[CurrentTheme].muted); }
static NSColor *Accent(void) { return RGB(Palettes[CurrentTheme].accent); }
static NSColor *Canvas(void) { return RGB(Palettes[CurrentTheme].canvas); }
static NSColor *Card(void) { return RGB(0xFFFFFF); }
static NSColor *Line(void) { return RGB(Palettes[CurrentTheme].line); }
static NSColor *Tint(void) { return RGB(Palettes[CurrentTheme].tint); }
static NSColor *Panel(void) { return RGB(Palettes[CurrentTheme].panel); }
static NSColor *Emphasis(void) { return RGB(Palettes[CurrentTheme].emphasis); }
static NSCalendar *Cal(void) { NSCalendar *c = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian]; c.firstWeekday = 2; return c; }

static NSTextField *Text(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color) {
    NSTextField *label = [NSTextField labelWithString:text ?: @""];
    label.font = [NSFont systemFontOfSize:size weight:weight]; label.textColor = color ?: Ink();
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}
static void Put(NSView *parent, NSView *child, CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    child.frame = NSMakeRect(x, y, w, h); [parent addSubview:child];
}
static void Clear(NSView *view) { for (NSView *child in view.subviews.copy) [child removeFromSuperview]; }
static void DrawText(NSString *text, NSRect rect, CGFloat size, NSFontWeight weight, NSColor *color, NSTextAlignment alignment) {
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new]; style.alignment = alignment; style.lineBreakMode = NSLineBreakByTruncatingTail;
    [text drawInRect:rect withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:size weight:weight], NSForegroundColorAttributeName:color, NSParagraphStyleAttributeName:style}];
}

@interface Surface : NSView
@property NSColor *fill;
@property NSColor *stroke;
@property CGFloat radius;
@property(copy) void (^onResize)(void);
@end
@implementation Surface
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5) xRadius:self.radius yRadius:self.radius];
    if (self.fill) { [self.fill setFill]; [path fill]; }
    if (self.stroke) { [self.stroke setStroke]; [path stroke]; }
}
- (void)setFrameSize:(NSSize)size { [super setFrameSize:size]; if (self.onResize) self.onResize(); }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES; }
@end

@interface ActionButton : NSButton
@property NSInteger tone;
@property BOOL selected;
@property BOOL hovered;
@property NSString *symbol;
@property NSTrackingArea *hoverArea;
@end
@implementation ActionButton
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) { self.bordered = NO; self.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium]; [self setButtonType:NSButtonTypeMomentaryPushIn]; self.focusRingType = NSFocusRingTypeDefault; }
    return self;
}
- (BOOL)isFlipped { return YES; }
- (void)updateTrackingAreas {
    if (self.hoverArea) [self removeTrackingArea:self.hoverArea];
    self.hoverArea = [[NSTrackingArea alloc] initWithRect:self.bounds options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect) owner:self userInfo:nil];
    [self addTrackingArea:self.hoverArea]; [super updateTrackingAreas];
}
- (void)mouseEntered:(NSEvent *)event { self.hovered = YES; self.needsDisplay = YES; }
- (void)mouseExited:(NSEvent *)event { self.hovered = NO; self.needsDisplay = YES; }
- (void)drawRect:(NSRect)dirtyRect {
    NSColor *fill = self.tone == 1 ? Emphasis() : (self.selected || self.tone == 2 ? Tint() : Card());
    if (self.tone == 3 && !self.selected && !self.hovered) fill = NSColor.clearColor;
    if (self.hovered || self.highlighted) fill = [fill blendedColorWithFraction:0.09 ofColor:Accent()];
    [fill setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 1) xRadius:8 yRadius:8] fill];
    NSColor *color = self.tone == 1 ? Accent() : (self.selected ? Accent() : Ink());
    if (!self.enabled) color = Muted();
    BOOL iconOnly = self.symbol.length && self.title.length == 0;
    CGFloat tx = self.symbol.length ? 35 : 8;
    if (self.symbol.length) {
        NSImage *image = [[NSImage imageWithSystemSymbolName:self.symbol accessibilityDescription:nil] imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithHierarchicalColor:color]];
        CGFloat imageX = iconOnly ? (self.bounds.size.width - 16) / 2 : 12;
        [image drawInRect:NSMakeRect(imageX, (self.bounds.size.height - 16) / 2, 16, 16) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:self.enabled ? 1 : 0.5 respectFlipped:YES hints:nil];
    }
    if (!iconOnly) DrawText(self.title, NSMakeRect(tx, (self.bounds.size.height - 17) / 2, self.bounds.size.width - tx - 8, 18), self.font.pointSize, NSFontWeightMedium, color, self.symbol.length ? NSTextAlignmentLeft : NSTextAlignmentCenter);
    if (self.window.firstResponder == self) { [Accent() setStroke]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 2, 2) xRadius:7 yRadius:7] stroke]; }
}
- (void)viewDidChangeEffectiveAppearance { self.needsDisplay = YES; }
@end
static ActionButton *Button(NSString *title, id target, SEL action, NSInteger tone) {
    ActionButton *b = [[ActionButton alloc] initWithFrame:NSZeroRect]; b.title = title; b.target = target; b.action = action; b.tone = tone; [b setAccessibilityLabel:title]; return b;
}
static Surface *Box(NSColor *fill, CGFloat radius) { Surface *v = [Surface new]; v.fill = fill; v.radius = radius; return v; }

@interface ThemeSegmentedControl : NSSegmentedControl
@end
@implementation ThemeSegmentedControl
- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = NSInsetRect(self.bounds, 0.5, 0.5);
    [Panel() setFill]; [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:9 yRadius:9] fill];
    NSInteger count = self.segmentCount; if (!count) return;
    CGFloat width = NSWidth(bounds) / count;
    for (NSInteger index = 0; index < count; index++) {
        NSRect segment = NSMakeRect(NSMinX(bounds) + index * width, NSMinY(bounds), width, NSHeight(bounds));
        BOOL selected = index == self.selectedSegment;
        if (selected) { [Emphasis() setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(segment, 1, 1) xRadius:8 yRadius:8] fill]; }
        else if (index > 0) { [Line() setStroke]; NSBezierPath *divider = [NSBezierPath bezierPath]; [divider moveToPoint:NSMakePoint(NSMinX(segment), NSMinY(segment) + 7)]; [divider lineToPoint:NSMakePoint(NSMinX(segment), NSMaxY(segment) - 7)]; [divider stroke]; }
        DrawText([self labelForSegment:index], NSInsetRect(segment, 4, 5), 12, selected ? NSFontWeightSemibold : NSFontWeightMedium, selected ? Accent() : Ink(), NSTextAlignmentCenter);
    }
    if (self.window.firstResponder == self) { [Accent() setStroke]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 1.5, 1.5) xRadius:8 yRadius:8] stroke]; }
}
- (void)mouseDown:(NSEvent *)event { [super mouseDown:event]; self.needsDisplay = YES; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES; }
@end
static ThemeSegmentedControl *Segments(NSArray<NSString *> *labels, id target, SEL action) {
    ThemeSegmentedControl *control = [[ThemeSegmentedControl alloc] initWithFrame:NSZeroRect]; control.segmentCount = labels.count;
    for (NSInteger index = 0; index < (NSInteger)labels.count; index++) [control setLabel:labels[index] forSegment:index];
    control.trackingMode = NSSegmentSwitchTrackingSelectOne; control.target = target; control.action = action; control.selectedSegment = 0;
    return control;
}

@interface DayButton : NSButton
@property NSDate *date;
@property BOOL inMonth;
@property BOOL chosen;
@property BOOL today;
@property BOOL compact;
@property NSArray<NSDictionary *> *tasks;
@end
@implementation DayButton
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    NSColor *bg = self.chosen ? Tint() : (self.highlighted ? Tint() : Card());
    [bg setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 2, 2) xRadius:8 yRadius:8] fill];
    CGFloat numberX = self.compact ? (self.bounds.size.width - 24) / 2 : 8;
    if (self.today) {
        [Emphasis() setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(numberX, 4, 24, 24) xRadius:12 yRadius:12] fill];
    }
    DrawText(DDLFormatDate(self.date, @"d"), NSMakeRect(numberX, 7, 24, 19), 12, self.today || self.chosen ? NSFontWeightSemibold : NSFontWeightRegular, self.today ? Accent() : (self.inMonth ? Ink() : Muted()), NSTextAlignmentCenter);
    if (self.compact && self.tasks.count) {
        [Accent() setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect((self.bounds.size.width - 3) / 2, self.bounds.size.height - 6, 3, 3)] fill];
    } else if (!self.compact && self.tasks.count) {
        NSDictionary *first = self.tasks.firstObject;
        NSColor *color = [first[@"completed"] boolValue] ? Muted() : Accent();
        DrawText(first[@"title"], NSMakeRect(8, 33, self.bounds.size.width - 14, 16), 10, NSFontWeightRegular, color, NSTextAlignmentLeft);
        if (self.tasks.count > 1) DrawText([NSString stringWithFormat:@"+%lu", self.tasks.count - 1], NSMakeRect(self.bounds.size.width - 33, 8, 26, 16), 9, NSFontWeightMedium, Accent(), NSTextAlignmentRight);
    }
}
@end

@interface MonthView : Surface
@property NSDate *month;
@property NSDate *selection;
@property NSArray<NSDictionary *> *tasks;
@property BOOL compact;
@property(copy) void (^onSelect)(NSDate *date);
@property(copy) void (^onMonthChange)(NSDate *date);
- (void)reload;
@end
@implementation MonthView
- (void)reload {
    Clear(self); CGFloat w = self.bounds.size.width;
    Put(self, Text(DDLFormatDate(self.month, @"yyyy 年 M 月"), self.compact ? 12 : 17, NSFontWeightSemibold, Ink()), 14, 13, w - 139, 25);
    ActionButton *today = Button(@"今天", self, @selector(goToday:), 3); today.font = [NSFont systemFontOfSize:10]; Put(self, today, w - 123, 10, 43, 28);
    ActionButton *prev = Button(@"‹", self, @selector(changeMonth:), 3); prev.tag = -1; prev.font = [NSFont systemFontOfSize:22]; prev.accessibilityLabel = @"上个月";
    ActionButton *next = Button(@"›", self, @selector(changeMonth:), 3); next.tag = 1; next.font = [NSFont systemFontOfSize:22]; next.accessibilityLabel = @"下个月";
    Put(self, prev, w - 77, 9, 32, 30); Put(self, next, w - 40, 9, 32, 30);
    NSArray *weekdays = @[@"一", @"二", @"三", @"四", @"五", @"六", @"日"];
    CGFloat cellW = (w - 16) / 7, top = self.compact ? 66 : 76, cellH = (self.bounds.size.height - top - 8) / 6;
    for (NSInteger i = 0; i < 7; i++) {
        NSTextField *label = Text(weekdays[i], 10, NSFontWeightMedium, Muted()); label.alignment = NSTextAlignmentCenter;
        Put(self, label, 8 + i * cellW, top - 24, cellW, 18);
    }
    NSCalendar *calendar = Cal(); NSDate *start;
    NSDictionary *tasksByDay = DDLTasksByDay(self.tasks, calendar);
    [calendar rangeOfUnit:NSCalendarUnitMonth startDate:&start interval:NULL forDate:self.month];
    NSInteger offset = ([calendar component:NSCalendarUnitWeekday fromDate:start] + 5) % 7;
    for (NSInteger i = 0; i < 42; i++) {
        NSDate *date = [calendar dateByAddingUnit:NSCalendarUnitDay value:i - offset toDate:start options:0];
        DayButton *b = [[DayButton alloc] initWithFrame:NSZeroRect]; b.date = date; b.bordered = NO; b.title = DDLFormatDate(date, @"M月d日");
        b.inMonth = [calendar component:NSCalendarUnitMonth fromDate:date] == [calendar component:NSCalendarUnitMonth fromDate:self.month];
        b.chosen = [calendar isDate:date inSameDayAsDate:self.selection]; b.today = [calendar isDateInToday:date]; b.compact = self.compact;
        b.tasks = tasksByDay[[calendar startOfDayForDate:date]] ?: @[];
        b.target = self; b.action = @selector(selectDay:);
        b.toolTip = [NSString stringWithFormat:@"%@ · %lu 项", DDLFormatDate(date, @"yyyy年M月d日 EEEE"), b.tasks.count]; b.accessibilityLabel = b.toolTip;
        Put(self, b, 8 + (i % 7) * cellW, top + (i / 7) * cellH, cellW, cellH);
    }
}
- (void)changeMonth:(NSButton *)sender { self.month = [Cal() dateByAddingUnit:NSCalendarUnitMonth value:sender.tag toDate:self.month options:0]; [self reload]; if (self.onMonthChange) self.onMonthChange(self.month); }
- (void)goToday:(id)sender { self.month = NSDate.date; self.selection = NSDate.date; [self reload]; if (self.onSelect) self.onSelect(self.selection); }
- (void)selectDay:(DayButton *)sender { self.selection = sender.date; self.month = sender.date; [self reload]; if (self.onSelect) self.onSelect(sender.date); }
@end

@class AppDelegate;

@interface CallbackButton : ActionButton
@property(copy) void (^onClick)(void);
@end
@implementation CallbackButton
- (instancetype)initWithFrame:(NSRect)frame { if ((self = [super initWithFrame:frame])) { self.target = self; self.action = @selector(invoke:); } return self; }
- (void)invoke:(id)sender { if (self.onClick) self.onClick(); }
@end

static NSColor *EventColor(NSDictionary *task) {
    if ([task[@"completed"] boolValue]) return Adaptive(0x568369, 0xA6D5B6);
    return [task[@"due"] timeIntervalSinceNow] < 0 ? Adaptive(0xB86154, 0xEFACA0) : Accent();
}
static NSColor *EventFill(NSDictionary *task) {
    if ([task[@"completed"] boolValue]) return Adaptive(0xEAF2EB, 0x2C4336);
    return [task[@"due"] timeIntervalSinceNow] < 0 ? Adaptive(0xF9EBE6, 0x49332E) : Tint();
}

@interface CalendarTaskButton : NSButton
@property NSDictionary *task;
@property(copy) void (^onClick)(void);
@end
@implementation CalendarTaskButton
- (BOOL)isFlipped { return YES; }
- (instancetype)initWithFrame:(NSRect)frame { if ((self = [super initWithFrame:frame])) { self.bordered = NO; self.target = self; self.action = @selector(invoke:); } return self; }
- (void)invoke:(id)sender { if (self.onClick) self.onClick(); }
- (void)drawRect:(NSRect)rect {
    BOOL done = [self.task[@"completed"] boolValue]; NSColor *ink = EventColor(self.task);
    [EventFill(self.task) setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0, 1) xRadius:5 yRadius:5] fill];
    CGFloat textY = (self.bounds.size.height - 16) / 2;
    DrawText(done ? @"✓" : ([self.task[@"due"] timeIntervalSinceNow] < 0 ? @"!" : @"○"), NSMakeRect(5, textY, 15, 16), 11, NSFontWeightSemibold, ink, NSTextAlignmentCenter);
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new]; style.lineBreakMode = NSLineBreakByTruncatingTail;
    NSMutableDictionary *attributes = [@{NSFontAttributeName:[NSFont systemFontOfSize:11 weight:NSFontWeightMedium], NSForegroundColorAttributeName:ink, NSParagraphStyleAttributeName:style} mutableCopy];
    if (done) attributes[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
    [self.task[@"title"] drawInRect:NSMakeRect(23, textY, self.bounds.size.width - 28, 16) withAttributes:attributes];
    if (self.highlighted) { [ink setStroke]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 2) xRadius:4 yRadius:4] stroke]; }
}
@end

@interface CalendarDayCell : Surface
@property NSDate *date;
@property BOOL inMonth;
@end
@implementation CalendarDayCell
@end

@interface OverviewGrid : Surface
@property NSDate *month;
@property NSDate *selection;
@property NSDictionary<NSDate *, NSArray<NSDictionary *> *> *tasksByDay;
- (void)updateSelection:(NSDate *)selection;
@property(copy) void (^onSelect)(NSDate *date, NSString *taskID);
- (void)reload;
@end
@implementation OverviewGrid
- (void)updateSelection:(NSDate *)selection {
    NSCalendar *calendar = Cal();
    if ([calendar isDate:self.selection inSameDayAsDate:selection]) return;
    self.selection = selection;
    for (NSView *view in self.subviews) {
        if (![view isKindOfClass:CalendarDayCell.class]) continue;
        CalendarDayCell *cell = (CalendarDayCell *)view;
        BOOL selected = [calendar isDate:cell.date inSameDayAsDate:selection];
        cell.fill = selected ? Panel() : (cell.inMonth ? Card() : Canvas());
        cell.stroke = selected ? Accent() : Line(); cell.needsDisplay = YES;
    }
}
- (void)reload {
    Clear(self);
    NSCalendar *calendar = Cal();
    NSArray<NSDate *> *dates = DDLMonthGrid(self.month, calendar);
    NSInteger rows = dates.count / 7;
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    CGFloat cellW = (width - 16) / 7, cellH = (height - 42) / rows;
    NSArray *weekdays = @[@"周一", @"周二", @"周三", @"周四", @"周五", @"周六", @"周日"];
    for (NSInteger i = 0; i < 7; i++) {
        NSTextField *weekday = Text(weekdays[i], 11, NSFontWeightMedium, Muted());
        Put(self, weekday, 21 + i * cellW, 12, cellW - 22, 18);
    }
    __weak typeof(self) weakSelf = self;
    for (NSInteger i = 0; i < (NSInteger)dates.count; i++) {
        NSDate *date = dates[i];
        BOOL inMonth = [calendar isDate:date equalToDate:self.month toUnitGranularity:NSCalendarUnitMonth];
        BOOL selected = [calendar isDate:date inSameDayAsDate:self.selection];
        BOOL today = [calendar isDateInToday:date];
        NSArray *tasks = self.tasksByDay[[calendar startOfDayForDate:date]] ?: @[];
        CalendarDayCell *cell = [CalendarDayCell new]; cell.date = date; cell.inMonth = inMonth; cell.radius = 9;
        cell.fill = selected ? Panel() : (inMonth ? Card() : Canvas());
        cell.stroke = selected ? Accent() : Line();
        Put(self, cell, 8 + (i % 7) * cellW + 2, 36 + (i / 7) * cellH + 2, cellW - 4, cellH - 4);
        CallbackButton *hit = [[CallbackButton alloc] initWithFrame:cell.bounds]; hit.title = @""; hit.tone = 3; hit.accessibilityLabel = [NSString stringWithFormat:@"%@，%lu 项任务", DDLFormatDate(date, @"yyyy年M月d日 EEEE"), tasks.count]; hit.onClick = ^{ if (weakSelf.onSelect) weakSelf.onSelect(date, nil); }; [cell addSubview:hit];
        CallbackButton *number = [[CallbackButton alloc] initWithFrame:NSZeroRect]; number.title = DDLFormatDate(date, @"d"); number.tone = today ? 1 : 3; number.font = [NSFont systemFontOfSize:12]; number.onClick = hit.onClick; number.accessibilityLabel = hit.accessibilityLabel;
        Put(cell, number, 6, 4, 40, 27); if (!inMonth) number.alphaValue = 0.45;
        if (tasks.count) {
            NSInteger done = 0; for (NSDictionary *t in tasks) if ([t[@"completed"] boolValue]) done++;
            NSTextField *count = Text([NSString stringWithFormat:@"%ld/%lu", (long)done, tasks.count], 9, NSFontWeightMedium, Muted()); count.alignment = NSTextAlignmentRight; count.toolTip = @"已完成 / 当天任务数";
            Put(cell, count, cellW - 48, 11, 32, 15);
        }
        CGFloat eventHeight = cellH < 90 ? 20 : 23, step = eventHeight + 2;
        NSInteger capacity = MAX(1, (NSInteger)((cellH - 38) / step));
        NSInteger shown = MIN((NSInteger)tasks.count, (NSInteger)tasks.count > capacity ? MAX(1, (NSInteger)((cellH - 56) / step)) : capacity);
        for (NSInteger j = 0; j < shown; j++) {
            NSDictionary *task = tasks[j]; CalendarTaskButton *event = [[CalendarTaskButton alloc] initWithFrame:NSZeroRect]; event.task = task; event.title = task[@"title"];
            NSString *state = [task[@"completed"] boolValue] ? @"已完成" : ([task[@"due"] timeIntervalSinceNow] < 0 ? @"已逾期" : @"待完成");
            event.accessibilityLabel = [NSString stringWithFormat:@"%@：%@，%@", state, task[@"title"], DDLFormatDate(task[@"due"], @"M月d日 HH:mm")];
            event.toolTip = [NSString stringWithFormat:@"%@ · %@\n[%@] %@\n点击查看详情", state, task[@"title"], task[@"subject"], DDLFormatDate(task[@"due"], @"yyyy-MM-dd HH:mm")];
            event.onClick = ^{ if (weakSelf.onSelect) weakSelf.onSelect(date, task[@"id"]); };
            Put(cell, event, 6, 32 + j * step, cellW - 16, eventHeight);
        }
        if ((NSInteger)tasks.count > shown) {
            CallbackButton *more = [[CallbackButton alloc] initWithFrame:NSZeroRect]; more.title = [NSString stringWithFormat:@"另 %lu 项 · 查看全部", tasks.count - shown]; more.font = [NSFont systemFontOfSize:9]; more.tone = 3; more.onClick = hit.onClick; more.accessibilityLabel = [NSString stringWithFormat:@"%@，查看全部 %lu 项任务", DDLFormatDate(date, @"M月d日"), tasks.count];
            Put(cell, more, 5, 32 + shown * step, cellW - 14, 16);
        }
    }
}
@end

@interface EditorController : NSWindowController <NSTextFieldDelegate>
@property(weak) AppDelegate *appDelegate;
@property NSDictionary *task;
@property NSTextField *titleField;
@property NSTextField *subjectField;
@property NSTextField *deadlineField;
@property NSTextView *notesField;
@property NSTextField *validation;
@property MonthView *calendar;
@property NSDatePicker *timePicker;
@property NSPopUpButton *priority;
@property NSPopUpButton *reminderPreset;
@property NSTextField *reminderField;
@property NSTextField *reminderValidation;
@property NSDate *selectedDate;
- (instancetype)initWithTask:(NSDictionary *)task owner:(AppDelegate *)owner;
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSSearchFieldDelegate, UNUserNotificationCenterDelegate>
@property NSWindow *window;
@property Surface *root;
@property Surface *sidebar;
@property Surface *header;
@property Surface *document;
@property NSScrollView *scroll;
@property NSSearchField *search;
@property NSSegmentedControl *viewMode;
@property NSSegmentedControl *calendarStatus;
@property NSTextField *calendarHint;
@property NSScrollView *calendarScroll;
@property Surface *calendarDocument;
@property NSDate *calendarBaseMonth;
@property BOOL calendarNeedsCenter;
@property CGFloat calendarSectionHeight;
@property NSPopUpButton *yearPicker;
@property NSPopUpButton *monthPicker;
@property NSTextField *calendarMonthTitle;
@property NSArray<NSTextField *> *calendarSummaryLabels;
@property NSTextField *calendarProgressText;
@property Surface *calendarProgressTrack;
@property Surface *agenda;
@property NSScrollView *agendaScroll;
@property Surface *agendaDocument;
@property NSString *focusedTaskID;
@property NSPopUpButton *sortMenu;
@property NSPopUpButton *themePicker;
@property NSMutableArray<NSMutableDictionary *> *tasks;
@property NSUndoManager *taskUndo;
@property NSStatusItem *statusItem;
@property EditorController *editor;
@property NSInteger filter;
@property BOOL calendarMode;
@property NSDate *month;
@property NSDate *selectedDay;
@property NSString *query;
@property NSString *notice;
@property NSString *notificationStatus;
@property NSString *notificationError;
@property NSInteger authorization;
@property NSInteger scheduledCount;
@property NSInteger notificationGeneration;
@property BOOL preview;
@property BOOL loading;
@property BOOL renderBusy;
@property NSTimer *ticker;
@property NSTimer *searchTimer;
@property NSArray<NSDictionary *> *overviewSnapshot;
@property NSDate *overviewBaseMonth;
@property NSString *overviewTimeZone;
@property NSSize overviewSize;
@property NSInteger overviewMinute;
- (void)render;
- (void)commitTask:(NSDictionary *)task originalID:(NSString *)identifier;
- (void)closeEditor;
- (void)editTask:(id)sender;
- (void)deleteTask:(id)sender;
- (void)restoreTask:(id)sender;
- (void)purgeTask:(id)sender;
- (void)addTask:(id)sender;
- (void)showWindow;
- (void)refreshReminders;
- (void)refreshPermission;
- (void)updateCalendarHeaderState;
- (void)scrollCalendarToMonth:(NSDate *)targetMonth animated:(BOOL)animated;
@end

@implementation EditorController
- (instancetype)initWithTask:(NSDictionary *)task owner:(AppDelegate *)owner {
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 642, 652) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:panel])) {
        self.appDelegate = owner; self.task = task;
        panel.title = task ? @"编辑 DDL" : @"新建 DDL"; panel.releasedWhenClosed = NO;
        Surface *root = Box(Canvas(), 0); root.frame = NSMakeRect(0, 0, 642, 652); panel.contentView = root;
        Put(root, Text(task ? @"让计划更合适。" : @"给下一件事，留个位置。", 22, NSFontWeightSemibold, Ink()), 28, 23, 580, 32);
        Put(root, Text(@"写下任务，再选一个合适的截止时间。", 12, NSFontWeightRegular, Muted()), 28, 62, 580, 20);
        Put(root, Text(@"任务名称", 11, NSFontWeightMedium, Muted()), 28, 99, 380, 18);
        self.titleField = [[NSTextField alloc] initWithFrame:NSZeroRect]; self.titleField.placeholderString = @"例如：完成数据结构实验报告"; self.titleField.stringValue = task[@"title"] ?: @"";
        self.titleField.font = [NSFont systemFontOfSize:15]; Put(root, self.titleField, 28, 121, 586, 30);
        Put(root, Text(@"学科 / 分类", 11, NSFontWeightMedium, Muted()), 28, 163, 300, 18);
        self.subjectField = [[NSTextField alloc] initWithFrame:NSZeroRect]; self.subjectField.placeholderString = @"例如：数据结构（选填）"; self.subjectField.stringValue = task[@"subject"] ?: @"";
        Put(root, self.subjectField, 28, 185, 370, 28);
        Put(root, Text(@"优先级", 11, NSFontWeightMedium, Muted()), 420, 163, 180, 18);
        self.priority = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [self.priority addItemsWithTitles:@[@"普通", @"重要", @"紧急"]]; [self.priority selectItemAtIndex:[task[@"priority"] integerValue]];
        Put(root, self.priority, 418, 184, 198, 30);
        Put(root, Text(@"截止时间", 11, NSFontWeightMedium, Muted()), 28, 226, 300, 18);
        self.selectedDate = task[@"due"] ?: DDLParseDate(@"明天 23:59", NSDate.date, Cal());
        self.deadlineField = [[NSTextField alloc] initWithFrame:NSZeroRect]; self.deadlineField.stringValue = DDLFormatDate(self.selectedDate, @"yyyy-MM-dd HH:mm"); self.deadlineField.placeholderString = @"明天 20:00 / 下周五 / 2026-10-01 23:59"; self.deadlineField.delegate = self;
        Put(root, self.deadlineField, 28, 248, 586, 28);
        self.calendar = [MonthView new]; self.calendar.fill = Card(); self.calendar.stroke = Line(); self.calendar.radius = 12; self.calendar.compact = YES; self.calendar.month = self.selectedDate; self.calendar.selection = self.selectedDate; self.calendar.tasks = @[];
        Put(root, self.calendar, 28, 289, 282, 280); [self.calendar reload];
        __weak typeof(self) weakSelf = self;
        self.calendar.onSelect = ^(NSDate *date) { [weakSelf chooseDate:date]; };
        Put(root, Text(@"具体时间", 11, NSFontWeightMedium, Muted()), 330, 291, 260, 18);
        self.timePicker = [[NSDatePicker alloc] initWithFrame:NSZeroRect]; self.timePicker.datePickerStyle = NSDatePickerStyleTextFieldAndStepper; self.timePicker.datePickerElements = NSDatePickerElementFlagHourMinute; self.timePicker.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"]; self.timePicker.dateValue = self.selectedDate; self.timePicker.target = self; self.timePicker.action = @selector(timeChanged:);
        Put(root, self.timePicker, 330, 315, 128, 28);
        NSPopUpButton *quickTime = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [quickTime addItemsWithTitles:@[@"常用时间", @"09:00", @"12:00", @"18:00", @"20:00", @"22:00", @"23:59"]]; quickTime.target = self; quickTime.action = @selector(quickTime:); Put(root, quickTime, 470, 313, 144, 30);
        NSArray *days = @[@"今天", @"明天", @"一周后"];
        for (NSInteger i = 0; i < 3; i++) { ActionButton *b = Button(days[i], self, @selector(quickDay:), 2); Put(root, b, 330 + i * 96, 355, 89, 30); }
        Put(root, Text(@"电脑提醒 · 可设置多次", 11, NSFontWeightMedium, Muted()), 330, 399, 250, 18);
        self.reminderField = [[NSTextField alloc] initWithFrame:NSZeroRect]; self.reminderField.placeholderString = @"例如：5小时、1小时、到期"; self.reminderField.delegate = self;
        NSArray *initialOffsets = task ? DDLReminderOffsetsForTask(task) : @[@1440, @60, @0]; self.reminderField.stringValue = DDLFormatReminderOffsets(initialOffsets); Put(root, self.reminderField, 328, 421, 288, 28);
        self.reminderPreset = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [self.reminderPreset addItemsWithTitles:@[@"选择常用方案…", @"1天、1小时、到期", @"5小时、1小时、到期", @"仅到期", @"不提醒"]]; self.reminderPreset.target = self; self.reminderPreset.action = @selector(reminderPresetChanged:); Put(root, self.reminderPreset, 328, 452, 146, 28);
        self.reminderValidation = Text(@"", 9, NSFontWeightRegular, Muted()); Put(root, self.reminderValidation, 482, 456, 134, 18); [self validateReminders];
        Put(root, Text(@"备注（选填）", 11, NSFontWeightMedium, Muted()), 330, 488, 250, 18);
        NSScrollView *notesScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect]; notesScroll.borderType = NSBezelBorder; notesScroll.hasVerticalScroller = YES;
        self.notesField = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 266, 49)]; self.notesField.font = [NSFont systemFontOfSize:12]; self.notesField.textContainerInset = NSMakeSize(7, 7); self.notesField.richText = NO; self.notesField.allowsUndo = YES; self.notesField.string = task[@"notes"] ?: @"";
        self.notesField.autoresizingMask = NSViewWidthSizable; self.notesField.textContainer.widthTracksTextView = YES; notesScroll.documentView = self.notesField; Put(root, notesScroll, 330, 510, 284, 59);
        self.validation = Text(@"", 11, NSFontWeightRegular, Muted()); Put(root, self.validation, 28, 580, 580, 19); [self validateDate];
        ActionButton *cancel = Button(@"取消", self, @selector(cancel:), 3); cancel.keyEquivalent = @"\033"; Put(root, cancel, 418, 610, 82, 32);
        ActionButton *save = Button(task ? @"保存修改" : @"添加任务", self, @selector(save:), 1); save.keyEquivalent = @"\r"; Put(root, save, 510, 608, 104, 36);
        self.titleField.nextKeyView = self.subjectField; self.subjectField.nextKeyView = self.priority; self.priority.nextKeyView = self.deadlineField;
        panel.initialFirstResponder = self.titleField;
    }
    return self;
}
- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == self.reminderField) { [self validateReminders]; return; }
    NSDate *date = DDLParseDate(self.deadlineField.stringValue, NSDate.date, Cal());
    if (date) { self.selectedDate = date; self.calendar.selection = date; self.calendar.month = date; [self.calendar reload]; self.timePicker.dateValue = date; }
    [self validateDate];
}
- (void)validateReminders {
    NSArray<NSNumber *> *offsets = DDLParseReminderOffsets(self.reminderField.stringValue);
    if (!offsets) { self.reminderValidation.stringValue = @"格式有误"; self.reminderValidation.textColor = NSColor.systemRedColor; return; }
    self.reminderValidation.stringValue = offsets.count ? [NSString stringWithFormat:@"共 %lu 次提醒", offsets.count] : @"已关闭提醒";
    self.reminderValidation.textColor = offsets.count ? Accent() : Muted();
}
- (void)reminderPresetChanged:(NSPopUpButton *)sender {
    NSArray *values = @[@"", @"1天、1小时、到期", @"5小时、1小时、到期", @"到期", @"不提醒"];
    if (sender.indexOfSelectedItem > 0) self.reminderField.stringValue = values[sender.indexOfSelectedItem];
    [self validateReminders]; [sender selectItemAtIndex:0];
}
- (void)validateDate {
    NSDate *date = DDLParseDate(self.deadlineField.stringValue, NSDate.date, Cal());
    if (!date) { self.validation.stringValue = @"请输入有效日期，例如：明天 20:00、下周五、2026-10-01 23:59"; self.validation.textColor = NSColor.systemRedColor; }
    else if (date.timeIntervalSinceNow <= 0) { self.validation.stringValue = @"这个时间已经过去，保存后会标记为逾期；不会补发过去的提醒。"; self.validation.textColor = NSColor.systemOrangeColor; }
    else { self.validation.stringValue = [NSString stringWithFormat:@"%@ · %@", DDLFormatDate(date, @"M月d日 EEEE HH:mm"), DDLRemaining(date, NSDate.date, NO)]; self.validation.textColor = Accent(); }
}
- (void)updateDate:(NSDate *)date {
    if (!date) return; self.selectedDate = date; self.deadlineField.stringValue = DDLFormatDate(date, @"yyyy-MM-dd HH:mm"); self.calendar.selection = date; self.calendar.month = date; self.timePicker.dateValue = date; [self.calendar reload]; [self validateDate];
}
- (void)chooseDate:(NSDate *)date {
    NSDateComponents *time = [Cal() components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:self.timePicker.dateValue];
    [self updateDate:[Cal() dateBySettingHour:time.hour minute:time.minute second:0 ofDate:date options:0]];
}
- (void)timeChanged:(id)sender {
    NSDate *base = DDLParseDate(self.deadlineField.stringValue, NSDate.date, Cal());
    if (!base) { [self validateDate]; return; }
    NSDateComponents *time = [Cal() components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:self.timePicker.dateValue];
    [self updateDate:[Cal() dateBySettingHour:time.hour minute:time.minute second:0 ofDate:base options:0]];
}
- (void)quickTime:(NSPopUpButton *)sender {
    if (sender.indexOfSelectedItem == 0) return;
    NSDate *base = DDLParseDate(self.deadlineField.stringValue, NSDate.date, Cal());
    if (!base) { [self validateDate]; return; }
    NSArray *parts = [sender.titleOfSelectedItem componentsSeparatedByString:@":"];
    [self updateDate:[Cal() dateBySettingHour:[parts[0] integerValue] minute:[parts[1] integerValue] second:0 ofDate:base options:0]];
    [sender selectItemAtIndex:0];
}
- (void)quickDay:(NSButton *)sender {
    NSDate *day = DDLParseDate(sender.title, NSDate.date, Cal());
    [self chooseDate:day];
}
- (void)cancel:(id)sender { [self.appDelegate closeEditor]; }
- (void)save:(id)sender {
    NSString *title = [self.titleField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!title.length) { self.validation.stringValue = @"先写一个任务名称。"; self.validation.textColor = NSColor.systemRedColor; [self.window makeFirstResponder:self.titleField]; return; }
    NSDate *date = DDLParseDate(self.deadlineField.stringValue, NSDate.date, Cal());
    if (!date) { [self validateDate]; [self.window makeFirstResponder:self.deadlineField]; return; }
    NSArray<NSNumber *> *reminderOffsets = DDLParseReminderOffsets(self.reminderField.stringValue);
    if (!reminderOffsets) { [self validateReminders]; [self.window makeFirstResponder:self.reminderField]; return; }
    NSMutableDictionary *task = self.task ? [self.task mutableCopy] : [@{@"id":NSUUID.UUID.UUIDString, @"completed":@NO, @"archived":@NO} mutableCopy];
    NSString *subject = [self.subjectField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSInteger legacyMode = reminderOffsets.count == 0 ? 4 : ([reminderOffsets isEqual:@[@0]] ? 0 : ([reminderOffsets isEqual:@[@60, @0]] ? 1 : ([reminderOffsets isEqual:@[@1440, @60, @0]] ? 2 : ([reminderOffsets isEqual:@[@4320, @1440, @60, @0]] ? 3 : 2))));
    task[@"title"] = title; task[@"subject"] = subject.length ? subject : @"其他"; task[@"due"] = date; task[@"notes"] = self.notesField.string; task[@"priority"] = @(self.priority.indexOfSelectedItem); task[@"reminder"] = @(legacyMode); task[@"reminderOffsets"] = reminderOffsets;
    [self.appDelegate commitTask:task originalID:self.task[@"id"]]; [self.appDelegate closeEditor];
}
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.preview = [NSProcessInfo.processInfo.arguments containsObject:@"--preview"];
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    CurrentTheme = self.preview ? 0 : ThemeIndex([NSUserDefaults.standardUserDefaults objectForKey:ThemePreferenceKey]);
    if (!self.preview) {
        NSArray *running = [NSRunningApplication runningApplicationsWithBundleIdentifier:NSBundle.mainBundle.bundleIdentifier];
        for (NSRunningApplication *other in running) if (other.processIdentifier != NSProcessInfo.processInfo.processIdentifier) {
            NSAlert *alert = [NSAlert new]; alert.messageText = @"另一个 DDL Manager 正在运行"; alert.informativeText = @"请先退出旧版本或预览窗口，再打开本版，避免两个版本同时保存任务。"; [alert addButtonWithTitle:@"知道了"]; [NSApp activateIgnoringOtherApps:YES]; [alert runModal]; [NSApp terminate:nil]; return;
        }
    }
    self.filter = 0; self.calendarMode = YES; self.query = @""; self.month = NSDate.date; self.selectedDay = NSDate.date; self.notice = @"";
    self.taskUndo = [NSUndoManager new]; self.taskUndo.levelsOfUndo = 30;
    self.notificationStatus = self.preview ? @"演示模式 · 提醒未发送" : @"正在检查通知权限…";
    self.authorization = -1;
    self.tasks = [NSMutableArray array];
    if (self.preview) [self loadPreview];
    else {
        id stored = [NSUserDefaults.standardUserDefaults objectForKey:@"ddl-manager.tasks.v1"];
        if ([stored isKindOfClass:NSArray.class]) {
            NSArray *valid = DDLNormalizeTasks(stored); [self.tasks addObjectsFromArray:valid];
            if (valid.count != [stored count]) {
                [NSUserDefaults.standardUserDefaults setObject:stored forKey:@"ddl-manager.recovery.original.v3"];
                self.notice = @"部分旧数据格式异常，原始内容已另存备份。";
            }
        } else if (stored) {
            [NSUserDefaults.standardUserDefaults setObject:stored forKey:@"ddl-manager.recovery.original.v3"];
            self.notice = @"旧数据格式异常，原始内容已另存备份。";
        }
    }
    [self installMenu];
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1280, 840) styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView) backing:NSBackingStoreBuffered defer:NO];
    self.window.title = self.preview ? @"DDL Manager · 界面预览" : @"DDL Manager"; self.window.titleVisibility = NSWindowTitleHidden; self.window.titlebarAppearsTransparent = YES;
    self.window.minSize = NSMakeSize(1100, 760); self.window.releasedWhenClosed = NO; self.window.delegate = self; self.window.movableByWindowBackground = YES;
    if (self.preview && [NSProcessInfo.processInfo.arguments containsObject:@"--compact"]) [self.window setContentSize:NSMakeSize(1100, 760)];
    self.window.backgroundColor = Canvas();
    self.root = Box(Canvas(), 0); self.root.frame = NSMakeRect(0, 0, 1280, 840); self.window.contentView = self.root;
    self.sidebar = Box(Panel(), 0); [self.root addSubview:self.sidebar];
    self.header = Box(Canvas(), 0); [self.root addSubview:self.header];
    self.search = [[NSSearchField alloc] initWithFrame:NSZeroRect]; self.search.placeholderString = @"搜索任务、学科、备注"; self.search.delegate = self; self.search.sendsSearchStringImmediately = YES; self.search.font = [NSFont systemFontOfSize:12]; [self.root addSubview:self.search];
    self.viewMode = Segments(@[@"清单", @"总日历"], self, @selector(changeView:)); [self.root addSubview:self.viewMode];
    self.calendarStatus = Segments(@[@"全部", @"待完成", @"已完成"], self, @selector(changeCalendarStatus:)); [self.root addSubview:self.calendarStatus];
    self.calendarHint = Text(@"", 10, NSFontWeightRegular, Muted()); [self.root addSubview:self.calendarHint];
    self.sortMenu = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [self.sortMenu addItemsWithTitles:@[@"按截止时间", @"按优先级"]]; self.sortMenu.target = self; self.sortMenu.action = @selector(sortChanged:); [self.root addSubview:self.sortMenu];
    self.scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect]; self.scroll.hasVerticalScroller = YES; self.scroll.autohidesScrollers = YES; self.scroll.drawsBackground = NO;
    self.document = Box(Canvas(), 0); self.scroll.documentView = self.document; [self.root addSubview:self.scroll];
    self.calendarScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect]; self.calendarScroll.hasVerticalScroller = YES; self.calendarScroll.autohidesScrollers = NO; self.calendarScroll.drawsBackground = NO; self.calendarScroll.borderType = NSNoBorder;
    self.calendarDocument = Box(Canvas(), 0); self.calendarScroll.documentView = self.calendarDocument; [self.root addSubview:self.calendarScroll]; self.calendarBaseMonth = self.month; self.calendarNeedsCenter = YES;
    self.calendarScroll.contentView.postsBoundsChangedNotifications = YES; [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(calendarScrolled:) name:NSViewBoundsDidChangeNotification object:self.calendarScroll.contentView];
    self.agenda = Box(Panel(), 14); [self.root addSubview:self.agenda];
    self.agendaScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect]; self.agendaScroll.hasVerticalScroller = YES; self.agendaScroll.autohidesScrollers = YES; self.agendaScroll.drawsBackground = NO;
    self.agendaDocument = Box(NSColor.clearColor, 0); self.agendaScroll.documentView = self.agendaDocument;
    self.themePicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.themePicker.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    self.themePicker.target = self; self.themePicker.action = @selector(changeTheme:);
    self.themePicker.accessibilityLabel = @"界面配色";
    self.themePicker.toolTip = @"六种淡色配色，选择后立即应用并记住偏好";
    for (NSInteger i = 0; i < (NSInteger)ThemeNames().count; i++) {
        [self.themePicker addItemWithTitle:[@"配色 · " stringByAppendingString:ThemeNames()[i]]];
        NSMenuItem *item = self.themePicker.lastItem; item.representedObject = ThemeIDs()[i];
        unsigned swatch = Palettes[i].emphasis, outline = Palettes[i].accent;
        item.image = [NSImage imageWithSize:NSMakeSize(14, 14) flipped:NO drawingHandler:^BOOL(NSRect rect) {
            NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, 1, 1)];
            [RGB(swatch) setFill]; [circle fill]; [RGB(outline) setStroke]; [circle stroke]; return YES;
        }];
    }
    [self.themePicker selectItemAtIndex:CurrentTheme]; [self.root addSubview:self.themePicker];
    __weak typeof(self) weakSelf = self;
    self.root.onResize = ^{ [weakSelf layout]; };
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"checklist" accessibilityDescription:@"DDL Manager"];
    self.statusItem.button.imagePosition = NSImageLeft; self.statusItem.button.target = self; self.statusItem.button.action = @selector(statusClick:); [self.statusItem.button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];
    [self layout]; [self.window center]; [self showWindow];
    if (!self.preview) { UNUserNotificationCenter.currentNotificationCenter.delegate = self; [self refreshPermission]; [self refreshReminders]; }
    self.ticker = [NSTimer timerWithTimeInterval:60 target:self selector:@selector(tick:) userInfo:nil repeats:YES]; [NSRunLoop.mainRunLoop addTimer:self.ticker forMode:NSRunLoopCommonModes];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(woke:) name:NSWorkspaceDidWakeNotification object:nil];
}
- (void)changeTheme:(NSPopUpButton *)sender {
    CurrentTheme = ThemeIndex(sender.selectedItem.representedObject);
    if (!self.preview) [NSUserDefaults.standardUserDefaults setObject:ThemeIDs()[CurrentTheme] forKey:ThemePreferenceKey];
    self.window.backgroundColor = Canvas();
    for (Surface *surface in @[self.root, self.header, self.document, self.calendarDocument]) { surface.fill = Canvas(); surface.needsDisplay = YES; }
    self.sidebar.fill = Panel(); self.sidebar.needsDisplay = YES;
    self.agenda.fill = Panel(); self.agenda.needsDisplay = YES;
    self.calendarHint.textColor = Muted();
    // Rebuild cached colors while preserving the date, scroll position and filters.
    self.overviewSnapshot = nil;
    [self render]; self.root.needsDisplay = YES;
    self.viewMode.needsDisplay = YES; self.calendarStatus.needsDisplay = YES;
}
- (void)loadPreview {
    NSArray *samples = @[
        @[@"数据结构", @"完成二叉树实验报告", @0, @20, @0, @2, @NO, @"整理实验结果，附上运行截图。"],
        @[@"英语", @"阅读论文并完成摘要", @1, @18, @0, @1, @NO, @"重点阅读 Introduction 和 Discussion。"],
        @[@"设计", @"整理作品集第一版", @3, @23, @59, @0, @NO, @"梳理三个最有代表性的项目。"],
        @[@"高等数学", @"提交第六周习题", @0, @23, @59, @1, @NO, @""],
        @[@"生活", @"预约周末的羽毛球场", @2, @12, @0, @0, @NO, @""],
        @[@"计算机网络", @"复习 TCP / IP 协议", @-1, @18, @0, @0, @YES, @""],
        @[@"英语", @"完成课程阅读", @0, @9, @0, @0, @YES, @"已经整理好阅读笔记。"],
        @[@"设计", @"小组方案沟通", @0, @17, @30, @1, @NO, @"带上草图，与大家确认下一步。"],
        @[@"高等数学", @"订正第二章错题", @-3, @21, @0, @0, @YES, @""],
        @[@"写作", @"提交读书心得", @-2, @18, @0, @1, @NO, @"补充最后一段思考。"],
        @[@"计算机网络", @"完成网络实验", @-9, @20, @0, @0, @YES, @""],
        @[@"英语", @"单词与听力复习", @-15, @20, @0, @0, @YES, @""],
        @[@"数据结构", @"完成链表练习", @-18, @23, @59, @0, @YES, @""]
    ];
    for (NSArray *row in samples) {
        NSDate *day = [Cal() dateByAddingUnit:NSCalendarUnitDay value:[row[2] integerValue] toDate:NSDate.date options:0];
        NSDate *due = [Cal() dateBySettingHour:[row[3] integerValue] minute:[row[4] integerValue] second:0 ofDate:day options:0];
        [self.tasks addObject:[@{@"id":NSUUID.UUID.UUIDString, @"subject":row[0], @"title":row[1], @"due":due, @"priority":row[5], @"completed":row[6], @"archived":@NO, @"notes":row[7], @"reminder":@2} mutableCopy]];
    }
}
- (void)installMenu {
    NSMenu *menu = [NSMenu new];
    NSMenuItem *appItem = [NSMenuItem new]; [menu addItem:appItem]; NSMenu *app = [[NSMenu alloc] initWithTitle:@"DDL Manager"]; appItem.submenu = app;
    [app addItemWithTitle:@"关于 DDL Manager" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    NSMenuItem *settings = [app addItemWithTitle:@"提醒设置…" action:@selector(showNotificationSettings:) keyEquivalent:@","]; settings.target = self;
    [app addItem:[NSMenuItem separatorItem]]; [app addItemWithTitle:@"隐藏 DDL Manager" action:@selector(hide:) keyEquivalent:@"h"];
    [app addItemWithTitle:@"退出 DDL Manager" action:@selector(terminate:) keyEquivalent:@"q"];
    NSMenuItem *fileItem = [NSMenuItem new]; [menu addItem:fileItem]; NSMenu *file = [[NSMenu alloc] initWithTitle:@"任务"]; fileItem.submenu = file;
    NSMenuItem *add = [file addItemWithTitle:@"新建 DDL" action:@selector(addTask:) keyEquivalent:@"n"]; add.target = self;
    NSMenuItem *search = [file addItemWithTitle:@"搜索任务" action:@selector(focusSearch:) keyEquivalent:@"f"]; search.target = self;
    NSMenuItem *calendar = [file addItemWithTitle:@"总览日历" action:@selector(openCalendar:) keyEquivalent:@"2"]; calendar.target = self;
    NSMenuItem *list = [file addItemWithTitle:@"返回清单" action:@selector(openList:) keyEquivalent:@"1"]; list.target = self;
    NSMenuItem *export = [file addItemWithTitle:@"导出任务备份…" action:@selector(exportTasks:) keyEquivalent:@""]; export.target = self;
    NSMenuItem *restore = [file addItemWithTitle:@"导入任务备份…" action:@selector(importTasks:) keyEquivalent:@""]; restore.target = self;
    [file addItemWithTitle:@"关闭窗口" action:@selector(performClose:) keyEquivalent:@"w"];
    NSMenuItem *editItem = [NSMenuItem new]; [menu addItem:editItem]; NSMenu *edit = [[NSMenu alloc] initWithTitle:@"编辑"]; editItem.submenu = edit;
    [edit addItemWithTitle:@"撤销" action:@selector(undo:) keyEquivalent:@"z"];
    NSMenuItem *redo = [edit addItemWithTitle:@"重做" action:@selector(redo:) keyEquivalent:@"z"]; redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [edit addItem:[NSMenuItem separatorItem]];
    [edit addItemWithTitle:@"剪切" action:@selector(cut:) keyEquivalent:@"x"]; [edit addItemWithTitle:@"复制" action:@selector(copy:) keyEquivalent:@"c"]; [edit addItemWithTitle:@"粘贴" action:@selector(paste:) keyEquivalent:@"v"]; [edit addItemWithTitle:@"全选" action:@selector(selectAll:) keyEquivalent:@"a"];
    NSMenuItem *windowItem = [NSMenuItem new]; [menu addItem:windowItem]; NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"窗口"]; windowItem.submenu = windowMenu;
    NSMenuItem *show = [windowMenu addItemWithTitle:@"显示 DDL Manager" action:@selector(showMain:) keyEquivalent:@"0"]; show.target = self;
    [windowMenu addItemWithTitle:@"最小化" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    NSApp.mainMenu = menu; NSApp.windowsMenu = windowMenu;
}
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window { return self.taskUndo; }
- (void)undo:(id)sender { [self.taskUndo undo]; }
- (void)redo:(id)sender { [self.taskUndo redo]; }
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(undo:)) { item.title = self.taskUndo.undoMenuItemTitle; return self.taskUndo.canUndo; }
    if (item.action == @selector(redo:)) { item.title = self.taskUndo.redoMenuItemTitle; return self.taskUndo.canRedo; }
    return YES;
}
- (void)layout {
    if (!self.scroll) return;
    CGFloat w = self.root.bounds.size.width, h = self.root.bounds.size.height;
    self.themePicker.frame = NSMakeRect(w - 198, 47, 166, 26);
    self.sidebar.hidden = self.calendarMode; self.scroll.hidden = self.calendarMode; self.viewMode.hidden = self.calendarMode; self.sortMenu.hidden = self.calendarMode;
    self.calendarScroll.hidden = !self.calendarMode; self.agenda.hidden = !self.calendarMode; self.calendarStatus.hidden = !self.calendarMode; self.calendarHint.hidden = !self.calendarMode;
    if (self.calendarMode) {
        self.header.frame = NSMakeRect(32, 48, w - 64, 112);
        self.calendarStatus.frame = NSMakeRect(32, 177, 228, 28);
        self.calendarHint.frame = NSMakeRect(280, 183, w - 634, 20);
        self.search.frame = NSMakeRect(w - 326, 176, 294, 30);
        self.calendarScroll.frame = NSMakeRect(32, 223, w - 384, h - 247);
        self.agenda.frame = NSMakeRect(w - 332, 223, 300, h - 247);
        [self render]; return;
    }
    self.sidebar.frame = NSMakeRect(0, 0, 210, h);
    CGFloat toolbarY = self.calendarMode ? 178 : 283;
    self.header.frame = NSMakeRect(240, 52, w - 272, self.calendarMode ? 112 : 212);
    self.viewMode.frame = NSMakeRect(240, toolbarY, 124, 28);
    self.sortMenu.frame = NSMakeRect(w - 168, toolbarY - 1, 136, 30);
    self.search.frame = NSMakeRect(w - 443, toolbarY - 1, 262, 29);
    self.scroll.frame = NSMakeRect(236, toolbarY + 47, w - 262, h - toolbarY - 87);
    [self render];
}
- (NSArray *)visibleTasks {
    NSDate *now = NSDate.date; NSCalendar *calendar = Cal();
    NSArray *tasks = [self.tasks filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *task, NSDictionary *bindings) { return DDLMatchesFilter(task, self.filter, self.query, now, calendar); }]];
    if (self.filter == 5) {
        return [tasks sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            NSDate *da = [a[@"deletedAt"] isKindOfClass:NSDate.class] ? a[@"deletedAt"] : [NSDate distantPast];
            NSDate *db = [b[@"deletedAt"] isKindOfClass:NSDate.class] ? b[@"deletedAt"] : [NSDate distantPast];
            NSComparisonResult comparison = [db compare:da];
            return comparison == NSOrderedSame ? [a[@"title"] localizedStandardCompare:b[@"title"]] : comparison;
        }];
    }
    BOOL priority = self.sortMenu.indexOfSelectedItem == 1;
    return [tasks sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        if (priority && [a[@"priority"] integerValue] != [b[@"priority"] integerValue]) return [b[@"priority"] compare:a[@"priority"]];
        NSComparisonResult comparison = [a[@"due"] compare:b[@"due"]];
        if (comparison == NSOrderedSame) return [a[@"title"] localizedStandardCompare:b[@"title"]];
        return self.filter == 3 ? -comparison : comparison;
    }];
}
- (NSInteger)countFilter:(NSInteger)filter {
    NSDate *now = NSDate.date; NSCalendar *calendar = Cal();
    NSInteger n = 0; for (NSDictionary *task in self.tasks) if (DDLMatchesFilter(task, filter, @"", now, calendar)) n++; return n;
}
- (void)render {
    if (self.renderBusy || !self.document) return; self.renderBusy = YES;
    if (!self.calendarMode) [self renderSidebar];
    [self renderHeader]; [self renderContent];
    NSInteger pending = [self countFilter:0]; self.statusItem.button.title = pending ? [NSString stringWithFormat:@" %ld", (long)pending] : @""; self.statusItem.button.toolTip = [NSString stringWithFormat:@"%ld 项待完成 · 点击打开 / 右键菜单", (long)pending];
    self.renderBusy = NO;
}
- (void)renderSidebar {
    Clear(self.sidebar); CGFloat h = self.sidebar.bounds.size.height;
    Surface *logo = Box(Emphasis(), 10); Put(self.sidebar, logo, 23, 64, 37, 37);
    NSTextField *mark = Text(@"✓", 23, NSFontWeightMedium, Accent()); mark.alignment = NSTextAlignmentCenter; Put(logo, mark, 0, 4, 37, 30);
    Put(self.sidebar, Text(@"DDL Manager", 15, NSFontWeightSemibold, Ink()), 70, 64, 130, 24);
    Put(self.sidebar, Text(@"一点计划，很多从容", 10, NSFontWeightRegular, Muted()), 70, 90, 130, 17);
    Put(self.sidebar, Text(@"我的计划", 10, NSFontWeightMedium, Muted()), 25, 143, 160, 18);
    ActionButton *calendar = Button(@"总览日历", self, @selector(openCalendar:), 2); calendar.symbol = @"calendar"; calendar.toolTip = @"查看整月待办与已完成任务（⌘2）"; Put(self.sidebar, calendar, 14, 167, 182, 39);
    NSArray *names = @[@"待办清单", @"今天", @"未来 7 天", @"已完成", @"已归档", @"最近删除"];
    NSArray *icons = @[@"square.stack", @"sun.max", @"calendar", @"checkmark.circle", @"archivebox", @"trash"];
    for (NSInteger i = 0; i < 6; i++) {
        ActionButton *b = Button([NSString stringWithFormat:@"%@     %ld", names[i], (long)[self countFilter:i]], self, @selector(changeFilter:), 3); b.symbol = icons[i]; b.tag = i; b.selected = self.filter == i;
        Put(self.sidebar, b, 14, 216 + i * 41, 182, 36);
    }
    Surface *tip = Box(Tint(), 12); Put(self.sidebar, tip, 18, h - 223, 174, 96);
    Put(tip, Text(@"留一点空白", 12, NSFontWeightSemibold, Accent()), 14, 14, 146, 20);
    NSTextField *tipText = Text(@"专注眼前的一件事。\n完成之后，记得休息一下。", 10, NSFontWeightRegular, Muted()); tipText.maximumNumberOfLines = 2; tipText.lineBreakMode = NSLineBreakByWordWrapping; Put(tip, tipText, 14, 42, 150, 42);
    ActionButton *notification = Button(@"提醒设置", self, @selector(showNotificationSettings:), 3); notification.symbol = @"bell"; Put(self.sidebar, notification, 16, h - 105, 176, 32);
    NSTextField *status = Text(self.notificationStatus, 9, NSFontWeightRegular, Muted()); status.toolTip = self.notificationStatus; Put(self.sidebar, status, 27, h - 68, 163, 16);
    Put(self.sidebar, Text(self.preview ? @"预览数据 · 不会保存" : @"仅存于此 Mac · v5.2", 9, NSFontWeightRegular, Muted()), 27, h - 35, 168, 17);
}
- (void)renderHeader {
    Clear(self.header); CGFloat w = self.header.bounds.size.width;
    if (self.calendarMode) { [self renderCalendarHeader]; return; }
    Put(self.header, Text([DDLFormatDate(NSDate.date, @"M月d日 · EEEE") uppercaseString], 11, NSFontWeightMedium, Muted()), 0, 0, 380, 22);
    NSArray *titles = @[@"把重要的事，安排好。", @"今天，专注眼前。", @"为接下来的一周留白。", @"每一小步，都算数。", @"暂时收起，也好找回。", @"删掉的，先在这里歇一会儿。"];
    Put(self.header, Text(titles[self.filter], 28, NSFontWeightSemibold, Ink()), 0, 32, w - 148, 42);
    NSInteger overdue = 0;
    for (NSDictionary *task in self.tasks) if (![task[@"completed"] boolValue] && ![task[@"archived"] boolValue] && ![task[@"deleted"] boolValue] && [task[@"due"] timeIntervalSinceNow] < 0) overdue++;
    NSString *subtitle = overdue ? [NSString stringWithFormat:@"有 %ld 项已逾期，给它们一个新的安排吧。", (long)overdue] : @"清单记住截止时间，你只管做好每一步。";
    Put(self.header, Text(self.notice.length ? self.notice : subtitle, 12, NSFontWeightRegular, Muted()), 0, 81, w, 23);
    ActionButton *add = Button(@"新建 DDL", self, @selector(addTask:), 1); add.symbol = @"plus"; add.toolTip = @"新建 DDL（⌘N）"; Put(self.header, add, w - 122, 37, 122, 38);
    if (self.calendarMode) return;
    NSArray *values = @[@([self countFilter:0]), @([self countFilter:1]), @([self countFilter:3])];
    NSArray *labels = @[@"待完成", @"今日截止", @"已经完成"];
    NSArray *subtitles = @[@"一步一步，就会完成", @"给今天一个清晰的节奏", @"把进步好好记下来"];
    CGFloat cardW = (w - 24) / 3;
    for (NSInteger i = 0; i < 3; i++) {
        Surface *card = Box(i == 0 ? Tint() : Card(), 12); card.stroke = i == 0 ? nil : Line(); Put(self.header, card, i * (cardW + 12), 123, cardW, 88);
        Put(card, Text(labels[i], 11, NSFontWeightMedium, i == 0 ? Accent() : Muted()), 16, 14, cardW - 74, 18);
        Put(card, Text([values[i] stringValue], 28, NSFontWeightSemibold, Ink()), cardW - 64, 9, 47, 40);
        Put(card, Text(subtitles[i], 10, NSFontWeightRegular, Muted()), 16, 58, cardW - 32, 17);
    }
}
- (Surface *)taskRow:(NSDictionary *)task width:(CGFloat)w {
    BOOL completed = [task[@"completed"] boolValue], archived = [task[@"archived"] boolValue];
    Surface *row = Box(Card(), 12); row.stroke = Line(); row.frame = NSMakeRect(0, 0, w, 98);
    NSButton *check = [NSButton checkboxWithTitle:@"" target:self action:@selector(toggleTask:)]; check.identifier = task[@"id"]; check.state = completed ? NSControlStateValueOn : NSControlStateValueOff; check.toolTip = completed ? @"恢复待完成" : @"标记完成"; check.accessibilityLabel = [NSString stringWithFormat:@"%@：%@", check.toolTip, task[@"title"]]; Put(row, check, 17, 36, 22, 26);
    NSTextField *subject = Text(task[@"subject"], 10, NSFontWeightSemibold, Accent()); Put(row, subject, 53, 12, 155, 18);
    NSInteger p = [task[@"priority"] integerValue]; if (p > 0) Put(row, Text(p == 2 ? @"● 紧急" : @"● 重要", 10, NSFontWeightMedium, p == 2 ? NSColor.systemRedColor : Adaptive(0xA27725, 0xDDBA6F)), 213, 12, 80, 18);
    NSString *remaining = DDLRemaining(task[@"due"], NSDate.date, completed);
    NSTextField *time = Text(remaining, 10, NSFontWeightMedium, !completed && [task[@"due"] timeIntervalSinceNow] < 0 ? NSColor.systemRedColor : Muted()); time.alignment = NSTextAlignmentRight; Put(row, time, w - 175, 12, 155, 18);
    NSTextField *title = Text(task[@"title"], 15, NSFontWeightMedium, completed ? Muted() : Ink()); title.selectable = YES; title.toolTip = task[@"title"]; Put(row, title, 53, 37, completed ? w - 226 : w - 176, 23);
    NSArray<NSNumber *> *offsets = DDLReminderOffsetsForTask(task);
    NSString *reminderText = offsets.count ? [NSString stringWithFormat:@"提醒：%@", DDLFormatReminderOffsets(offsets)] : @"提醒已关闭";
    if (completed || archived) reminderText = @"提醒已停止";
    NSString *detail = [NSString stringWithFormat:@"%@   ·   %@", DDLFormatDate(task[@"due"], @"M月d日 E HH:mm"), reminderText];
    if ([task[@"notes"] length]) detail = [detail stringByAppendingFormat:@"   ·   %@", [task[@"notes"] stringByReplacingOccurrencesOfString:@"\n" withString:@" "]];
    NSTextField *description = Text(detail, 10, NSFontWeightRegular, Muted()); description.toolTip = task[@"notes"]; Put(row, description, 53, 70, w - 135, 17);
    ActionButton *edit = Button(@"编辑", self, @selector(editTask:), 3); edit.identifier = task[@"id"]; edit.accessibilityLabel = [NSString stringWithFormat:@"编辑：%@", task[@"title"]]; Put(row, edit, w - 109, 38, 48, 28);
    ActionButton *more = Button(archived ? @"恢复" : @"归档", self, @selector(archiveTask:), 3); more.identifier = task[@"id"]; more.toolTip = archived ? @"恢复到清单" : @"暂时收起此任务，可在已归档中恢复"; Put(row, more, w - 60, 38, 47, 28);
    if (completed) { ActionButton *remove = Button(@"删除", self, @selector(deleteTask:), 3); remove.identifier = task[@"id"]; remove.accessibilityLabel = [NSString stringWithFormat:@"删除：%@", task[@"title"]]; Put(row, remove, w - 164, 38, 52, 28); }
    NSMenu *context = [NSMenu new]; NSMenuItem *copy = [context addItemWithTitle:@"复制任务内容" action:@selector(copyTask:) keyEquivalent:@""]; copy.target = self; copy.representedObject = task[@"id"];
    NSMenuItem *editItem = [context addItemWithTitle:@"编辑任务…" action:@selector(editTask:) keyEquivalent:@""]; editItem.target = self; editItem.representedObject = task[@"id"]; row.menu = context;
    return row;
}

- (Surface *)deletedRow:(NSDictionary *)task width:(CGFloat)w {
    Surface *row = Box(Card(), 12); row.stroke = Line(); row.frame = NSMakeRect(0, 0, w, 98);
    NSTextField *subject = Text(task[@"subject"], 10, NSFontWeightSemibold, Muted()); Put(row, subject, 17, 13, w - 220, 18);
    NSTextField *title = Text(task[@"title"], 15, NSFontWeightMedium, Muted()); title.selectable = YES; title.toolTip = task[@"title"];
    title.attributedStringValue = [[NSAttributedString alloc] initWithString:task[@"title"] attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:15 weight:NSFontWeightMedium], NSForegroundColorAttributeName:Muted(), NSStrikethroughStyleAttributeName:@(NSUnderlineStyleSingle)}];
    Put(row, title, 17, 35, w - 210, 24);
    NSString *deletedInfo = [task[@"deletedAt"] isKindOfClass:NSDate.class] ? [NSString stringWithFormat:@"删除于 %@ · 截止 %@", DDLFormatDate(task[@"deletedAt"], @"M月d日 HH:mm"), DDLFormatDate(task[@"due"], @"M月d日 HH:mm")] : @"最近删除";
    Put(row, Text(deletedInfo, 10, NSFontWeightRegular, Muted()), 17, 67, w - 210, 17);
    ActionButton *restore = Button(@"恢复", self, @selector(restoreTask:), 2); restore.identifier = task[@"id"]; restore.accessibilityLabel = [NSString stringWithFormat:@"恢复：%@", task[@"title"]]; Put(row, restore, w - 172, 34, 64, 30);
    ActionButton *purge = Button(@"彻底删除", self, @selector(purgeTask:), 3); purge.identifier = task[@"id"]; purge.accessibilityLabel = [NSString stringWithFormat:@"彻底删除：%@", task[@"title"]]; Put(row, purge, w - 104, 34, 90, 30);
    return row;
}

- (void)renderCalendarHeader {
    CGFloat w = self.header.bounds.size.width;
    Put(self.header, Text(@"日程总览  /  DDL MANAGER", 10, NSFontWeightMedium, Muted()), 0, 0, 290, 20);
    self.calendarMonthTitle = Text(@"", 28, NSFontWeightSemibold, Ink()); Put(self.header, self.calendarMonthTitle, 0, 28, 205, 44);
    self.yearPicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSInteger year = 1900; year <= 2200; year++) [self.yearPicker addItemWithTitle:[NSString stringWithFormat:@"%ld 年", (long)year]];
    [self.yearPicker selectItemWithTitle:DDLFormatDate(self.month, @"yyyy 年")]; self.yearPicker.target = self; self.yearPicker.action = @selector(jumpCalendar:); self.yearPicker.toolTip = @"精确跳转到年份";
    self.monthPicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSInteger month = 1; month <= 12; month++) [self.monthPicker addItemWithTitle:[NSString stringWithFormat:@"%ld 月", (long)month]];
    [self.monthPicker selectItemWithTitle:DDLFormatDate(self.month, @"M 月")]; self.monthPicker.target = self; self.monthPicker.action = @selector(jumpCalendar:); self.monthPicker.toolTip = @"精确跳转到月份";
    Put(self.header, self.yearPicker, 208, 34, 88, 30); Put(self.header, self.monthPicker, 300, 34, 66, 30);
    ActionButton *prev = Button(@"", self, @selector(navigateCalendar:), 3); prev.tag = -1; prev.symbol = @"chevron.up"; prev.accessibilityLabel = @"上个月"; prev.toolTip = @"向上翻到上个月";
    ActionButton *today = Button(@"今天", self, @selector(navigateCalendar:), 2); today.tag = 0;
    ActionButton *next = Button(@"", self, @selector(navigateCalendar:), 3); next.tag = 1; next.symbol = @"chevron.down"; next.accessibilityLabel = @"下个月"; next.toolTip = @"向下翻到下个月";
    Put(self.header, prev, 374, 34, 32, 32); Put(self.header, today, 410, 34, 52, 32); Put(self.header, next, 466, 34, 32, 32);
    ActionButton *list = Button(@"返回清单", self, @selector(openList:), 3); list.symbol = @"list.bullet"; Put(self.header, list, w - 252, 29, 112, 38);
    ActionButton *add = Button(@"新建 DDL", self, @selector(addTask:), 1); add.symbol = @"plus"; Put(self.header, add, w - 126, 29, 126, 38);
    NSArray *colors = @[Ink(), Accent(), Adaptive(0x568369, 0xA6D5B6), Adaptive(0xB86154, 0xEFACA0)];
    NSMutableArray<NSTextField *> *summaryLabels = [NSMutableArray array];
    for (NSInteger i = 0; i < 4; i++) {
        Surface *badge = Box(i == 0 ? Tint() : Card(), 7); Put(self.header, badge, i * 127, 82, 117, 28);
        NSTextField *label = Text(@"", 11, NSFontWeightMedium, colors[i]); Put(badge, label, 10, 6, 100, 18); [summaryLabels addObject:label];
    }
    self.calendarSummaryLabels = summaryLabels;
    self.calendarProgressText = Text(@"", 10, NSFontWeightMedium, Muted()); Put(self.header, self.calendarProgressText, w - 210, 78, 210, 18);
    self.calendarProgressTrack = Box(Line(), 3); Put(self.header, self.calendarProgressTrack, w - 210, 104, 210, 5);
    [self updateCalendarHeaderState];
    self.calendarHint.stringValue = self.notice.length ? self.notice : @"上下滚动浏览月份；点击日期或任务，在右侧查看详情。";
    self.calendarHint.toolTip = self.calendarHint.stringValue;
}
- (void)updateCalendarHeaderState {
    if (!self.calendarMode || !self.calendarMonthTitle) return;
    self.calendarMonthTitle.stringValue = DDLFormatDate(self.month, @"yyyy 年 M 月");
    [self.yearPicker selectItemWithTitle:DDLFormatDate(self.month, @"yyyy 年")];
    [self.monthPicker selectItemWithTitle:DDLFormatDate(self.month, @"M 月")];
    NSDictionary *summary = DDLMonthSummary(self.tasks, self.month, NSDate.date, Cal());
    NSArray *labels = @[[NSString stringWithFormat:@"本月 %@ 项", summary[@"total"]], [NSString stringWithFormat:@"○ 待完成  %@", summary[@"pending"]], [NSString stringWithFormat:@"✓ 已完成  %@", summary[@"completed"]], [NSString stringWithFormat:@"! 已逾期  %@", summary[@"overdue"]]];
    for (NSInteger i = 0; i < MIN((NSInteger)labels.count, (NSInteger)self.calendarSummaryLabels.count); i++) self.calendarSummaryLabels[i].stringValue = labels[i];
    double ratio = [summary[@"total"] doubleValue] > 0 ? [summary[@"completed"] doubleValue] / [summary[@"total"] doubleValue] : 0;
    self.calendarProgressText.stringValue = [summary[@"total"] integerValue] ? [NSString stringWithFormat:@"本月完成度  %.0f%%", ratio * 100] : @"这个月，等待新的计划";
    Clear(self.calendarProgressTrack); if (ratio > 0) Put(self.calendarProgressTrack, Box(Accent(), 3), 0, 0, MAX(5, 210 * ratio), 5);
}
- (Surface *)agendaRow:(NSDictionary *)task width:(CGFloat)w {
    BOOL done = [task[@"completed"] boolValue];
    Surface *row = Box(Card(), 11); row.stroke = [self.focusedTaskID isEqual:task[@"id"]] ? Accent() : Line();
    Put(row, Text(task[@"subject"], 10, NSFontWeightSemibold, EventColor(task)), 14, 13, w - 83, 18);
    NSTextField *time = Text(DDLFormatDate(task[@"due"], @"HH:mm"), 11, NSFontWeightSemibold, Ink()); time.alignment = NSTextAlignmentRight; Put(row, time, w - 71, 12, 57, 20);
    NSTextField *title = Text(task[@"title"], 14, NSFontWeightMedium, done ? Muted() : Ink()); title.maximumNumberOfLines = 2; title.lineBreakMode = NSLineBreakByWordWrapping; title.selectable = YES; title.toolTip = task[@"title"];
    if (done) title.attributedStringValue = [[NSAttributedString alloc] initWithString:task[@"title"] attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:14 weight:NSFontWeightMedium], NSForegroundColorAttributeName:Muted(), NSStrikethroughStyleAttributeName:@(NSUnderlineStyleSingle)}];
    Put(row, title, 14, 40, w - 28, 40);
    NSString *state = done ? @"✓ 已完成" : DDLRemaining(task[@"due"], NSDate.date, NO);
    if ([task[@"priority"] integerValue] > 0 && !done) state = [state stringByAppendingString:[task[@"priority"] integerValue] == 2 ? @" · 紧急" : @" · 重要"];
    Put(row, Text(state, 10, NSFontWeightMedium, EventColor(task)), 14, 86, w - 28, 18);
    ActionButton *toggle = Button(done ? @"恢复待办" : @"标记完成", self, @selector(toggleTask:), done ? 2 : 1); toggle.identifier = task[@"id"]; toggle.accessibilityLabel = [NSString stringWithFormat:@"%@：%@", toggle.title, task[@"title"]]; Put(row, toggle, 14, 115, 104, 30);
    ActionButton *edit = Button(@"编辑", self, @selector(editTask:), 3); edit.identifier = task[@"id"]; edit.accessibilityLabel = [NSString stringWithFormat:@"编辑：%@", task[@"title"]]; Put(row, edit, w - 68, 115, 54, 30);
    if (done) { ActionButton *remove = Button(@"删除", self, @selector(deleteTask:), 3); remove.identifier = task[@"id"]; remove.accessibilityLabel = [NSString stringWithFormat:@"删除：%@", task[@"title"]]; Put(row, remove, 124, 115, 54, 30); }
    row.toolTip = task[@"notes"];
    return row;
}
- (void)renderOverview {
    NSArray *visible = DDLCalendarTasks(self.tasks, self.calendarStatus.selectedSegment, self.query);
    NSPoint calendarPosition = self.calendarScroll.contentView.bounds.origin;
    NSCalendar *calendar = Cal();
    NSDictionary *tasksByDay = DDLTasksByDay(visible, calendar);
    if (!self.calendarBaseMonth) self.calendarBaseMonth = self.month;
    NSDate *baseStart = nil; [Cal() rangeOfUnit:NSCalendarUnitMonth startDate:&baseStart interval:NULL forDate:self.calendarBaseMonth];
    CGFloat calendarWidth = self.calendarScroll.contentSize.width;
    self.calendarSectionHeight = MAX(510, self.calendarScroll.contentSize.height);
    NSInteger minute = (NSInteger)floor(NSDate.date.timeIntervalSince1970 / 60);
    BOOL rebuild = ![self.overviewSnapshot isEqualToArray:visible] || ![self.overviewBaseMonth isEqual:baseStart]
        || !NSEqualSizes(self.overviewSize, self.calendarScroll.contentSize) || self.overviewMinute != minute
        || ![self.overviewTimeZone isEqual:calendar.timeZone.name];
    __weak typeof(self) weakSelf = self;
    if (rebuild) {
        Clear(self.calendarDocument);
        for (NSInteger offset = -6; offset <= 6; offset++) {
            NSDate *month = [Cal() dateByAddingUnit:NSCalendarUnitMonth value:offset toDate:baseStart options:0];
            CGFloat sectionY = (offset + 6) * self.calendarSectionHeight;
            NSTextField *monthTitle = Text(DDLFormatDate(month, @"yyyy 年 M 月"), 18, NSFontWeightSemibold, Ink()); Put(self.calendarDocument, monthTitle, 4, sectionY + 6, calendarWidth - 8, 28);
            OverviewGrid *grid = [OverviewGrid new]; grid.fill = Card(); grid.stroke = Line(); grid.radius = 14; grid.month = month; grid.selection = self.selectedDay; grid.tasksByDay = tasksByDay;
            grid.onSelect = ^(NSDate *date, NSString *taskID) {
                weakSelf.selectedDay = date; weakSelf.month = date; weakSelf.focusedTaskID = taskID; weakSelf.notice = @"";
                [weakSelf.agendaScroll.contentView scrollToPoint:NSZeroPoint]; [weakSelf render];
            };
            Put(self.calendarDocument, grid, 0, sectionY + 38, calendarWidth - 6, self.calendarSectionHeight - 48); [grid reload];
        }
        self.overviewSnapshot = [[NSArray alloc] initWithArray:visible copyItems:YES];
        self.overviewBaseMonth = baseStart; self.overviewSize = self.calendarScroll.contentSize; self.overviewMinute = minute;
        self.overviewTimeZone = calendar.timeZone.name;
    } else {
        for (NSView *view in self.calendarDocument.subviews) if ([view isKindOfClass:OverviewGrid.class]) [(OverviewGrid *)view updateSelection:self.selectedDay];
    }
    self.calendarDocument.frame = NSMakeRect(0, 0, calendarWidth, self.calendarSectionHeight * 13);
    if (self.calendarNeedsCenter) calendarPosition.y = self.calendarSectionHeight * 6;
    calendarPosition.y = MAX(0, MIN(calendarPosition.y, self.calendarDocument.frame.size.height - self.calendarScroll.contentSize.height));
    [self.calendarScroll.contentView scrollToPoint:calendarPosition]; [self.calendarScroll reflectScrolledClipView:self.calendarScroll.contentView]; self.calendarNeedsCenter = NO;
    NSPoint position = self.agendaScroll.contentView.bounds.origin;
    Clear(self.agenda); Clear(self.agendaDocument);
    Put(self.agenda, Text(DDLFormatDate(self.selectedDay, @"M 月 d 日"), 23, NSFontWeightSemibold, Ink()), 18, 20, 223, 32);
    ActionButton *add = Button(@"+", self, @selector(addTask:), 2); add.accessibilityLabel = [NSString stringWithFormat:@"为 %@ 新建任务", DDLFormatDate(self.selectedDay, @"M月d日")]; add.font = [NSFont systemFontOfSize:20]; Put(self.agenda, add, 248, 19, 32, 32);
    NSArray *dayTasks = tasksByDay[[calendar startOfDayForDate:self.selectedDay]] ?: @[];
    NSInteger completed = 0; for (NSDictionary *task in dayTasks) if ([task[@"completed"] boolValue]) completed++;
    NSString *detail = [NSString stringWithFormat:@"%@ · %lu 项待做 · %ld 项已完成", DDLFormatDate(self.selectedDay, @"EEEE"), dayTasks.count - completed, (long)completed];
    Put(self.agenda, Text(detail, 10, NSFontWeightRegular, Muted()), 18, 62, 264, 18);
    Put(self.agenda, self.agendaScroll, 12, 96, 276, self.agenda.bounds.size.height - 111);
    CGFloat w = self.agendaScroll.contentSize.width - 4, y = 0, focusY = -1;
    for (NSDictionary *task in dayTasks) {
        if ([self.focusedTaskID isEqual:task[@"id"]]) focusY = y;
        Put(self.agendaDocument, [self agendaRow:task width:w], 2, y, w, 159); y += 171;
    }
    if (!dayTasks.count) {
        NSTextField *mark = Text(@"☀", 32, NSFontWeightLight, Accent()); mark.alignment = NSTextAlignmentCenter; Put(self.agendaDocument, mark, 0, 42, w, 48);
        NSString *message = self.query.length || self.calendarStatus.selectedSegment != 0 ? @"这一天没有匹配的任务" : @"这一天，留一点空白。";
        NSTextField *title = Text(message, 13, NSFontWeightMedium, Ink()); title.alignment = NSTextAlignmentCenter; Put(self.agendaDocument, title, 0, 100, w, 23);
        NSTextField *hint = Text(self.query.length || self.calendarStatus.selectedSegment != 0 ? @"试试切换到「全部」或清空搜索。" : @"也可以点 +，为这一天安排新任务。", 10, NSFontWeightRegular, Muted()); hint.alignment = NSTextAlignmentCenter; Put(self.agendaDocument, hint, 0, 137, w, 36);
        y = 185;
    }
    self.agendaDocument.frame = NSMakeRect(0, 0, self.agendaScroll.contentSize.width, MAX(y, self.agendaScroll.contentSize.height));
    if (focusY >= 0) position.y = focusY;
    position.y = MAX(0, MIN(position.y, self.agendaDocument.frame.size.height - self.agendaScroll.contentSize.height));
    [self.agendaScroll.contentView scrollToPoint:position]; [self.agendaScroll reflectScrolledClipView:self.agendaScroll.contentView];
}
- (void)navigateCalendar:(NSButton *)sender {
    NSDate *targetMonth = nil;
    if (sender.tag == 0) {
        targetMonth = NSDate.date; self.selectedDay = NSDate.date; self.month = targetMonth;
        self.focusedTaskID = nil; self.notice = @""; [self.agendaScroll.contentView scrollToPoint:NSZeroPoint]; [self render];
    }
    else {
        NSDate *first; [Cal() rangeOfUnit:NSCalendarUnitMonth startDate:&first interval:NULL forDate:self.month];
        targetMonth = [Cal() dateByAddingUnit:NSCalendarUnitMonth value:sender.tag toDate:first options:0];
    }
    [self scrollCalendarToMonth:targetMonth animated:YES];
}
- (void)scrollCalendarToMonth:(NSDate *)targetMonth animated:(BOOL)animated {
    if (!targetMonth || self.calendarSectionHeight <= 0 || !self.calendarBaseMonth) return;
    NSDate *baseStart = nil, *targetStart = nil;
    [Cal() rangeOfUnit:NSCalendarUnitMonth startDate:&baseStart interval:NULL forDate:self.calendarBaseMonth];
    [Cal() rangeOfUnit:NSCalendarUnitMonth startDate:&targetStart interval:NULL forDate:targetMonth];
    NSInteger offset = [[Cal() components:NSCalendarUnitMonth fromDate:baseStart toDate:targetStart options:0] month];
    self.month = targetStart;
    if (offset < -6 || offset > 6) {
        self.calendarBaseMonth = targetStart; self.calendarNeedsCenter = YES; [self render]; return;
    }
    CGFloat maximumY = MAX(0, self.calendarDocument.frame.size.height - self.calendarScroll.contentSize.height);
    NSPoint point = NSMakePoint(0, MAX(0, MIN((offset + 6) * self.calendarSectionHeight, maximumY)));
    [self updateCalendarHeaderState];
    if (!animated) { [self.calendarScroll.contentView scrollToPoint:point]; [self.calendarScroll reflectScrolledClipView:self.calendarScroll.contentView]; return; }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.24; context.allowsImplicitAnimation = YES;
        [[self.calendarScroll.contentView animator] setBoundsOrigin:point];
    } completionHandler:^{ [self.calendarScroll reflectScrolledClipView:self.calendarScroll.contentView]; }];
}
- (void)jumpCalendar:(id)sender {
    NSInteger year = self.yearPicker.titleOfSelectedItem.integerValue;
    NSInteger month = self.monthPicker.titleOfSelectedItem.integerValue;
    NSDateComponents *selected = [Cal() components:(NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:self.selectedDay];
    NSDateComponents *firstParts = [NSDateComponents new]; firstParts.year = year; firstParts.month = month; firstParts.day = 1; firstParts.hour = selected.hour; firstParts.minute = selected.minute;
    NSDate *first = [Cal() dateFromComponents:firstParts]; if (!first) return;
    NSInteger lastDay = [Cal() rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitMonth forDate:first].length;
    self.month = first; self.selectedDay = [Cal() dateByAddingUnit:NSCalendarUnitDay value:MIN(lastDay, selected.day) - 1 toDate:first options:0];
    self.calendarBaseMonth = first; self.calendarNeedsCenter = YES; self.focusedTaskID = nil; self.notice = @""; [self.agendaScroll.contentView scrollToPoint:NSZeroPoint]; [self render];
}
- (void)calendarScrolled:(NSNotification *)notification {
    if (!self.calendarMode || self.calendarSectionHeight <= 0 || !self.calendarBaseMonth) return;
    CGFloat centerY = self.calendarScroll.contentView.bounds.origin.y + self.calendarScroll.contentSize.height * 0.45;
    NSInteger index = MAX(0, MIN(12, (NSInteger)floor(centerY / self.calendarSectionHeight)));
    NSDate *baseStart = nil; [Cal() rangeOfUnit:NSCalendarUnitMonth startDate:&baseStart interval:NULL forDate:self.calendarBaseMonth];
    NSDate *visibleMonth = [Cal() dateByAddingUnit:NSCalendarUnitMonth value:index - 6 toDate:baseStart options:0];
    if ([Cal() isDate:visibleMonth equalToDate:self.month toUnitGranularity:NSCalendarUnitMonth]) return;
    self.month = visibleMonth; [self updateCalendarHeaderState];
}
- (void)changeCalendarStatus:(id)sender { self.focusedTaskID = nil; self.notice = @""; [self.agendaScroll.contentView scrollToPoint:NSZeroPoint]; [self render]; }
- (void)openCalendar:(id)sender {
    [self.searchTimer invalidate]; self.searchTimer = nil;
    self.calendarMode = YES; self.calendarStatus.selectedSegment = 0; self.query = @""; self.search.stringValue = @""; self.notice = @""; self.focusedTaskID = nil; self.calendarBaseMonth = self.month; self.calendarNeedsCenter = YES; [self showWindow]; [self layout];
}
- (void)openList:(id)sender { [self.searchTimer invalidate]; self.searchTimer = nil; self.calendarMode = NO; self.viewMode.selectedSegment = 0; self.query = @""; self.search.stringValue = @""; self.notice = @""; [self showWindow]; [self layout]; }
- (void)renderContent {
    if (self.calendarMode) { [self renderOverview]; return; }
    NSPoint position = self.scroll.contentView.bounds.origin;
    Clear(self.document); CGFloat w = self.scroll.contentSize.width - 8, y = 0;
    NSArray *tasks = [self visibleTasks];
    if (self.calendarMode) {
        MonthView *calendar = [MonthView new]; calendar.fill = Card(); calendar.stroke = Line(); calendar.radius = 14; calendar.month = self.month; calendar.selection = self.selectedDay; calendar.tasks = tasks;
        CGFloat calendarHeight = MAX(392, MIN(480, self.scroll.contentSize.height - 8));
        Put(self.document, calendar, 4, 0, w, calendarHeight); [calendar reload];
        __weak typeof(self) weakSelf = self;
        calendar.onSelect = ^(NSDate *date) { weakSelf.month = date; weakSelf.selectedDay = date; [weakSelf renderContent]; };
        calendar.onMonthChange = ^(NSDate *date) { weakSelf.month = date; };
        // Preserve the navigated month when changing task filters or refreshing.
        calendar.onResize = nil;
        y = calendarHeight + 20;
        tasks = [tasks filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *t, NSDictionary *b) { return [Cal() isDate:t[@"due"] inSameDayAsDate:self.selectedDay]; }]];
        Put(self.document, Text([NSString stringWithFormat:@"%@ · %lu 项安排", DDLFormatDate(self.selectedDay, @"M月d日 EEEE"), tasks.count], 13, NSFontWeightSemibold, Ink()), 6, y, w - 12, 24); y += 38;
    } else {
        NSString *heading = self.query.length ? [NSString stringWithFormat:@"搜索结果 · %lu", tasks.count] : [NSString stringWithFormat:@"%@ · %lu", @[@"待办清单", @"今天的安排", @"未来 7 天", @"已完成", @"已归档", @"最近删除"][self.filter], tasks.count];
        Put(self.document, Text(heading, 12, NSFontWeightSemibold, Muted()), 5, 0, w - 12, 22); y = 33;
    }
    if (tasks.count == 0) {
        Surface *empty = Box(Card(), 14); empty.stroke = Line(); Put(self.document, empty, 4, y, w, 202);
        NSTextField *icon = Text(self.query.length ? @"⌕" : @"✓", 32, NSFontWeightLight, Accent()); icon.alignment = NSTextAlignmentCenter; Put(empty, icon, 0, 31, w, 42);
        NSString *emptyTitle = self.query.length ? @"没有找到匹配的任务" : (self.calendarMode ? @"这一天还没有安排" : (self.filter == 5 ? @"最近删除是空的" : @"这里暂时没有任务"));
        NSString *emptyHint = self.query.length ? @"试试学科、任务名称，或清空搜索。" : (self.filter == 5 ? @"删除已完成的任务后会暂时放在这里，可随时恢复。" : @"点右上角「新建 DDL」，开始一份轻松的计划。");
        NSTextField *title = Text(emptyTitle, 16, NSFontWeightSemibold, Ink()); title.alignment = NSTextAlignmentCenter; Put(empty, title, 0, 86, w, 25);
        NSTextField *hint = Text(emptyHint, 12, NSFontWeightRegular, Muted()); hint.alignment = NSTextAlignmentCenter; Put(empty, hint, 0, 124, w, 23);
        y += 218;
    } else {
        for (NSDictionary *task in tasks) {
            Surface *row = self.filter == 5 ? [self deletedRow:task width:w] : [self taskRow:task width:w];
            Put(self.document, row, 4, y, w, 98); y += 109;
        }
    }
    self.document.frame = NSMakeRect(0, 0, self.scroll.contentSize.width, MAX(y + 12, self.scroll.contentSize.height));
    position.y = MIN(position.y, MAX(0, self.document.frame.size.height - self.scroll.contentSize.height)); [self.scroll.contentView scrollToPoint:position]; [self.scroll reflectScrolledClipView:self.scroll.contentView];
}
- (void)changeFilter:(NSButton *)sender { self.filter = sender.tag; self.calendarMode = NO; self.notice = @""; [self.scroll.contentView scrollToPoint:NSZeroPoint]; [self layout]; }
- (void)changeView:(NSSegmentedControl *)sender { if (sender.selectedSegment == 1) [self openCalendar:sender]; else [self openList:sender]; }
- (void)sortChanged:(id)sender { [self renderContent]; }
- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object != self.search) return;
    [self.searchTimer invalidate]; self.searchTimer = nil;
    self.query = [self.search.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    self.focusedTaskID = nil;
    if (!self.query.length) { [self applySearch]; return; }
    __weak typeof(self) weakSelf = self;
    self.searchTimer = [NSTimer scheduledTimerWithTimeInterval:0.18 repeats:NO block:^(NSTimer *timer) { [weakSelf applySearch]; }];
}
- (void)applySearch {
    [self.searchTimer invalidate]; self.searchTimer = nil;
    [self.scroll.contentView scrollToPoint:NSZeroPoint]; [self.agendaScroll.contentView scrollToPoint:NSZeroPoint];
    [self renderContent];
}
- (void)focusSearch:(id)sender { [self showWindow]; [self.window makeFirstResponder:self.search]; }
- (void)showWindow { [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; }
- (void)showMain:(id)sender { [self showWindow]; }
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag { [self showWindow]; return YES; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return NO; }
- (void)applicationDidBecomeActive:(NSNotification *)notification { if (!self.preview && self.window) [self refreshPermission]; }
- (void)tick:(NSTimer *)timer { [self render]; if (!self.preview) [self refreshReminders]; }
- (void)woke:(NSNotification *)notification { [self render]; if (!self.preview) { [self refreshPermission]; [self refreshReminders]; } }
- (void)statusClick:(id)sender {
    if (NSApp.currentEvent.type == NSEventTypeRightMouseUp) {
        NSMenu *menu = [NSMenu new];
        NSMenuItem *show = [menu addItemWithTitle:@"打开 DDL Manager" action:@selector(showMain:) keyEquivalent:@""]; show.target = self;
        NSMenuItem *add = [menu addItemWithTitle:@"新建 DDL" action:@selector(addTask:) keyEquivalent:@""]; add.target = self;
        [menu addItem:[NSMenuItem separatorItem]]; [menu addItemWithTitle:@"退出" action:@selector(terminate:) keyEquivalent:@"q"];
        [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, self.statusItem.button.bounds.size.height) inView:self.statusItem.button];
    } else if (self.window.visible && self.window.keyWindow) [self.window orderOut:nil]; else [self showWindow];
}
- (NSString *)identifierForSender:(id)sender {
    return [sender isKindOfClass:NSMenuItem.class] ? [sender representedObject] : [sender identifier];
}
- (NSMutableDictionary *)taskWithID:(NSString *)identifier { for (NSMutableDictionary *task in self.tasks) if ([task[@"id"] isEqual:identifier]) return task; return nil; }
- (void)addTask:(id)sender {
    [self showWindow]; if (self.window.attachedSheet) return;
    self.editor = [[EditorController alloc] initWithTask:nil owner:self];
    if (self.calendarMode) [self.editor chooseDate:self.selectedDay];
    [self.window beginSheet:self.editor.window completionHandler:nil];
}
- (void)editTask:(id)sender {
    if (self.window.attachedSheet) return; NSDictionary *task = [self taskWithID:[self identifierForSender:sender]]; if (!task) return;
    self.editor = [[EditorController alloc] initWithTask:task owner:self]; [self.window beginSheet:self.editor.window completionHandler:nil];
}
- (void)closeEditor { [self.window endSheet:self.editor.window]; [self.editor.window orderOut:nil]; self.editor = nil; }
- (NSArray *)snapshot { return [[NSArray alloc] initWithArray:self.tasks copyItems:YES]; }
- (void)prepareUndo:(NSString *)name { NSArray *snapshot = [self snapshot]; [self.taskUndo registerUndoWithTarget:self handler:^(AppDelegate *target) { [target restoreSnapshot:snapshot]; }]; [self.taskUndo setActionName:name]; }
- (void)restoreSnapshot:(NSArray *)snapshot { [self prepareUndo:@"任务修改"]; self.tasks = [DDLNormalizeTasks(snapshot) mutableCopy]; self.notice = @"已恢复上一步操作。"; [self persistAndRefresh]; }
- (void)commitTask:(NSDictionary *)task originalID:(NSString *)identifier {
    [self prepareUndo:identifier ? @"编辑任务" : @"添加任务"];
    NSMutableDictionary *existing = [self taskWithID:identifier]; if (existing) [existing setDictionary:task]; else [self.tasks addObject:[task mutableCopy]];
    if (!identifier) { self.filter = 0; self.query = @""; self.search.stringValue = @""; if (self.calendarMode) self.calendarStatus.selectedSegment = 0; }
    if (self.calendarMode) { self.selectedDay = task[@"due"]; self.month = task[@"due"]; self.calendarBaseMonth = self.month; self.calendarNeedsCenter = YES; self.focusedTaskID = task[@"id"]; }
    self.notice = identifier ? @"任务已更新，提醒时间也已同步。" : @"新任务已加入清单。"; [self persistAndRefresh];
}
- (void)toggleTask:(NSButton *)sender {
    NSMutableDictionary *task = [self taskWithID:sender.identifier]; if (!task) return; [self prepareUndo:@"完成状态"];
    task[@"completed"] = @(![task[@"completed"] boolValue]); self.notice = [task[@"completed"] boolValue] ? @"又完成了一件事，做得不错。可按 ⌘Z 撤销。" : @"任务已恢复到待办清单。"; [self persistAndRefresh];
}
- (void)archiveTask:(NSButton *)sender {
    NSMutableDictionary *task = [self taskWithID:sender.identifier]; if (!task) return; [self prepareUndo:@"归档任务"];
    task[@"archived"] = @(![task[@"archived"] boolValue]); self.notice = [task[@"archived"] boolValue] ? @"任务已归档，可在「已归档」中恢复。" : @"任务已恢复。"; [self persistAndRefresh];
}
- (void)deleteTask:(id)sender {
    NSString *identifier = [self identifierForSender:sender];
    NSMutableDictionary *task = [self taskWithID:identifier]; if (!task) return;
    [self prepareUndo:@"删除任务"];
    task[@"deleted"] = @YES; task[@"deletedAt"] = NSDate.date;
    if ([self.focusedTaskID isEqual:identifier]) self.focusedTaskID = nil;
    self.notice = @"任务已移入「最近删除」，可按 ⌘Z 撤销。"; [self persistAndRefresh];
}
- (void)restoreTask:(id)sender {
    NSString *identifier = [self identifierForSender:sender];
    NSMutableDictionary *task = [self taskWithID:identifier]; if (!task) return;
    [self prepareUndo:@"恢复任务"];
    task[@"deleted"] = @NO; [task removeObjectForKey:@"deletedAt"];
    self.notice = @"任务已恢复。"; [self persistAndRefresh];
}
- (void)purgeTask:(id)sender {
    NSString *identifier = [self identifierForSender:sender];
    NSMutableDictionary *task = [self taskWithID:identifier]; if (!task) return;
    [self prepareUndo:@"彻底删除"];
    [self.tasks removeObject:task];
    if ([self.focusedTaskID isEqual:identifier]) self.focusedTaskID = nil;
    self.notice = @"任务已彻底删除，可按 ⌘Z 撤销。"; [self persistAndRefresh];
}
- (void)copyTask:(NSMenuItem *)sender {
    NSDictionary *task = [self taskWithID:sender.representedObject]; if (!task) return;
    NSString *text = [NSString stringWithFormat:@"[%@] %@\n截止：%@\n%@", task[@"subject"], task[@"title"], DDLFormatDate(task[@"due"], @"yyyy-MM-dd HH:mm"), task[@"notes"]];
    [NSPasteboard.generalPasteboard clearContents]; [NSPasteboard.generalPasteboard setString:text forType:NSPasteboardTypeString];
}
- (void)persistAndRefresh {
    if (!self.preview) {
        NSArray *previous = [NSUserDefaults.standardUserDefaults arrayForKey:@"ddl-manager.tasks.v1"];
        if (previous) [NSUserDefaults.standardUserDefaults setObject:previous forKey:@"ddl-manager.tasks.backup.v3"];
        [NSUserDefaults.standardUserDefaults setObject:self.tasks forKey:@"ddl-manager.tasks.v1"];
        [self refreshReminders];
        if (self.authorization == UNAuthorizationStatusNotDetermined) [self requestPermission];
    }
    [self render];
}
- (void)exportTasks:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel]; panel.nameFieldStringValue = [NSString stringWithFormat:@"DDL-备份-%@.plist", DDLFormatDate(NSDate.date, @"yyyyMMdd-HHmmss")]; panel.title = @"导出全部任务备份";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSError *error = nil; NSData *data = [NSPropertyListSerialization dataWithPropertyList:self.tasks format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
        BOOL ok = data && [data writeToURL:panel.URL options:NSDataWritingAtomic error:&error];
        self.notice = ok ? @"任务备份已导出。" : [NSString stringWithFormat:@"导出失败：%@", error.localizedDescription]; [self render];
    }];
}
- (void)importTasks:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel]; panel.canChooseDirectories = NO; panel.allowsMultipleSelection = NO; panel.title = @"导入 DDL 任务备份"; panel.message = @"导入会合并任务，相同内容会跳过。现有任务会保留，也可以按 ⌘Z 撤销导入。";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSError *error; NSData *data = [NSData dataWithContentsOfURL:panel.URL options:NSDataReadingMappedIfSafe error:&error];
        id items = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error] : nil;
        if (![items isKindOfClass:NSArray.class]) { self.notice = @"备份格式无效，请选择本软件导出的 plist 文件。"; [self render]; return; }
        NSArray *valid = DDLNormalizeTasks(items); if (valid.count != [items count]) { self.notice = @"备份含有异常任务，本次未导入。原有任务保持完整。"; [self render]; return; }
        NSArray *merged = DDLMergeTasks(self.tasks, valid); NSInteger added = merged.count - self.tasks.count;
        if (added > 0) { [self prepareUndo:@"导入备份"]; self.tasks = [merged mutableCopy]; [self persistAndRefresh]; }
        self.notice = [NSString stringWithFormat:@"已导入 %ld 项任务，相同内容自动跳过。", (long)added]; [self render];
    }];
}

- (void)refreshPermission {
    if (self.preview) return;
    [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.authorization = settings.authorizationStatus;
            if (self.notificationError.length) self.notificationStatus = @"提醒安排失败 · 点此重试";
            else if (settings.authorizationStatus == UNAuthorizationStatusDenied) self.notificationStatus = @"通知未开启 · 点此设置";
            else if (settings.authorizationStatus == UNAuthorizationStatusNotDetermined) self.notificationStatus = @"允许通知后可收到提醒";
            else if (settings.alertSetting != UNNotificationSettingEnabled) self.notificationStatus = @"横幅未开启 · 点此设置";
            else self.notificationStatus = [NSString stringWithFormat:@"通知已开启 · %ld 条待提醒", (long)self.scheduledCount];
            [self renderSidebar];
        });
    }];
}
- (void)requestPermission {
    if (self.preview) return;
    [UNUserNotificationCenter.currentNotificationCenter requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound completionHandler:^(BOOL granted, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) self.notice = [NSString stringWithFormat:@"通知授权遇到问题：%@", error.localizedDescription];
            else if (!granted) self.notice = @"任务已保存；在系统设置中允许通知后，电脑才能显示提醒。";
            [self refreshPermission]; [self refreshReminders]; [self render];
        });
    }];
}
- (void)refreshReminders {
    if (self.preview) return;
    self.notificationError = nil;
    NSInteger generation = ++self.notificationGeneration;
    NSDate *now = NSDate.date; NSMutableArray *plans = [NSMutableArray array];
    for (NSDictionary *task in [self snapshot]) [plans addObjectsFromArray:DDLReminderPlan(task, now, Cal())];
    [plans sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"date"] compare:b[@"date"]]; }];
    // Keep the nearest reminders queued. Refill while running, on wake, and on launch.
    NSArray *queue = [plans subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)60, plans.count))];
    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
    [center getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> *pending) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.notificationGeneration) return;
            NSMutableDictionary *existing = [NSMutableDictionary dictionary]; for (UNNotificationRequest *r in pending) existing[r.identifier] = r;
            NSMutableSet *desired = [NSMutableSet set];
            dispatch_group_t scheduled = dispatch_group_create();
            for (NSDictionary *plan in queue) {
                NSString *identifier = plan[@"id"]; [desired addObject:identifier]; NSDictionary *task = plan[@"task"];
                NSString *body = [NSString stringWithFormat:@"%@：%@\n截止 %@", plan[@"message"], task[@"title"], DDLFormatDate(task[@"due"], @"M月d日 HH:mm")];
                UNNotificationRequest *old = existing[identifier]; NSDate *oldDate = [old.trigger isKindOfClass:UNCalendarNotificationTrigger.class] ? [(UNCalendarNotificationTrigger *)old.trigger nextTriggerDate] : nil;
                if (oldDate && fabs([oldDate timeIntervalSinceDate:plan[@"date"]]) < 1 && [old.content.body isEqual:body] && [old.content.title isEqual:task[@"subject"]]) continue;
                UNMutableNotificationContent *content = [UNMutableNotificationContent new]; content.title = task[@"subject"]; content.body = body; content.sound = UNNotificationSound.defaultSound; content.threadIdentifier = task[@"id"]; content.userInfo = @{@"taskID":task[@"id"]};
                NSDateComponents *parts = [Cal() components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond) fromDate:plan[@"date"]]; parts.timeZone = NSTimeZone.localTimeZone;
                UNCalendarNotificationTrigger *trigger = [UNCalendarNotificationTrigger triggerWithDateMatchingComponents:parts repeats:NO];
                UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger];
                dispatch_group_enter(scheduled);
                [center addNotificationRequest:request withCompletionHandler:^(NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (error && generation == self.notificationGeneration) { self.notificationError = error.localizedDescription; self.notice = [NSString stringWithFormat:@"提醒安排失败：%@", error.localizedDescription]; [self render]; }
                        dispatch_group_leave(scheduled);
                    });
                }];
            }
            NSMutableArray *stale = [NSMutableArray array];
            for (UNNotificationRequest *request in pending) if (![desired containsObject:request.identifier] && ![request.identifier isEqual:@"ddl.test"]) [stale addObject:request.identifier];
            if (stale.count) [center removePendingNotificationRequestsWithIdentifiers:stale];
            if (plans.count > 60) self.notice = @"已优先安排最近 60 条提醒；保持应用运行以继续补充后续提醒。";
            dispatch_group_notify(scheduled, dispatch_get_main_queue(), ^{
                [center getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> *actual) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (generation != self.notificationGeneration) return;
                        NSInteger count = 0; for (UNNotificationRequest *r in actual) if ([desired containsObject:r.identifier]) count++;
                        self.scheduledCount = count; [self refreshPermission];
                    });
                }];
            });
            NSMutableSet *activeIDs = [NSMutableSet set]; for (NSDictionary *task in self.tasks) if (![task[@"completed"] boolValue] && ![task[@"archived"] boolValue]) [activeIDs addObject:task[@"id"]];
            [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *notifications) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (generation != self.notificationGeneration) return;
                    NSMutableArray *finished = [NSMutableArray array]; for (UNNotification *n in notifications) { NSString *taskID = n.request.content.userInfo[@"taskID"]; if (taskID && ![activeIDs containsObject:taskID]) [finished addObject:n.request.identifier]; }
                    if (finished.count) [center removeDeliveredNotificationsWithIdentifiers:finished];
                });
            }];
        });
    }];
}
- (void)showNotificationSettings:(id)sender {
    [self showWindow]; if (self.window.attachedSheet) return;
    NSAlert *alert = [NSAlert new]; alert.messageText = @"把提醒，交给这台 Mac。";
    if (self.preview) {
        alert.informativeText = @"当前是界面预览，任务只存在内存中，系统通知未注册。正常启动后，可以在这里开启通知、发送测试提醒。"; [alert addButtonWithTitle:@"知道了"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil]; return;
    }
    BOOL notDetermined = self.authorization == UNAuthorizationStatusNotDetermined;
    BOOL denied = self.authorization == UNAuthorizationStatusDenied;
    alert.informativeText = [NSString stringWithFormat:@"%@\n\n每个任务可以设置最多 10 个提醒点，例如「5小时、1小时、到期」。点击测试后，约 5 秒会出现系统通知。\n\n请在系统通知设置中允许 DDL Manager 的横幅和声音。专注模式可能使提醒静音；电脑关机时不显示提醒。关闭窗口后应用仍在菜单栏运行。", self.notificationStatus];
    [alert addButtonWithTitle:notDetermined ? @"允许电脑提醒" : (denied ? @"打开系统设置" : @"发送测试提醒")];
    [alert addButtonWithTitle:@"完成"]; if (!denied) [alert addButtonWithTitle:@"系统通知设置"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) {
            if (notDetermined) [self requestPermission]; else if (denied) [self openSystemNotifications]; else [self testNotification];
        } else if (response == NSAlertThirdButtonReturn) [self openSystemNotifications];
    }];
}
- (void)openSystemNotifications { [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.Notifications-Settings.extension"]]; }
- (void)testNotification {
    if (self.preview) return;
    UNMutableNotificationContent *content = [UNMutableNotificationContent new]; content.title = @"DDL Manager · 提醒测试"; content.body = @"收到这条通知，就说明电脑提醒已准备好。"; content.sound = UNNotificationSound.defaultSound;
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:@"ddl.test" content:content trigger:[UNTimeIntervalNotificationTrigger triggerWithTimeInterval:5 repeats:NO]];
    [UNUserNotificationCenter.currentNotificationCenter addNotificationRequest:request withCompletionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ self.notice = error ? [NSString stringWithFormat:@"测试提醒失败：%@", error.localizedDescription] : @"测试提醒已安排，将在约 5 秒后显示。"; [self render]; });
    }];
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList | UNNotificationPresentationOptionSound);
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))completionHandler {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showWindow]; NSString *identifier = response.notification.request.content.userInfo[@"taskID"];
        if (identifier && !self.window.attachedSheet) { NSMenuItem *item = [NSMenuItem new]; item.representedObject = identifier; [self editTask:item]; }
        completionHandler();
    });
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication; [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        AppDelegate *delegate = [AppDelegate new]; application.delegate = delegate; [application run];
    }
    return 0;
}
