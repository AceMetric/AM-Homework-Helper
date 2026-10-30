#import <Cocoa/Cocoa.h>
void AMPreflightSetRenderer(NSDictionary *(^renderer)(NSString *,NSString *));
void AMInstallRenderer(void);
@interface AMDocumentView : NSView
@property(nonatomic,copy) NSString *markdown;
@property(nonatomic) BOOL renderedOnly;
@property(nonatomic,copy) void (^sourceHandler)(NSString *,NSUInteger);
- (void)loadSnapshot:(NSDictionary *)snapshot path:(NSString *)path;
- (void)setAnnotations:(NSArray<NSDictionary *> *)annotations selected:(NSString *)identifier;
- (void)highlightRegion:(NSArray *)region;
- (void)showSource:(BOOL)source;
- (void)locateLine:(NSUInteger)line;
@end
