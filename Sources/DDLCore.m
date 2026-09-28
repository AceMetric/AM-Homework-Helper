#import "DDLCore.h"
#include <math.h>

static NSArray<NSString *> *Match(NSString *text, NSString *pattern) {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
    NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!match) return nil;
    NSMutableArray *parts = [NSMutableArray array];
    for (NSUInteger i = 1; i < match.numberOfRanges; i++) {
        NSRange range = [match rangeAtIndex:i];
        [parts addObject:range.location == NSNotFound ? @"" : [text substringWithRange:range]];
    }
    return parts;
}

static NSDate *CivilDate(NSCalendar *calendar, NSInteger year, NSInteger month, NSInteger day, NSInteger hour, NSInteger minute) {
    if (year < 1900 || year > 9999 || month < 1 || month > 12 || day < 1 || day > 31 || hour < 0 || hour > 23 || minute < 0 || minute > 59) return nil;
    NSDateComponents *parts = [NSDateComponents new];
    parts.year = year; parts.month = month; parts.day = day; parts.hour = hour; parts.minute = minute; parts.second = 0;
    NSDate *date = [calendar dateFromComponents:parts];
    NSDateComponents *check = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:date];
    if (check.year != year || check.month != month || check.day != day || check.hour != hour || check.minute != minute) return nil;
    return date;
}

NSDate *DDLParseDate(NSString *input, NSDate *now, NSCalendar *calendar) {
    NSString *text = [[input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] stringByReplacingOccurrencesOfString:@"：" withString:@":"];
    NSArray *absolute = Match(text, @"^(\\d{4})[-/](\\d{1,2})[-/](\\d{1,2})(?:[Tt\\s]+(\\d{1,2}):(\\d{2}))?$");
    if (absolute) return CivilDate(calendar, [absolute[0] integerValue], [absolute[1] integerValue], [absolute[2] integerValue], [absolute[3] length] ? [absolute[3] integerValue] : 23, [absolute[4] length] ? [absolute[4] integerValue] : 59);
    text = [[text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""];

    NSArray *relative = Match(text, @"^(今天|今晚|明天|后天|一周后|两周后|二周后|下周|\\d{1,5}天后|\\d{1,4}周后|(?:本周|这周|下周|周|星期)[一二三四五六日天])(?:(\\d{1,2}):(\\d{2}))?$");
    if (!relative) return nil;
    NSString *dayText = relative[0];
    NSInteger hour = [relative[1] length] ? [relative[1] integerValue] : 23;
    NSInteger minute = [relative[2] length] ? [relative[2] integerValue] : 59;
    if (hour > 23 || minute > 59) return nil;
    NSInteger offset = 0;
    if ([dayText isEqualToString:@"明天"]) offset = 1;
    else if ([dayText isEqualToString:@"后天"]) offset = 2;
    else if ([dayText isEqualToString:@"一周后"] || [dayText isEqualToString:@"下周"]) offset = 7;
    else if ([dayText isEqualToString:@"两周后"] || [dayText isEqualToString:@"二周后"]) offset = 14;
    else if ([dayText hasSuffix:@"后"]) {
        offset = dayText.integerValue * ([dayText containsString:@"周"] ? 7 : 1);
        if (offset > 36500) return nil;
    } else if ([dayText containsString:@"周"] || [dayText containsString:@"星期"]) {
        NSString *last = [dayText substringFromIndex:dayText.length - 1];
        NSInteger weekday = [@[@"一", @"二", @"三", @"四", @"五", @"六", @"日"] indexOfObject:last];
        if ([last isEqualToString:@"天"]) weekday = 6;
        NSInteger current = ([calendar component:NSCalendarUnitWeekday fromDate:now] + 5) % 7;
        offset = weekday - current;
        if ([dayText hasPrefix:@"下周"]) offset += 7;
        else if (![dayText hasPrefix:@"本周"] && ![dayText hasPrefix:@"这周"] && offset < 0) offset += 7;
    }
    NSDate *day = [calendar dateByAddingUnit:NSCalendarUnitDay value:offset toDate:now options:0];
    NSDateComponents *parts = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:day];
    return CivilDate(calendar, parts.year, parts.month, parts.day, hour, minute);
}

NSString *DDLFormatDate(NSDate *date, NSString *format) {
    // Formatters are expensive to construct. Keep a bounded cache per thread.
    NSMutableDictionary *thread = NSThread.currentThread.threadDictionary;
    NSCache *cache = thread[@"DDLDateFormatters"];
    if (!cache) { cache = [NSCache new]; cache.countLimit = 32; thread[@"DDLDateFormatters"] = cache; }
    NSDateFormatter *formatter = [cache objectForKey:format];
    if (!formatter) {
        formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
        formatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        formatter.dateFormat = format;
        [cache setObject:formatter forKey:format];
    }
    NSTimeZone *zone = NSTimeZone.defaultTimeZone;
    if (![formatter.timeZone isEqual:zone]) formatter.timeZone = zone;
    return [formatter stringFromDate:date];
}

