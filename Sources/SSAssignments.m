#import "SSAssignments.h"
#import "DDLImport.h"

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
static NSString *Title(NSString *line, NSString *heading, NSString *previous) {
    NSString *inlineTitle = CleanTitle(line);
    if (inlineTitle.length > 2 && !Match(inlineTitle, @"^(?:请在|最晚|提交时间|时间|日期|before|by)\\s*$")) return inlineTitle;
    NSString *title = CleanTitle(heading);
    if (!title.length) title = CleanTitle(previous);
    return title.length ? title : @"待确认作业";
}
static NSDictionary *Candidate(NSString *title, NSString *repository, NSString *path, NSString *blobSHA, NSUInteger line, NSString *snippet, NSDate *due, BOOL needsDate, BOOL needsTime, NSMutableDictionary *counts) {
    NSString *identity = [NSString stringWithFormat:@"%@|%@|%@", repository.lowercaseString, path, title.lowercaseString];
    NSUInteger ordinal = [counts[identity] unsignedIntegerValue] + 1; counts[identity] = @(ordinal);
    NSMutableDictionary *candidate = [@{@"id":[NSString stringWithFormat:@"%@|%lu", identity, (unsigned long)ordinal], @"repository":repository, @"path":path, @"line":@(line), @"blobSHA":blobSHA, @"title":title, @"needsDate":@(needsDate), @"needsTime":@(needsTime), @"snippet":snippet.length > 1000 ? [snippet substringToIndex:1000] : snippet} mutableCopy];
    if (due) candidate[@"due"] = due;
    return candidate;
}
NSArray<NSDictionary<NSString *, id> *> *SSAssignmentsFromDocument(NSString *text, NSString *repository, NSString *path, NSString *blobSHA, NSDate *now, NSCalendar *calendar) {
    if (!text.length || !repository.length || !path.length) return @[];
    NSArray *lines = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] componentsSeparatedByString:@"\n"];
    NSMutableArray *result = NSMutableArray.array; NSMutableDictionary *counts = NSMutableDictionary.dictionary;
    NSString *heading = @"", *previous = @""; BOOL fence = NO;
    NSString *datePattern = @"(?<![0-9])(?:20[0-9]{2}[-/年]\\s*[0-9]{1,2}[-/月]\\s*[0-9]{1,2}[日号]?|[0-9]{1,2}\\s*月\\s*[0-9]{1,2}[日号]?|[0-9]{1,2}/[0-9]{1,2})(?![0-9])|今天|今晚|明天|后天|下周[一二三四五六日天]?";
    for (NSUInteger index = 0; index < lines.count; index++) {
        NSString *line = [lines[index] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([line hasPrefix:@"```"] || [line hasPrefix:@"~~~"]) { fence = !fence; continue; } if (fence || !line.length) continue;
        if ([line hasPrefix:@"#"]) heading = CleanTitle(line);
        NSString *context = [NSString stringWithFormat:@"%@\n%@\n%@", heading, previous, line];
        BOOL taskCue = Match(context, @"作业|实验|报告|提交|截止|最晚|homework|assignment|deadline|\\bdue\\b|\\bsubmit\\b|\\bhw[0-9]+\\b|\\bddl\\b");
        NSArray *dates = [Regex(datePattern) matchesInString:line options:0 range:NSMakeRange(0, line.length)];
        if (!dates.count && taskCue && Match(line, @"(?:截止|deadline|due|ddl).{0,12}(?:待定|未定|TBA|TBD)")) {
            [result addObject:Candidate(Title(line, heading, previous), repository, path, blobSHA, index + 1, context, nil, YES, YES, counts)];
        }
        for (NSUInteger d = 0; taskCue && d < dates.count; d++) {
            NSTextCheckingResult *dateMatch = dates[d];
            NSString *prefix = [line substringToIndex:dateMatch.range.location];
            if (Match(prefix, @"(?:发布|更新|release|published|updated|created).{0,14}$") && !Match(prefix, @"(?:截止|deadline|due|ddl).{0,14}$")) continue;
            NSUInteger end = d + 1 < dates.count ? [dates[d + 1] range].location : line.length;
            NSString *dateText = [line substringWithRange:NSMakeRange(dateMatch.range.location, end - dateMatch.range.location)];
            dateText = [dateText stringByReplacingOccurrencesOfString:@"：" withString:@":"];
            dateText = Replace(dateText, @"(?<=\\d)T(?=\\d)", @" ");
            BOOL explicitYear = Match(dateText, @"^20\\d{2}[-/年]");
            BOOL explicitTime = Match(dateText, @"(?<!\\d)(?:[01]?\\d|2[0-3]):[0-5]\\d(?!\\d)|(?:凌晨|上午|中午|下午|晚上)?\\s*\\d{1,2}\\s*点");
            NSCalendar *dateCalendar = calendar.copy;
            NSTextCheckingResult *zone = [Regex(@"UTC\\s*([+-])\\s*(\\d{1,2})(?::([0-5]\\d))?") firstMatchInString:dateText options:0 range:NSMakeRange(0, dateText.length)];
            if (zone) {
                NSInteger hours = [[dateText substringWithRange:[zone rangeAtIndex:2]] integerValue];
                NSInteger minutes = [zone rangeAtIndex:3].location != NSNotFound ? [[dateText substringWithRange:[zone rangeAtIndex:3]] integerValue] : 0;
                if (hours <= 14) dateCalendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:([dateText substringWithRange:[zone rangeAtIndex:1]].UTF8String[0] == '-' ? -1 : 1) * (hours * 3600 + minutes * 60)];
            }
            NSDate *due = DDLFieldsFromAnnouncement([@"截止：" stringByAppendingString:dateText], now, dateCalendar)[@"due"];
            NSTextCheckingResult *iso = [Regex(@"^(20\\d{2}-\\d{2}-\\d{2}) ([0-2]\\d:[0-5]\\d)(?::[0-5]\\d)?(Z|[+-][0-2]\\d:[0-5]\\d)") firstMatchInString:dateText options:0 range:NSMakeRange(0, dateText.length)];
            if (iso) {
                NSString *value = [NSString stringWithFormat:@"%@T%@:00%@", [dateText substringWithRange:[iso rangeAtIndex:1]], [dateText substringWithRange:[iso rangeAtIndex:2]], [dateText substringWithRange:[iso rangeAtIndex:3]]];
                due = [NSISO8601DateFormatter.new dateFromString:value];
            }
            if (!due) continue;
            [result addObject:Candidate(Title(line, heading, previous), repository, path, blobSHA, index + 1, context, due, !explicitYear, !explicitTime, counts)];
        }
        if (!dates.count && ![line hasPrefix:@"#"]) previous = line;
    }
    return result;
}
