// Shared AppKit form surfaces; native editing and menu keyboard behavior are retained.
static void DrawFieldChrome(NSRect bounds, BOOL focused, BOOL filled) {
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 1, 1) xRadius:8 yRadius:8];
    [[[NSGradient alloc] initWithStartingColor:(filled ? Tint() : Panel()) endingColor:Card()] drawInBezierPath:path angle:-70];
    [(focused ? Accent() : Line()) setStroke]; path.lineWidth = focused ? 1.5 : 1; [path stroke];
}
static void ThemeEditor(NSTextView *editor) {
    editor.insertionPointColor = Accent();
    editor.selectedTextAttributes = @{NSBackgroundColorAttributeName:Emphasis(), NSForegroundColorAttributeName:Ink()};
}
@interface PastelTextCell : NSTextFieldCell
@end
@implementation PastelTextCell
- (NSRect)textRect:(NSRect)rect {
    CGFloat height = ceil(self.font.ascender - self.font.descender) + 2;
    return NSMakeRect(NSMinX(rect) + 10, NSMinY(rect) + floor((NSHeight(rect) - height) / 2), MAX(0, NSWidth(rect) - 20), height);
}
- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view {
    DrawFieldChrome(frame, [(NSTextField *)view currentEditor] != nil, NO);
    self.textColor = Ink();
    [super drawInteriorWithFrame:[self textRect:frame] inView:view];
}
- (void)editWithFrame:(NSRect)rect inView:(NSView *)view editor:(NSText *)editor delegate:(id)delegate event:(NSEvent *)event {
    ThemeEditor((NSTextView *)editor);
    [super editWithFrame:[self textRect:rect] inView:view editor:editor delegate:delegate event:event];
    ThemeEditor((NSTextView *)editor);
}
- (void)selectWithFrame:(NSRect)rect inView:(NSView *)view editor:(NSText *)editor delegate:(id)delegate start:(NSInteger)start length:(NSInteger)length {
    ThemeEditor((NSTextView *)editor);
    [super selectWithFrame:[self textRect:rect] inView:view editor:editor delegate:delegate start:start length:length];
    ThemeEditor((NSTextView *)editor);
}
@end
@interface PastelTextField : NSTextField
@end
@implementation PastelTextField
+ (Class)cellClass { return PastelTextCell.class; }
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.bezeled = NO; self.bordered = NO; self.drawsBackground = NO; self.focusRingType = NSFocusRingTypeNone;
        self.font = [NSFont systemFontOfSize:13]; self.textColor = Ink(); self.cell.scrollable = YES;
    }
    return self;
}
- (void)setPlaceholderString:(NSString *)placeholder {
    self.placeholderAttributedString = [[NSAttributedString alloc] initWithString:placeholder ?: @"" attributes:@{NSForegroundColorAttributeName:Muted(), NSFontAttributeName:self.font}];
}
- (BOOL)becomeFirstResponder { BOOL result = [super becomeFirstResponder]; ThemeEditor((NSTextView *)self.currentEditor); self.needsDisplay = YES; return result; }
- (BOOL)resignFirstResponder { BOOL result = [super resignFirstResponder]; self.needsDisplay = YES; return result; }
- (void)textDidBeginEditing:(NSNotification *)notification { [super textDidBeginEditing:notification]; ThemeEditor((NSTextView *)self.currentEditor); self.needsDisplay = YES; }
- (void)textDidEndEditing:(NSNotification *)notification { [super textDidEndEditing:notification]; self.needsDisplay = YES; }
@end

@interface PastelNotesView : NSTextView
@end
@implementation PastelNotesView
- (void)updateFocus:(BOOL)focused {
    Surface *surface = (Surface *)self.enclosingScrollView.superview;
    surface.stroke = focused ? Accent() : Line(); surface.needsDisplay = YES;
    ThemeEditor(self);
}
- (BOOL)becomeFirstResponder { BOOL result = [super becomeFirstResponder]; if (result) [self updateFocus:YES]; return result; }
- (BOOL)resignFirstResponder { BOOL result = [super resignFirstResponder]; if (result) [self updateFocus:NO]; return result; }
@end

