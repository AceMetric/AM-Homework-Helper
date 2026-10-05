#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A candidate always requires a human review before becoming a DDL task.
NSArray<NSDictionary<NSString *, id> *> *SSAssignmentsFromDocument(NSString *text,
    NSString *repository, NSString *path, NSString *blobSHA, NSDate *now, NSCalendar *calendar);
BOOL SSIsSupportedDocument(NSString *path);
/// All activity types; only assignment records are eligible for DDL review.
NSArray<NSDictionary *> *SSDiscoveriesFromDocument(NSString *text, NSString *repository,
    NSString *path, NSString *blobSHA, NSDate *now, NSCalendar *calendar);
NSArray<NSDictionary *> *SSGroupMaterials(NSArray<NSDictionary *> *records);
NSArray<NSDictionary *> *SSConsolidateAssignments(NSArray<NSDictionary *> *records);
NSString *SSActivityKindLabel(NSString *kind);
NSDictionary *SSApplyDateReference(NSDictionary *candidate, NSDate *referenceDate,
    NSString *commit, NSCalendar *calendar);

NS_ASSUME_NONNULL_END
