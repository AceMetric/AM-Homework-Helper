#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
@interface SSCourseWindow : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
@property (copy) NSArray<NSDictionary *> * (^tasksProvider)(void);
@property (copy) void (^reviewCandidate)(NSDictionary *candidate);
- (void)show;
- (void)startAutomaticChecks;
@end
NS_ASSUME_NONNULL_END
