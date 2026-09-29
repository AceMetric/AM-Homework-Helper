#import "DDLImport.h"
#import "DDLCore.h"
#import <Vision/Vision.h>
#include <math.h>

static NSTextCheckingResult *ImportMatch(NSString *text, NSString *pattern) {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:NULL];
    return [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
}

static NSString *ImportGroup(NSString *text, NSTextCheckingResult *match, NSUInteger index) {
    if (!match || index >= match.numberOfRanges) return @"";
    NSRange range = [match rangeAtIndex:index];
    return range.location == NSNotFound ? @"" : [text substringWithRange:range];
}

static NSString *ImportTimeAfterDate(NSString *line) {
    NSTextCheckingResult *clock = ImportMatch(line, @"(?<![0-9])([01]?[0-9]|2[0-3]):([0-5][0-9])(?![0-9])");
    if (clock) return [NSString stringWithFormat:@"%02ld:%02ld", (long)[ImportGroup(line, clock, 1) integerValue], (long)[ImportGroup(line, clock, 2) integerValue]];
    NSTextCheckingResult *chinese = ImportMatch(line, @"(凌晨|早上|上午|中午|下午|傍晚|晚上|今晚)?\\s*([0-9]{1,2})\\s*点(半|[0-9]{1,2}分?)?");
    if (chinese) {
        NSString *period = ImportGroup(line, chinese, 1);
        NSInteger hour = [ImportGroup(line, chinese, 2) integerValue];
        NSString *minuteText = ImportGroup(line, chinese, 3);
        NSInteger minute = [minuteText isEqualToString:@"半"] ? 30 : minuteText.integerValue;
        if (([period isEqualToString:@"下午"] || [period isEqualToString:@"傍晚"] || [period isEqualToString:@"晚上"] || [period isEqualToString:@"今晚"]) && hour < 12) hour += 12;
        if ([period isEqualToString:@"凌晨"] && hour == 12) hour = 0;
        if (hour < 24 && minute < 60) return [NSString stringWithFormat:@"%02ld:%02ld", (long)hour, (long)minute];
    }
    return @"23:59";
}

static NSDate *ImportDueDate(NSString *text, NSDate *now, NSCalendar *calendar) {
    NSString *normalized = [[[text stringByReplacingOccurrencesOfString:@"：" withString:@":"] stringByReplacingOccurrencesOfString:@"／" withString:@"/"] stringByReplacingOccurrencesOfString:@"－" withString:@"-"];
    NSArray<NSString *> *patterns = @[
        @"(?<![0-9])(20[0-9]{2})\\s*年\\s*([0-9]{1,2})\\s*月\\s*([0-9]{1,2})\\s*[日号]?",
        @"(?<![0-9])(20[0-9]{2})[-/]([0-9]{1,2})[-/]([0-9]{1,2})(?![0-9])",
        @"(?<![0-9])([0-9]{1,2})\\s*月\\s*([0-9]{1,2})\\s*[日号]?",
        @"(?<![0-9])([0-9]{1,2})/([0-9]{1,2})(?![0-9])",
        @"今天|今晚|明天|后天|一周后|两周后|二周后|下周[一二三四五六日天]?|(?:本周|这周|周|星期)[一二三四五六日天]|[0-9]{1,3}天后|[0-9]{1,2}周后"
    ];
    NSDate *bestDate = nil;
    NSInteger bestScore = NSIntegerMin;
    NSUInteger bestPosition = 0;
    for (NSUInteger kind = 0; kind < patterns.count; kind++) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:patterns[kind] options:0 error:NULL];
        for (NSTextCheckingResult *match in [regex matchesInString:normalized options:0 range:NSMakeRange(0, normalized.length)]) {
            NSRange lineEnd = [normalized rangeOfString:@"\n" options:0 range:NSMakeRange(NSMaxRange(match.range), normalized.length - NSMaxRange(match.range))];
            NSUInteger end = lineEnd.location == NSNotFound ? normalized.length : lineEnd.location;
            NSString *afterDate = [normalized substringWithRange:NSMakeRange(NSMaxRange(match.range), MIN((NSUInteger)36, end - NSMaxRange(match.range)))];
            NSString *time = ImportTimeAfterDate(afterDate);
            NSString *candidate;
            if (kind <= 3) {
                NSInteger year = kind <= 1 ? [ImportGroup(normalized, match, 1) integerValue] : [calendar component:NSCalendarUnitYear fromDate:now];
                NSUInteger offset = kind <= 1 ? 2 : 1;
                NSInteger month = [ImportGroup(normalized, match, offset) integerValue];
                NSInteger day = [ImportGroup(normalized, match, offset + 1) integerValue];
                candidate = [NSString stringWithFormat:@"%04ld-%02ld-%02ld %@", (long)year, (long)month, (long)day, time];
            } else candidate = [NSString stringWithFormat:@"%@ %@", ImportGroup(normalized, match, 0), time];
            NSDate *due = DDLParseDate(candidate, now, calendar);
            if (!due) continue;
            NSInteger score = kind <= 1 ? 5 : 0;
            NSRegularExpression *markers = [NSRegularExpression regularExpressionWithPattern:@"截止|最晚|到期|deadline|ddl|提交|交作业|交报告|之前|前" options:NSRegularExpressionCaseInsensitive error:NULL];
            for (NSTextCheckingResult *marker in [markers matchesInString:normalized options:0 range:NSMakeRange(0, normalized.length)]) {
                NSInteger distance = llabs((long long)marker.range.location - (long long)match.range.location);
                NSInteger relevance = 100 - MIN(distance, 100);
                if (ImportMatch(ImportGroup(normalized, marker, 0), @"截止|最晚|到期|deadline|ddl")) relevance += 15;
                score = MAX(score, relevance);
            }
            if (!bestDate || score > bestScore || (score == bestScore && match.range.location > bestPosition)) {
                bestDate = due; bestScore = score; bestPosition = match.range.location;
            }
        }
    }
    return bestDate;
}

