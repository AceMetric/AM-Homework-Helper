#import "DDLUI.h"
NSColor *RGB(unsigned value) { return [NSColor colorWithSRGBRed:((value >> 16) & 255) / 255.0 green:((value >> 8) & 255) / 255.0 blue:(value & 255) / 255.0 alpha:1]; }
NSColor *Adaptive(unsigned light, unsigned dark) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        BOOL isDark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqual:NSAppearanceNameDarkAqua];
        return RGB(isDark ? dark : light);
    }];
}
NSColor *Ink(void) { return Adaptive(0x20252D, 0xE8EBF0); }
NSColor *Muted(void) { return Adaptive(0x606977, 0xADB6C5); }
NSColor *Accent(void) { return Adaptive(0x2262B0, 0x85B7FF); }
NSColor *Canvas(void) { return Adaptive(0xF5F6F8, 0x191C22); }
NSColor *Card(void) { return Adaptive(0xFFFFFF, 0x252A32); }
NSColor *Line(void) { return Adaptive(0xDCE0E6, 0x434C5B); }
NSColor *Tint(void) { return Adaptive(0xEAF1FA, 0x293950); }
NSColor *Panel(void) { return Adaptive(0xECEFF3, 0x20242C); }
NSColor *Emphasis(void) { return Adaptive(0xDCEAFE, 0x324C6D); }
NSTextField *Text(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color) {
    NSTextField *label = [NSTextField labelWithString:text ?: @""];
    label.font = [NSFont systemFontOfSize:size weight:weight]; label.textColor = color ?: Ink();
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}
void Put(NSView *parent, NSView *child, CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    child.frame = NSMakeRect(x, y, w, h); [parent addSubview:child];
}
void Clear(NSView *view) { for (NSView *child in view.subviews.copy) [child removeFromSuperview]; }
void DrawText(NSString *text, NSRect rect, CGFloat size, NSFontWeight weight, NSColor *color, NSTextAlignment alignment) {
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new]; style.alignment = alignment; style.lineBreakMode = NSLineBreakByTruncatingTail;
    [text drawInRect:rect withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:size weight:weight], NSForegroundColorAttributeName:color, NSParagraphStyleAttributeName:style}];
}

@implementation DDLFormPanel
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    NSEventModifierFlags modifiers = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift);
    BOOL multiline=[self.firstResponder isKindOfClass:NSTextView.class] && ![(NSTextView *)self.firstResponder isFieldEditor];
    if (((!modifiers && !multiline) || modifiers==NSEventModifierFlagCommand) && ([event.charactersIgnoringModifiers isEqual:@"\r"] || [event.charactersIgnoringModifiers isEqual:@"\003"])) { [self makeFirstResponder:nil]; if (self.onConfirm) { self.onConfirm(); return YES; } }
    if (!modifiers && [event.charactersIgnoringModifiers isEqual:@"\033"] && self.onCancel) { self.onCancel(); return YES; }
    return [super performKeyEquivalent:event];
}
@end

@implementation Surface
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5) xRadius:self.radius yRadius:self.radius];
    if (self.fill) {
        if (self.gradientEnd) [[[NSGradient alloc] initWithStartingColor:self.fill endingColor:self.gradientEnd] drawInBezierPath:path angle:-70];
        else { [self.fill setFill]; [path fill]; }
    }
    if (self.stroke) { [self.stroke setStroke]; [path stroke]; }
}
- (void)setFrameSize:(NSSize)size { [super setFrameSize:size]; if (self.onResize) self.onResize(); }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES; if (self.onAppearanceChange) self.onAppearanceChange(); }
@end

