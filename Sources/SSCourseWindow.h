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
@property (readonly) BOOL operationBusy;
@property (nonatomic) BOOL operationsPaused;
@property (copy, nullable) void (^operationStateChanged)(void);
@property (readonly) BOOL hasSubmissionSheet;
@property (readonly) BOOL hasUnsavedSubmission;
@property (readonly) BOOL submissionFailedDuringExit;
- (void)cancelPendingLogin;
- (BOOL)saveSubmissionForExit;
- (void)discardSubmission;
- (void)acknowledgeSubmissionFailure;
- (BOOL)persistForExit:(NSError **)error;
- (instancetype)initWithPreview:(BOOL)preview;
- (void)startAutomaticChecks;
- (void)refreshPresentation;
- (NSArray<NSDictionary *> *)pendingReviewCandidates;
- (void)layoutContent;
- (void)focusSearch;
- (void)accountSettings:(nullable id)sender;
- (void)setClientID:(nullable id)sender;
@end
NS_ASSUME_NONNULL_END
