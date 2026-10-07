#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
NSDictionary *SSRecognitionSettings(void);
BOOL SSValidateRecognitionSettings(NSDictionary *settings, NSError **error);
NSArray *SSAttachLinkedDocuments(NSArray *records, NSArray *documents);
NSDictionary *SSCourseRecognitionSettings(NSDictionary *settings, NSDictionary *course);
NSArray * _Nullable SSValidatedSkillResults(id result, NSArray *documents, NSArray *references, NSError **error);
BOOL SSValidateCourseTemplate(NSDictionary *template, NSError **error);
NSDictionary *SSEnrichDiscovery(NSDictionary *record);
BOOL SSCanAutomaticallyImport(NSDictionary *record, NSArray *tasks, NSDate *now);
NSDictionary * _Nullable SSReviewedTask(NSDictionary *record, NSDictionary *draft, NSDictionary * _Nullable existing, NSError **error);
NSArray *SSValidatedModelResults(id results, NSString *text, NSString *repository, NSString *path, NSString *blob, NSCalendar *calendar, NSError **error);
NSArray *SSRecognizeDocument(NSString *text, NSString *repository, NSString *path, NSString *blob, NSCalendar *calendar, NSDictionary *settings, NSMutableDictionary *cache, NSError **error);
/// Network transport is replaceable for isolated tests; responses are never logged.
@interface SSRecognitionClient : NSObject <NSURLSessionTaskDelegate>
@property (copy, nullable) NSData * _Nullable (^transport)(NSURLRequest *request, NSError **error);
- (id _Nullable)extract:(NSString *)text settings:(NSDictionary *)settings error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
