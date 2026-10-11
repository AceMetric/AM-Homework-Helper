NSString *AMQuickDateText(NSDate *date,NSString *zone){NSDateFormatter *formatter=NSDateFormatter.new;formatter.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];formatter.calendar=[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];formatter.timeZone=[NSTimeZone timeZoneWithName:zone] ?: NSTimeZone.localTimeZone;formatter.dateFormat=@"yyyy-MM-dd HH:mm";return [formatter stringFromDate:date];}
static NSString *AMQuickVersion(NSString *text,NSDate *reference,NSString *zone){return RHash([NSString stringWithFormat:@"%@\n%@\n%@",text,[NSISO8601DateFormatter.new stringFromDate:reference],zone]);}
NSDictionary *AMQuickMaterial(NSString *text,NSDate *reference,NSString *zone) {
    return @{@"id":NSUUID.UUID.UUIDString,@"version":AMQuickVersion(text,reference,zone),@"text":text,@"referenceDate":reference,@"timeZone":zone};
}
NSArray *AMQuickParse(NSString *text,NSString *sourceID,NSDate *reference,NSCalendar *calendar) {
    if(![text isKindOfClass:NSString.class] || text.length>100000 || !RTrim(text).length)return @[];
    NSMutableArray *blocks=NSMutableArray.array;NSMutableString *block=NSMutableString.string;
    NSString *normalized=[text stringByReplacingOccurrencesOfString:@"；" withString:@"\n\n"];
    for(NSString *line in [normalized componentsSeparatedByString:@"\n"]){BOOL heading=RMatch(line,@"^\\s*(?:#{1,6}\\s+|[0-9一二三四五六七八九十]+[、.)）]\\s*)");if(heading && RTrim(block).length){[blocks addObject:block.copy];[block setString:@""];}if(!RTrim(line).length && RMatch(block,@"截止|提交|完成|作业|报告|实验|论文")){[blocks addObject:block.copy];[block setString:@""];}else [block appendFormat:@"%@\n",line];}
    if(RTrim(block).length)[blocks addObject:block.copy];if(!blocks.count)[blocks addObject:text];
    NSMutableArray *entries=NSMutableArray.array;NSUInteger index=0;
    for(NSString *part in blocks){
        NSDictionary *fields=DDLFieldsFromAnnouncement(part,reference,calendar);if(!fields[@"title"] && !fields[@"due"])continue;
        NSArray *rules=SSAssignmentsFromDocument([@"# 作业\n" stringByAppendingString:part],@"local/material",@"material.md",RHash(text),reference,calendar);NSDictionary *rule=rules.firstObject;
        NSMutableDictionary *entry=[@{@"id":[NSString stringWithFormat:@"%@:%lu",sourceID,(unsigned long)index++],@"sourceID":sourceID,@"referenceDate":reference,@"version":RHash(text),@"title":fields[@"title"] ?: @"",@"subject":fields[@"subject"] ?: @"其他",@"notes":@"",@"evidence":RTrim(part),@"deadlineEvidence":rule[@"dateText"] ?: @"",@"timeZone":rule[@"timeZone"] ?: calendar.timeZone.name,@"dateText":@"",@"reminderOffsets":DDLDefaultReminderOffsets(),@"selected":@YES,@"edited":@NO} mutableCopy];
        NSString *summary=RTrim(part);NSRegularExpression *deadline=[NSRegularExpression regularExpressionWithPattern:@"(?m)^.*(?:截止|deadline|ddl).*$" options:NSRegularExpressionCaseInsensitive error:NULL];summary=RTrim([deadline stringByReplacingMatchesInString:summary options:0 range:NSMakeRange(0,summary.length) withTemplate:@""]);entry[@"summary"]=summary.length>240 ? [[summary substringToIndex:240] stringByAppendingString:@"…"]:summary;entry[@"submissionRequirements"]=@"";
        if(summary.length && ![summary isEqual:entry[@"title"]])entry[@"notes"]=[@"作业内容\n" stringByAppendingString:entry[@"summary"]];
        NSDate *due=rule[@"due"] ?: fields[@"due"];NSArray *warnings=rule[@"warnings"] ?: @[];
        if([rule[@"relative"] boolValue]){NSDictionary *suggestion=SSApplyDateReference(rule,reference,@"local-message",calendar);due=suggestion[@"suggestedDue"];entry[@"hint"]=@"相对日期按消息／录入日期推算，请核对。";}
        else if(warnings.count && ![warnings.firstObject containsString:@"未说明"]){due=nil;entry[@"hint"]=[warnings componentsJoinedByString:@"；"];}
        NSMutableSet *deadlines=NSMutableSet.set;for(NSDictionary *candidate in rules)if(candidate[@"due"] || candidate[@"dateOnly"] || [candidate[@"relative"] boolValue])[deadlines addObject:candidate[@"dateText"] ?: @""];
        if(deadlines.count>1){due=nil;entry[@"hint"]=@"发现多个截止日期，请核对这项作业对应的日期和时间。";}
        if(due)entry[@"dateText"]=AMQuickDateText(due,entry[@"timeZone"]);
        else {entry[@"dateText"]=rule[@"dateOnly"] ?: @"";entry[@"hint"]=entry[@"hint"] ?: (rule[@"dateOnly"] ? @"已识别日期，请补全截止时间。":@"请补全明确的截止日期与时间。");}
        [entries addObject:entry];
    }return entries;
}
NSDictionary *AMQuickTask(NSDictionary *entry,NSError **error) {
    if(![entry isKindOfClass:NSDictionary.class] || ![entry[@"dateText"] isKindOfClass:NSString.class] || ![entry[@"title"] isKindOfClass:NSString.class] || ![entry[@"id"] isKindOfClass:NSString.class] || ![entry[@"sourceID"] isKindOfClass:NSString.class] || ![entry[@"version"] isKindOfClass:NSString.class]){if(error)*error=RError(@"录入条目格式无效。");return nil;}
    for(NSString *key in @[@"notes",@"subject",@"timeZone",@"evidence",@"deadlineEvidence",@"summary",@"submissionRequirements",@"courseRepository"])if(entry[key] && ![entry[key] isKindOfClass:NSString.class]){if(error)*error=RError(@"作业字段格式无效。");return nil;}
    if(entry[@"referenceDate"] && ![entry[@"referenceDate"] isKindOfClass:NSDate.class]){if(error)*error=RError(@"消息日期格式无效。");return nil;}
    NSString *date=entry[@"dateText"],*title=entry[@"title"];NSCalendar *cal=[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];cal.timeZone=[NSTimeZone timeZoneWithName:entry[@"timeZone"]] ?: NSTimeZone.localTimeZone;
    NSDate *due=RMatch(date,@"^\\d{4}-\\d{1,2}-\\d{1,2} [0-9]{1,2}:[0-9]{2}$") ? DDLParseDate(date,NSDate.date,cal):nil;
    if(!RTrim(title).length || !due){if(error)*error=RError(!RTrim(title).length ? @"请填写作业名称。":@"请补全有效的截止日期和时间，例如 2026-10-20 18:00。");return nil;}
    NSMutableDictionary *task=[@{@"id":NSUUID.UUID.UUIDString,@"title":RTrim(title),@"subject":entry[@"subject"] ?: @"其他",@"due":due,@"notes":entry[@"notes"] ?: @"",@"reminderOffsets":entry[@"reminderOffsets"] ?: DDLDefaultReminderOffsets(),@"entryID":entry[@"id"],@"entrySourceID":entry[@"sourceID"],@"entryVersion":entry[@"version"],@"entryEvidence":entry[@"evidence"] ?: @"",@"entryDeadlineEvidence":entry[@"deadlineEvidence"] ?: @"",@"sourceSummary":entry[@"summary"] ?: @"",@"sourceRequirements":entry[@"submissionRequirements"] ?: @"",@"notesOrigin":[entry[@"edited"] boolValue] ? @"user":@"generated",@"notesUserEdited":entry[@"edited"] ?: @NO} mutableCopy];if(entry[@"referenceDate"])task[@"entryReferenceDate"]=entry[@"referenceDate"];task[@"entryTimeZone"]=cal.timeZone.name;if([entry[@"courseRepository"] length])task[@"courseRepository"]=entry[@"courseRepository"];return DDLNormalizeTasks(@[task]).firstObject;
}
NSDictionary *AMQuickValidateResult(NSDictionary *result,NSDictionary *material,NSDictionary *batch,NSError **error) {
    if(![result isKindOfClass:NSDictionary.class] || ![material isKindOfClass:NSDictionary.class] || ![batch isKindOfClass:NSDictionary.class] || ![material[@"text"] isKindOfClass:NSString.class] || ![material[@"referenceDate"] isKindOfClass:NSDate.class] || ![material[@"timeZone"] isKindOfClass:NSString.class] || ![material[@"version"] isEqual:AMQuickVersion(material[@"text"],material[@"referenceDate"],material[@"timeZone"])]){if(error)*error=RError(@"材料不完整，请重新准备识别。" );return nil;}
    if(![result[@"format"] isEqual:@"am-local-results-v1"] || ![result[@"batchID"] isEqual:batch[@"id"]] || ![batch[@"version"] isEqual:material[@"version"]] || ![result[@"documents"] isKindOfClass:NSArray.class] || [result[@"documents"] count]!=1){if(error)*error=RError(@"批次或材料版本不匹配，请重新识别。");return nil;}
    NSDictionary *doc=[result[@"documents"] firstObject];if(![doc isKindOfClass:NSDictionary.class] || ![doc[@"sourceID"] isEqual:material[@"id"]] || ![doc[@"version"] isEqual:material[@"version"]] || ![doc[@"activities"] isKindOfClass:NSArray.class] || [doc[@"activities"] count]>100){if(error)*error=RError(@"本机材料来源无效。");return nil;}
    NSMutableArray *entries=NSMutableArray.array,*issues=NSMutableArray.array;NSMutableSet *seen=NSMutableSet.set;NSCalendar *cal=[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];cal.timeZone=[NSTimeZone timeZoneWithName:material[@"timeZone"]] ?: NSTimeZone.localTimeZone;
    for(id value in doc[@"activities"]){if(![value isKindOfClass:NSDictionary.class]){[issues addObject:@"无效条目"];continue;}NSDictionary *activity=value;
        NSString *title=activity[@"title"],*evidence=activity[@"evidence"],*deadline=activity[@"deadlineEvidence"];
        if(![title isKindOfClass:NSString.class] || !RTrim(title).length || ![evidence isKindOfClass:NSString.class] || !evidence.length || [material[@"text"] rangeOfString:evidence].location==NSNotFound || ![deadline isKindOfClass:NSString.class] || title.length>300 || evidence.length>100000 || deadline.length>4000 || (deadline.length && ([material[@"text"] rangeOfString:deadline].location==NSNotFound || [evidence rangeOfString:deadline].location==NSNotFound))){[issues addObject:@"名称或原文证据无效"];continue;}
        if(![activity[@"kind"] isEqual:@"assignment"]){[issues addObject:@"非作业条目未加入，仍可手动录入。"];continue;}
        NSString *key=RHash(evidence);if([seen containsObject:key])continue;[seen addObject:key];
        NSArray *parsed=AMQuickParse([NSString stringWithFormat:@"%@\n%@",title,deadline],material[@"id"],material[@"referenceDate"],cal);NSMutableDictionary *entry=[parsed.firstObject mutableCopy];if(!entry){[issues addObject:@"条目无法解析"];continue;}
        entry[@"id"]=[material[@"id"] stringByAppendingFormat:@":skill:%@",key];entry[@"version"]=material[@"version"];entry[@"title"]=title;entry[@"evidence"]=evidence;entry[@"deadlineEvidence"]=deadline;entry[@"summary"]=[activity[@"summary"] isKindOfClass:NSString.class] ? activity[@"summary"]:@"";entry[@"submissionRequirements"]=[activity[@"submissionRequirements"] isKindOfClass:NSString.class] ? activity[@"submissionRequirements"]:@"";entry[@"notes"]=SSSuggestedNotes(entry);entry[@"recognizer"]=@"skill-local";[entries addObject:entry];
    }return @{@"entries":entries,@"issues":issues};
}
