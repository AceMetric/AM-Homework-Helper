#import "DDLUI.h"
#import "AMUI-Swift.h"
#import <objc/runtime.h>
NSColor *RGB(unsigned value) { return [NSColor colorWithSRGBRed:((value >> 16) & 255) / 255.0 green:((value >> 8) & 255) / 255.0 blue:(value & 255) / 255.0 alpha:1]; }
NSColor *Adaptive(unsigned light, unsigned dark) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        BOOL isDark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqual:NSAppearanceNameDarkAqua];
        return RGB(isDark ? dark : light);
    }];
}
NSColor *Ink(void) { return AMAppearance.ink; }
NSColor *Muted(void) { return AMAppearance.muted; }
NSColor *Accent(void) { return AMAppearance.accent; }
NSColor *Canvas(void) { return AMAppearance.canvas; }
NSColor *Card(void) { return AMAppearance.surface; }
NSColor *Line(void) { return AMAppearance.separator; }
NSColor *Tint(void) { return AMAppearance.selection; }
NSColor *Panel(void) { return AMAppearance.sidebar; }
NSColor *Emphasis(void) { return AMAppearance.selection; }
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
    if (self.stroke) { BOOL contrast=NSWorkspace.sharedWorkspace.accessibilityDisplayShouldIncreaseContrast;[(contrast ? NSColor.secondaryLabelColor:self.stroke) setStroke];path.lineWidth=contrast ? 1.5:1;[path stroke]; }
}
- (void)setFrameSize:(NSSize)size { [super setFrameSize:size]; if (self.onResize) self.onResize(); }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES; if (self.onAppearanceChange) self.onAppearanceChange(); }
@end

@implementation ActionButton
@synthesize tone=_tone;
@synthesize symbol=_symbol;
- (instancetype)initWithFrame:(NSRect)frame {if((self=[super initWithFrame:frame])){self.bezelStyle=NSBezelStyleRounded;self.font=[NSFont systemFontOfSize:13];[self setButtonType:NSButtonTypeMomentaryPushIn];self.focusRingType=NSFocusRingTypeDefault;}return self;}
- (void)setTone:(NSInteger)tone {
    _tone=tone;self.bordered=tone!=3;self.bezelStyle=NSBezelStyleRounded;
    self.bezelColor=tone==1 ? Accent():nil;self.contentTintColor=nil;
}
- (void)setSymbol:(NSString *)symbol {_symbol=symbol.copy;self.image=symbol.length ? [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil]:nil;self.imagePosition=symbol.length ? (self.title.length ? NSImageLeft:NSImageOnly):NSNoImage;}
@end
ActionButton *Button(NSString *title, id target, SEL action, NSInteger tone) {
    ActionButton *b = [[ActionButton alloc] initWithFrame:NSZeroRect]; b.title = title; b.target = target; b.action = action; b.tone = tone; [b setAccessibilityLabel:title]; return b;
}
Surface *Box(NSColor *fill, CGFloat radius) { Surface *v = [Surface new]; v.fill = fill; v.radius = radius; return v; }
Surface *GradientBox(NSColor *start, NSColor *end, CGFloat radius) { Surface *v = Box(start, radius); v.gradientEnd = nil; return v; }

// System field drawing and focus rings; retain class names for existing controllers.
void ThemeEditor(NSTextView *editor) {editor.insertionPointColor=NSColor.controlAccentColor;editor.selectedTextAttributes=@{NSBackgroundColorAttributeName:NSColor.selectedTextBackgroundColor,NSForegroundColorAttributeName:NSColor.selectedTextColor};}
@implementation PastelTextCell @end
void AMConfigureSingleLineField(NSTextField *field) {
    // isBordered and isBezeled are mutually exclusive in AppKit. Setting
    // isBordered after isBezeled disables the rounded bezel altogether.
    field.bordered=NO;field.bezeled=YES;field.bezelStyle=NSTextFieldRoundedBezel;
    field.controlSize=NSControlSizeRegular;field.drawsBackground=YES;field.backgroundColor=NSColor.textBackgroundColor;
    field.focusRingType=NSFocusRingTypeDefault;field.maximumNumberOfLines=1;
    NSTextFieldCell *cell=(NSTextFieldCell *)field.cell;cell.scrollable=YES;cell.usesSingleLineMode=YES;
}
@implementation PastelTextField
- (instancetype)initWithFrame:(NSRect)frame {if((self=[super initWithFrame:frame])){AMConfigureSingleLineField(self);self.font=[NSFont systemFontOfSize:13];}return self;}
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
        self.bordered = YES; self.bezelStyle = NSBezelStyleRounded; self.focusRingType = NSFocusRingTypeDefault; self.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        self.menu.delegate = self;
    }
    return self;
}
- (void)drawRect:(NSRect)rect { [super drawRect:rect]; }
- (void)menuWillOpen:(NSMenu *)menu { for (NSMenuItem *item in menu.itemArray) item.view = nil; }
- (BOOL)becomeFirstResponder { BOOL result = [super becomeFirstResponder]; self.needsDisplay = YES; return result; }
- (BOOL)resignFirstResponder { BOOL result = [super resignFirstResponder]; self.needsDisplay = YES; return result; }
@end


