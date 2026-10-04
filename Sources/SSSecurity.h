#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
NSString * _Nullable SSCanonicalRepository(NSString *url);
BOOL SSValidBranch(NSString *branch);
BOOL SSSensitivePath(NSString *path);
BOOL SSContainsSecret(NSData *data);
NSString *SSRedactedText(NSString *text);
NS_ASSUME_NONNULL_END
