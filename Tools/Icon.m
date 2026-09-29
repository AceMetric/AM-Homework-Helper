#import <Cocoa/Cocoa.h>
#import "../Sources/ThemeIcon.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) return 1;
        NSString *directory = @(argv[1]);
        for (NSNumber *points in @[@16, @32, @128, @256, @512]) for (NSInteger scale = 1; scale <= 2; scale++) {
            NSInteger pixels = points.integerValue * scale;
            NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:pixels pixelsHigh:pixels bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
            [NSGraphicsContext saveGraphicsState]; [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];
            NSAffineTransform *transform = [NSAffineTransform transform]; [transform scaleBy:pixels / 1024.0]; [transform concat];
            DDLDrawThemeIcon(0x2766B0);
            [NSGraphicsContext restoreGraphicsState];
            NSString *name = [NSString stringWithFormat:@"icon_%@x%@%@.png", points, points, scale == 2 ? @"@2x" : @""];
            NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]; if (![png writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES]) return 2;
        }
        NSArray<NSString *> *names = @[@"icon_16x16.png", @"icon_32x32.png", @"icon_32x32@2x.png", @"icon_128x128.png", @"icon_256x256.png", @"icon_512x512.png", @"icon_512x512@2x.png", @"icon_16x16@2x.png", @"icon_128x128@2x.png", @"icon_256x256@2x.png"];
        NSArray<NSString *> *types = @[@"icp4", @"icp5", @"icp6", @"ic07", @"ic08", @"ic09", @"ic10", @"ic11", @"ic13", @"ic14"];
        NSMutableData *icon = [NSMutableData data];
        [icon appendBytes:"icns" length:4]; uint32_t placeholder = 0; [icon appendBytes:&placeholder length:4];
        for (NSUInteger index = 0; index < names.count; index++) {
            NSData *png = [NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:names[index]]];
            if (!png) return 3;
            [icon appendBytes:types[index].UTF8String length:4];
            uint32_t length = CFSwapInt32HostToBig((uint32_t)png.length + 8); [icon appendBytes:&length length:4];
            [icon appendData:png];
        }
        uint32_t total = CFSwapInt32HostToBig((uint32_t)icon.length); [icon replaceBytesInRange:NSMakeRange(4, 4) withBytes:&total];
        if (![icon writeToFile:@(argv[2]) atomically:YES]) return 4;
    }
    return 0;
}
