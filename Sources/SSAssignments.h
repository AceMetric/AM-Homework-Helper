#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A candidate always requires a human review before becoming a DDL task.
NSArray<NSDictionary<NSString *, id> *> *SSAssignmentsFromDocument(NSString *text,
    NSString *repository, NSString *path, NSString *blobSHA, NSDate *now, NSCalendar *calendar);
BOOL SSIsSupportedDocument(NSString *path);

NS_ASSUME_NONNULL_END
