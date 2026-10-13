#import "DDLImport.h"
#import "DDLCore.h"
#import "AMDocumentRules.h"
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

static NSDate *ImportDueDate(NSString *text, NSDate *now, NSCalendar *calendar) {
    NSString *normalized=AMReplace(AMReplace(text,@"[：]",@":"),@"[*_`]",@"");
    NSArray *matches=[AMRule(AMDatePattern()) matchesInString:normalized options:0 range:NSMakeRange(0,normalized.length)];
    NSMutableArray *explicit=NSMutableArray.array,*fallback=NSMutableArray.array;BOOL unresolved=NO;
    for(NSUInteger i=0;i<matches.count;i++){NSTextCheckingResult *match=matches[i];NSRange row=[normalized lineRangeForRange:match.range];NSUInteger end=NSMaxRange(row);if(i+1<matches.count)end=MIN(end,[matches[i+1] range].location);
        NSString *line=[normalized substringWithRange:row],*tail=[normalized substringWithRange:NSMakeRange(match.range.location,end-match.range.location)];
        if(AMHas(line,@"^(?:发布|更新|published|updated|created|[^\\n]*老师[ :：])") && !AMDeadlineCue(line))continue;
        if(!AMHas(tail,@"[0-9](?:[:点时]|\\s*[ap]\\.?m)") && NSMaxRange(row)<normalized.length){NSRange next=[normalized lineRangeForRange:NSMakeRange(NSMaxRange(row),0)];NSString *clock=[normalized substringWithRange:next];if(AMHas(clock,@"^\\s*(?:时间[:：]\\s*)?[0-9]{1,2}(?:[:点时]|\\s*[ap]\\.?m)"))tail=[tail stringByAppendingString:clock];}
        NSDictionary *fields=AMDateFields([normalized substringWithRange:match.range],tail,calendar);NSDate *date=fields[@"due"];
        if([fields[@"relative"] boolValue] && fields[@"clock"] && ![fields[@"warnings"] count]){NSCalendar *zone=calendar.copy;zone.timeZone=[NSTimeZone timeZoneWithName:fields[@"timeZone"]];NSString *token=fields[@"relativeToken"];if(!AMHas(token,@"末|^(?:本|这|下)周$"))date=DDLParseDate([token stringByAppendingFormat:@" %@",fields[@"clock"]],now,zone);}
        if(!date && AMDeadlineCue(line))unresolved=YES;
        if(date)[(AMDeadlineCue(line) || AMHas(line,@"提交|完成|submit|before|by") ? explicit:fallback) addObject:date];
    }
    NSArray *dates=explicit.count ? explicit:fallback;NSSet *unique=[NSSet setWithArray:dates];return !unresolved && unique.count==1 ? dates.firstObject:nil;
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

NSDictionary *DDLOCRResultFromImage(NSImage *image, NSError **error) {
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
    NSMutableArray *lines=NSMutableArray.array,*segments=NSMutableArray.array,*uncertain=NSMutableArray.array;CGFloat lastY=-1,lastHeight=0;
    for(VNRecognizedTextObservation *observation in sorted){NSArray<VNRecognizedText *> *candidates=[observation topCandidates:2];VNRecognizedText *top=candidates.firstObject;NSString *value=top.string;if(!value.length)continue;CGRect box=observation.boundingBox;BOOL sameRow=lastY>=0 && fabs(lastY-box.origin.y)<MAX(.012,MIN(lastHeight,box.size.height)*.55);BOOL gap=lastY>=0 && lastY-box.origin.y>MAX(.04,lastHeight*1.9);
        if(sameRow && lines.count)lines[lines.count-1]=[lines.lastObject stringByAppendingFormat:@" %@",value];else {if(gap)[lines addObject:@""];[lines addObject:value];}
        BOOL doubt=top.confidence<.8 && AMHas(value,@"[0-9]|截止|due|deadline");if(candidates.count>1 && top.confidence<.95 && ![candidates[1].string isEqual:value] && AMHas(value,@"[0-9]"))doubt=YES;
        NSDictionary *segment=@{@"text":value,@"confidence":@(top.confidence),@"line":@(lines.count),@"box":@[@(box.origin.x),@(box.origin.y),@(box.size.width),@(box.size.height)],@"uncertain":@(doubt)};[segments addObject:segment];if(doubt)[uncertain addObject:segment];lastY=box.origin.y;lastHeight=box.size.height;
    }
    return @{@"text":[lines componentsJoinedByString:@"\n"],@"segments":segments,@"uncertain":uncertain};
}
NSString *DDLOCRTextFromImage(NSImage *image,NSError **error){return DDLOCRResultFromImage(image,error)[@"text"];}
