#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSNotificationName const AMOperationsChanged;
NSString *AMOperationBegin(NSString *kind,NSString *target,BOOL cancellable,void (^ _Nullable cancel)(void));
NSString *AMOperationBeginWithExitPolicy(NSString *kind,NSString *target,BOOL cancellable,BOOL blocksExit,void (^ _Nullable cancel)(void));
void AMOperationProgress(NSString * _Nullable identifier,NSString *stage,NSInteger completed,NSInteger total);
void AMOperationFinish(NSString * _Nullable identifier,NSString *state,NSString *message);
void AMOperationCancel(NSString *identifier);
BOOL AMCurrentOperationCancelled(void);
typedef BOOL (^AMCancellationCheck)(void);
AMCancellationCheck _Nullable AMCurrentCancellationCheck(void);
NSArray<NSDictionary *> *AMOperations(void);
NSArray<NSDictionary *> *AMExitBlockingOperations(void);
/// Active requests with the same key coalesce. Start runs on a worker; finish
/// releases resources. Queued cancellation never calls start.
NSString *AMOperationEnqueue(NSString *key,NSString *kind,NSString *target,NSArray<NSString *> *resources,NSInteger priority,void (^start)(NSString *identifier),void (^ _Nullable cancel)(BOOL beforeStart));
NSString *AMOperationSchedule(NSString *key,NSString *kind,NSString *target,NSArray<NSString *> *resources,NSInteger priority,BOOL cancellableWhileRunning,void (^start)(NSString *identifier),void (^ _Nullable cancel)(BOOL beforeStart));
NSUInteger AMQueuedOperationCount(void);
void AMCancelQueuedOperations(void);
// Internal resource work belongs to one user-visible task; scheduling and exit
// protection still track the child independently.
id _Nullable AMPerformResourceOperationInTask(NSString *task,NSString *key,NSString *kind,NSString *target,NSArray<NSString *> *resources,NSInteger priority,BOOL (^ _Nullable cancelled)(void),id _Nullable (^perform)(NSError **error),NSError **error);
id _Nullable AMPerformResourceOperation(NSString *key,NSString *kind,NSString *target,NSArray<NSString *> *resources,NSInteger priority,BOOL (^ _Nullable cancelled)(void),id _Nullable (^perform)(NSError **error),NSError **error);
id _Nullable AMPerformModelOperation(NSString *key,NSString *target,BOOL manual,BOOL (^ _Nullable cancelled)(void),id _Nullable (^perform)(NSError **error),NSError **error);
NS_ASSUME_NONNULL_END
