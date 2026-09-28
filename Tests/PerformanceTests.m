#import "../Sources/DDLCore.h"
#include <stdio.h>
int main(void) {
    @autoreleasepool {
        NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        calendar.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
        NSDate *base = DDLParseDate(@"2026-01-01 00:00", NSDate.date, calendar);
        NSMutableArray *tasks = [NSMutableArray array], *dates = [NSMutableArray array];
        for (NSInteger i = 0; i < 2000; i++) [tasks addObject:@{@"due":[calendar dateByAddingUnit:NSCalendarUnitHour value:i * 5 toDate:base options:0], @"title":@"样本任务"}];
        for (NSInteger i = 0; i < 13; i++) [dates addObjectsFromArray:DDLMonthGrid([calendar dateByAddingUnit:NSCalendarUnitMonth value:i toDate:base options:0], calendar)];
        NSUInteger oldCount = 0, newCount = 0;
        NSTimeInterval start = NSDate.timeIntervalSinceReferenceDate;
        for (NSDate *day in dates) for (NSDictionary *task in tasks) if ([calendar isDate:task[@"due"] inSameDayAsDate:day]) oldCount++;
        NSTimeInterval scan = NSDate.timeIntervalSinceReferenceDate - start;
        start = NSDate.timeIntervalSinceReferenceDate;
        NSDictionary *index = DDLTasksByDay(tasks, calendar);
        for (NSDate *day in dates) newCount += [index[[calendar startOfDayForDate:day]] count];
        NSTimeInterval indexed = NSDate.timeIntervalSinceReferenceDate - start;
        if (oldCount != newCount) return 1;
        printf("PASS: 2000 tasks, %lu date cells, %lu matching entries\n", (unsigned long)dates.count, (unsigned long)newCount);
        printf("Date lookup: scan %.2f ms, indexed %.2f ms (%.1fx)\n", scan * 1000, indexed * 1000, scan / MAX(indexed, 0.000001));
    }
    return 0;
}