NSDictionary<NSString *, id> *DDLFieldsFromAnnouncement(NSString *text, NSDate *now, NSCalendar *calendar) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) return @{};
    NSMutableDictionary<NSString *, id> *fields = [NSMutableDictionary dictionary];
    NSDate *due = ImportDueDate(trimmed, now, calendar);
    if (due) fields[@"due"] = due;
    NSTextCheckingResult *subjectMatch = ImportMatch(trimmed, @"【([^】\\n]{1,24})】");
    NSString *subject = ImportGroup(trimmed, subjectMatch, 1);
    if (subject.length) fields[@"subject"] = subject;
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *raw in [trimmed componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (line.length) [lines addObject:line];
    }
    NSString *title = @"";
    for (NSString *line in lines) {
        if (ImportMatch(line, @"^\\s*(截止|ddl|deadline|时间)\\s*[:：]") || ImportMatch(line, @"^\\s*[0-9]{1,2}:[0-9]{2}\\s*$")) continue;
        NSTextCheckingResult *action = ImportMatch(line, @"(?:请|务必|记得|需要|请大家|大家)?(?:在.{0,45}?[前之]?)?(?:提交|完成|上传|交上?)(.{2,70})");
        if (action) title = ImportGroup(line, action, 1);
        else if (ImportMatch(line, @"作业|实验|报告|论文|测验|考试|项目|任务")) title = line;
        if (title.length) break;
    }
    if (!title.length) for (NSString *line in lines) {
        if (!ImportMatch(line, @"截止|deadline|ddl|^[0-9年月日/:：\\s-]+$")) { title = line; break; }
    }
    if (subject.length) title = [title stringByReplacingOccurrencesOfString:subjectMatch ? [trimmed substringWithRange:subjectMatch.range] : @"" withString:@""];
    title = [[title stringByReplacingOccurrencesOfString:@"^[：:，,。\\s]+|[：:，,。\\s]+$" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, title.length)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (title.length > 80) title = [title substringToIndex:80];
    if (title.length) fields[@"title"] = title;
    fields[@"notes"] = trimmed.length > 5000 ? [trimmed substringToIndex:5000] : trimmed;
    return fields;
}

NSDate *DDLPersonalDueDate(NSDate *announcedDue, NSInteger leadDays, NSCalendar *calendar) {
    if (!announcedDue || leadDays < 0 || leadDays > 365) return nil;
    return [calendar dateByAddingUnit:NSCalendarUnitDay value:-leadDays toDate:announcedDue options:0];
}

NSString *DDLOCRTextFromImage(NSImage *image, NSError **error) {
    NSData *tiff = image.TIFFRepresentation;
    NSBitmapImageRep *bitmap = tiff ? [[NSBitmapImageRep alloc] initWithData:tiff] : nil;
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (!png) {
        if (error) *error = [NSError errorWithDomain:@"DDLImport" code:1 userInfo:@{NSLocalizedDescriptionKey:@"无法读取截图图像"}];
        return nil;
    }
    VNRecognizeTextRequest *request = [VNRecognizeTextRequest new];
    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.recognitionLanguages = @[@"zh-Hans", @"en-US"];
    request.usesLanguageCorrection = YES;
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithData:png options:@{}];
    if (![handler performRequests:@[request] error:error]) return nil;
    NSArray<VNRecognizedTextObservation *> *sorted = [request.results sortedArrayUsingComparator:^NSComparisonResult(VNRecognizedTextObservation *a, VNRecognizedTextObservation *b) {
        CGFloat delta = a.boundingBox.origin.y - b.boundingBox.origin.y;
        if (fabs(delta) > 0.025) return delta > 0 ? NSOrderedAscending : NSOrderedDescending;
        return a.boundingBox.origin.x < b.boundingBox.origin.x ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (VNRecognizedTextObservation *observation in sorted) {
        NSString *value = [observation topCandidates:1].firstObject.string;
        if (value.length) [lines addObject:value];
    }
    return [lines componentsJoinedByString:@"\n"];
}
