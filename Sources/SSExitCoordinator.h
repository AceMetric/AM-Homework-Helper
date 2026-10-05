#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
// All providers and callbacks run on the main thread. No Git process is interrupted.
@interface SSExitCoordinator : NSObject
@property (copy) BOOL (^operationBusy)(void);
@property (copy) void (^pauseOperations)(BOOL paused);
@property (copy) void (^cancelLogin)(void);
@property (copy) BOOL (^resolveEdits)(BOOL updating);
@property (copy) BOOL (^persist)(void);
@property (readonly) BOOL pending;
- (void)requestForUpdate:(BOOL)updating completion:(void (^)(BOOL))completion;
- (void)operationStateChanged;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