@implementation ActionButton
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) { self.bordered = NO; self.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium]; [self setButtonType:NSButtonTypeMomentaryPushIn]; self.focusRingType = NSFocusRingTypeNone; self.allowsHoverFill = YES; }
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
    BOOL hoverFill = self.allowsHoverFill && (self.hovered || self.highlighted);
    if (self.tone == 3 && !self.selected && !hoverFill) fill = NSColor.clearColor;
    if (hoverFill) fill = [fill blendedColorWithFraction:0.10 ofColor:Accent()];
    NSBezierPath *buttonPath = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 1) xRadius:8 yRadius:8];
    [fill setFill]; [buttonPath fill];
    NSColor *color = self.tone == 1 ? Accent() : (self.selected ? Accent() : Ink());
    if (!self.enabled) color = Muted();
    BOOL iconOnly = self.symbol.length && self.title.length == 0;
    CGFloat tx = self.symbol.length ? 35 : 8;
    if (self.symbol.length) {
        NSImage *image = [[NSImage imageWithSystemSymbolName:self.symbol accessibilityDescription:nil] imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithHierarchicalColor:color]];
        CGFloat imageSize = MIN(16, self.bounds.size.height - 6);
        CGFloat imageX = iconOnly ? (self.bounds.size.width - imageSize) / 2 : 12;
        [image drawInRect:NSMakeRect(imageX, (self.bounds.size.height - imageSize) / 2, imageSize, imageSize) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:self.enabled ? 1 : 0.5 respectFlipped:YES hints:nil];
    }
    if (!iconOnly) DrawText(self.title, NSMakeRect(tx, (self.bounds.size.height - 17) / 2, self.bounds.size.width - tx - 8, 18), self.font.pointSize, NSFontWeightMedium, color, self.symbol.length ? NSTextAlignmentLeft : NSTextAlignmentCenter);
    if (self.window.firstResponder == self) { [Accent() setStroke]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 2, 2) xRadius:7 yRadius:7] stroke]; }
}
- (void)viewDidChangeEffectiveAppearance { self.needsDisplay = YES; }
@end
ActionButton *Button(NSString *title, id target, SEL action, NSInteger tone) {
    ActionButton *b = [[ActionButton alloc] initWithFrame:NSZeroRect]; b.title = title; b.target = target; b.action = action; b.tone = tone; [b setAccessibilityLabel:title]; return b;
}
Surface *Box(NSColor *fill, CGFloat radius) { Surface *v = [Surface new]; v.fill = fill; v.radius = radius; return v; }
Surface *GradientBox(NSColor *start, NSColor *end, CGFloat radius) { Surface *v = Box(start, radius); v.gradientEnd = nil; return v; }

// Shared AppKit form surfaces; native editing and menu keyboard behavior are retained.
static void DrawFieldChrome(NSRect bounds, BOOL focused, BOOL filled) {
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 1, 1) xRadius:8 yRadius:8];
    [(filled ? Tint() : Card()) setFill]; [path fill];
    [(focused ? Accent() : Line()) setStroke]; path.lineWidth = focused ? 1.5 : 1; [path stroke];
}
void ThemeEditor(NSTextView *editor) {
    editor.insertionPointColor = Accent();
    editor.selectedTextAttributes = @{NSBackgroundColorAttributeName:Emphasis(), NSForegroundColorAttributeName:Ink()};
}
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

@implementation PastelNotesView
- (void)updateFocus:(BOOL)focused {
    Surface *surface = (Surface *)self.enclosingScrollView.superview;
    if ([surface isKindOfClass:Surface.class] && surface.radius > 0) { surface.stroke = focused ? Accent() : Line(); surface.needsDisplay = YES; }
    ThemeEditor(self);
}
- (BOOL)becomeFirstResponder { BOOL result = [super becomeFirstResponder]; if (result) [self updateFocus:YES]; return result; }
- (BOOL)resignFirstResponder { BOOL result = [super resignFirstResponder]; if (result) [self updateFocus:NO]; return result; }
@end

@implementation PastelPopUpButton
- (instancetype)initWithFrame:(NSRect)frame pullsDown:(BOOL)pullsDown {
    if ((self = [super initWithFrame:frame pullsDown:pullsDown])) {
        self.bordered = NO; self.focusRingType = NSFocusRingTypeNone; self.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
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
- (void)menuWillOpen:(NSMenu *)menu { for (NSMenuItem *item in menu.itemArray) item.view = nil; }
- (BOOL)becomeFirstResponder { BOOL result = [super becomeFirstResponder]; self.needsDisplay = YES; return result; }
- (BOOL)resignFirstResponder { BOOL result = [super resignFirstResponder]; self.needsDisplay = YES; return result; }
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
ThemeSegmentedControl *Segments(NSArray<NSString *> *labels, id target, SEL action) {
    ThemeSegmentedControl *control = [[ThemeSegmentedControl alloc] initWithFrame:NSZeroRect]; control.segmentCount = labels.count;
    for (NSInteger index = 0; index < (NSInteger)labels.count; index++) [control setLabel:labels[index] forSegment:index];
    control.focusRingType = NSFocusRingTypeNone; control.trackingMode = NSSegmentSwitchTrackingSelectOne; control.target = target; control.action = action; control.selectedSegment = 0;
    return control;
}
