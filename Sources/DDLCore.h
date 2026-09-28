#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
NSDate * _Nullable DDLParseDate(NSString *input, NSDate *now, NSCalendar *calendar);
NSString *DDLFormatDate(NSDate *date, NSString *format);
NSString *DDLRemaining(NSDate *due, NSDate *now, BOOL completed);
NSArray<NSDictionary *> *DDLReminderPlan(NSDictionary *task, NSDate *now, NSCalendar *calendar);
NSArray<NSNumber *> * _Nullable DDLParseReminderOffsets(NSString *input);
NSString *DDLFormatReminderOffsets(NSArray<NSNumber *> *offsets);
NSArray<NSNumber *> *DDLReminderOffsetsForTask(NSDictionary *task);
NSArray<NSMutableDictionary *> *DDLNormalizeTasks(NSArray *items);
NSArray<NSMutableDictionary *> *DDLMergeTasks(NSArray *existing, NSArray *incoming);
BOOL DDLMatchesFilter(NSDictionary *task, NSInteger filter, NSString *query, NSDate *now, NSCalendar *calendar);
NSDictionary<NSDate *, NSArray<NSDictionary *> *> *DDLTasksByDay(NSArray<NSDictionary *> *items, NSCalendar *calendar);
NSArray<NSDate *> *DDLMonthGrid(NSDate *month, NSCalendar *calendar);
NSArray<NSDictionary *> *DDLCalendarTasks(NSArray *items, NSInteger status, NSString *query);
NSDictionary<NSString *, NSNumber *> *DDLMonthSummary(NSArray *items, NSDate *month, NSDate *now, NSCalendar *calendar);
NS_ASSUME_NONNULL_END
