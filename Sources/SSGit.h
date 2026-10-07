#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface SSGit : NSObject
/// Required before cloning, committing, merging or pushing. Rechecks GitHub ownership.
@property (copy, nullable) void (^progress)(NSString *phase);
@property (copy, nullable) NSDictionary *recognitionSettings;
@property (copy) NSDictionary * _Nullable (^identityVerifier)(NSDictionary *course, NSError **error);
/// Course keys: fork, upstream, branch, upstreamBranch, path, upstreamURL.
- (BOOL)validateCourse:(NSDictionary *)course error:(NSError **)error;
- (BOOL)linkCourse:(NSDictionary *)course error:(NSError **)error;
- (BOOL)cloneFork:(NSDictionary *)course into:(NSString *)destination token:(NSString *)token error:(NSError **)error;
- (NSDictionary * _Nullable)scanCourse:(NSDictionary *)course cache:(NSMutableDictionary *)cache error:(NSError **)error;
- (NSDictionary * _Nullable)syncCourse:(NSDictionary *)course token:(NSString *)token error:(NSError **)error;
- (NSArray<NSDictionary *> * _Nullable)changesForCourse:(NSDictionary *)course error:(NSError **)error;
/// Read-only, bounded, credential-redacted preview; never executes diff drivers.
- (NSString * _Nullable)previewForCourse:(NSDictionary *)course path:(NSString *)path error:(NSError **)error;
- (BOOL)commitCourse:(NSDictionary *)course paths:(NSArray<NSString *> *)paths message:(NSString *)message
      login:(NSString *)login userID:(NSNumber *)userID token:(NSString *)token error:(NSError **)error;
- (BOOL)continueMergeForCourse:(NSDictionary *)course token:(NSString *)token error:(NSError **)error;
- (BOOL)pushCourse:(NSDictionary *)course token:(NSString *)token error:(NSError **)error;
- (BOOL)stageResolvedFiles:(NSDictionary *)course paths:(NSArray<NSString *> *)paths error:(NSError **)error;
- (BOOL)abortMerge:(NSDictionary *)course error:(NSError **)error;
- (NSArray<NSString *> * _Nullable)conflicts:(NSDictionary *)course error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
