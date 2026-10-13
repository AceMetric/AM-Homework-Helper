#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSNotificationName const AMOperationsChanged;
NSString *AMOperationBegin(NSString *kind,NSString *target,BOOL cancellable,void (^ _Nullable cancel)(void));
void AMOperationProgress(NSString * _Nullable identifier,NSString *stage,NSInteger completed,NSInteger total);
void AMOperationFinish(NSString * _Nullable identifier,NSString *state,NSString *message);
void AMOperationCancel(NSString *identifier);
NSArray<NSDictionary *> *AMOperations(void);
NS_ASSUME_NONNULL_END
