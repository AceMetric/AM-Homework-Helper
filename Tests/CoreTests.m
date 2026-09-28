#import "../Sources/DDLCore.h"
#include <stdio.h>
#include <stdlib.h>

static NSInteger count = 0;
static void Check(BOOL passed, NSString *message) {
    count++; if (!passed) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
int main(void) {
    @autoreleasepool {
        NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian]; calendar.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
        NSDateComponents *parts = [NSDateComponents new]; parts.year = 2026; parts.month = 9; parts.day = 24; parts.hour = 10; parts.minute = 30;
        NSDate *now = [calendar dateFromComponents:parts];
        NSArray *cases = @[@[@"明天 20:00", @2026, @9, @25, @20, @0], @[@"下周五 18:30", @2026, @10, @2, @18, @30], @[@"周五", @2026, @9, @25, @23, @59], @[@"2028-02-29 09:00", @2028, @2, @29, @9, @0], @[@"2026/10/1 23：59", @2026, @10, @1, @23, @59], @[@"两周后", @2026, @10, @8, @23, @59], @[@"3天后 12:00", @2026, @9, @27, @12, @0]];
        for (NSArray *row in cases) {
            NSDate *date = DDLParseDate(row[0], now, calendar); Check(date != nil, row[0]);
            NSDateComponents *p = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute fromDate:date];
            Check(p.year == [row[1] integerValue] && p.month == [row[2] integerValue] && p.day == [row[3] integerValue] && p.hour == [row[4] integerValue] && p.minute == [row[5] integerValue], row[0]);
        }
        for (NSString *bad in @[@"", @"明天 25:00", @"明天 20:99", @"明天 20:00 垃圾", @"2026-02-29", @"2026-02-30", @"2026-13-01", @"2026-00-01", @"2026-10-01 24:00", @"99:99", @"99999周后", @"明天abc", @"下周五20:000"]) Check(DDLParseDate(bad, now, calendar) == nil, [@"reject " stringByAppendingString:bad]);
        Check([DDLRemaining([now dateByAddingTimeInterval:-180], now, NO) isEqual:@"逾期 3 分钟"], @"minute-accurate overdue");
        Check([DDLRemaining([now dateByAddingTimeInterval:7200], now, NO) isEqual:@"剩余 2 小时"], @"hour countdown");
        Check([DDLRemaining(now, now, YES) isEqual:@"已完成"], @"completed status");
        NSMutableDictionary *task = [@{@"id":@"task-1", @"title":@"报告", @"subject":@"数学", @"due":[now dateByAddingTimeInterval:5 * 86400], @"completed":@NO, @"archived":@NO, @"reminder":@3, @"notes":@"论文"} mutableCopy];
        Check(DDLReminderPlan(task, now, calendar).count == 4, @"all reminder slots");
        task[@"reminder"] = @2; Check(DDLReminderPlan(task, now, calendar).count == 3, @"default reminder slots");
        task[@"reminder"] = @1; Check(DDLReminderPlan(task, now, calendar).count == 2, @"one hour reminder slots");
        task[@"reminder"] = @0; Check(DDLReminderPlan(task, now, calendar).count == 1, @"due-only reminder");
        task[@"reminder"] = @4; Check(DDLReminderPlan(task, now, calendar).count == 0, @"reminders off");
        Check([DDLParseReminderOffsets(@"5小时、1小时、到期") isEqual:@[@300, @60, @0]], @"parse custom five-hour reminders");
        Check([DDLParseReminderOffsets(@"2天, 30分钟") isEqual:@[@2880, @30]], @"parse mixed custom reminders");
        Check([DDLParseReminderOffsets(@"不提醒") isEqual:@[]], @"parse disabled reminders");
        Check(DDLParseReminderOffsets(@"5小时、随便") == nil, @"reject malformed custom reminders");
        Check([DDLFormatReminderOffsets(@[@300, @60, @0]) isEqual:@"5小时、1小时、到期"], @"format custom reminders");
        [task removeObjectForKey:@"reminder"]; task[@"reminderOffsets"] = @[@300, @60, @0]; task[@"due"] = [now dateByAddingTimeInterval:6 * 3600];
        NSArray *fiveHourPlan = DDLReminderPlan(task, now, calendar);
        Check(fiveHourPlan.count == 3, @"custom reminder count");
        Check([fiveHourPlan[0][@"message"] isEqual:@"5 小时后截止"], @"custom five-hour reminder message");
        [task removeObjectForKey:@"reminderOffsets"]; task[@"reminder"] = @3;
        task[@"reminder"] = @3; task[@"due"] = [now dateByAddingTimeInterval:1800]; Check(DDLReminderPlan(task, now, calendar).count == 1, @"never schedule past reminders");
        task[@"completed"] = @YES; Check(DDLReminderPlan(task, now, calendar).count == 0, @"completed cancels reminders");
        task[@"completed"] = @NO; task[@"archived"] = @YES; Check(DDLReminderPlan(task, now, calendar).count == 0, @"archive cancels reminders");
        Check(DDLMatchesFilter(task, 4, @"论文", now, calendar), @"archive / notes search");
        Check(!DDLMatchesFilter(task, 0, @"", now, calendar), @"archive excluded from pending");
        task[@"archived"] = @NO; Check(DDLMatchesFilter(task, 1, @"数学", now, calendar), @"today / subject search");
        Check(!DDLMatchesFilter(task, 0, @"missing", now, calendar), @"search no results");
        task[@"due"] = [now dateByAddingTimeInterval:8 * 86400]; Check(!DDLMatchesFilter(task, 2, @"", now, calendar), @"future seven days bound");
        NSArray *valid = DDLNormalizeTasks(@[task, task, @{@"title":@"bad", @"due":@"bad"}, @"bad"]);
        Check(valid.count == 2, @"ignore malformed entries"); Check(![valid[0][@"id"] isEqual:valid[1][@"id"]], @"repair duplicate identifiers");
        NSArray *legacy = DDLNormalizeTasks(@[@{@"title":@"旧版任务", @"due":now}]);
        Check([legacy[0][@"subject"] isEqual:@"其他"] && [legacy[0][@"reminder"] integerValue] == 2, @"migrate legacy tasks");
        Check([legacy[0][@"reminderOffsets"] isEqual:@[@1440, @60, @0]], @"migrate legacy reminder schedule");
        Check(DDLMergeTasks(@[task], @[task]).count == 1, @"backup skips identical task");
        NSMutableDictionary *changed = [task mutableCopy]; changed[@"title"] = @"不同版本";
        NSArray *merged = DDLMergeTasks(@[task], @[changed]);
        Check(merged.count == 2 && ![merged[0][@"id"] isEqual:merged[1][@"id"]], @"backup preserves ID conflict as separate task");
        Check(DDLMergeTasks(merged, @[changed]).count == 2, @"reimport conflict version without duplication");
        NSCalendar *dst = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian]; dst.timeZone = [NSTimeZone timeZoneWithName:@"America/Los_Angeles"];
        Check(DDLParseDate(@"2026-03-08 02:30", now, dst) == nil, @"reject nonexistent daylight-saving time");
        NSArray *september = DDLMonthGrid(now, calendar);
        Check(september.count == 35, @"September 2026 uses five calendar rows");
        Check([calendar component:NSCalendarUnitWeekday fromDate:september.firstObject] == 2, @"month grid starts Monday");
        Check([calendar component:NSCalendarUnitDay fromDate:september.firstObject] == 31, @"leading August day visible");
        Check([calendar component:NSCalendarUnitMonth fromDate:september.lastObject] == 10 && [calendar component:NSCalendarUnitDay fromDate:september.lastObject] == 4, @"trailing October dates visible");
        Check(DDLMonthGrid(DDLParseDate(@"2026-03-15", now, calendar), calendar).count == 42, @"six-week month fits all days");
        Check(DDLMonthGrid(DDLParseDate(@"2027-02-15", now, calendar), calendar).count == 28, @"four-week month");
        Check(DDLMonthGrid(DDLParseDate(@"2028-02-15", now, calendar), calendar).count == 35, @"leap February");
        Check([calendar component:NSCalendarUnitYear fromDate:DDLMonthGrid(DDLParseDate(@"2026-12-15", now, calendar), calendar).lastObject] == 2027, @"calendar crosses year boundary");
        NSMutableDictionary *pending = [task mutableCopy]; pending[@"id"] = @"pending"; pending[@"due"] = now;
        NSMutableDictionary *done = [pending mutableCopy]; done[@"id"] = @"done"; done[@"completed"] = @YES;
        NSMutableDictionary *archive = [pending mutableCopy]; archive[@"id"] = @"archive"; archive[@"archived"] = @YES;
        NSMutableDictionary *nextMonth = [pending mutableCopy]; nextMonth[@"id"] = @"next"; nextMonth[@"due"] = DDLParseDate(@"2026-10-01 00:00", now, calendar);
        NSMutableDictionary *late = [pending mutableCopy]; late[@"id"] = @"late"; late[@"due"] = [now dateByAddingTimeInterval:-3600];
        NSArray *overview = @[pending, done, archive, nextMonth, late];
        Check(DDLCalendarTasks(overview, 0, @"").count == 4, @"overview combines completed and pending, excludes archive");
        Check(DDLCalendarTasks(overview, 1, @"").count == 3, @"overview pending filter");
        Check(DDLCalendarTasks(overview, 2, @"").count == 1, @"overview completed filter");
        Check(DDLCalendarTasks(overview, 0, @"  数学  ").count == 4, @"overview search trims whitespace");
        Check(DDLCalendarTasks(overview, 0, @"不存在").count == 0, @"overview empty search result");
        NSDictionary *summary = DDLMonthSummary(overview, now, now, calendar);
        Check([summary[@"total"] integerValue] == 3 && [summary[@"pending"] integerValue] == 2 && [summary[@"completed"] integerValue] == 1, @"monthly counts include both states only in month");
        Check([summary[@"overdue"] integerValue] == 1, @"overdue excludes completed and archived");
        Check([DDLMonthSummary(@[], now, now, calendar)[@"total"] integerValue] == 0, @"empty month summary");
        pending[@"completed"] = @YES;
        Check(DDLCalendarTasks(overview, 0, @"").count == 4 && [DDLMonthSummary(overview, now, now, calendar)[@"completed"] integerValue] == 2, @"completing retains calendar event and updates monthly progress");
        NSMutableDictionary *deletedTask = [done mutableCopy]; deletedTask[@"id"] = @"deleted"; deletedTask[@"deleted"] = @YES; deletedTask[@"deletedAt"] = now;
        Check(DDLMatchesFilter(deletedTask, 5, @"", now, calendar), @"recently deleted filter shows deleted");
        Check(!DDLMatchesFilter(deletedTask, 0, @"", now, calendar), @"deleted excluded from pending list");
        Check(!DDLMatchesFilter(deletedTask, 3, @"", now, calendar), @"deleted excluded from completed list");
        Check(DDLMatchesFilter(deletedTask, 5, @"数学", now, calendar), @"recently deleted supports search");
        NSArray *withDeleted = @[pending, deletedTask];
        Check(DDLCalendarTasks(withDeleted, 0, @"").count == 1, @"calendar excludes deleted tasks");
        Check([DDLMonthSummary(withDeleted, now, now, calendar)[@"total"] integerValue] == 1, @"monthly summary excludes deleted tasks");
        NSMutableDictionary *deletedActive = [@{@"id":@"deleted-active", @"title":@"已删未完成", @"subject":@"数学", @"due":[now dateByAddingTimeInterval:86400], @"completed":@NO, @"archived":@NO, @"deleted":@YES, @"deletedAt":now, @"reminder":@2} mutableCopy];
        Check(DDLReminderPlan(deletedActive, now, calendar).count == 0, @"deleted task cancels reminders");
        NSArray *normalizedDeleted = DDLNormalizeTasks(@[@{@"id":@"d1", @"title":@"旧删除", @"due":now, @"deleted":@YES, @"deletedAt":now}]);
        Check([normalizedDeleted[0][@"deleted"] boolValue], @"normalize preserves deleted flag");
        Check([normalizedDeleted[0][@"deletedAt"] isKindOfClass:NSDate.class], @"normalize keeps deleted date");
        NSArray *missingDate = DDLNormalizeTasks(@[@{@"title":@"旧删除", @"due":now, @"deleted":@YES}]);
        Check([missingDate[0][@"deletedAt"] isKindOfClass:NSDate.class], @"normalize fills missing deleted date");
        Check(DDLMatchesFilter(task, 0, @"  数学 \n", now, calendar), @"list search trims surrounding whitespace");
        Check(DDLMatchesFilter(task, 0, @" \n ", now, calendar), @"whitespace-only list search shows all tasks");
        NSDictionary *days = DDLTasksByDay(DDLCalendarTasks(overview, 0, @""), calendar);
        Check([days[[calendar startOfDayForDate:now]] count] == 3, @"day index includes completed and pending tasks");
        Check([days[[calendar startOfDayForDate:nextMonth[@"due"]]] count] == 1, @"day index crosses month boundary");
        Check(DDLTasksByDay(@[], calendar).count == 0, @"empty day index");
        NSArray *ordered = DDLCalendarTasks(overview, 0, @"");
        for (NSDate *day in days) {
            NSArray *expected = [ordered filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
                (void)bindings; return [calendar isDate:item[@"due"] inSameDayAsDate:day];
            }]];
            Check([days[day] isEqual:expected], @"day index preserves task display order");
        }
        NSDate *dstMorning = DDLParseDate(@"2026-03-08 00:30", now, dst);
        NSDate *dstEvening = DDLParseDate(@"2026-03-08 23:30", now, dst);
        NSDate *dstNext = DDLParseDate(@"2026-03-09 00:00", now, dst);
        NSDictionary *dstDays = DDLTasksByDay(@[@{@"due":dstMorning}, @{@"due":dstEvening}, @{@"due":dstNext}], dst);
        Check(dstDays.count == 2 && [dstDays[[dst startOfDayForDate:dstMorning]] count] == 2, @"day index respects 23-hour daylight-saving day");
        NSCalendar *utc = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian]; utc.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        NSDate *localMidnight = DDLParseDate(@"2026-10-01 00:30", now, calendar);
        Check(![[calendar startOfDayForDate:localMidnight] isEqual:[utc startOfDayForDate:localMidnight]], @"fixture spans local and UTC days");
        NSDictionary *localDays = DDLTasksByDay(@[@{@"due":localMidnight}], calendar);
        Check([localDays[[calendar startOfDayForDate:localMidnight]] count] == 1, @"day index uses supplied time zone");
        NSTimeZone *originalZone = NSTimeZone.defaultTimeZone;
        [NSTimeZone setDefaultTimeZone:calendar.timeZone];
        Check([DDLFormatDate(localMidnight, @"yyyy-MM-dd HH:mm") isEqual:@"2026-10-01 00:30"], @"cached formatter first time zone");
        [NSTimeZone setDefaultTimeZone:utc.timeZone];
        Check([DDLFormatDate(localMidnight, @"yyyy-MM-dd HH:mm") isEqual:@"2026-09-30 16:30"], @"cached formatter follows time zone changes");
        Check([DDLFormatDate(localMidnight, @"d") isEqual:@"30"], @"formatter caches distinct formats");
        [NSTimeZone setDefaultTimeZone:originalZone];
        printf("PASS: %ld core assertions\n", (long)count);
    }
    return 0;
}
