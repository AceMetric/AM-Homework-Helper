#import "SSAssignments.h"
#import "DDLImport.h"
#import "DDLCore.h"

static NSRegularExpression *Regex(NSString *pattern) { return [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:NULL]; }
static BOOL Match(NSString *text, NSString *pattern) { return [Regex(pattern) firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil; }
static NSString *Replace(NSString *text, NSString *pattern, NSString *value) { return [Regex(pattern) stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:value]; }
BOOL SSIsSupportedDocument(NSString *path) {
    NSString *extension = path.pathExtension.lowercaseString;
    if (extension.length) return [@[@"md", @"markdown", @"mdx", @"txt", @"rst", @"adoc", @"org", @"tex"] containsObject:extension];
    NSString *name = path.lastPathComponent.lowercaseString;
    return [name isEqual:@"readme"] || [name isEqual:@"assignment"] || [name isEqual:@"homework"] || [name isEqual:@"作业"];
}
static NSString *CleanTitle(NSString *raw) {
    NSString *title = Replace(raw, @"^\\s*(?:#{1,6}|[-*+]|\\d+[.)])\\s*", @"");
    title = Replace(title, @"(?:截止(?:时间|日期)?|deadline|due(?: date)?|ddl)\\s*[:：]?.*$", @"");
    title = Replace(title, @"(?:20\\d{2}[-/年]\\d{1,2}[-/月]\\d{1,2}|\\d{1,2}月\\d{1,2}日?).*$", @"");
    title = Replace(title, @"[|`*_]+", @" ");
    title = [title stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \t\n:：-—，,。"]];
    return title.length > 90 ? [title substringToIndex:90] : title;
}
static BOOL GenericTitle(NSString *title) {
    return !title.length || Match(title, @"^(?:规则|要求|提交(?:规则|要求|说明)?|说明|任务|作业(?:目标|要求|内容|说明|规则)?|截止时间|时间|日期|rules?|requirements?|instructions?|tasks?|readme|[0-9]+[.)]?)$");
}
static NSString *DocumentTitle(NSArray *lines, NSString *path) {
    BOOL fence = NO;
    for (NSString *raw in lines) {
        NSString *line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([line hasPrefix:@"```"] || [line hasPrefix:@"~~~"]) { fence = !fence; continue; }
        if (!fence && [line hasPrefix:@"#"]) {
            NSString *title = CleanTitle(line);
            if (!GenericTitle(title)) return title;
        }
    }
    NSString *name = path.lastPathComponent.stringByDeletingPathExtension;
    if (!GenericTitle(name)) return name;
    NSString *folder = path.stringByDeletingLastPathComponent.lastPathComponent;
    return folder.length && !GenericTitle(folder) ? folder : @"待确认作业";
}
static NSString *Title(NSString *line, NSString *heading, NSString *previous, NSString *documentTitle) {
    NSString *inlineTitle = CleanTitle(line);
    if (inlineTitle.length > 2 && !GenericTitle(inlineTitle) && !Match(inlineTitle, @"^(?:请在|最晚|提交时间|before|by)\\s*$") && !Match(inlineTitle, @"^(?:今天|今晚|明天|后天|(?:本|这|下)?(?:周|星期|礼拜)|20\\d{2}[-/年]|\\d{1,2}月)") && !Match(line, @"^\\s*[-*+]?\\s*(?:\\*\\*)?(?:截止|deadline|due|ddl)")) return inlineTitle;
    NSString *title = CleanTitle(heading);
    if (!GenericTitle(title)) return title;
    title = CleanTitle(previous);
    if (Match(previous, @"^\\s*#") && !GenericTitle(title)) return title;
    return documentTitle;
}
static NSString *Snippet(NSArray *lines, NSUInteger index, NSString *heading) {
    // Include the enclosing activity, including requirements far below its deadline.
    NSUInteger start = 0, end = lines.count, level=6;
    NSString *activity = @"作业|homework|assignment|考试|exam|课堂|课上|classroom";
    BOOL (^isActivity)(NSString *)=^BOOL(NSString *line){NSString *title=CleanTitle(line);return [line hasPrefix:@"#"] && !GenericTitle(title) && !Match(title,@"^作业(?:选题|结构|提交|评分|提示|格式|目的|目标|要求|内容|说明|规则)") && Match(title,activity);};
    NSUInteger (^depth)(NSString *)=^NSUInteger(NSString *line){NSUInteger n=0;while(n<line.length && [line characterAtIndex:n]=='#')n++;return n;};
    for (NSUInteger i = 0; i <= index && i < lines.count; i++) if (isActivity(lines[i])) {start = i;level=depth(lines[i]);}
    for (NSUInteger i = index + 1; i < lines.count; i++) if (isActivity(lines[i]) && depth(lines[i])<=level) { end = i; break; }
    NSString *excerpt = [[lines subarrayWithRange:NSMakeRange(start, end - start)] componentsJoinedByString:@"\n"];
    return heading.length ? [NSString stringWithFormat:@"%@\n%@", heading, excerpt] : excerpt;
}
static NSDictionary *Candidate(NSString *title, NSString *repository, NSString *path, NSString *blobSHA, NSUInteger line, NSString *snippet, NSDate *due, BOOL needsDate, BOOL needsTime, NSMutableDictionary *counts) {
    NSString *identity = [NSString stringWithFormat:@"%@|%@|%@", repository.lowercaseString, path, title.lowercaseString];
    NSUInteger ordinal = [counts[identity] unsignedIntegerValue] + 1; counts[identity] = @(ordinal);
    NSMutableDictionary *candidate = [@{@"id":[NSString stringWithFormat:@"%@|%lu", identity, (unsigned long)ordinal], @"repository":repository, @"path":path, @"line":@(line), @"blobSHA":blobSHA, @"title":title, @"sourceTitle":title, @"needsDate":@(needsDate), @"needsTime":@(needsTime), @"snippet":snippet} mutableCopy];
    if (due) candidate[@"due"] = due;
    return candidate;
}
NSString *SSActivityKindLabel(NSString *kind) {
    return @{@"assignment":@"作业", @"exam":@"考试", @"classroom":@"课上任务", @"unknown":@"待确认类型"}[kind] ?: @"待确认类型";
}
static NSDictionary *Classification(NSString *context, NSString *path) {
    NSString *evidence = [NSString stringWithFormat:@"%@\n%@", path, context];
    BOOL exam = Match(evidence, @"考试|测验|(?:^|[/_\\s-])(?:exam(?:ination)?|quiz)(?:[/_\\s.-]|$)");
    BOOL classroom = Match(evidence, @"课上(?:任务|练习|实验)|课堂(?:任务|练习|实验)|随堂|当堂|classroom|in[_ -]class");
    NSString *kind = exam && classroom ? @"unknown" : exam ? @"exam" : classroom ? @"classroom" : Match(evidence, @"作业|课后|homework|assignment|(?:^|[/_\\s-])hw[0-9]|提交|截止|deadline|\\bdue\\b|\\bsubmit\\b") ? @"assignment" : @"unknown";
    return @{@"kind":kind, @"kindReason":exam && classroom ? @"考试与课堂任务线索冲突，请确认类型" : exam ? @"考试标题或所在目录" : classroom ? @"明确的课堂任务说明" : [kind isEqual:@"assignment"] ? @"作业名称或提交要求" : @"未找到明确活动类型，请确认"};
}
static NSString *GroupPath(NSString *path, NSString *kind) {
    if ([kind isEqual:@"exam"] || [kind isEqual:@"classroom"]) {
        NSArray *parts = path.pathComponents;
        for (NSUInteger i = 0; i + 1 < parts.count; i++) {
            NSDictionary *type = Classification(@"", parts[i]);
            if ([type[@"kind"] isEqual:kind]) return [[parts subarrayWithRange:NSMakeRange(0, i + 1)] componentsJoinedByString:@"/"];
        }
    }
    return path;
}
static NSString *Normalized(NSString *text) {
    for (NSArray *pair in @[@[@"：", @":"], @[@"／", @"/"], @[@"－", @"-"], @[@"（", @"("], @[@"）", @")"], @[@"＊", @"*"]]) text = [text stringByReplacingOccurrencesOfString:pair[0] withString:pair[1]];
    return Replace(text, @"[*_`]", @"");
}
static NSString *Group(NSString *text, NSTextCheckingResult *match, NSUInteger index) {
    NSRange range = [match rangeAtIndex:index]; return range.location == NSNotFound ? @"" : [text substringWithRange:range];
}
static NSString *Clock(NSString *text, BOOL *invalid) {
    NSTextCheckingResult *clock = [Regex(@"(?<![0-9+-])([0-9]{1,2}):([0-9]{2})(?![0-9])") firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    NSInteger hour, minute;
    if (clock) { hour = [Group(text, clock, 1) integerValue]; minute = [Group(text, clock, 2) integerValue]; }
    else {
        clock = [Regex(@"(凌晨|早上|上午|中午|下午|傍晚|晚上|今晚)?\\s*([0-9]{1,2})\\s*[点时](半|[0-9]{1,2}分?)?") firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
        if (!clock) return nil;
        NSString *period = Group(text, clock, 1), *minutes = Group(text, clock, 3);
        hour = [Group(text, clock, 2) integerValue]; minute = [minutes isEqual:@"半"] ? 30 : minutes.integerValue;
        if (Match(period, @"下午|傍晚|晚上|今晚") && hour < 12) hour += 12;
        if (Match(period, @"凌晨|上午|早上") && hour == 12) hour = 0;
        if ([period isEqual:@"中午"] && hour < 11) hour += 12;
    }
    if (hour > 23 || minute > 59) { *invalid = YES; return nil; }
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)hour, (long)minute];
}
static NSCalendar *DateCalendar(NSString *text, NSCalendar *calendar, BOOL *invalid) {
    NSCalendar *result = calendar.copy;
    if (Match(text, @"北京时间|中国标准时间")) result.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:8 * 3600];
    NSTextCheckingResult *zone = [Regex(@"(?:UTC|GMT)\\s*([+-])\\s*(\\d{1,2})(?::([0-9]{2}))?|(?<=[0-9])([+-])(\\d{2}):([0-9]{2})\\b") firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (zone) {
        NSUInteger offset = [zone rangeAtIndex:1].location == NSNotFound ? 4 : 1;
        NSInteger hours = [Group(text, zone, offset + 1) integerValue], minutes = [Group(text, zone, offset + 2) integerValue];
        if (hours > 14 || minutes > 59 || (hours == 14 && minutes)) *invalid = YES;
        else result.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:([Group(text, zone, offset) isEqual:@"-"] ? -1 : 1) * (hours * 3600 + minutes * 60)];
    } else if (Match(text, @"(?<=[0-9])Z\\b")) result.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    return result;
}
static NSDictionary *DateFields(NSString *dateText, NSString *token, NSCalendar *calendar) {
    NSMutableDictionary *fields = NSMutableDictionary.dictionary;
    BOOL invalid = NO; NSString *clock = Clock(dateText, &invalid);
    NSCalendar *zone = DateCalendar(dateText, calendar, &invalid); fields[@"timeZone"] = zone.timeZone.name;
    if (clock) fields[@"clock"] = clock;
    fields[@"needsTime"] = @(!clock); fields[@"needsDate"] = @YES;
    if (Match(token, @"今天|今晚|明天|后天|周|星期|礼拜|天后")) { fields[@"relative"] = @YES; fields[@"relativeToken"] = token; }
    else {
        NSString *compact = Replace(token, @"\\s+", @"");
        NSTextCheckingResult *date = [Regex(@"^(?:(20[0-9]{2})[-/年])?([0-9]{1,2})[-/月]([0-9]{1,2})[日号]?$") firstMatchInString:compact options:0 range:NSMakeRange(0, compact.length)];
        if (date) {
            BOOL yearKnown = Group(compact, date, 1).length > 0;
            NSInteger year = yearKnown ? [Group(compact, date, 1) integerValue] : 2000;
            NSString *civil = [NSString stringWithFormat:@"%04ld-%02ld-%02ld", (long)year, (long)[Group(compact, date, 2) integerValue], (long)[Group(compact, date, 3) integerValue]];
            NSDate *value = DDLParseDate([civil stringByAppendingFormat:@" %@", clock ?: @"00:00"], NSDate.date, zone);
            if (!value) invalid = YES;
            else if (yearKnown) {
                fields[@"dateOnly"] = civil; fields[@"needsDate"] = @NO;
                if (clock && !invalid) fields[@"due"] = value;
                NSTextCheckingResult *weekday = [Regex(@"\\(\\s*(?:星期|周|礼拜)([一二三四五六日天])\\s*\\)") firstMatchInString:dateText options:0 range:NSMakeRange(0, dateText.length)];
                if (weekday) {
                    NSString *day = Group(dateText, weekday, 1); NSUInteger expected = [@[@"日", @"一", @"二", @"三", @"四", @"五", @"六"] indexOfObject:[day isEqual:@"天"] ? @"日" : day];
                    if ([zone component:NSCalendarUnitWeekday fromDate:value] != (NSInteger)expected + 1) { fields[@"needsDate"] = @YES; fields[@"warnings"] = @[@"日期与括号中的星期不一致，请核对老师原文"]; }
                }
            }
        } else invalid = YES;
    }
    if (invalid) { [fields removeObjectForKey:@"due"]; fields[@"needsDate"] = @YES; fields[@"warnings"] = @[@"日期、时间或时区无效，请核对并补全"]; }
    return fields;
}
NSArray<NSDictionary *> *SSDiscoveriesFromDocument(NSString *text, NSString *repository, NSString *path, NSString *blobSHA, NSDate *now, NSCalendar *calendar) {
    if (!text.length || !repository.length || !path.length) return @[];
    NSArray *lines = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] componentsSeparatedByString:@"\n"];
    NSMutableArray *result = NSMutableArray.array, *sections = NSMutableArray.array; NSMutableDictionary *counts = NSMutableDictionary.dictionary;
    NSString *heading = @"", *previous = @"", *documentTitle = DocumentTitle(lines, path); BOOL fence = NO, actionable = NO; NSUInteger headingLine = 1;
    NSString *relativePattern = @"今天|今晚|明天|后天|(?:本|这|下)(?:周|星期|礼拜)(?:[一二三四五六日天末])?|(?:周|星期|礼拜)[一二三四五六日天末]|一周后|两周后|二周后|[0-9]{1,3}天后|[0-9]{1,2}周后";
    NSString *datePattern = [@"(?<![0-9])(?:20[0-9]{2}\\s*[-/年]\\s*[0-9]{1,2}\\s*[-/月]\\s*[0-9]{1,2}\\s*[日号]?|[0-9]{1,2}\\s*月\\s*[0-9]{1,2}\\s*[日号]?|[0-9]{1,2}/[0-9]{1,2})(?![0-9])|" stringByAppendingString:relativePattern];
    // Metadata and teaching examples do not create deadline records.
    if (Match(documentTitle, @"^(?:教材|示例|发布日志|更新日志|课程介绍|changelog|examples?|tutorial)\\b") || Match(path, @"(?:^|/)(?:examples?|reference|changelog)(?:/|\\.)")) return @[];
    for (NSUInteger index = 0; index < lines.count; index++) {
        NSString *raw = [lines[index] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([raw hasPrefix:@"~~~"] || [raw hasPrefix:@"```"]) { fence = !fence; continue; }
        NSString *line = Normalized(raw);
        if (fence || !line.length) continue;
        if ([line hasPrefix:@"#"] && !GenericTitle(CleanTitle(line))) { heading = CleanTitle(line); headingLine = index + 1; }
        if ([line hasPrefix:@"#"] && !GenericTitle(CleanTitle(line)) && Match(CleanTitle(line), @"考试|测验|课上|课堂|随堂|作业|homework|assignment|exam|quiz")) [sections addObject:@{@"line":@(index), @"heading":CleanTitle(line)}];
        if (![line hasPrefix:@"#"] && !Match(line, @"^[-*+]?\\s*\\[.*\\]\\(.*\\)\\s*$") && Match(line, @"完成|提交|解答|实现|回答|必答|分析|solve|implement|submit|answer")) actionable = YES;
        NSString *context = [NSString stringWithFormat:@"%@\n%@\n%@\n%@", documentTitle, heading, previous, line];
        NSDictionary *classification = Classification(context, path);
        BOOL taskCue = ![classification[@"kind"] isEqual:@"unknown"] || Match(context, @"实验|报告|最晚|\\bddl\\b");
        NSArray *matches = [Regex(datePattern) matchesInString:line options:0 range:NSMakeRange(0, line.length)]; NSMutableArray *dates = NSMutableArray.array;
        NSArray *annotations = [Regex(@"\\(\\s*(?:周|星期|礼拜)[一二三四五六日天]\\s*\\)") matchesInString:line options:0 range:NSMakeRange(0, line.length)];
        for (NSTextCheckingResult *match in matches) {
            BOOL annotation = NO; for (NSTextCheckingResult *note in annotations) if (NSLocationInRange(match.range.location, note.range)) annotation = YES;
            if (!annotation) [dates addObject:match];
        }
        BOOL deadline = Match(line, @"截止|最晚|deadline|\\bdue\\b|\\bddl\\b");
        BOOL dateCue = deadline || Match(previous, @"截止|最晚|deadline|\\bdue\\b|\\bddl\\b") || (Match(line, @"提交|交作业|交报告|完成|submit|hand in") && Match(line, @"前|之前|最晚|于|在|\\bby\\b|before"));
        if (!dates.count && taskCue && deadline && !Match(line, @"[:：]\\s*$")) {
            NSMutableDictionary *candidate = [Candidate(Title(line, heading, previous, documentTitle), repository, path, blobSHA, index + 1, Snippet(lines, index, heading), nil, YES, YES, counts) mutableCopy];
            [candidate addEntriesFromDictionary:classification]; candidate[@"dateText"] = line; candidate[@"warnings"] = @[@"未识别到完整截止日期，请补全"];
            candidate[@"sectionLine"] = @(headingLine);
            BOOL invalidClock = NO; NSString *clock = Clock(line, &invalidClock); if (clock) { candidate[@"clock"] = clock; candidate[@"needsTime"] = @NO; }
            [result addObject:candidate];
        }
        NSUInteger eligible = 0;
        for (NSUInteger d = 0; taskCue && dateCue && d < dates.count; d++) {
            NSTextCheckingResult *dateMatch = dates[d]; NSString *prefix = [line substringToIndex:dateMatch.range.location];
            if (Match(prefix, @"(?:发布|更新|release|published|updated|created).{0,14}$") && !Match(prefix, @"(?:截止|deadline|due|ddl).{0,14}$")) continue;
            NSUInteger end = d + 1 < dates.count ? [dates[d + 1] range].location : line.length;
            NSString *dateText = [line substringWithRange:NSMakeRange(dateMatch.range.location, end - dateMatch.range.location)];
            // A clock on the following line is allowed only while still inside this deadline block.
            if (deadline && index + 1 < lines.count && !Match(dateText, @"[0-9]:[0-9]|点|时")) {
                NSString *next = Normalized(lines[index + 1]);
                if (Match(next, @"^\\s*(?:时间[:：]\\s*)?(?:凌晨|上午|中午|下午|晚上)?\\s*[0-9]{1,2}[:点时]")) dateText = [dateText stringByAppendingFormat:@" %@", next];
            }
            NSMutableDictionary *candidate = [Candidate(Title(line, heading, previous, documentTitle), repository, path, blobSHA, index + 1, Snippet(lines, index, heading), nil, YES, YES, counts) mutableCopy];
            [candidate addEntriesFromDictionary:classification]; [candidate addEntriesFromDictionary:DateFields(dateText, [line substringWithRange:dateMatch.range], calendar)];
            candidate[@"sectionLine"] = @(headingLine);
            candidate[@"dateText"] = [dateText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if ([candidate[@"relative"] boolValue]) candidate[@"deadlineText"] = candidate[@"dateText"];
            if (++eligible > 1) {
                NSMutableDictionary *first = result.lastObject; [first removeObjectForKey:@"due"]; first[@"needsDate"] = @YES; first[@"warnings"] = @[@"同一截止说明包含多个日期，请确认正确日期"]; first[@"dateText"] = line; continue;
            }
            [result addObject:candidate];
        }
        if (!dates.count && ![line hasPrefix:@"#"]) previous = line;
    }
    if (!result.count) {
        NSDictionary *classification = Classification(documentTitle, path); NSString *kind = classification[@"kind"];
        if ((actionable && (![kind isEqual:@"unknown"] || Match(documentTitle, @"任务|练习|题目|项目|exercise|project|task"))) || [kind isEqual:@"exam"] || [kind isEqual:@"classroom"]) {
            NSMutableDictionary *candidate = [Candidate(documentTitle, repository, path, blobSHA, 1, Snippet(lines, 0, @""), nil, YES, YES, counts) mutableCopy];
            [candidate addEntriesFromDictionary:classification]; candidate[@"warnings"] = @[@"未说明截止时间"]; [result addObject:candidate];
        }
    }
    for (NSUInteger i = 0; i < sections.count; i++) {
        NSUInteger start = [sections[i][@"line"] unsignedIntegerValue], end = i + 1 < sections.count ? [sections[i + 1][@"line"] unsignedIntegerValue] : lines.count;
        BOOL present = NO; for (NSDictionary *record in result) if ([record[@"line"] unsignedIntegerValue] >= start + 1 && [record[@"line"] unsignedIntegerValue] <= end) present = YES;
        NSString *body = [[lines subarrayWithRange:NSMakeRange(start, end - start)] componentsJoinedByString:@"\n"];
        if (present || !Match(body, @"完成|提交|解答|实现|回答|分析|solve|implement|submit|answer")) continue;
        NSMutableDictionary *record = [Candidate(sections[i][@"heading"], repository, path, blobSHA, start + 1, Snippet(lines, start, @""), nil, YES, YES, counts) mutableCopy];
        [record addEntriesFromDictionary:Classification(sections[i][@"heading"], path)]; record[@"warnings"] = @[@"未说明截止时间"]; [result addObject:record];
    }
    NSMutableArray *merged = NSMutableArray.array; NSMutableDictionary *deadlines = NSMutableDictionary.dictionary;
    for (NSMutableDictionary *record in result) {
        record[@"activityID"] = [NSString stringWithFormat:@"%@|%@|%@", repository.lowercaseString, record[@"kind"], GroupPath(path, record[@"kind"])];
        NSString *key = [NSString stringWithFormat:@"%@|%@|%@", record[@"kind"], record[@"sectionLine"] ?: @1, record[@"title"]];
        NSMutableDictionary *first = deadlines[key];
        if (first && record[@"dateText"] && first[@"dateText"]) {
            BOOL equal = YES;
            for (NSString *field in @[@"due", @"dateOnly", @"relativeToken", @"clock", @"needsDate", @"needsTime", @"warnings"]) if (![(first[field] ?: NSNull.null) isEqual:(record[field] ?: NSNull.null)]) equal = NO;
            if (!equal) { [first removeObjectForKey:@"due"]; first[@"needsDate"] = @YES; first[@"warnings"] = @[@"同一作业说明出现多个不同日期，请核对正确截止要求"]; first[@"dateText"] = [first[@"dateText"] stringByAppendingFormat:@"\n%@", record[@"dateText"]]; }
            continue;
        }
        if (record[@"dateText"]) deadlines[key] = record;
        [merged addObject:record];
    }
    return merged;
}
NSArray<NSDictionary *> *SSAssignmentsFromDocument(NSString *text, NSString *repository, NSString *path, NSString *blobSHA, NSDate *now, NSCalendar *calendar) {
    return [SSDiscoveriesFromDocument(text, repository, path, blobSHA, now, calendar) filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) { return [item[@"kind"] isEqual:@"assignment"]; }]];
}
NSArray<NSDictionary *> *SSGroupMaterials(NSArray<NSDictionary *> *records) {
    NSMutableArray *result = NSMutableArray.array; NSMutableDictionary *groups = NSMutableDictionary.dictionary;
    for (NSDictionary *record in records) {
        if ([record[@"kind"] isEqual:@"assignment"]) continue;
        NSString *key = record[@"activityID"] ?: record[@"id"]; NSMutableDictionary *group = groups[key];
        if (!group) { group = record.mutableCopy; group[@"id"] = key; group[@"documents"] = NSMutableArray.array; groups[key] = group; [result addObject:group]; }
        [group[@"documents"] addObject:record];
        if ([group[@"documents"] count] > 1) group[@"title"] = [GroupPath(record[@"path"], record[@"kind"]) lastPathComponent];
    }
    return result;
}
NSArray<NSDictionary *> *SSConsolidateAssignments(NSArray<NSDictionary *> *records) {
    NSMutableArray *assignments = NSMutableArray.array;
    for (NSDictionary *record in records) if ([record[@"kind"] isEqual:@"assignment"]) [assignments addObject:record.mutableCopy];
    NSMutableSet *attachments = NSMutableSet.set;
    for (NSMutableDictionary *record in assignments) {
        if (record[@"dateText"] || record[@"due"] || record[@"dateOnly"] || [[[record[@"path"] lastPathComponent] stringByDeletingPathExtension].lowercaseString isEqual:@"readme"]) continue;
        NSString *name = Normalized([[record[@"path"] lastPathComponent] stringByDeletingPathExtension]);
        name = Replace(name, @"\\s+", @"");
        for (NSMutableDictionary *announcement in assignments) {
            if (announcement == record || ![announcement[@"repository"] isEqual:record[@"repository"]] || ![[announcement[@"path"] stringByDeletingLastPathComponent] isEqual:[record[@"path"] stringByDeletingLastPathComponent]]) continue;
            if (![[[announcement[@"path"] lastPathComponent] stringByDeletingPathExtension].lowercaseString isEqual:@"readme"] || !announcement[@"dateText"]) continue;
            NSString *source = Replace(Normalized([announcement[@"snippet"] stringByRemovingPercentEncoding] ?: announcement[@"snippet"]), @"\\s+", @"");
            if (!name.length || [source rangeOfString:name].location == NSNotFound) continue;
            NSMutableArray *docs = [announcement[@"attachments"] mutableCopy] ?: NSMutableArray.array;
            [docs addObject:record]; announcement[@"attachments"] = docs; [attachments addObject:record[@"id"]]; break;
        }
    }
    [assignments filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) { return ![attachments containsObject:item[@"id"]]; }]];
    return assignments;
}
NSDictionary *SSApplyDateReference(NSDictionary *candidate, NSDate *referenceDate, NSString *commit, NSCalendar *calendar) {
    if (![candidate[@"relative"] boolValue] || ![candidate[@"clock"] length] || [candidate[@"warnings"] count]) return candidate;
    NSString *token = candidate[@"relativeToken"]; if (!token.length || [token containsString:@"末"] || Match(token, @"^(?:本|这|下)(?:周|星期|礼拜)$")) return candidate;
    token = [token stringByReplacingOccurrencesOfString:@"星期" withString:@"周"]; token = [token stringByReplacingOccurrencesOfString:@"礼拜" withString:@"周"];
    NSCalendar *zone = calendar.copy; zone.timeZone = [NSTimeZone timeZoneWithName:candidate[@"timeZone"] ?: calendar.timeZone.name] ?: calendar.timeZone;
    NSDate *suggestion = DDLParseDate([token stringByAppendingFormat:@" %@", candidate[@"clock"]], referenceDate, zone);
    if (!suggestion) return candidate;
    NSMutableDictionary *copy = candidate.mutableCopy; copy[@"suggestedDue"] = suggestion;
    copy[@"dateBasis"] = @{@"commit":commit, @"date":referenceDate}; return copy;
}
