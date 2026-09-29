#import <Cocoa/Cocoa.h>
#import "../Sources/DDLImport.h"
#import "../Sources/DDLCore.h"

static void Check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

int main(void) {
    @autoreleasepool {
        NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        calendar.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
        NSDateComponents *parts = [NSDateComponents new];
        parts.year = 2026; parts.month = 9; parts.day = 28; parts.hour = 12;
        NSDate *now = [calendar dateFromComponents:parts];

        NSDictionary *message = DDLFieldsFromAnnouncement(@"张老师 2026年9月28日 20:30\n请于10月1日 23:59前提交数据结构实验报告", now, calendar);
        NSDateComponents *due = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute fromDate:message[@"due"]];
        Check(due.year == 2026 && due.month == 10 && due.day == 1 && due.hour == 23 && due.minute == 59, @"应优先识别消息中的截止日期，而非聊天时间");
        Check([message[@"title"] containsString:@"数据结构实验报告"], @"应提取提交的任务名称");

        message = DDLFieldsFromAnnouncement(@"【高等数学】请在明天晚上8点提交第三章习题", now, calendar);
        due = [calendar components:NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute fromDate:message[@"due"]];
        Check(due.day == 29 && due.hour == 20 && due.minute == 0, @"应识别相对日期和中文时间");
        Check([message[@"subject"] isEqualToString:@"高等数学"], @"应提取课程名称");

        message = DDLFieldsFromAnnouncement(@"截止：2026-10-15 18:00", now, calendar);
        Check(message[@"due"] != nil && message[@"title"] == nil, @"只有日期时不应编造任务名称");
        message = DDLFieldsFromAnnouncement(@"请按时交作业", now, calendar);
        Check(message[@"due"] == nil, @"无日期的通知需要人工确认");
        message = DDLFieldsFromAnnouncement(@"10月32日截止", now, calendar);
        Check(message[@"due"] == nil, @"无效日期不能通过识别");

        parts.month = 10; parts.day = 8; parts.hour = 23; parts.minute = 59;
        NSDate *teacherDue = [calendar dateFromComponents:parts];
        NSDate *myDue = DDLPersonalDueDate(teacherDue, 1, calendar);
        due = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute fromDate:myDue];
        Check(due.year == 2026 && due.month == 10 && due.day == 7 && due.hour == 23 && due.minute == 59, @"老师 8 号交，提前一天应设为 7 号同一时间");
        Check([DDLPersonalDueDate(teacherDue, 0, calendar) isEqualToDate:teacherDue], @"不提前时应保留老师的截止时间");
        Check(DDLPersonalDueDate(teacherDue, -1, calendar) == nil, @"手动设置不应触发自动提前");
        NSDictionary *stored = @{ @"id": @"lead-test", @"title": @"实验报告", @"due": myDue, @"announcedDue": teacherDue, @"leadDays": @1 };
        NSDictionary *normalized = DDLNormalizeTasks(@[stored]).firstObject;
        Check([normalized[@"announcedDue"] isEqualToDate:teacherDue] && [normalized[@"leadDays"] integerValue] == 1, @"保存时应保留老师原定时间和提前选项");

        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(1400, 180)];
        [image lockFocus];
        [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0, 0, 1400, 180));
        [@"高数作业 截止10月15日 18:00" drawAtPoint:NSMakePoint(35, 58) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:55 weight:NSFontWeightSemibold], NSForegroundColorAttributeName:NSColor.blackColor}];
        [image unlockFocus];
        NSError *ocrError = nil;
        NSString *ocr = DDLOCRTextFromImage(image, &ocrError);
        Check(ocr.length > 0 && [ocr containsString:@"10月15日"], [NSString stringWithFormat:@"应从截图提取日期，结果：%@，错误：%@", ocr, ocrError]);
        NSLog(@"导入解析测试通过");
    }
    return 0;
}
