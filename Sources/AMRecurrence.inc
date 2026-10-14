// Verified mainland 2026 calendar: 国办发明电〔2025〕7号.
// Official notice: https://www.gov.cn/zhengce/zhengceku/202511/content_7047091.htm
// Verified government republication:
// https://www.haishu.gov.cn/col/col1229825334/art/2025/art_5fc4718a8a495bac1b9a2e2f231be305.html
NSDictionary *DDLChinaDayInfo(NSDate *date,NSCalendar *calendar,NSDictionary *overrides) {
    NSString *key=DDLPlanKey(date,calendar);NSDictionary *custom=overrides[key];
    NSInteger weekday=[calendar component:NSCalendarUnitWeekday fromDate:date];BOOL rest=weekday==1 || weekday==7;
    BOOL known=[calendar component:NSCalendarUnitYear fromDate:date]==2026;NSString *name=rest ? @"周末":@"工作日";NSString *kind=rest ? @"weekend":@"workday";
    if(known){
        for(NSArray *range in @[@[@"2026-01-01",@"2026-01-03",@"元旦"],@[@"2026-02-15",@"2026-02-23",@"春节"],@[@"2026-04-04",@"2026-04-06",@"清明节"],@[@"2026-05-01",@"2026-05-05",@"劳动节"],@[@"2026-06-19",@"2026-06-21",@"端午节"],@[@"2026-09-25",@"2026-09-27",@"中秋节"],@[@"2026-10-01",@"2026-10-07",@"国庆节"]])if([key compare:range[0]]!=NSOrderedAscending && [key compare:range[1]]!=NSOrderedDescending){name=range[2];kind=@"holiday";rest=YES;}
        if([@[@"2026-01-04",@"2026-02-14",@"2026-02-28",@"2026-05-09",@"2026-09-20",@"2026-10-10"] containsObject:key]){name=@"调休补班";kind=@"makeup";rest=NO;}
    }
    NSString *source=known ? @"国务院办公厅 2026 年放假调休安排":@"节假日安排未收录，仅显示星期";
    if([custom isKindOfClass:NSDictionary.class] && [custom[@"rest"] isKindOfClass:NSNumber.class] && [custom[@"name"] isKindOfClass:NSString.class]){rest=[custom[@"rest"] boolValue];name=custom[@"name"];kind=@"override";source=custom[@"reason"] ?: @"本机日期覆盖";known=YES;}
    return @{@"key":key,@"rest":@(rest),@"known":@(known),@"name":name,@"kind":kind,@"source":source};
}
static NSCalendar *RC(NSDictionary *r){NSCalendar *c=[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];c.timeZone=[NSTimeZone timeZoneWithName:r[@"timeZone"] ?: @"Asia/Shanghai"] ?: [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];return c;}
static NSError *RCE(NSString *message){return [NSError errorWithDomain:@"AMRecurrence" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];}
BOOL DDLRecurrenceValid(NSDictionary *r){
    if(![r isKindOfClass:NSDictionary.class] || ![@[@"fixed",@"completion"] containsObject:r[@"mode"]] || ![@[@"day",@"week",@"month",@"year"] containsObject:r[@"unit"]] || ![r[@"anchor"] isKindOfClass:NSDate.class] || ![r[@"interval"] isKindOfClass:NSNumber.class] || [r[@"interval"] integerValue]<1 || [r[@"interval"] integerValue]>1000 || ![@[@"keep",@"skip",@"previous",@"next"] containsObject:r[@"holidayPolicy"]])return NO;
    if(r[@"timeZone"] && (![r[@"timeZone"] isKindOfClass:NSString.class] || ![NSTimeZone timeZoneWithName:r[@"timeZone"]]))return NO;
    if(r[@"until"] && ![r[@"until"] isKindOfClass:NSDate.class])return NO;
    if(r[@"count"] && (![r[@"count"] isKindOfClass:NSNumber.class] || [r[@"count"] integerValue]<1 || [r[@"count"] integerValue]>10000))return NO;
    if(r[@"allowedUnknownYears"]){if(![r[@"allowedUnknownYears"] isKindOfClass:NSArray.class])return NO;for(id year in r[@"allowedUnknownYears"])if(![year isKindOfClass:NSNumber.class] || [year integerValue]<1900 || [year integerValue]>9999)return NO;}
    if(r[@"weekdays"]){if(![r[@"weekdays"] isKindOfClass:NSArray.class] || [r[@"weekdays"] count]>7)return NO;for(id d in r[@"weekdays"])if(![d isKindOfClass:NSNumber.class] || [d integerValue]<1 || [d integerValue]>7)return NO;}
    for(NSString *key in r)if(![@[@"mode",@"unit",@"interval",@"anchor",@"timeZone",@"holidayPolicy",@"until",@"count",@"weekdays",@"allowedUnknownYears",@"allowUnknownCalendar"] containsObject:key])return NO;
    return YES;
}
static NSDate *RCShift(NSDictionary *r,NSDate *anchor,NSInteger index){
    NSCalendar *c=RC(r);NSInteger interval=[r[@"interval"] integerValue];NSString *unit=r[@"unit"];
    if([unit isEqual:@"day"] || [unit isEqual:@"week"])return [c dateByAddingUnit:NSCalendarUnitDay value:index*interval*([unit isEqual:@"week"] ? 7:1) toDate:anchor options:0];
    NSDateComponents *a=[c components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|NSCalendarUnitHour|NSCalendarUnitMinute fromDate:anchor];
    NSDate *start=[c dateFromComponents:({NSDateComponents *b=NSDateComponents.new;b.year=a.year;b.month=a.month;b.day=1;b;})];
    NSDate *target=[c dateByAddingUnit:[unit isEqual:@"month"] ? NSCalendarUnitMonth:NSCalendarUnitYear value:index*interval toDate:start options:0];
    NSDateComponents *b=[c components:NSCalendarUnitYear|NSCalendarUnitMonth fromDate:target];b.day=MIN(a.day,(NSInteger)[c rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitMonth forDate:target].length);b.hour=a.hour;b.minute=a.minute;return [c dateFromComponents:b];
}
static NSDate *RCAdjust(NSDictionary *r,NSDate *date,NSDictionary *overrides,NSError **error){
    NSString *policy=r[@"holidayPolicy"];if([policy isEqual:@"keep"])return date;NSCalendar *c=RC(r);
    for(NSInteger i=0;i<370;i++){
        NSDictionary *info=DDLChinaDayInfo(date,c,overrides);
        if(![info[@"known"] boolValue] && ![r[@"allowUnknownCalendar"] boolValue] && ![r[@"allowedUnknownYears"] containsObject:@([c component:NSCalendarUnitYear fromDate:date])]){if(error)*error=RCE(@"所需年份的节假日安排未收录。请确认仅按周末处理，或保持原日期。");return nil;}
        if(![info[@"rest"] boolValue])return date;if([policy isEqual:@"skip"])return nil;
        date=[c dateByAddingUnit:NSCalendarUnitDay value:[policy isEqual:@"previous"] ? -1:1 toDate:date options:0];
    }
    if(error)*error=RCE(@"无法找到可用工作日，请检查本机日期覆盖。");return nil;
}
NSArray *DDLRecurrenceDates(NSDictionary *r,NSDate *from,NSDate *to,NSDictionary *overrides,NSError **error){
    if(!DDLRecurrenceValid(r) || [to compare:from]==NSOrderedAscending){if(error)*error=RCE(@"重复规则或日期范围无效。");return nil;}
    NSMutableArray *result=NSMutableArray.array;NSDate *anchor=r[@"anchor"];NSCalendar *c=RC(r);BOOL weekdays=[r[@"unit"] isEqual:@"week"] && [r[@"weekdays"] count];NSInteger ordinal=0;
    // Enumerate nominal dates, then apply holiday adjustment. Their identity and
    // count remain nominal even when multiple dates move to the same workday.
    for(NSInteger index=0;index<100000;index++){
        NSDate *nominal=weekdays ? [c dateByAddingUnit:NSCalendarUnitDay value:index toDate:anchor options:0]:RCShift(r,anchor,index);
        if(!nominal){if(error)*error=RCE(@"重复日期超出可计算范围。");return nil;}
        if([nominal timeIntervalSinceDate:to]>14*86400 || ([nominal compare:to]==NSOrderedDescending && ![r[@"holidayPolicy"] isEqual:@"previous"]))break;
        if(weekdays){NSInteger wd=[c component:NSCalendarUnitWeekday fromDate:nominal];NSDate *aMonday=[c dateByAddingUnit:NSCalendarUnitDay value:-(([c component:NSCalendarUnitWeekday fromDate:anchor]+5)%7) toDate:[c startOfDayForDate:anchor] options:0];NSInteger weeks=[[c components:NSCalendarUnitDay fromDate:aMonday toDate:[c startOfDayForDate:nominal] options:0] day]/7;if(weeks%[r[@"interval"] integerValue] || ![r[@"weekdays"] containsObject:@(wd)])continue;}
        if(r[@"until"] && [nominal compare:r[@"until"]]==NSOrderedDescending)break;
        if(r[@"count"] && ordinal>=[r[@"count"] integerValue])break;NSInteger occurrence=ordinal++;
        if([nominal timeIntervalSinceDate:from]<-370*86400)continue;
        NSError *failure=nil;NSDate *date=RCAdjust(r,nominal,overrides,&failure);if(failure){if(error)*error=failure;return nil;}if(!date)continue;
        if([date compare:from]==NSOrderedAscending || [date compare:to]==NSOrderedDescending)continue;
        NSString *key=[NSString stringWithFormat:@"%@:%ld",DDLPlanKey(nominal,c),(long)occurrence];[result addObject:@{@"key":key,@"due":date,@"nominal":nominal,@"index":@(occurrence)}];
        if(result.count>=10000){if(error)*error=RCE(@"此范围将生成超过一万项，请缩小范围。");return nil;}
    }
    return result;
}
NSArray *DDLMaterializeRecurringTasks(NSArray *tasks,NSArray *series,NSDate *now,NSDate *end,NSDictionary *overrides,NSError **error){
    NSMutableArray *out=[tasks mutableCopy];NSMutableSet *seen=NSMutableSet.set;
    for(NSDictionary *task in tasks)if(task[@"seriesID"] && task[@"occurrenceKey"])[seen addObject:[NSString stringWithFormat:@"%@|%@",task[@"seriesID"],task[@"occurrenceKey"]]];
    for(NSDictionary *s in series){if([s[@"stopped"] boolValue])continue;NSDictionary *rule=s[@"rule"],*template=s[@"template"];if(!DDLRecurrenceValid(rule) || ![s[@"id"] isKindOfClass:NSString.class] || ![template[@"title"] isKindOfClass:NSString.class]){if(error)*error=RCE(@"周期系列记录无效，原任务保留。");return nil;}for(NSString *key in s[@"skippedKeys"] ?: @[])[seen addObject:[NSString stringWithFormat:@"%@|%@",s[@"id"],key]];
        NSArray *dates=nil;
        if([rule[@"mode"] isEqual:@"fixed"]){dates=DDLRecurrenceDates(rule,now,end,overrides,error);if(!dates)return nil;}
        else {
            NSMutableArray *next=NSMutableArray.array;
            BOOL hasOccurrence=NO;for(NSDictionary *task in tasks)if([task[@"seriesID"] isEqual:s[@"id"]]){hasOccurrence=YES;if(![task[@"completed"] boolValue] || ![task[@"completedAt"] isKindOfClass:NSDate.class])continue;
                NSString *key=[@"after:" stringByAppendingString:task[@"id"]];
                NSDate *completed=task[@"completedAt"];NSDateComponents *time=[RC(rule) components:NSCalendarUnitHour|NSCalendarUnitMinute fromDate:rule[@"anchor"]];NSDate *base=[RC(rule) dateBySettingHour:time.hour minute:time.minute second:0 ofDate:completed options:0];
                for(NSInteger step=1;step<=370;step++){NSInteger index=[task[@"occurrenceIndex"] integerValue]+step;if(rule[@"count"] && index>=[rule[@"count"] integerValue])break;NSDate *nominal=RCShift(rule,base,step);if(rule[@"until"] && [nominal compare:rule[@"until"]]==NSOrderedDescending)break;NSError *failure=nil;NSDate *date=RCAdjust(rule,nominal,overrides,&failure);if(failure){if(error)*error=failure;return nil;}if(date){[next addObject:@{@"key":key,@"due":date,@"nominal":nominal,@"index":@(index)}];break;}if(![rule[@"holidayPolicy"] isEqual:@"skip"])break;}

            }
            if(!hasOccurrence){NSDate *date=RCAdjust(rule,rule[@"anchor"],overrides,error);if(!date && error && *error)return nil;if(date)[next addObject:@{@"key":@"initial",@"due":date,@"nominal":rule[@"anchor"],@"index":@0}];}dates=next;
        }
        for(NSDictionary *date in dates){NSString *identity=[NSString stringWithFormat:@"%@|%@",s[@"id"],date[@"key"]];if([seen containsObject:identity])continue;[seen addObject:identity];NSMutableDictionary *task=template.mutableCopy;task[@"id"]=NSUUID.UUID.UUIDString;task[@"seriesID"]=s[@"id"];task[@"occurrenceKey"]=date[@"key"];task[@"occurrenceIndex"]=date[@"index"];task[@"nominalDue"]=date[@"nominal"];task[@"due"]=date[@"due"];task[@"completed"]=@NO;task[@"archived"]=@NO;task[@"deleted"]=@NO;[task removeObjectForKey:@"completedAt"];[task removeObjectForKey:@"plannedDate"];[task removeObjectForKey:@"deletedAt"];if(task[@"subtasks"]){NSMutableArray *children=NSMutableArray.array;for(NSDictionary *sub in task[@"subtasks"]){NSMutableDictionary *child=sub.mutableCopy;child[@"id"]=NSUUID.UUID.UUIDString;child[@"completed"]=@NO;[child removeObjectForKey:@"plannedDate"];[children addObject:child];}task[@"subtasks"]=children;}[out addObject:task];}
    }
    return out;
}