NSString *DDLRemaining(NSDate *due, NSDate *now, BOOL completed) {
    if (completed) return @"已完成";
    NSTimeInterval interval = [due timeIntervalSinceDate:now];
    NSInteger minutes = MAX(1, (NSInteger)ceil(fabs(interval) / 60));
    NSString *amount;
    if (minutes < 60) amount = [NSString stringWithFormat:@"%ld 分钟", (long)minutes];
    else if (minutes < 1440) amount = [NSString stringWithFormat:@"%ld 小时", (long)(minutes / 60)];
    else amount = [NSString stringWithFormat:@"%ld 天", (long)(minutes / 1440)];
    return [NSString stringWithFormat:interval < 0 ? @"逾期 %@" : @"剩余 %@", amount];
}

static NSArray<NSNumber *> *LegacyReminderOffsets(NSInteger mode) {
    if (mode == 0) return @[@0];
    if (mode == 1) return @[@60, @0];
    if (mode == 2) return @[@1440, @60, @0];
    if (mode == 3) return @[@4320, @1440, @60, @0];
    return @[];
}

static NSArray<NSNumber *> *NormalizedReminderOffsets(id value) {
    if (![value isKindOfClass:NSArray.class]) return nil;
    NSMutableSet<NSNumber *> *seen = [NSMutableSet set];
    for (id item in value) {
        if (![item respondsToSelector:@selector(integerValue)]) continue;
        NSInteger minutes = [item integerValue];
        if (minutes < 0 || minutes > 5256000) continue;
        [seen addObject:@(minutes)];
        if (seen.count >= 10) break;
    }
    return [[seen allObjects] sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) { return [b compare:a]; }];
}

NSArray<NSNumber *> *DDLReminderOffsetsForTask(NSDictionary *task) {
    NSArray<NSNumber *> *custom = NormalizedReminderOffsets(task[@"reminderOffsets"]);
    if (custom) return custom;
    NSInteger mode = task[@"reminder"] ? [task[@"reminder"] integerValue] : 2;
    return LegacyReminderOffsets(mode);
}

NSArray<NSNumber *> *DDLParseReminderOffsets(NSString *input) {
    NSString *text = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text.length) return nil;
    if ([@[@"不提醒", @"关闭", @"无"] containsObject:text]) return @[];
    for (NSString *separator in @[@"，", @"、", @"+", @"＋", @"；", @";"]) text = [text stringByReplacingOccurrencesOfString:separator withString:@","];
    NSMutableSet<NSNumber *> *offsets = [NSMutableSet set];
    NSRegularExpression *duration = [NSRegularExpression regularExpressionWithPattern:@"^(?:提前)?(\\d{1,6})(分钟|分|小时|时|天)$" options:0 error:NULL];
    for (NSString *raw in [text componentsSeparatedByString:@","]) {
        NSString *token = [[raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] stringByReplacingOccurrencesOfString:@" " withString:@""];
        if (!token.length) continue;
        if ([@[@"到期", @"到期时", @"准时"] containsObject:token]) { [offsets addObject:@0]; continue; }
        NSTextCheckingResult *match = [duration firstMatchInString:token options:0 range:NSMakeRange(0, token.length)];
        if (!match) return nil;
        NSInteger amount = [[token substringWithRange:[match rangeAtIndex:1]] integerValue];
        NSString *unit = [token substringWithRange:[match rangeAtIndex:2]];
        NSInteger minutes = amount * ([unit containsString:@"天"] ? 1440 : ([unit containsString:@"时"] ? 60 : 1));
        if (amount <= 0 || minutes > 5256000) return nil;
        [offsets addObject:@(minutes)];
        if (offsets.count > 10) return nil;
    }
    if (!offsets.count) return nil;
    return [[offsets allObjects] sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) { return [b compare:a]; }];
}

NSString *DDLFormatReminderOffsets(NSArray<NSNumber *> *offsets) {
    NSArray<NSNumber *> *normalized = NormalizedReminderOffsets(offsets) ?: @[];
    if (!normalized.count) return @"不提醒";
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSNumber *value in normalized) {
        NSInteger minutes = value.integerValue;
        if (minutes == 0) [parts addObject:@"到期"];
        else if (minutes % 1440 == 0) [parts addObject:[NSString stringWithFormat:@"%ld天", (long)(minutes / 1440)]];
        else if (minutes % 60 == 0) [parts addObject:[NSString stringWithFormat:@"%ld小时", (long)(minutes / 60)]];
        else [parts addObject:[NSString stringWithFormat:@"%ld分钟", (long)minutes]];
    }
    return [parts componentsJoinedByString:@"、"];
}

