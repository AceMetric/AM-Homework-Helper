#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN
@interface SSUpdateController : NSObject
@property (readonly) BOOL installing;
@property (readonly) BOOL available;
@property (readonly) BOOL automaticallyChecks;
@property (copy, nullable) void (^statusChanged)(NSString *message);
+ (BOOL)canUpdateApplicationAtPath:(NSString *)path;
- (instancetype)initWithPreview:(BOOL)preview;
- (void)checkForUpdates:(nullable id)sender;
- (void)showSettings:(nullable id)sender;
- (void)terminationCancelled;
@end
NS_ASSUME_NONNULL_END
