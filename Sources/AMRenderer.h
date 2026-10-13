#import <Cocoa/Cocoa.h>
void AMPreflightSetRenderer(NSDictionary *(^renderer)(NSString *,NSString *));
void AMInstallRenderer(void);
@interface AMDocumentView : NSView
- (void)loadSnapshot:(NSDictionary *)snapshot path:(NSString *)path;
- (void)highlightRegion:(NSArray *)region;
- (void)showSource:(BOOL)source;
- (void)locateLine:(NSUInteger)line;
@end
