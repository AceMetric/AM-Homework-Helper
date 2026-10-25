#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
NSString * _Nullable SSCanonicalRepository(NSString *url);
BOOL SSValidBranch(NSString *branch);
BOOL SSSensitivePath(NSString *path);
BOOL SSContainsSecret(NSData *data);
// Exact IDX unsigned-byte arrays, optionally one bounded gzip member; no arbitrary archives.
BOOL SSValidatedTrainingData(NSData *data);
NSString *SSRedactedText(NSString *text);
NSString *SSRedactedContent(NSString *text);
NS_ASSUME_NONNULL_END
