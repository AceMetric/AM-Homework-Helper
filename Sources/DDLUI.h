#import <Cocoa/Cocoa.h>

// Shared, system-adaptive presentation; no persisted theme selection.
NSColor *RGB(unsigned value);
NSColor *Adaptive(unsigned light, unsigned dark);
NSColor *Ink(void); NSColor *Muted(void); NSColor *Accent(void);
NSColor *Canvas(void); NSColor *Card(void); NSColor *Line(void);
NSColor *Tint(void); NSColor *Panel(void); NSColor *Emphasis(void);
NSTextField *Text(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color);
void Put(NSView *parent, NSView *child, CGFloat x, CGFloat y, CGFloat w, CGFloat h);
void Clear(NSView *view);
void DrawText(NSString *text, NSRect rect, CGFloat size, NSFontWeight weight, NSColor *color, NSTextAlignment alignment);
void ThemeEditor(NSTextView *editor);
@interface DDLFormPanel : NSPanel
@property(copy) void (^onConfirm)(void);
@property(copy) void (^onCancel)(void);
@end

@interface Surface : NSView
@property NSColor *fill;
@property NSColor *gradientEnd;
@property NSColor *stroke;
@property CGFloat radius;
@property(copy) void (^onResize)(void);
@property(copy) void (^onAppearanceChange)(void);
@end

@interface ActionButton : NSButton
@property NSInteger tone;
@property BOOL selected;
@property BOOL hovered;
@property BOOL allowsHoverFill;
@property NSString *symbol;
@property NSTrackingArea *hoverArea;
@end

@interface ThemeSegmentedControl : NSSegmentedControl
@end

@interface PastelTextCell : NSTextFieldCell
@end

@interface PastelTextField : NSTextField
@end

@interface PastelNotesView : NSTextView
@end

@interface PastelPopUpButton : NSPopUpButton <NSMenuDelegate>
@end
ActionButton *Button(NSString *title, id target, SEL action, NSInteger tone);
Surface *Box(NSColor *fill, CGFloat radius);
Surface *GradientBox(NSColor *start, NSColor *end, CGFloat radius);
ThemeSegmentedControl *Segments(NSArray<NSString *> *labels, id target, SEL action);
