// Local calendar dates deliberately contain no time zone or midnight timestamp.
NSString *DDLPlanKey(NSDate *date,NSCalendar *calendar) {
    NSDateComponents *c=[calendar components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:date];
    return [NSString stringWithFormat:@"%04ld-%02ld-%02ld",(long)c.year,(long)c.month,(long)c.day];
}
NSDate *DDLPlanDate(NSString *key,NSCalendar *calendar) {
    if(![key isKindOfClass:NSString.class])return nil;
    NSArray *parts=Match(key,@"^(\\d{4})-(\\d{2})-(\\d{2})$");if(!parts)return nil;
    return CivilDate(calendar,[parts[0] integerValue],[parts[1] integerValue],[parts[2] integerValue],12,0);
}
BOOL DDLPlanningValid(NSDictionary *task) {
    NSCalendar *calendar=[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];calendar.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0];
    if(task[@"plannedDate"] && !DDLPlanDate(task[@"plannedDate"],calendar))return NO;
    for(NSString *key in @[@"seriesID",@"occurrenceKey"])if(task[key] && ![task[key] isKindOfClass:NSString.class])return NO;
    for(NSString *key in @[@"completedAt",@"nominalDue"])if(task[key] && ![task[key] isKindOfClass:NSDate.class])return NO;
    if(task[@"completionEvidence"]){id evidence=task[@"completionEvidence"];if(![evidence isKindOfClass:NSDictionary.class] || [evidence count]!=5 || ![evidence[@"verifiedAt"] isKindOfClass:NSDate.class])return NO;for(NSString *key in @[@"recordID",@"repository",@"branch",@"commit"])if(![evidence[key] isKindOfClass:NSString.class] || ![evidence[key] length])return NO;
        if(![[NSUUID alloc] initWithUUIDString:evidence[@"recordID"]] || [evidence[@"commit"] rangeOfString:@"^[a-f0-9]{40,64}$" options:NSRegularExpressionSearch].location==NSNotFound)return NO;}
    if(task[@"occurrenceOverrides"]){if(![task[@"occurrenceOverrides"] isKindOfClass:NSArray.class])return NO;for(id key in task[@"occurrenceOverrides"])if(![key isKindOfClass:NSString.class] || ![@[@"title",@"subject",@"courseID",@"courseRepository",@"notes",@"priority",@"reminderOffsets",@"reminder",@"plannedDate",@"subtasks",@"due",@"recurrence"] containsObject:key])return NO;}
    id children=task[@"subtasks"];if(!children)return YES;if(![children isKindOfClass:NSArray.class] || [children count]>500)return NO;
    NSMutableSet *seen=NSMutableSet.set;
    for(id sub in children){if(![sub isKindOfClass:NSDictionary.class] || ![sub[@"id"] isKindOfClass:NSString.class] || ![sub[@"id"] length] || [seen containsObject:sub[@"id"]] || ![sub[@"title"] isKindOfClass:NSString.class] || ![[sub[@"title"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length] || ![sub[@"completed"] isKindOfClass:NSNumber.class])return NO;if(sub[@"plannedDate"] && !DDLPlanDate(sub[@"plannedDate"],calendar))return NO;[seen addObject:sub[@"id"]];}return YES;
}
NSDictionary *DDLTaskCompletion(NSDictionary *task,BOOL complete) {
    NSMutableDictionary *result=task.mutableCopy;result[@"completed"]=@(complete);
    if(!complete)[result removeObjectForKey:@"completionEvidence"];
    if(complete && ![task[@"completed"] boolValue])result[@"completedAt"]=NSDate.date;
    if(complete && task[@"subtasks"]){NSMutableArray *children=NSMutableArray.array;for(NSDictionary *sub in task[@"subtasks"]){NSMutableDictionary *copy=sub.mutableCopy;copy[@"completed"]=@YES;[children addObject:copy];}result[@"subtasks"]=children;}
    return result;
}
NSArray<NSDictionary *> *DDLWeekSections(NSArray *tasks,NSDate *now,NSInteger offset,NSCalendar *calendar,NSString *query) {
    NSDate *today=[calendar startOfDayForDate:now];NSInteger weekday=([calendar component:NSCalendarUnitWeekday fromDate:today]+5)%7;
    NSDate *monday=[calendar dateByAddingUnit:NSCalendarUnitDay value:-weekday+offset*7 toDate:today options:0];
    NSMutableArray *sections=NSMutableArray.array;NSMutableDictionary *byDate=NSMutableDictionary.dictionary;
    for(NSInteger i=0;i<7;i++){NSDate *date=[calendar dateByAddingUnit:NSCalendarUnitDay value:i toDate:monday options:0];NSString *key=DDLPlanKey(date,calendar);NSMutableDictionary *section=[@{@"id":key,@"label":[NSString stringWithFormat:@"%@ · %ld/%ld",@[@"周一",@"周二",@"周三",@"周四",@"周五",@"周六",@"周日"][i],(long)[calendar component:NSCalendarUnitMonth fromDate:date],(long)[calendar component:NSCalendarUnitDay fromDate:date]],@"items":NSMutableArray.array,@"date":date,@"dayInfo":DDLChinaDayInfo(date,calendar,@{})} mutableCopy];[sections addObject:section];byDate[key]=section;}
    NSMutableDictionary *overdue=[@{@"id":@"overdue",@"label":@"待重新安排",@"items":NSMutableArray.array} mutableCopy],*unplanned=[@{@"id":@"unplanned",@"label":@"尚未安排",@"items":NSMutableArray.array} mutableCopy];
    NSString *todayKey=DDLPlanKey(today,calendar);query=[query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    for(NSDictionary *task in tasks){if([task[@"completed"] boolValue] || [task[@"archived"] boolValue] || [task[@"deleted"] boolValue])continue;
        NSMutableArray *items=[NSMutableArray arrayWithObject:@{@"id":task[@"id"],@"taskID":task[@"id"],@"subtaskID":@"",@"title":task[@"title"],@"parentTitle":@"",@"plannedDate":task[@"plannedDate"] ?: @"",@"due":task[@"due"],@"subject":task[@"subject"] ?: @""}];
        for(NSDictionary *sub in task[@"subtasks"])if(![sub[@"completed"] boolValue])[items addObject:@{@"id":[NSString stringWithFormat:@"%lu:%@%@",(unsigned long)[task[@"id"] length],task[@"id"],sub[@"id"]],@"taskID":task[@"id"],@"subtaskID":sub[@"id"],@"title":sub[@"title"],@"parentTitle":task[@"title"],@"plannedDate":sub[@"plannedDate"] ?: @"",@"due":task[@"due"],@"subject":task[@"subject"] ?: @""}];
        for(NSDictionary *item in items){NSString *search=[NSString stringWithFormat:@"%@ %@ %@ %@",item[@"title"],task[@"title"],task[@"subject"] ?: @"",task[@"notes"] ?: @""];if(query.length && ![search localizedStandardContainsString:query])continue;NSString *key=item[@"plannedDate"];NSMutableDictionary *section=!key.length ? unplanned:([key compare:todayKey]==NSOrderedAscending ? overdue:byDate[key]);if(section)[section[@"items"] addObject:item];}
    }
    [sections addObject:overdue];[sections addObject:unplanned];for(NSDictionary *section in sections)[section[@"items"] sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){NSComparisonResult comparison=[a[@"due"] compare:b[@"due"]];return comparison==NSOrderedSame ? [a[@"title"] localizedStandardCompare:b[@"title"]]:comparison;}];return sections;
}
