#import <Cocoa/Cocoa.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 1;
        NSString *directory = @(argv[1]);
        for (NSNumber *points in @[@16, @32, @128, @256, @512]) for (NSInteger scale = 1; scale <= 2; scale++) {
            NSInteger pixels = points.integerValue * scale;
            NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:pixels pixelsHigh:pixels bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
            [NSGraphicsContext saveGraphicsState]; [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];
            NSAffineTransform *transform = [NSAffineTransform transform]; [transform scaleBy:pixels / 1024.0]; [transform concat];
            NSBezierPath *base = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(80, 80, 864, 864) xRadius:195 yRadius:195];
            NSShadow *shadow = [NSShadow new]; shadow.shadowOffset = NSMakeSize(0, -18); shadow.shadowBlurRadius = 24; shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.16]; [shadow set];
            [[NSColor colorWithSRGBRed:0.23 green:0.39 blue:0.29 alpha:1] setFill]; [base fill];
            shadow.shadowColor = NSColor.clearColor; [shadow set];
            NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithSRGBRed:0.32 green:0.49 blue:0.38 alpha:1] endingColor:[NSColor colorWithSRGBRed:0.20 green:0.35 blue:0.26 alpha:1]];
            [gradient drawInBezierPath:base angle:-75];
            NSBezierPath *page = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(270, 247, 484, 510) xRadius:56 yRadius:56];
            [[NSColor colorWithSRGBRed:0.95 green:0.97 blue:0.92 alpha:1] setFill]; [page fill];
            [[NSColor colorWithSRGBRed:0.76 green:0.83 blue:0.72 alpha:1] setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(329, 635, 366, 20) xRadius:10 yRadius:10] fill];
            NSBezierPath *check = [NSBezierPath bezierPath]; [check moveToPoint:NSMakePoint(360, 470)]; [check lineToPoint:NSMakePoint(463, 371)]; [check lineToPoint:NSMakePoint(665, 569)]; check.lineWidth = 58; check.lineCapStyle = NSLineCapStyleRound; check.lineJoinStyle = NSLineJoinStyleRound;
            [[NSColor colorWithSRGBRed:0.25 green:0.43 blue:0.32 alpha:1] setStroke]; [check stroke];
            [NSGraphicsContext restoreGraphicsState];
            NSString *name = [NSString stringWithFormat:@"icon_%@x%@%@.png", points, points, scale == 2 ? @"@2x" : @""];
            NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]; if (![png writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES]) return 2;
        }
    }
    return 0;
}