@interface AMPopupToolbarTarget:NSObject<NSMenuItemValidation>
@property(weak) NSPopUpButton *control;
- (void)choose:(NSMenuItem *)sender;
@end
@implementation AMPopupToolbarTarget
- (void)choose:(NSMenuItem *)sender{if(sender.tag<0 || sender.tag>=self.control.numberOfItems)return;[self.control selectItemAtIndex:sender.tag];[NSApp sendAction:self.control.action to:self.control.target from:self.control];}
- (BOOL)validateMenuItem:(NSMenuItem *)item{item.state=self.control.indexOfSelectedItem==item.tag ? NSControlStateValueOn:NSControlStateValueOff;return self.control.enabled;}
@end
NSToolbarItem *PopupToolbarItem(NSString *identifier,NSString *label,NSPopUpButton *control){
    NSToolbarItem *item=[[NSToolbarItem alloc] initWithItemIdentifier:identifier];item.label=label;[control sizeToFit];item.view=control;
    AMPopupToolbarTarget *target=AMPopupToolbarTarget.new;target.control=control;objc_setAssociatedObject(item,@selector(choose:),target,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSMenuItem *overflow=[[NSMenuItem alloc] initWithTitle:label action:nil keyEquivalent:@""];NSMenu *menu=[[NSMenu alloc] initWithTitle:label];
    for(NSInteger i=0;i<control.numberOfItems;i++){NSMenuItem *choice=[menu addItemWithTitle:[control itemTitleAtIndex:i] action:@selector(choose:) keyEquivalent:@""];choice.tag=i;choice.target=target;}
    overflow.submenu=menu;item.menuFormRepresentation=overflow;return item;
}
@implementation ThemeSegmentedControl
- (void)chooseToolbarSegment:(NSMenuItem *)sender {NSInteger index=sender.tag;if(index<0 || index>=self.segmentCount)return;self.selectedSegment=index;[NSApp sendAction:self.action to:self.target from:self];}
- (BOOL)validateMenuItem:(NSMenuItem *)item {item.state=self.selectedSegment==item.tag ? NSControlStateValueOn:NSControlStateValueOff;return self.enabled;}
- (void)drawRect:(NSRect)dirtyRect { [super drawRect:dirtyRect]; }
- (void)mouseDown:(NSEvent *)event { [super mouseDown:event]; self.needsDisplay = YES; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES; }
@end
static ThemeSegmentedControl *AMSegments(NSArray<NSString *> *labels,id target,SEL action,BOOL navigation) {
    ThemeSegmentedControl *control=[[ThemeSegmentedControl alloc] initWithFrame:NSZeroRect];control.segmentCount=labels.count;
    for(NSInteger index=0;index<(NSInteger)labels.count;index++)[control setLabel:labels[index] forSegment:index];
    control.segmentStyle=NSSegmentStyleAutomatic;control.controlSize=NSControlSizeRegular;control.segmentDistribution=NSSegmentDistributionFit;
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 260000
    if(@available(macOS 26.0,*))control.borderShape=NSControlBorderShapeCapsule;
#endif
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 270000
    if(@available(macOS 27.0,*))control.role=navigation ? NSSegmentedControlRoleTabs:NSSegmentedControlRoleValueSelection;
#endif
    control.focusRingType=NSFocusRingTypeDefault;control.trackingMode=NSSegmentSwitchTrackingSelectOne;control.target=target;control.action=action;control.selectedSegment=0;return control;
}
ThemeSegmentedControl *Segments(NSArray<NSString *> *labels,id target,SEL action){return AMSegments(labels,target,action,YES);}
ThemeSegmentedControl *FilterSegments(NSArray<NSString *> *labels,id target,SEL action){return AMSegments(labels,target,action,NO);}
NSToolbarItem *SegmentToolbarItem(NSString *identifier,NSString *label,NSSegmentedControl *control){
    NSToolbarItem *item=[[NSToolbarItem alloc] initWithItemIdentifier:identifier];item.label=label;control.accessibilityLabel=label;[control sizeToFit];item.view=control;
    NSMenuItem *overflow=[[NSMenuItem alloc] initWithTitle:label action:nil keyEquivalent:@""];NSMenu *menu=[[NSMenu alloc] initWithTitle:label];
    for(NSInteger index=0;index<control.segmentCount;index++){NSMenuItem *choice=[menu addItemWithTitle:[control labelForSegment:index] action:@selector(chooseToolbarSegment:) keyEquivalent:@""];choice.tag=index;choice.target=control;}
    overflow.submenu=menu;item.menuFormRepresentation=overflow;return item;
}
#import "AMNativeUI.inc"
#import "AMProgressUI.inc"
#import "AMActivityUI.inc"

#import "AMRenderer.inc"

@implementation AMCheckWindow
- (void)performClose:(id)sender{[self orderOut:sender];}
@end

NSWindow *AMMakeCheckWorkspace(NSWindow *parent){AMCheckWindow *window=[[AMCheckWindow alloc] initWithContentRect:NSMakeRect(0,0,1120,760) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];window.releasedWhenClosed=NO;window.contentMinSize=NSMakeSize(900,620);if(![window setFrameUsingName:@"AMFileCheckWorkspace"])[window center];[window setFrameAutosaveName:@"AMFileCheckWorkspace"];NSRect available=(parent.screen ?: NSScreen.mainScreen).visibleFrame;NSRect frame=window.frame;frame.size.width=MIN(frame.size.width,available.size.width);frame.size.height=MIN(frame.size.height,available.size.height);frame.origin.x=MAX(NSMinX(available),MIN(frame.origin.x,NSMaxX(available)-frame.size.width));frame.origin.y=MAX(NSMinY(available),MIN(frame.origin.y,NSMaxY(available)-frame.size.height));[window setFrame:frame display:NO];return window;}
