#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
NSURL *SSDataDirectory(void);
id _Nullable SSReadPlist(NSString *name);
BOOL SSWritePlist(NSString *name, id value, NSError **error);
NSDictionary * _Nullable SSReadSecret(NSString *account);
BOOL SSWriteSecret(NSString *account, NSDictionary *value);
void SSDeleteSecret(NSString *account);
NS_ASSUME_NONNULL_END
