#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
NSDate * _Nullable DDLParseDate(NSString *input, NSDate *now, NSCalendar *calendar);
NSString *DDLFormatDate(NSDate *date, NSString *format);
NSString *DDLRemaining(NSDate *due, NSDate *now, BOOL completed);
NSArray<NSDictionary *> *DDLReminderPlan(NSDictionary *task, NSDate *now, NSCalendar *calendar);
NSArray<NSNumber *> * _Nullable DDLParseReminderOffsets(NSString *input);
NSString *DDLFormatReminderOffsets(NSArray<NSNumber *> *offsets);
NSArray<NSNumber *> *DDLReminderOffsetsForTask(NSDictionary *task);
NSArray<NSNumber *> *DDLDefaultReminderOffsets(void);
NSArray<NSMutableDictionary *> *DDLNormalizeTasks(NSArray *items);
NSArray<NSMutableDictionary *> *DDLMergeTasks(NSArray *existing, NSArray *incoming);
BOOL DDLMatchesFilter(NSDictionary *task, NSInteger filter, NSString *query, NSDate *now, NSCalendar *calendar);
NSDictionary<NSDate *, NSArray<NSDictionary *> *> *DDLTasksByDay(NSArray<NSDictionary *> *items, NSCalendar *calendar);
NSArray<NSDate *> *DDLMonthGrid(NSDate *month, NSCalendar *calendar);
NSArray<NSDictionary *> *DDLCalendarTasks(NSArray *items, NSInteger status, NSString *query);
NSDictionary<NSString *, NSNumber *> *DDLMonthSummary(NSArray *items, NSDate *month, NSDate *now, NSCalendar *calendar);
NSString *DDLPlanKey(NSDate *date, NSCalendar *calendar);
NSDate * _Nullable DDLPlanDate(NSString * _Nullable key, NSCalendar *calendar);
BOOL DDLPlanningValid(NSDictionary *task);
NSDictionary *DDLChinaDayInfo(NSDate *date, NSCalendar *calendar, NSDictionary *overrides);
BOOL DDLRecurrenceValid(NSDictionary *rule);
NSArray * _Nullable DDLRecurrenceDates(NSDictionary *rule, NSDate *from, NSDate *to, NSDictionary *overrides, NSError **error);
NSArray * _Nullable DDLMaterializeRecurringTasks(NSArray *tasks, NSArray *series, NSDate *now, NSDate *end, NSDictionary *overrides, NSError **error);
NSDictionary *DDLTaskCompletion(NSDictionary *task, BOOL complete);
NSArray<NSDictionary *> *DDLWeekSections(NSArray *tasks, NSDate *now, NSInteger offset, NSCalendar *calendar, NSString *query);
NS_ASSUME_NONNULL_END
