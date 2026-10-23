#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
NSString *SSRecognitionCacheKey(NSString *repository, NSString *path, NSString *blob, NSCalendar *calendar, NSDictionary *settings);
NSArray * _Nullable SSCachedRecognition(NSString *repository, NSString *path, NSString *blob, NSCalendar *calendar, NSDictionary *settings, NSMutableDictionary *cache);
NSArray *AMQuickParse(NSString *text, NSString *sourceID, NSDate *reference, NSCalendar *calendar);
NSString *AMQuickDateText(NSDate *date, NSString *zone);
NSDictionary *AMQuickMaterial(NSString *text, NSDate *reference, NSString *zone);
NSDictionary * _Nullable AMQuickValidateResult(NSDictionary *result, NSDictionary *material, NSDictionary *batch, NSError **error);
NSDictionary * _Nullable AMQuickTask(NSDictionary *entry, NSError **error);
NSString *SSSuggestedNotes(NSDictionary *record);
NSDictionary * _Nullable SSSkillReadResult(NSURL *url, NSError **error);
NSDictionary *SSRecognitionSettings(void);
BOOL SSValidateRecognitionSettings(NSDictionary *settings, NSError **error);
NSArray *SSAttachLinkedDocuments(NSArray *records, NSArray *documents);
NSDictionary *SSCourseRecognitionSettings(NSDictionary *settings, NSDictionary *course);
NSArray * _Nullable SSValidatedSkillResults(id result, NSArray *documents, NSArray *references, NSError **error);
NSDictionary *SSSkillExport(NSArray *courses, NSDictionary *scans, NSDictionary *progress, BOOL all);
NSDictionary * _Nullable SSSkillValidateBatch(id result, NSArray *courses, NSDictionary *scans, NSDictionary *batches, NSString * _Nullable legacyCourse, NSError **error);
NSString *SSSkillProgressKey(NSString *course, NSDictionary *document);
NSString *SSSkillVersion(NSDictionary *document);
BOOL SSValidateCourseTemplate(NSDictionary *template, NSError **error);
NSDictionary *SSEnrichDiscovery(NSDictionary *record);
BOOL SSCanAutomaticallyImport(NSDictionary *record, NSArray *tasks, NSDate *now);
NSDictionary * _Nullable SSReviewedTask(NSDictionary *record, NSDictionary *draft, NSDictionary * _Nullable existing, NSError **error);
NSArray *SSValidatedModelResults(id results, NSString *text, NSString *repository, NSString *path, NSString *blob, NSCalendar *calendar, NSError **error);
/// Internal evidence contract: records, issues (index/field/code/reason), complete.
NSDictionary *SSModelValidationReport(id results, NSString *text, NSString *repository, NSString *path, NSString *blob, NSCalendar *calendar);
/// Preserve per-document failure causes in workflow/activity presentation.
NSError * _Nullable SSRecognitionFailureError(NSDictionary *failures);
id _Nullable SSRecognitionJSONObject(NSString *content, BOOL local);
NSArray *SSRecognizeDocument(NSString *text, NSString *repository, NSString *path, NSString *blob, NSCalendar *calendar, NSDictionary *settings, NSMutableDictionary *cache, NSError **error);
/// Network transport is replaceable for isolated tests; responses are never logged.
@interface SSRecognitionClient : NSObject <NSURLSessionTaskDelegate>
@property (copy, nullable) NSData * _Nullable (^transport)(NSURLRequest *request, NSError **error);
- (NSArray * _Nullable)localModels:(NSDictionary *)settings error:(NSError **)error;
- (id _Nullable)extract:(NSString *)text settings:(NSDictionary *)settings error:(NSError **)error;
@end
NSArray *SSRecognizeDocumentWithClient(NSString *text, NSString *repository, NSString *path, NSString *blob, NSCalendar *calendar, NSDictionary *settings, NSMutableDictionary *cache, SSRecognitionClient *client, NSError **error);
NS_ASSUME_NONNULL_END
