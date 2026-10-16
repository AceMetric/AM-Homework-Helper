#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
NSURL *SSDataDirectory(void);
id _Nullable SSReadPlist(NSString *name);
BOOL SSWritePlist(NSString *name, id value, NSError **error);
NSMutableDictionary * _Nullable AMScanCacheLoad(NSError **error);
BOOL AMScanCacheSave(NSMutableDictionary *cache, NSError **error);
NSDictionary * _Nullable AMReviewDecisions(NSError **error);
BOOL AMReviewIsDeleted(NSDictionary *record);
BOOL AMReviewSetDeleted(NSArray *records, BOOL deleted, NSError **error);
NSArray *AMReviewDeletedRecords(void);
NSDictionary * _Nullable SSReadSecret(NSString *account);
BOOL SSWriteSecret(NSString *account, NSDictionary *value);
void SSDeleteSecret(NSString *account);
NS_ASSUME_NONNULL_END

NS_ASSUME_NONNULL_BEGIN
// Task-only recovery points; credentials and course directories are never backed up.
NSArray * _Nullable SSLoadTasks(NSError **error);
BOOL SSSaveTasks(NSArray *previous, NSArray *tasks, NSError **error);
NSArray<NSDictionary *> *SSRecoveryPoints(void);
NSArray * _Nullable SSRecoveryTasks(NSString *identifier, NSError **error);
BOOL AMRecoverBackup(NSError **error);
NSDictionary * _Nullable AMBackupEnvelope(NSArray *tasks, NSError **error);
NSDictionary * _Nullable AMDecodeBackup(id value, NSError **error);
BOOL AMRestoreBackup(NSArray *previous, NSArray *tasks, NSArray *records, NSError **error);
NSArray * _Nullable AMSubmissionRecords(NSError **error);
NSArray * _Nullable SSRecurrenceSeries(NSError **error);
NSDictionary *SSCalendarOverrides(void);
BOOL SSSaveScheduledTasks(NSArray *previous, NSArray *tasks, NSArray *series, NSDictionary *overrides, NSError **error);
BOOL AMRestoreScheduledBackup(NSArray *previous, NSDictionary *decoded, NSError **error);
BOOL AMStoreSubmission(NSDictionary *record, NSError **error);
NSString *AMSubmissionStateLabel(NSDictionary *record);
void SSDiagnostic(NSString *stage, NSString *outcome, NSTimeInterval seconds);
NSArray<NSDictionary *> *SSDiagnostics(void);

NS_ASSUME_NONNULL_END
#import "AMOperation.h"
