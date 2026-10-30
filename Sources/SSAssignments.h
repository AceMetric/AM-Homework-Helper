#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Rules return evidence-backed candidates; the task service decides import eligibility.
NSArray<NSDictionary<NSString *, id> *> *SSAssignmentsFromDocument(NSString *text,
    NSString *repository, NSString *path, NSString *blobSHA, NSDate *now, NSCalendar *calendar);
NSDictionary *SSClassifyActivity(NSString *context, NSString *path);
BOOL SSSeparateSubmission(NSString *text);
NSString *SSProseText(NSString *text);
NSDictionary *SSSourceAnalysis(NSString *text, NSString *path);
NSArray *SSActivityBlocks(NSString *text, NSString *path, BOOL local);
NSString *SSActivityAnchor(NSDictionary *block, NSUInteger count);
NSArray *SSReconcileDiscoveryIDs(NSArray *previous, NSArray *current);
BOOL SSIsSupportedDocument(NSString *path);
/// Assignment and classroom proposals; actual exams are excluded from recognition.
NSArray<NSDictionary *> *SSDiscoveriesFromDocument(NSString *text, NSString *repository,
    NSString *path, NSString *blobSHA, NSDate *now, NSCalendar *calendar);
NSArray<NSDictionary *> *SSGroupMaterials(NSArray<NSDictionary *> *records);
NSArray<NSDictionary *> *SSConsolidateAssignments(NSArray<NSDictionary *> *records);
NSString *SSActivityKindLabel(NSString *kind);
NSDictionary *SSApplyDateReference(NSDictionary *candidate, NSDate *referenceDate,
    NSString *commit, NSCalendar *calendar);

NS_ASSUME_NONNULL_END
