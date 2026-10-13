#import <Foundation/Foundation.h>
#import "DDLCore.h"

// Shared deterministic parsing; every result retains its original source span.
static inline NSRegularExpression *AMRule(NSString *pattern) { return [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:NULL]; }
static inline BOOL AMHas(NSString *text,NSString *pattern) { return [AMRule(pattern) firstMatchInString:text options:0 range:NSMakeRange(0,text.length)]!=nil; }
static inline NSString *AMReplace(NSString *text,NSString *pattern,NSString *replacement) {return [AMRule(pattern) stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0,text.length) withTemplate:replacement];}
static inline NSString *AMTrim(NSString *text) {return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];}
static inline NSString *AMGroup(NSString *text,NSTextCheckingResult *match,NSUInteger i) {if(!match || i>=match.numberOfRanges)return @"";NSRange r=[match rangeAtIndex:i];return r.location==NSNotFound ? @"":[text substringWithRange:r];}
static inline NSString *AMMonthPattern(void) {return @"(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\\.?";}
static inline NSString *AMRelativePattern(void) {return @"今天|今晚|明天|后天|(?:本|这|下)(?:周|星期|礼拜)(?:[一二三四五六日天末])?|(?:周|星期|礼拜)[一二三四五六日天末]|一周后|两周后|二周后|[0-9]{1,3}天后|[0-9]{1,2}周后|\\b(?:tomorrow|today|tonight|(?:this|next)\\s+(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|weekend|week))\\b";}
static inline NSString *AMDatePattern(void) {NSString *month=AMMonthPattern();return [NSString stringWithFormat:@"(?<![0-9])(?:20[0-9]{2}\\s*[-/年]\\s*[0-9]{1,2}\\s*[-/月]\\s*[0-9]{1,2}\\s*[日号]?|[0-9]{1,2}\\s*月\\s*[0-9]{1,2}\\s*[日号]?|[0-9]{1,2}/[0-9]{1,2}(?:/20[0-9]{2})?)(?![0-9])|\\b(?:%@\\s+[0-9]{1,2}(?:st|nd|rd|th)?(?:,?\\s+20[0-9]{2})?|[0-9]{1,2}(?:st|nd|rd|th)?\\s+%@(?:,?\\s+20[0-9]{2})?)\\b|%@",month,month,AMRelativePattern()];}
static inline NSString *AMClock(NSString *text,BOOL *invalid) {
    NSTextCheckingResult *m=[AMRule(@"(?<![0-9:])([0-9]{1,2})(?::([0-9]{2}))?\\s*([ap])\\.?m\\.?(?![A-Za-z])") firstMatchInString:text options:0 range:NSMakeRange(0,text.length)];
    NSInteger h=0,min=0;
    if(m){h=AMGroup(text,m,1).integerValue;min=AMGroup(text,m,2).integerValue;if(h<1 || h>12 || min>59){*invalid=YES;return nil;}h=h%12+([AMGroup(text,m,3).lowercaseString isEqual:@"p"] ? 12:0);}
    else {m=[AMRule(@"(?<![0-9+-])([0-9]{1,2}):([0-9]{2})(?![0-9])") firstMatchInString:text options:0 range:NSMakeRange(0,text.length)];
        if(m){h=AMGroup(text,m,1).integerValue;min=AMGroup(text,m,2).integerValue;}
        else {m=[AMRule(@"(凌晨|早上|上午|中午|下午|傍晚|晚上|今晚)?\\s*([0-9]{1,2})\\s*[点时](半|[0-9]{1,2}分?)?") firstMatchInString:text options:0 range:NSMakeRange(0,text.length)];if(!m)return nil;NSString *period=AMGroup(text,m,1),*minutes=AMGroup(text,m,3);h=AMGroup(text,m,2).integerValue;min=[minutes isEqual:@"半"] ? 30:minutes.integerValue;if(AMHas(period,@"下午|傍晚|晚上|今晚") && h<12)h+=12;if(AMHas(period,@"凌晨|上午|早上") && h==12)h=0;if([period isEqual:@"中午"] && h<11)h+=12;}}
    if(h>23 || min>59){*invalid=YES;return nil;}return [NSString stringWithFormat:@"%02ld:%02ld",(long)h,(long)min];
}
static inline NSCalendar *AMDateCalendar(NSString *text,NSCalendar *calendar,BOOL *invalid) {
    NSCalendar *result=calendar.copy;
    if(AMHas(text,@"北京时间|中国标准时间"))result.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:8*3600];
    NSTextCheckingResult *m=[AMRule(@"(?:UTC|GMT)\\s*([+-])\\s*(\\d{1,2})(?::([0-9]{2}))?|(?<=[0-9])([+-])(\\d{2}):([0-9]{2})\\b") firstMatchInString:text options:0 range:NSMakeRange(0,text.length)];
    if(m){NSUInteger offset=[m rangeAtIndex:1].location==NSNotFound ? 4:1;NSInteger h=AMGroup(text,m,offset+1).integerValue,min=AMGroup(text,m,offset+2).integerValue;if(h>14 || min>59 || (h==14 && min))*invalid=YES;else result.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:([AMGroup(text,m,offset) isEqual:@"-"] ? -1:1)*(h*3600+min*60)];}
    else if(AMHas(text,@"(?<=[0-9])Z\\b|\\b(?:UTC|GMT)\\b"))result.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0];
    if(AMHas(text,@"\\b(?:CST|IST|BST|PST|PDT|EST|EDT|CET|CEST)\\b"))*invalid=YES;
    return result;
}
static inline NSString *AMRelativeToken(NSString *raw) {
    NSString *token=raw.lowercaseString;
    if([token isEqual:@"tomorrow"])return @"明天";if([token isEqual:@"today"])return @"今天";if([token isEqual:@"tonight"])return @"今晚";
    NSArray *days=@[@"monday",@"tuesday",@"wednesday",@"thursday",@"friday",@"saturday",@"sunday"];
    for(NSUInteger i=0;i<days.count;i++)if([token hasSuffix:days[i]])return [NSString stringWithFormat:@"%@周%@",[token hasPrefix:@"next"] ? @"下":@"本",@[@"一",@"二",@"三",@"四",@"五",@"六",@"日"][i]];
    if([token containsString:@"weekend"])return @"周末";if([token isEqual:@"next week"])return @"下周";if([token isEqual:@"this week"])return @"本周";return raw;
}
static inline NSDictionary *AMDateFields(NSString *token,NSString *text,NSCalendar *calendar) {
    NSMutableDictionary *f=NSMutableDictionary.dictionary;BOOL invalid=NO;NSString *clock=AMClock(text,&invalid);NSCalendar *zone=AMDateCalendar(text,calendar,&invalid);
    f[@"timeZone"]=zone.timeZone.name;f[@"needsDate"]=@YES;f[@"needsTime"]=@(!clock);if(clock)f[@"clock"]=clock;
    if(AMHas(token,AMRelativePattern())){f[@"relative"]=@YES;f[@"relativeToken"]=AMRelativeToken(token);}
    else {
        NSString *compact=AMReplace(token,@"\\s+",@"");NSTextCheckingResult *m=[AMRule(@"^(?:(20[0-9]{2})[-/年])?([0-9]{1,2})[-/月]([0-9]{1,2})[日号]?$") firstMatchInString:compact options:0 range:NSMakeRange(0,compact.length)];
        NSInteger year=0,month=0,day=0;
        if(m){year=AMGroup(compact,m,1).integerValue;month=AMGroup(compact,m,2).integerValue;day=AMGroup(compact,m,3).integerValue;}
        else {NSString *pattern=[NSString stringWithFormat:@"\\b(%@)\\s+([0-9]{1,2})(?:st|nd|rd|th)?(?:,?\\s+(20[0-9]{2}))?|\\b([0-9]{1,2})(?:st|nd|rd|th)?\\s+(%@)(?:,?\\s+(20[0-9]{2}))?",AMMonthPattern(),AMMonthPattern()];m=[AMRule(pattern) firstMatchInString:token options:0 range:NSMakeRange(0,token.length)];if(m){BOOL first=[m rangeAtIndex:1].location!=NSNotFound;NSString *name=AMGroup(token,m,first ? 1:5).lowercaseString;NSArray *names=@[@"jan",@"feb",@"mar",@"apr",@"may",@"jun",@"jul",@"aug",@"sep",@"oct",@"nov",@"dec"];NSUInteger n=[names indexOfObject:[name substringToIndex:MIN((NSUInteger)3,name.length)]];month=n==NSNotFound ? 0:n+1;day=AMGroup(token,m,first ? 2:4).integerValue;year=AMGroup(token,m,first ? 3:6).integerValue;}}
        if(!m || !month || !day)invalid=YES;
        else {NSString *civil=[NSString stringWithFormat:@"%04ld-%02ld-%02ld",(long)(year ?: 2000),(long)month,(long)day];NSDate *date=DDLParseDate([civil stringByAppendingFormat:@" %@",clock ?: @"00:00"],NSDate.date,zone);if(!date)invalid=YES;else if(year){f[@"dateOnly"]=civil;f[@"needsDate"]=@NO;if(clock && !invalid)f[@"due"]=date;
            NSTextCheckingResult *note=[AMRule(@"(?:(?:星期|周|礼拜)([一二三四五六日天])|\\b(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Mon|Tue|Wed|Thu|Fri|Sat|Sun)\\b\\.?)") firstMatchInString:text options:0 range:NSMakeRange(0,text.length)];if(note){NSString *ch=AMGroup(text,note,1),*en=AMGroup(text,note,2).lowercaseString;NSUInteger expected=ch.length ? [@[@"日",@"一",@"二",@"三",@"四",@"五",@"六"] indexOfObject:[ch isEqual:@"天"] ? @"日":ch]:[@[@"sun",@"mon",@"tue",@"wed",@"thu",@"fri",@"sat"] indexOfObject:[en substringToIndex:3]];if([zone component:NSCalendarUnitWeekday fromDate:date]!=(NSInteger)expected+1){f[@"needsDate"]=@YES;[f removeObjectForKey:@"due"];f[@"warnings"]=@[@"日期与星期不一致，请核对原文"];}}
        }else f[@"warnings"]=@[@"截止日期缺少年份，请补全"];}
    }
    if(invalid){[f removeObjectForKey:@"due"];f[@"needsDate"]=@YES;f[@"warnings"]=@[@"日期、时间或时区无效或含糊，请核对并补全"];}
    return f;
}
static inline BOOL AMDeadlineCue(NSString *line) {return AMHas(line,@"截止|最晚|deadline|\\bdue\\b|\\bddl\\b|no later than|submit(?:ted)?\\s+by|hand\\s+in.{0,30}\\bby\\b");}