@interface PastelMenuRow : NSView
@property BOOL hovered;
@property BOOL keyboardHighlighted;
@property NSTrackingArea *hoverArea;
- (void)activate;
@end
@implementation PastelMenuRow
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isFlipped { return YES; }
- (void)updateTrackingAreas {
    if (self.hoverArea) [self removeTrackingArea:self.hoverArea];
    self.hoverArea = [[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:self.hoverArea]; [super updateTrackingAreas];
}
- (void)mouseEntered:(NSEvent *)event { self.hovered = YES; self.needsDisplay = YES; }
- (void)mouseExited:(NSEvent *)event { self.hovered = NO; self.needsDisplay = YES; }
- (void)drawRect:(NSRect)rect {
    NSMenuItem *item = self.enclosingMenuItem;
    [Canvas() setFill]; NSRectFill(self.bounds);
    BOOL highlighted = self.hovered || self.keyboardHighlighted || item.highlighted;
    if (highlighted || item.state == NSControlStateValueOn) {
        [[[NSGradient alloc] initWithStartingColor:(highlighted ? Emphasis() : Tint()) endingColor:(highlighted ? Tint() : Panel())] drawInBezierPath:[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 4, 1) xRadius:6 yRadius:6] angle:-70];
    }
    CGFloat y = floor((NSHeight(self.bounds) - 18) / 2);
    if (item.state == NSControlStateValueOn) DrawText(@"✓", NSMakeRect(10, y, 17, 18), 12, NSFontWeightSemibold, Accent(), NSTextAlignmentCenter);
    CGFloat x = 32;
    if (item.image) { [item.image drawInRect:NSMakeRect(x, y + 1, 14, 14) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil]; x += 21; }
    DrawText(item.title, NSMakeRect(x, y, NSWidth(self.bounds) - x - 12, 18), 12, NSFontWeightMedium, item.enabled ? Ink() : Muted(), NSTextAlignmentLeft);
}
- (void)activate {
    NSMenuItem *item = self.enclosingMenuItem; NSMenu *menu = item.menu;
    if (!item.enabled) return;
    NSInteger index = [menu indexOfItem:item];
    [menu cancelTracking];
    if (index >= 0) [menu performActionForItemAtIndex:index];
}
- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49) [self activate];
    else if (event.keyCode == 53) [self.enclosingMenuItem.menu cancelTracking];
    else [super keyDown:event];
}
- (void)mouseUp:(NSEvent *)event { if (NSPointInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds)) [self activate]; }
- (BOOL)isAccessibilityElement { return YES; }
- (NSString *)accessibilityRole { return NSAccessibilityMenuItemRole; }
- (NSString *)accessibilityLabel { return self.enclosingMenuItem.title; }
- (BOOL)accessibilityPerformPress { [self activate]; return YES; }
@end

@interface PastelPopUpButton : NSPopUpButton <NSMenuDelegate>
@end
@implementation PastelPopUpButton
- (instancetype)initWithFrame:(NSRect)frame pullsDown:(BOOL)pullsDown {
    if ((self = [super initWithFrame:frame pullsDown:pullsDown])) {
        self.bordered = NO; self.focusRingType = NSFocusRingTypeNone; self.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
        self.menu.delegate = self;
    }
    return self;
}
- (void)drawRect:(NSRect)rect {
    DrawFieldChrome(self.bounds, self.window.firstResponder == self || self.highlighted, YES);
    CGFloat x = 11, y = floor((NSHeight(self.bounds) - 18) / 2);
    if (self.selectedItem.image) { [self.selectedItem.image drawInRect:NSMakeRect(x, y + 1, 14, 14) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil]; x += 21; }
    DrawText(self.titleOfSelectedItem ?: @"", NSMakeRect(x, y, MAX(0, NSWidth(self.bounds) - x - 27), 18), self.font.pointSize, NSFontWeightMedium, self.enabled ? Ink() : Muted(), NSTextAlignmentLeft);
    NSBezierPath *chevron = [NSBezierPath bezierPath]; CGFloat cx = NSWidth(self.bounds) - 16, cy = NSMidY(self.bounds);
    [chevron moveToPoint:NSMakePoint(cx - 3, cy - 1.5)]; [chevron lineToPoint:NSMakePoint(cx, cy + 1.5)]; [chevron lineToPoint:NSMakePoint(cx + 3, cy - 1.5)];
    [Muted() setStroke]; chevron.lineWidth = 1.4; [chevron stroke];
}
- (void)menuWillOpen:(NSMenu *)menu {
    CGFloat width = NSWidth(self.bounds);
    for (NSMenuItem *item in menu.itemArray) width = MAX(width, [item.title sizeWithAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium]}].width + (item.image ? 70 : 50));
    for (NSMenuItem *item in menu.itemArray) {
        PastelMenuRow *row = [[PastelMenuRow alloc] initWithFrame:NSMakeRect(0, 0, ceil(width), 29)]; item.view = row;
    }
}
- (void)menu:(NSMenu *)menu willHighlightItem:(NSMenuItem *)item {
    for (NSMenuItem *candidate in menu.itemArray) { PastelMenuRow *row = (PastelMenuRow *)candidate.view; row.keyboardHighlighted = candidate == item; row.needsDisplay = YES; }
}
- (BOOL)becomeFirstResponder { BOOL result = [super becomeFirstResponder]; self.needsDisplay = YES; return result; }
- (BOOL)resignFirstResponder { BOOL result = [super resignFirstResponder]; self.needsDisplay = YES; return result; }
@end