NSArray<NSDictionary *> *DDLReminderPlan(NSDictionary *task, NSDate *now, NSCalendar *calendar) {
    (void)calendar;
    if ([task[@"completed"] boolValue] || [task[@"archived"] boolValue] || [task[@"deleted"] boolValue]) return @[];
    NSDate *due = task[@"due"];
    NSMutableArray *result = [NSMutableArray array];
    for (NSNumber *offset in DDLReminderOffsetsForTask(task)) {
        NSInteger minutes = offset.integerValue;
        NSDate *date = [due dateByAddingTimeInterval:-minutes * 60.0];
        if ([date compare:now] != NSOrderedDescending) continue;
        NSString *message = minutes == 0 ? @"DDL 到时间了" : (minutes % 1440 == 0 ? [NSString stringWithFormat:@"%ld 天后截止", (long)(minutes / 1440)] : (minutes % 60 == 0 ? [NSString stringWithFormat:@"%ld 小时后截止", (long)(minutes / 60)] : [NSString stringWithFormat:@"%ld 分钟后截止", (long)minutes]));
        [result addObject:@{@"date": date, @"id": [NSString stringWithFormat:@"ddl.%@.offset.%ld", task[@"id"], (long)minutes], @"message": message, @"task": task}];
    }
    return result;
}

NSArray<NSMutableDictionary *> *DDLNormalizeTasks(NSArray *items) {
    NSMutableArray *result = [NSMutableArray array];
    NSMutableSet *ids = [NSMutableSet set];
    for (id item in items) {
        if (![item isKindOfClass:NSDictionary.class] || ![item[@"due"] isKindOfClass:NSDate.class] || ![item[@"title"] isKindOfClass:NSString.class]) continue;
        NSMutableDictionary *task = [item mutableCopy];
        NSString *identifier = [task[@"id"] isKindOfClass:NSString.class] ? task[@"id"] : nil;
        if (!identifier.length || [ids containsObject:identifier]) identifier = NSUUID.UUID.UUIDString;
        task[@"id"] = identifier;
        [ids addObject:identifier];
        task[@"subject"] = [task[@"subject"] isKindOfClass:NSString.class] && [task[@"subject"] length] ? task[@"subject"] : @"其他";
        task[@"notes"] = [task[@"notes"] isKindOfClass:NSString.class] ? task[@"notes"] : @"";
        task[@"completed"] = @([task[@"completed"] respondsToSelector:@selector(boolValue)] && [task[@"completed"] boolValue]);
        task[@"archived"] = @([task[@"archived"] respondsToSelector:@selector(boolValue)] && [task[@"archived"] boolValue]);
        BOOL deleted = [task[@"deleted"] respondsToSelector:@selector(boolValue)] && [task[@"deleted"] boolValue];
        task[@"deleted"] = @(deleted);
        if (deleted) task[@"deletedAt"] = [task[@"deletedAt"] isKindOfClass:NSDate.class] ? task[@"deletedAt"] : [NSDate date];
        else [task removeObjectForKey:@"deletedAt"];
        NSInteger priority = [task[@"priority"] respondsToSelector:@selector(integerValue)] ? [task[@"priority"] integerValue] : 0;
        task[@"priority"] = @(MAX(0, MIN(2, priority)));
        NSInteger mode = [task[@"reminder"] respondsToSelector:@selector(integerValue)] ? [task[@"reminder"] integerValue] : 2;
        mode = MAX(0, MIN(4, mode)); task[@"reminder"] = @(mode);
        NSArray<NSNumber *> *offsets = NormalizedReminderOffsets(task[@"reminderOffsets"]);
        task[@"reminderOffsets"] = offsets ?: LegacyReminderOffsets(mode);
        [result addObject:task];
    }
    return result;
}

BOOL DDLMatchesFilter(NSDictionary *task, NSInteger filter, NSString *query, NSDate *now, NSCalendar *calendar) {
    BOOL deleted = [task[@"deleted"] boolValue];
    query = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *searchable = [NSString stringWithFormat:@"%@ %@ %@", task[@"subject"], task[@"title"], task[@"notes"] ?: @""];
    if (filter == 5) return deleted && (query.length == 0 || [searchable localizedStandardContainsString:query]);
    if (deleted) return NO;
    BOOL archived = [task[@"archived"] boolValue], completed = [task[@"completed"] boolValue];
    if (filter == 4) { if (!archived) return NO; }
    else if (archived || (filter == 3 ? !completed : completed)) return NO;
    NSDate *due = task[@"due"];
    if (filter == 1 && ![calendar isDate:due inSameDayAsDate:now]) return NO;
    if (filter == 2) {
        NSDate *end = [calendar dateByAddingUnit:NSCalendarUnitDay value:7 toDate:[calendar startOfDayForDate:now] options:0];
        if ([due compare:now] == NSOrderedAscending || [due compare:end] != NSOrderedAscending) return NO;
    }
    return query.length == 0 || [searchable localizedStandardContainsString:query];
}

