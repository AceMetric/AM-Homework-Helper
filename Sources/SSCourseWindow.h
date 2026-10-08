#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
@interface SSCourseController : NSViewController <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@property (copy) NSArray<NSDictionary *> * (^tasksProvider)(void);
@property (copy) void (^reviewCandidate)(NSDictionary *candidate);
@property (copy) void (^editTask)(NSString *identifier);
@property (copy) void (^stateChanged)(void);
@property (copy, nullable) NSString * (^saveReviewItems)(NSArray<NSDictionary *> *items, BOOL automatic);
@property (readonly) BOOL hasUnsavedReview;
- (BOOL)resolveUnsavedReview;
- (void)discardReview;
- (BOOL)deferAutomaticImportOfTasks:(NSArray *)tasks error:(NSError **)error;
@property (nonatomic) BOOL inbox;
@property (readonly) NSUInteger pendingCount;
@property (readonly) NSString *accountSummary;
@property (readonly) NSArray<NSString *> *courseRepositoryNames;
@property (readonly) NSArray<NSDictionary *> *courseSnapshots;
@property (readonly, nullable) NSString *selectedCourseID;
- (BOOL)selectCourseID:(nullable NSString *)identifier;
- (void)exportSkillContext:(nullable id)sender;
- (void)importSkillResults:(nullable id)sender;
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
- (void)setup:(nullable id)sender;
- (void)startUsing:(nullable id)sender;
@property (copy, nullable) void (^onboardingNavigation)(BOOL review);
- (void)refreshPresentation;
- (NSArray<NSDictionary *> *)pendingReviewCandidates;
- (NSArray<NSDictionary *> *)allPendingReviewCandidates;
- (nullable NSDictionary *)reviewSourceWithID:(NSString *)identifier;
- (void)layoutContent;
- (void)focusSearch;
- (void)accountSettings:(nullable id)sender;
- (void)authenticationSettings:(nullable id)sender;
- (void)setClientID:(nullable id)sender;
@end
NS_ASSUME_NONNULL_END
