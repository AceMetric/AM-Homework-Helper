#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN
NSString *AMPreflightHash(NSData *data);
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