NSArray<NSMutableDictionary *> *DDLMergeTasks(NSArray *existing, NSArray *incoming) {
    NSMutableArray *merged = [DDLNormalizeTasks(existing) mutableCopy];
    for (NSMutableDictionary *task in DDLNormalizeTasks(incoming)) {
        BOOL duplicate = NO, conflict = NO;
        NSMutableDictionary *content = [task mutableCopy]; [content removeObjectForKey:@"id"];
        for (NSDictionary *old in merged) {
            NSMutableDictionary *oldContent = [old mutableCopy]; [oldContent removeObjectForKey:@"id"];
            if ([oldContent isEqualToDictionary:content]) duplicate = YES;
            if ([old[@"id"] isEqual:task[@"id"]]) conflict = YES;
        }
        if (duplicate) continue;
        if (conflict) task[@"id"] = NSUUID.UUID.UUIDString;
        [merged addObject:task];
    }
    return merged;
}

NSDictionary<NSDate *, NSArray<NSDictionary *> *> *DDLTasksByDay(NSArray<NSDictionary *> *items, NSCalendar *calendar) {
    NSMutableDictionary<NSDate *, NSMutableArray<NSDictionary *> *> *days = [NSMutableDictionary dictionary];
    for (NSDictionary *task in items) {
        NSDate *day = [calendar startOfDayForDate:task[@"due"]];
        if (!days[day]) days[day] = [NSMutableArray array];
        [days[day] addObject:task];
    }
    return days;
}

NSArray<NSDate *> *DDLMonthGrid(NSDate *month, NSCalendar *calendar) {
    NSDate *start;
    [calendar rangeOfUnit:NSCalendarUnitMonth startDate:&start interval:NULL forDate:month];
    NSInteger offset = ([calendar component:NSCalendarUnitWeekday fromDate:start] + 5) % 7;
    NSInteger days = [calendar rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitMonth forDate:month].length;
    NSInteger slots = ((offset + days + 6) / 7) * 7;
    NSMutableArray *dates = [NSMutableArray array];
    for (NSInteger i = 0; i < slots; i++) [dates addObject:[calendar dateByAddingUnit:NSCalendarUnitDay value:i - offset toDate:start options:0]];
    return dates;
}

NSArray<NSDictionary *> *DDLCalendarTasks(NSArray *items, NSInteger status, NSString *query) {
    NSString *trimmed = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSArray *filtered = [items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *task, NSDictionary *bindings) {
        (void)bindings;
        if ([task[@"archived"] boolValue] || [task[@"deleted"] boolValue]) return NO;
        BOOL done = [task[@"completed"] boolValue];
        if ((status == 1 && done) || (status == 2 && !done)) return NO;
        NSString *text = [NSString stringWithFormat:@"%@ %@ %@", task[@"title"], task[@"subject"], task[@"notes"] ?: @""];
        return trimmed.length == 0 || [text localizedStandardContainsString:trimmed];
    }]];
    return [filtered sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult dateOrder = [a[@"due"] compare:b[@"due"]];
        if (dateOrder != NSOrderedSame) return dateOrder;
        if ([a[@"completed"] boolValue] != [b[@"completed"] boolValue]) return [a[@"completed"] boolValue] ? NSOrderedDescending : NSOrderedAscending;
        return [a[@"title"] localizedStandardCompare:b[@"title"]];
    }];
}

NSDictionary<NSString *, NSNumber *> *DDLMonthSummary(NSArray *items, NSDate *month, NSDate *now, NSCalendar *calendar) {
    NSInteger total = 0, completed = 0, overdue = 0;
    NSDate *start;
    [calendar rangeOfUnit:NSCalendarUnitMonth startDate:&start interval:NULL forDate:month];
    NSDate *end = [calendar dateByAddingUnit:NSCalendarUnitMonth value:1 toDate:start options:0];
    for (NSDictionary *task in items) {
        NSDate *due = task[@"due"];
        if ([task[@"archived"] boolValue] || [task[@"deleted"] boolValue] || [due compare:start] == NSOrderedAscending || [due compare:end] != NSOrderedAscending) continue;
        total++;
        if ([task[@"completed"] boolValue]) completed++;
        else if ([due compare:now] == NSOrderedAscending) overdue++;
    }
    return @{@"total":@(total), @"completed":@(completed), @"pending":@(total - completed), @"overdue":@(overdue)};
}
