#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN
NSString *AMPreflightHash(NSData *data);
NSString *AMPreflightSpellingProse(NSString *text);
NSURL * _Nullable AMPreflightAttachmentArchive(NSString *batch, NSError **error);
NSString *AMPreflightAttachmentPrompt(void);
BOOL AMPreflightImportResult(NSURL *url, NSString *batch, NSError **error);
NSArray *AMPreflightImageReferences(NSString *text);
NSString * _Nullable AMPreflightResolveImage(NSString *document, NSString *reference);
NSArray *AMPreflightListSelectedFiles(NSURL *folder, NSArray *paths);
NSString * _Nullable AMPreflightExcludedReason(NSString *path);
NSString *AMPreflightFileStamp(NSURL *folder, NSString *path);
NSDictionary * _Nullable AMPreflightListFolder(NSURL *folder, BOOL (^ _Nullable cancelled)(void), void (^ _Nullable progress)(NSUInteger), NSError **error);
NSDictionary *AMPreflightCheck(NSDictionary *snapshot, NSString *requirements, NSMutableDictionary *cache, BOOL (^ _Nullable cancelled)(void));
NSDictionary * _Nullable AMPreflightExport(NSDictionary *report, NSDictionary *snapshot, NSString *requirements, NSArray *images, NSURL *folder, NSError **error);
NSDictionary * _Nullable AMPreflightValidateResult(id result, NSDictionary *context, NSError **error);
NS_ASSUME_NONNULL_END
NS_ASSUME_NONNULL_BEGIN
NSArray *AMPreflightJobs(void);
NSDictionary *AMPreflightSavedSnapshot(NSString *batch);
BOOL AMPreflightRegister(NSDictionary *context,NSDictionary *report,NSString *courseID,NSError **error);
void AMPreflightPoll(void);
NSDictionary * _Nullable AMPreflightJobForReport(NSString *version);
BOOL AMPreflightJobAction(NSString *action,NSString *batch);
NSURL * _Nullable AMPreflightFolder(NSString *batch);
NS_ASSUME_NONNULL_END

NS_ASSUME_NONNULL_BEGIN
NSDictionary *AMOnlineReviewSettings(void);
BOOL AMOnlineReviewSaveSettings(BOOL enabled, NSString *key, NSError **error);
void AMOnlineReviewCleanup(void);
NSUInteger AMOnlineReviewPendingUploads(void);
BOOL AMOnlineReviewRegister(NSDictionary *context,NSDictionary *report,NSString *courseID,NSError **error);
void AMOnlineReviewFailed(NSString *batch);
void AMShowOnlineReviewSettings(NSWindow * _Nullable parent);
@interface AMOnlineReviewClient : NSObject <NSURLSessionTaskDelegate>
@property(atomic) BOOL cancelled;
@property BOOL forceCleanup;
#ifdef DDL_TESTING
@property(copy,nullable) NSString * _Nullable (^credentialProvider)(void);
@property(copy,nullable) NSData * _Nullable (^transport)(NSURLRequest *, NSHTTPURLResponse * _Nullable * _Nullable, NSError * _Nullable * _Nullable);
#endif
- (BOOL)testConnectionWithKey:(NSString *)key error:(NSError **)error;
- (NSUInteger)cleanupWithKey:(NSString *)key error:(NSError **)error;
- (NSDictionary * _Nullable)reviewContext:(NSDictionary *)context folder:(NSURL *)folder focus:(NSDictionary * _Nullable)focus progress:(void (^ _Nullable)(NSString *))progress error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
