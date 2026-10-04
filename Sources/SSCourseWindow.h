#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
@interface SSCourseController : NSViewController <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@property (copy) NSArray<NSDictionary *> * (^tasksProvider)(void);
@property (copy) void (^reviewCandidate)(NSDictionary *candidate);
@property (copy) void (^editTask)(NSString *identifier);
@property (copy) void (^stateChanged)(void);
@property (nonatomic) BOOL inbox;
@property (readonly) NSUInteger pendingCount;
@property (readonly) NSString *accountSummary;
- (instancetype)initWithPreview:(BOOL)preview;
- (void)startAutomaticChecks;
- (void)refreshPresentation;
- (void)layoutContent;
- (void)focusSearch;
- (void)accountSettings:(nullable id)sender;
- (void)setClientID:(nullable id)sender;
@end
NS_ASSUME_NONNULL_END
