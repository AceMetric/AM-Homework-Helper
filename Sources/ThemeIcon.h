#import <Cocoa/Cocoa.h>

static NSColor *DDLIconColor(unsigned value) {
    return [NSColor colorWithSRGBRed:((value >> 16) & 255) / 255.0
                              green:((value >> 8) & 255) / 255.0
                               blue:(value & 255) / 255.0 alpha:1];
}

// Draws in a 1024 × 1024 coordinate space for both the bundled icon and Dock icon.
static void DDLDrawThemeIcon(unsigned accentHex) {
    NSColor *accent = DDLIconColor(accentHex);
    NSBezierPath *base = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(80, 80, 864, 864) xRadius:195 yRadius:195];
    NSShadow *shadow = [NSShadow new]; shadow.shadowOffset = NSMakeSize(0, -16); shadow.shadowBlurRadius = 30;
    shadow.shadowColor = [NSColor colorWithWhite:0.12 alpha:0.13]; [shadow set];
    NSColor *pale = [NSColor.whiteColor blendedColorWithFraction:0.11 ofColor:accent];
    [[[NSGradient alloc] initWithStartingColor:NSColor.whiteColor endingColor:pale] drawInBezierPath:base angle:-65];
    shadow.shadowColor = NSColor.clearColor; [shadow set];
    [[NSColor.whiteColor blendedColorWithFraction:0.33 ofColor:accent] setStroke]; base.lineWidth = 3; [base stroke];
    NSBezierPath *check = [NSBezierPath bezierPath];
    [check moveToPoint:NSMakePoint(285, 510)]; [check lineToPoint:NSMakePoint(440, 355)]; [check lineToPoint:NSMakePoint(745, 680)];
    check.lineWidth = 105; check.lineCapStyle = NSLineCapStyleRound; check.lineJoinStyle = NSLineJoinStyleRound;
    [accent setStroke]; [check stroke];
}
