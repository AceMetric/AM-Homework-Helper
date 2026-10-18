#import "AMPrompts.h"
#import "AMOperation.h"
#import "SSRecognition.h"
#import "SSAssignments.h"
#import "SSLocalData.h"
#import "SSSecurity.h"
#import "DDLCore.h"
#import "DDLImport.h"
#import <CommonCrypto/CommonDigest.h>
#include <math.h>

static NSError *RError(NSString *message) { return [NSError errorWithDomain:@"AMRecognition" code:1 userInfo:@{NSLocalizedDescriptionKey:message}]; }
static BOOL RMatch(NSString *text, NSString *pattern) { NSRegularExpression *r = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:NULL]; return [r firstMatchInString:text ?: @"" options:0 range:NSMakeRange(0, text.length)] != nil; }
static NSString *RTrim(NSString *text) { return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; }
static NSString *RHash(NSString *text) { NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding]; unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes, (CC_LONG)data.length, digest); NSMutableString *value = NSMutableString.string; for (NSUInteger i=0;i<sizeof(digest);i++) [value appendFormat:@"%02x",digest[i]]; return value; }
BOOL SSValidateCourseTemplate(NSDictionary *template, NSError **error) {
    if (![template isKindOfClass:NSDictionary.class]) { if(error)*error=RError(@"课程模板须是JSON对象。");return NO; }
    for (NSString *key in template) {
        id pattern=template[key];
        if (![@[@"titlePattern",@"contentPattern",@"deadlinePattern"] containsObject:key] || ![pattern isKindOfClass:NSString.class] || [pattern length]>256 || ![NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionAnchorsMatchLines error:NULL]) { if(error)*error=RError(@"模板仅支持 titlePattern、contentPattern、deadlinePattern 三项有效正则表达式（每项最多256字）。");return NO; }
    }
    return YES;
}
static NSString *TemplateField(NSString *text, NSString *pattern) {
    if (!pattern.length) return nil;
    NSRegularExpression *regex=[NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionAnchorsMatchLines error:NULL];
    // Patterns run on bounded lines, not an unbounded document/backtracking subject.
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (line.length>2000) continue;__block NSTextCheckingResult *match=nil; NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:0.05];
        [regex enumerateMatchesInString:line options:NSMatchingReportProgress range:NSMakeRange(0,line.length) usingBlock:^(NSTextCheckingResult *value, NSMatchingFlags flags, BOOL *stop){ if (value) {match=value;*stop=YES;} else if (limit.timeIntervalSinceNow<0) *stop=YES; }];
        if (match) {NSRange range=[match rangeAtIndex:match.numberOfRanges>1 ? 1 : 0];if(range.location!=NSNotFound)return RTrim([line substringWithRange:range]);}
    }
    return nil;
}
NSDictionary *SSRecognitionSettings(void) {
    NSMutableDictionary *settings = [@{@"mode":@"rules", @"endpoint":@"http://localhost:11434", @"model":@"", @"automaticImport":@YES, @"dailyLimit":@20, @"localAutomatic":@YES} mutableCopy];
    id saved = SSReadPlist(@"recognition-settings.plist"); if ([saved isKindOfClass:NSDictionary.class]) [settings addEntriesFromDictionary:saved];
    return settings;
}
BOOL SSValidateRecognitionSettings(NSDictionary *settings, NSError **error) {
    NSString *mode = settings[@"mode"];
    if (![@[@"rules",@"local",@"cloud"] containsObject:mode]) { if(error)*error=RError(@"请选择有效的识别方式。"); return NO; }
    if ([mode isEqual:@"rules"]) return YES;
    NSURL *url = [NSURL URLWithString:settings[@"endpoint"] ?: @""];
    BOOL local = [mode isEqual:@"local"];
    BOOL loopback = [@[@"localhost",@"127.0.0.1",@"::1",@"[::1]"] containsObject:url.host.lowercaseString];
    if (!url.host.length || url.user || url.password || url.query || url.fragment || !(local ? loopback && [@[@"http",@"https"] containsObject:url.scheme] : [url.scheme isEqual:@"https"])) {
        if(error)*error=RError(local ? @"本地模型地址须指向这台 Mac 的 localhost，不可包含凭据或查询参数。" : @"云端地址须使用 HTTPS，且不可包含凭据或查询参数。"); return NO;
    }
    if (![settings[@"model"] isKindOfClass:NSString.class] || ![RTrim(settings[@"model"]) length]) { if(error)*error=RError(@"请填写已安装的本地模型名，或服务提供方的模型名。"); return NO; }
    return YES;
}
NSArray *SSAttachLinkedDocuments(NSArray *records, NSArray *documents) {
    NSMutableArray *result=NSMutableArray.array;
    NSRegularExpression *links=[NSRegularExpression regularExpressionWithPattern:@"\\[[^\\]\\n]+\\]\\(([^)\\n]+)\\)" options:0 error:NULL];
    for(NSDictionary *record in records){NSMutableDictionary *copy=record.mutableCopy;NSMutableArray *attachments=[record[@"attachments"] mutableCopy] ?: NSMutableArray.array;NSMutableSet *seen=NSMutableSet.set;for(NSDictionary *old in attachments)if(old[@"path"])[seen addObject:old[@"path"]];
        NSString *text=record[@"snippet"] ?: @"";
        for(NSTextCheckingResult *match in [links matchesInString:text options:0 range:NSMakeRange(0,text.length)]){
            NSString *target=RTrim([text substringWithRange:[match rangeAtIndex:1]]);target=[[target componentsSeparatedByString:@"#"] firstObject];target=[target stringByRemovingPercentEncoding] ?: target;
            if(!target.length || [target hasPrefix:@"/"] || [target containsString:@":"] || [target containsString:@"?"] || [target hasPrefix:@"<"])continue;
            NSString *joined=[[[@"/" stringByAppendingString:record[@"path"]] stringByDeletingLastPathComponent] stringByAppendingPathComponent:target];
            NSString *normalized=joined.stringByStandardizingPath;NSString *path=[normalized hasPrefix:@"/"] ? [normalized substringFromIndex:1] : normalized;
            if([path hasPrefix:@"../"] || [path isEqual:record[@"path"]] || [seen containsObject:path])continue;
            for(NSDictionary *source in documents)if([source[@"repository"] isEqual:record[@"repository"]] && [source[@"path"] isEqual:path]){[attachments addObject:@{@"repository":source[@"repository"],@"path":path,@"blobSHA":source[@"blobSHA"],@"snippet":source[@"text"]}];[seen addObject:path];break;}
        }
        if(attachments.count)copy[@"attachments"]=attachments;[result addObject:copy];
    }
    return result;
}
NSDictionary *SSCourseRecognitionSettings(NSDictionary *settings, NSDictionary *course) {
    NSMutableDictionary *copy=settings.mutableCopy;
    if ([copy[@"mode"] isEqual:@"cloud"] && (![copy[@"cloudCourses"] isKindOfClass:NSArray.class] || ![copy[@"cloudCourses"] containsObject:course[@"fork"]])) copy[@"mode"]=@"rules";
    if([copy[@"mode"] isEqual:@"cloud"] && ![copy[@"manualCloud"] boolValue])copy[@"mode"]=@"rules";
    if([copy[@"mode"] isEqual:@"local"] && [copy[@"localAutomatic"] isEqual:@NO] && ![copy[@"manualLocal"] boolValue])copy[@"mode"]=@"rules";
    if ([course[@"recognitionTemplate"] isKindOfClass:NSDictionary.class]) copy[@"courseTemplate"]=course[@"recognitionTemplate"];
    return copy;
}
NSArray *SSValidatedSkillResults(id result, NSArray *documents, NSArray *references, NSError **error) {
    if (![result isKindOfClass:NSDictionary.class] || ![result[@"format"] isEqual:@"am-course-results-v1"] || ![result[@"documents"] isKindOfClass:NSArray.class] || [result[@"documents"] count]>1000) {if(error)*error=RError(@"Skill 结果格式无效，未修改任务。");return nil;}
    NSMutableArray *records=NSMutableArray.array;
    for(id document in result[@"documents"]){
        if (![document isKindOfClass:NSDictionary.class] || ![document[@"activities"] isKindOfClass:NSArray.class]) {if(error)*error=RError(@"Skill 文档格式无效。");return nil;}
        NSDictionary *live=nil;
        for(NSDictionary *source in documents)if([source[@"repository"] isEqual:document[@"repository"]] && [source[@"path"] isEqual:document[@"path"]] && [source[@"blobSHA"] isEqual:document[@"blobSHA"]]){live=source;break;}
        if(!live){if(error)*error=RError(@"老师原文已变化或结果属于其他课程，请重新导出识别。");return nil;}
        NSCalendar *calendar=NSCalendar.currentCalendar.copy;calendar.timeZone=[NSTimeZone timeZoneWithName:live[@"timeZone"]] ?: NSTimeZone.localTimeZone;
        NSError *validation=nil;NSArray *found=SSValidatedModelResults(document[@"activities"],live[@"text"],live[@"repository"],live[@"path"],live[@"blobSHA"],calendar,&validation);
        if(validation || found.count!=[document[@"activities"] count]){if(error)*error=validation ?: RError(@"Skill 结果有无效字段或原文引用，未导入。");return nil;}
        for(NSDictionary *record in found){NSMutableDictionary *copy=record.mutableCopy;copy[@"recognizer"]=@"skill-v1";copy[@"modelOnly"]=@YES;
            for(NSDictionary *reference in references)if([reference[@"id"] isEqual:record[@"id"]] && [reference[@"blobSHA"] isEqual:record[@"blobSHA"]])for(NSString *field in @[@"dateBasis",@"suggestedDue"])if(reference[field])copy[field]=reference[field];
            [records addObject:copy];}
    }
    return records;
}
NSDictionary *SSEnrichDiscovery(NSDictionary *record) {
    NSMutableDictionary *copy = record.mutableCopy;
    copy[@"sourceTitle"] = record[@"sourceTitle"] ?: record[@"title"] ?: @"作业";
    copy[@"suggestedTitle"] = record[@"suggestedTitle"] ?: record[@"title"] ?: @"作业";
    NSMutableOrderedSet *summary = NSMutableOrderedSet.orderedSet, *requirements = NSMutableOrderedSet.orderedSet, *fallback=NSMutableOrderedSet.orderedSet;
    BOOL fenced = NO;
    for (NSString *raw in [record[@"snippet"] componentsSeparatedByString:@"\n"]) {
        NSString *line = RTrim(raw);
        if ([line hasPrefix:@"```"] || [line hasPrefix:@"~~~"]) { fenced = !fenced; continue; }
        if (fenced || !line.length || [line hasPrefix:@"#"] || RMatch(line,@"截止|deadline|\\bdue\\b|^[-=_]{3,}$")) continue;
        if (![line isEqual:copy[@"sourceTitle"]] && !RMatch(line,@"^\\s*[-*+]?\\s*\\[.*\\]\\(.*\\)\\s*$")) [fallback addObject:line];
        if (RMatch(line,@"提交|命名|格式|附件|文件|submit|filename|format|attachment")) [requirements addObject:line];
        if (RMatch(line,@"完成|解答|实现|分析|回答|证明|阅读|观看|练习|solve|implement|answer|read|write|deliver|design|build|analyse|analyze|compare|evaluate|demonstrate|must|should|需要|不得|至少|必须")) [summary addObject:line];
    }
    if (!copy[@"summary"]) {NSArray *content=summary.count ? summary.array : fallback.array;copy[@"summary"] = [content componentsJoinedByString:@"\n"];}
    if (!copy[@"submissionRequirements"]) copy[@"submissionRequirements"] = [requirements.array componentsJoinedByString:@"\n"];
    if (!copy[@"recognizer"]) copy[@"recognizer"] = @"rules-v8";
    return copy;
}
static BOOL SameSource(NSDictionary *task, NSDictionary *record) {
    if ([task[@"sourceID"] isEqual:record[@"id"]]) return YES;
    for (NSString *alias in record[@"legacyIDs"] ?: @[]) if ([task[@"sourceID"] isEqual:alias]) return YES;
    return NO;
}
BOOL SSCanAutomaticallyImport(NSDictionary *record, NSArray *tasks, NSDate *now) {
    if([record[@"requiresReview"] boolValue])return NO;
    if (![record[@"kind"] isEqual:@"assignment"] || [record[@"relative"] boolValue] || [record[@"modelOnly"] boolValue] || [record[@"needsDate"] boolValue] || [record[@"needsTime"] boolValue] || [record[@"warnings"] count] || ![record[@"dateText"] length] || ![record[@"due"] isKindOfClass:NSDate.class] || [record[@"due"] compare:now] != NSOrderedDescending) return NO;
    // A user type override or uncertain identity requires a fresh review.
    if ([record[@"automaticDeferred"] boolValue] || [record[@"identityUncertain"] boolValue] || [record[@"kindReason"] isEqual:@"你已手动确认类型"]) return NO;
    for (NSDictionary *task in tasks) if (SameSource(task,record) || ([task[@"sourceRepository"] isEqual:record[@"repository"]] && [task[@"sourcePath"] isEqual:record[@"path"]])) return NO;
    return YES;
}
NSString *SSSuggestedNotes(NSDictionary *record) {
    NSString *summary=[record[@"sourceSummary"] isKindOfClass:NSString.class] ? record[@"sourceSummary"]:record[@"summary"];
    NSString *requirements=[record[@"sourceRequirements"] isKindOfClass:NSString.class] ? record[@"sourceRequirements"]:record[@"submissionRequirements"];
    if(![summary isKindOfClass:NSString.class])summary=@"";if(![requirements isKindOfClass:NSString.class])requirements=@"";
    NSMutableArray *parts=NSMutableArray.array;
    if([summary isKindOfClass:NSString.class] && RTrim(summary).length)[parts addObject:[@"作业内容\n" stringByAppendingString:RTrim(summary)]];
    if([requirements isKindOfClass:NSString.class] && RTrim(requirements).length && ![RTrim(requirements) isEqual:RTrim(summary ?: @"")])[parts addObject:[@"提交要求\n" stringByAppendingString:RTrim(requirements)]];
    return [parts componentsJoinedByString:@"\n\n"];
}
NSDictionary *SSReviewedTask(NSDictionary *record, NSDictionary *draft, NSDictionary *existing, NSError **error) {
    NSString *title = RTrim(draft[@"title"] ?: record[@"suggestedTitle"] ?: record[@"title"] ?: @"");
    // due is the only active deadline. Legacy draft fields remain readable for
    // compatibility; existing deadlines and user notes are never migrated blindly.
    NSDate *teacher = draft[@"assignmentDue"] ?: draft[@"personalDue"] ?: draft[@"teacherDue"] ?: existing[@"due"] ?: record[@"due"];
    NSString *problem=nil;
    if (![record[@"kind"] ?: @"assignment" isEqual:@"assignment"])problem=@"请先确认材料类型为作业。";
    else if(!title.length)problem=@"请填写作业名称。";
    else if(![teacher isKindOfClass:NSDate.class])problem=@"请补全截止日期和时间。";
    else if(([record[@"needsDate"] boolValue] || [record[@"needsTime"] boolValue] || [record[@"warnings"] count]) && ![draft[@"dateConfirmed"] boolValue])problem=@"请核对并确认完整截止日期和时间。";
    if(problem){if(error)*error=RError(problem);return nil;}
    NSMutableDictionary *task = existing ? existing.mutableCopy : [@{@"id":NSUUID.UUID.UUIDString,@"completed":@NO,@"archived":@NO,@"reminderOffsets":DDLDefaultReminderOffsets()} mutableCopy];
    task[@"title"] = title;
    task[@"subject"] = draft[@"subject"] ?: existing[@"subject"] ?: [record[@"repository"] lastPathComponent] ?: @"课程";
    NSString *generated=SSSuggestedNotes(record);task[@"notes"] = draft[@"notes"] ?: existing[@"notes"] ?: generated;
    if(!existing){task[@"notesOrigin"]=[task[@"notes"] isEqual:generated] ? @"generated":@"user";task[@"notesUserEdited"]=@(![task[@"notes"] isEqual:generated]);}
    else if(draft[@"notes"] && ![draft[@"notes"] isEqual:existing[@"notes"]]){task[@"notesOrigin"]=@"user";task[@"notesUserEdited"]=@YES;}
    if (draft[@"reminderOffsets"]) task[@"reminderOffsets"] = draft[@"reminderOffsets"];
    task[@"due"] = teacher;
    if([draft[@"priority"] isKindOfClass:NSNumber.class])task[@"priority"]=@(MAX(0,MIN(2,[draft[@"priority"] integerValue])));
    // Original deadline evidence stays in sourceObservedDue. Old split-deadline
    // metadata may remain on old tasks, but never drives new scheduling.
    task[@"sourceID"] = record[@"id"]; task[@"sourceBlobSHA"] = record[@"blobSHA"] ?: @"";
    task[@"sourceRepository"] = record[@"repository"] ?: @""; task[@"sourcePath"] = record[@"path"] ?: @""; task[@"sourceLine"] = record[@"line"] ?: @1;
    task[@"sourceObservedDue"] = record[@"observedDue"] ?: record[@"due"] ?: teacher;
    task[@"sourceSuggestedTitle"] = record[@"suggestedTitle"] ?: record[@"title"] ?: @"";
    task[@"sourceSummary"] = record[@"summary"] ?: @"";if(record[@"fieldEvidence"])task[@"sourceFieldEvidence"]=record[@"fieldEvidence"];
    task[@"sourceRequirements"] = record[@"submissionRequirements"] ?: @"";
    if (record[@"dateBasis"]) task[@"sourceDateBasis"] = record[@"dateBasis"];
    [task removeObjectForKey:@"_reviewCandidate"]; [task removeObjectForKey:@"_existing"];
    return DDLNormalizeTasks(@[task]).firstObject;
}
static NSString *RCanonicalText(NSString *text){return [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];}
static BOOL RLineNumber(id value){return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value)!=CFBooleanGetTypeID() && isfinite([value doubleValue]) && [value doubleValue]==floor([value doubleValue]);}
static NSDictionary *RIssue(NSUInteger index,NSString *field,NSString *code,NSString *reason){return @{@"index":@(index),@"field":field,@"code":code,@"reason":reason};}
static NSError *RValidationError(NSDictionary *report){return [NSError errorWithDomain:@"AMRecognition" code:2 userInfo:@{NSLocalizedDescriptionKey:[report[@"issues"] firstObject][@"reason"] ?: @"结果未通过核验",@"validationIssues":report[@"issues"] ?: @[]}];}
id SSRecognitionJSONObject(NSString *content,BOOL local){
    if(![content isKindOfClass:NSString.class] || content.length>1024*1024)return nil;
    content=RTrim(content);
    if([content hasPrefix:@"```"] && [content hasSuffix:@"```"]){NSRange newline=[content rangeOfString:@"\n"];if(newline.location!=NSNotFound)content=RTrim([content substringWithRange:NSMakeRange(NSMaxRange(newline),content.length-NSMaxRange(newline)-3)]);}
    id object=[NSJSONSerialization JSONObjectWithData:[content dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];if(object || !local)return object;
    // Local Qwen-compatible adapters may leak a thinking envelope. Only remove
    // explicit outer protocol markers; never hunt for JSON inside arbitrary prose.
    if([content hasPrefix:@"<think>"]){NSRange close=[content rangeOfString:@"</think>"];if(close.location==NSNotFound)return nil;content=RTrim([content substringFromIndex:NSMaxRange(close)]);}
    if([content hasSuffix:@"</think>"])content=RTrim([content substringToIndex:content.length-8]);
    return [NSJSONSerialization JSONObjectWithData:[content dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
}
NSDictionary *SSModelValidationReport(id results, NSString *text, NSString *repository, NSString *path, NSString *blob, NSCalendar *calendar) {
    text=RCanonicalText(text);
    NSMutableArray *issues=NSMutableArray.array,*acceptedIndices=NSMutableArray.array;
    if (![results isKindOfClass:NSArray.class] || [results count] > 32) return @{ @"records":@[],@"issues":@[RIssue(0,@"activities",@"format",@"活动列表格式无效")],@"complete":@NO,@"acceptedIndices":@[] };
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    NSArray *rules = SSDiscoveriesFromDocument(text,repository,path,blob,NSDate.date,calendar);
    NSArray *blocks=SSActivityBlocks(text,path,NO);
    NSMutableArray *validated = NSMutableArray.array;
    NSUInteger index=0;
    for (id raw in results) {
        NSUInteger itemIndex=index++;NSUInteger before=issues.count;
        void (^reject)(NSString *,NSString *,NSString *)=^(NSString *field,NSString *code,NSString *reason){[issues addObject:RIssue(itemIndex,field,code,reason)];};
        if (![raw isKindOfClass:NSDictionary.class]) {reject(@"activity",@"format",@"条目格式无效");continue;}
        NSMutableDictionary *item=[raw mutableCopy];
        for(NSString *field in @[@"evidence",@"summaryEvidence",@"requirementsEvidence",@"deadlineEvidence"])if([item[field] isKindOfClass:NSString.class])item[field]=RCanonicalText(item[field]);
        NSString *kind=item[@"kind"], *title=item[@"title"], *quote=item[@"evidence"];
        if (![kind isKindOfClass:NSString.class] || ![@[@"assignment",@"exam",@"classroom",@"unknown"] containsObject:kind] || ![title isKindOfClass:NSString.class] || !title.length || title.length > 160 || ![quote isKindOfClass:NSString.class] || !quote.length) {reject(@"activity",@"format",@"名称、类型或原文证据格式无效");continue;}
        if ([text rangeOfString:quote options:NSLiteralSearch].location == NSNotFound) {reject(@"evidence",@"source-mismatch",@"引用未匹配到原文");continue;}
        for (NSString *field in @[@"summary",@"submissionRequirements",@"deadlineEvidence",@"summaryEvidence",@"requirementsEvidence"]) if (item[field] && ![item[field] isKindOfClass:NSString.class]) {reject(field,@"format",@"字段须为文本");item[field]=@"";}
        if ([item[@"summary"] length] > 4000 || [item[@"submissionRequirements"] length] > 4000) {reject(@"summary",@"format",@"概括或提交要求过长");continue;}
        if (SSContainsSecret([NSJSONSerialization dataWithJSONObject:item options:0 error:NULL])) {reject(@"activity",@"sensitive",@"条目含敏感内容");continue;}
        if(item[@"deadlineShared"] && CFGetTypeID((__bridge CFTypeRef)item[@"deadlineShared"])!=CFBooleanGetTypeID()){reject(@"deadlineShared",@"format",@"共享截止标记须为布尔值");item[@"deadlineShared"]=@NO;}
        NSString *deadline=item[@"deadlineEvidence"] ?: @"";
        if (deadline.length && [text rangeOfString:deadline options:NSLiteralSearch].location == NSNotFound) {reject(@"deadlineEvidence",@"source-mismatch",@"截止依据未匹配到原文");continue;}
        NSRange location=[text rangeOfString:quote options:NSLiteralSearch];NSUInteger line=[[text substringToIndex:location.location] componentsSeparatedByString:@"\n"].count;
        if(item[@"startLine"] || item[@"endLine"]){
            if(!RLineNumber(item[@"startLine"]) || !RLineNumber(item[@"endLine"])) {reject(@"startLine",@"line-range",@"行号须为原文整数行号");continue;}NSUInteger start=[item[@"startLine"] unsignedIntegerValue],end=[item[@"endLine"] unsignedIntegerValue];if(start<1 || end<start || end>lines.count){reject(@"startLine",@"line-range",@"行号超出原文范围");continue;}
            NSString *span=[[lines subarrayWithRange:NSMakeRange(start-1,end-start+1)] componentsJoinedByString:@"\n"];NSRange exact=[span rangeOfString:quote options:NSLiteralSearch];if(exact.location==NSNotFound){reject(@"evidence",@"line-mismatch",@"引用不在指定行范围内");continue;}NSRange after=NSMakeRange(NSMaxRange(exact),span.length-NSMaxRange(exact));if([span rangeOfString:quote options:NSLiteralSearch range:after].location!=NSNotFound){reject(@"evidence",@"ambiguous",@"指定范围内引用重复");continue;}line=start+[[span substringToIndex:exact.location] componentsSeparatedByString:@"\n"].count-1;
        }else {NSRange remaining=NSMakeRange(NSMaxRange(location),text.length-NSMaxRange(location));if([text rangeOfString:quote options:NSLiteralSearch range:remaining].location!=NSNotFound){reject(@"evidence",@"ambiguous",@"引用重复，需要准确行号");continue;}}
        NSUInteger evidenceEnd=line+[quote componentsSeparatedByString:@"\n"].count-1;NSDictionary *block=nil;
        for(NSDictionary *candidate in blocks)if(line>=[candidate[@"line"] unsignedIntegerValue] && evidenceEnd<=[candidate[@"endLine"] unsignedIntegerValue]){block=candidate;break;}
        if(!block){reject(@"evidence",@"activity-boundary",@"引用跨越独立活动，请分别提取");continue;}
        BOOL deadlineInActivity=deadline.length && block && [block[@"raw"] rangeOfString:deadline options:NSLiteralSearch].location!=NSNotFound;
        BOOL sharedPreamble=block && blocks.count && ![blocks[0][@"activityBoundary"] boolValue] && [blocks[0][@"endLine"] unsignedIntegerValue]<[block[@"line"] unsignedIntegerValue] && [blocks[0][@"raw"] rangeOfString:deadline options:NSLiteralSearch].location!=NSNotFound;
        BOOL shared=sharedPreamble && deadline.length && [item[@"deadlineShared"] respondsToSelector:@selector(boolValue)] && [item[@"deadlineShared"] boolValue] && RMatch(deadline,@"全部|所有|统一|下列.*(?:作业|任务)|\\ball\\b|\\bboth\\b");
        NSMutableArray *sameActivity=NSMutableArray.array;
        for(NSDictionary *rule in rules)if(block && [rule[@"sectionLine"] unsignedIntegerValue]==[block[@"line"] unsignedIntegerValue] && [rule[@"endLine"] unsignedIntegerValue]==[block[@"endLine"] unsignedIntegerValue])[sameActivity addObject:rule];
        NSDictionary *matched=sameActivity.count==1 ? sameActivity.firstObject:nil;
        if(sameActivity.count>1){BOOL examGroup=YES;for(NSDictionary *rule in sameActivity)if(![rule[@"kind"] isEqual:@"exam"])examGroup=NO;if(examGroup)matched=sameActivity.firstObject;}
        if(!matched && sameActivity.count>1){NSMutableArray *withinEvidence=NSMutableArray.array;for(NSDictionary *rule in sameActivity)if([rule[@"line"] unsignedIntegerValue]>=line && [rule[@"line"] unsignedIntegerValue]<=evidenceEnd)[withinEvidence addObject:rule];if(withinEvidence.count==1)matched=withinEvidence.firstObject;}
        // Bind by activity ownership before considering any deadline. Adjacent
        // activities with identical dates must never claim each other's IDs.
        NSMutableDictionary *record = matched ? matched.mutableCopy : [@{@"id":[NSString stringWithFormat:@"%@|%@|model|%@",repository.lowercaseString,path,RHash(quote)],@"repository":repository,@"path":path,@"line":@(line),@"blobSHA":blob,@"title":title,@"sourceTitle":title,@"snippet":block[@"raw"] ?: text,@"needsDate":@YES,@"needsTime":@YES,@"modelOnly":@YES} mutableCopy];
        // Original exam/classroom context always wins over a model's assignment label.
        if ([matched[@"kind"] isEqual:@"exam"] || [matched[@"kind"] isEqual:@"classroom"]) kind=matched[@"kind"];
        if (RMatch(path,@"(?:^|[/_-])(?:exam|quiz)|考试|测验")) kind=@"exam";
        record[@"kind"]=kind; record[@"kindReason"]=matched[@"kindReason"] ?: @"模型提取，需确认类型";
        if (!matched || ![matched[@"kind"] isEqual:kind]) record[@"modelOnly"]=@YES;
        record[@"suggestedTitle"]=title; record[@"summary"]=item[@"summary"] ?: @""; record[@"submissionRequirements"]=item[@"submissionRequirements"] ?: @""; record[@"evidence"]=quote; record[@"recognizer"]=AMCoursePromptVersion();
        if(deadline.length && !deadlineInActivity && !shared){reject(@"deadlineEvidence",@"activity-boundary",@"截止依据属于其他活动");NSMutableArray *warnings=[record[@"warnings"] mutableCopy] ?: NSMutableArray.array;[warnings addObject:@"模型给出的截止依据不属于本活动，未用于填写日期。请核对原文。"];record[@"warnings"]=warnings;record[@"requiresReview"]=@YES;record[@"modelOnly"]=@YES;}
        record[@"fieldEvidence"]=@{@"activityStartLine":block[@"line"] ?: @(line),@"activityEndLine":block[@"endLine"] ?: @(evidenceEnd),@"titleEvidence":quote,@"deadlineEvidence":(deadlineInActivity || shared) ? deadline:@""};
        NSMutableDictionary *fieldEvidence=[record[@"fieldEvidence"] mutableCopy];
        for(NSArray *pair in @[@[@"summary",@"summaryEvidence"],@[@"submissionRequirements",@"requirementsEvidence"]])if([record[pair[0]] length]){
            NSString *support=item[pair[1]];BOOL validSupport=support.length && block && [block[@"raw"] rangeOfString:support options:NSLiteralSearch].location!=NSNotFound;
            if(validSupport)fieldEvidence[pair[1]]=support;
            else {reject(pair[1],@"field-evidence",@"字段缺少本活动的原文依据");record[pair[0]]=@"";record[@"modelOnly"]=@YES;record[@"requiresReview"]=@YES;NSMutableArray *warnings=[record[@"contentWarnings"] mutableCopy] ?: NSMutableArray.array;[warnings addObject:@"模型概括或提交要求缺少本活动的字段依据，请对照原文审核。"];record[@"contentWarnings"]=warnings;}
        }
        record[@"fieldEvidence"]=fieldEvidence;
        if ((!matched || !matched[@"due"]) && deadline.length && (deadlineInActivity || shared)) {
            record[@"line"]=@([[text substringToIndex:[text rangeOfString:deadline options:NSLiteralSearch].location] componentsSeparatedByString:@"\n"].count);
            // Parse the exact original sentence, not a model-supplied timestamp.
            NSArray *dates=SSAssignmentsFromDocument([@"# 作业\n" stringByAppendingString:deadline],repository,path,blob,NSDate.date,calendar);
            if (dates.count==1) for (NSString *field in @[@"due",@"dateOnly",@"clock",@"needsDate",@"needsTime",@"relative",@"relativeToken",@"warnings",@"timeZone",@"dateText",@"deadlineText"]) if (dates[0][field]) record[field]=dates[0][field];
        }
        if(issues.count>before){record[@"requiresReview"]=@YES;record[@"modelOnly"]=@YES;}else [acceptedIndices addObject:@(itemIndex)];
        if ([lines count]) [validated addObject:SSEnrichDiscovery(record)];
    }
    return @{@"records":validated,@"issues":issues,@"complete":@(issues.count==0),@"acceptedIndices":acceptedIndices};
}
NSArray *SSValidatedModelResults(id results, NSString *text, NSString *repository, NSString *path, NSString *blob, NSCalendar *calendar, NSError **error) {
    NSDictionary *report=SSModelValidationReport(results,text,repository,path,blob,calendar);
    if(![report[@"complete"] boolValue] && error)*error=RValidationError(report);
    return report[@"records"];
}
@implementation SSRecognitionClient
- (NSString *)cloudKeyForEndpoint:(NSString *)endpoint { NSDictionary *secret=SSReadSecret(@"recognition-api");return [secret[@"endpoint"] isEqual:endpoint] ? secret[@"key"] : nil; }
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler { completionHandler(nil); }
- (NSArray *)localModels:(NSDictionary *)settings error:(NSError **)error {
    NSMutableDictionary *local=settings.mutableCopy;local[@"mode"]=@"local";local[@"model"]=@"validation-only";
    if(!SSValidateRecognitionSettings(local,error))return nil;
    NSString *base=[local[@"endpoint"] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:[base stringByAppendingString:@"/api/tags"]]];request.timeoutInterval=6;
    __block NSData *data=nil;__block NSError *failure=nil;
    if(self.transport)data=self.transport(request,&failure);else {
        NSURLSessionConfiguration *configuration=NSURLSessionConfiguration.ephemeralSessionConfiguration;configuration.URLCache=nil;configuration.URLCredentialStorage=nil;configuration.HTTPCookieStorage=nil;configuration.timeoutIntervalForResource=8;
        NSURLSession *session=[NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];dispatch_semaphore_t done=dispatch_semaphore_create(0);
        NSURLSessionDataTask *task=[session dataTaskWithRequest:request completionHandler:^(NSData *response,NSURLResponse *metadata,NSError *networkError){if(networkError || [(NSHTTPURLResponse *)metadata statusCode]!=200)failure=RError(@"无法连接本地模型服务。请启动 Ollama，或检查高级设置中的地址。");else data=response;dispatch_semaphore_signal(done);}];[task resume];NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];while(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC))){if(AMCurrentOperationCancelled() || deadline.timeIntervalSinceNow<=0){[task cancel];failure=RError(AMCurrentOperationCancelled() ? @"本地服务检测已终止。":@"本地服务检测超时，请检查 Ollama 是否运行。");break;}}[session invalidateAndCancel];
    }
    if(failure || !data || data.length>1024*1024){if(error)*error=failure ?: RError(@"本地服务返回无效模型列表。");return nil;}
    id object=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];id models=[object isKindOfClass:NSDictionary.class] ? object[@"models"] : nil;
    if(![models isKindOfClass:NSArray.class] || [models count]>500){if(error)*error=RError(@"本地服务不支持模型列表，可在高级设置手填模型名。");return nil;}
    NSMutableArray *result=NSMutableArray.array;for(id model in models)if([model isKindOfClass:NSDictionary.class] && [model[@"name"] isKindOfClass:NSString.class] && [model[@"name"] length]>0 && [model[@"name"] length]<256)[result addObject:@{@"name":model[@"name"],@"digest":[model[@"digest"] isKindOfClass:NSString.class] ? model[@"digest"]:@""}];
    return [result sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"name"] localizedStandardCompare:b[@"name"]];}];
}
- (id)extract:(NSString *)text settings:(NSDictionary *)settings error:(NSError **)error {
    static NSLock *lock;static dispatch_once_t once;dispatch_once(&once,^{lock=NSLock.new;});
    NSMutableDictionary *bounded=settings.mutableCopy;if(![bounded[@"requestDeadline"] isKindOfClass:NSDate.class])bounded[@"requestDeadline"]=[NSDate dateWithTimeIntervalSinceNow:70];
    while(![lock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]])if(AMCurrentOperationCancelled() || [bounded[@"requestDeadline"] timeIntervalSinceNow]<=0){if(error)*error=[NSError errorWithDomain:@"AMRecognition" code:AMCurrentOperationCancelled() ? NSUserCancelledError:NSURLErrorTimedOut userInfo:@{NSLocalizedDescriptionKey:AMCurrentOperationCancelled() ? @"识别已取消":@"识别超时"}];return nil;}
    @try {return [self extractSerial:text settings:bounded error:error];}@finally{[lock unlock];}
}
- (id)extractSerial:(NSString *)text settings:(NSDictionary *)settings error:(NSError **)error {
    if(AMCurrentOperationCancelled() || [settings[@"requestDeadline"] timeIntervalSinceNow]<=0){if(error)*error=[NSError errorWithDomain:@"AMRecognition" code:AMCurrentOperationCancelled() ? NSUserCancelledError:NSURLErrorTimedOut userInfo:@{NSLocalizedDescriptionKey:AMCurrentOperationCancelled() ? @"识别已取消":@"识别超时"}];return nil;}
    if (!SSValidateRecognitionSettings(settings,error) || [settings[@"mode"] isEqual:@"rules"]) return nil;
    if (text.length > 48000 || SSContainsSecret([text dataUsingEncoding:NSUTF8StringEncoding])) { if(error)*error=RError(@"文档过长或含疑似凭据，仅使用本机规则。"); return nil; }
    BOOL cloud=[settings[@"mode"] isEqual:@"cloud"];
    if (cloud && ![settings[@"cloudConsent"] boolValue]) { if(error)*error=RError(@"请先在设置确认发送课程原文的范围，仅使用规则。"); return nil; }
    NSString *key=cloud ? [self cloudKeyForEndpoint:settings[@"endpoint"]] : nil;
    if (cloud && !key.length) { if(error)*error=RError(@"云端密钥未配置，仅使用规则。"); return nil; }
    if (cloud) {
        @synchronized(SSRecognitionClient.class) {
            NSString *day=DDLFormatDate(NSDate.date,@"yyyy-MM-dd"); NSDictionary *saved=SSReadPlist(@"recognition-usage.plist"); NSUInteger used=[saved[@"day"] isEqual:day] ? [saved[@"count"] unsignedIntegerValue] : 0;
            if (used>=20) { if(error)*error=RError(@"今日云端请求已达20次，继续使用免费规则。"); return nil; }
            if (!SSWritePlist(@"recognition-usage.plist",@{@"day":day,@"count":@(used+1)},error)) return nil;
        }
    }
    NSDate *budget=settings[@"requestDeadline"] ?: [NSDate dateWithTimeIntervalSinceNow:70];
    if(AMCurrentOperationCancelled() || budget.timeIntervalSinceNow<=0){if(error)*error=[NSError errorWithDomain:@"AMRecognition" code:AMCurrentOperationCancelled() ? NSUserCancelledError:NSURLErrorTimedOut userInfo:@{NSLocalizedDescriptionKey:AMCurrentOperationCancelled() ? @"识别已取消":@"识别超时"}];return nil;}
    text=RCanonicalText(text);NSMutableArray *numbered=NSMutableArray.array;NSUInteger line=0;for(NSString *row in [text componentsSeparatedByString:@"\n"])[numbered addObject:@{@"line":@(++line),@"text":row}];
    NSMutableDictionary *material=[@{@"text":text,@"lines":numbered} mutableCopy];
    NSString *system=AMCoursePrompt();
    if(settings[@"repairIssues"]){material[@"repairIssues"]=settings[@"repairIssues"];material[@"previousActivities"]=settings[@"previousActivities"] ?: @[];material[@"acceptedIndices"]=settings[@"acceptedIndices"] ?: @[];system=[system stringByAppendingString:@"\nCORRECTION: Correct only the rejected fields/items using the original text. Return the complete activities array in the same order and count as previousActivities. Copy items at acceptedIndices unchanged. Do not add activities or broaden the source scope. Each rejection names its original zero-based index. If previousActivities is empty because parsing failed, extract again from the same original only."];}
    NSString *input=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:material options:NSJSONWritingSortedKeys error:NULL] encoding:NSUTF8StringEncoding];
    NSArray *messages=@[@{@"role":@"system",@"content":system},@{@"role":@"user",@"content":input}];
    NSMutableDictionary *body=[@{@"model":settings[@"model"],@"messages":messages,@"stream":@NO} mutableCopy];
    if (!cloud) body[@"think"]=@NO;
    if (cloud) body[@"response_format"]=@{@"type":@"json_object"}; else { body[@"format"]=AMCourseOutputSchema(); body[@"options"]=@{@"temperature":@0}; }
    NSString *base=[settings[@"endpoint"] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
    NSURL *url=[NSURL URLWithString:[base stringByAppendingString:cloud ? @"/chat/completions" : @"/api/chat"]];
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url]; request.HTTPMethod=@"POST"; request.timeoutInterval=MAX(0.1,MIN(60,budget.timeIntervalSinceNow)); [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    if (key) [request setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    request.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:error];
    __block NSData *data=nil; __block NSError *failure=nil;
    if (self.transport) data=self.transport(request,&failure);
    else {
        NSURLSessionConfiguration *configuration=NSURLSessionConfiguration.ephemeralSessionConfiguration; configuration.URLCache=nil; configuration.HTTPCookieStorage=nil; configuration.URLCredentialStorage=nil; configuration.timeoutIntervalForResource=65;
        NSURLSession *session=[NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil]; dispatch_semaphore_t done=dispatch_semaphore_create(0);
        // Some Ollama-compatible local backends cannot constrain JSON generation.
        // Retry only that explicit capability error, on the same loopback endpoint;
        // returned text still passes identical JSON and source-evidence validation.
        for (NSUInteger attempt=0;attempt<2;attempt++) {
            __block BOOL unsupported=NO;
            NSURLSessionDataTask *task=[session dataTaskWithRequest:request completionHandler:^(NSData *response, NSURLResponse *metadata, NSError *networkError) {
                NSInteger status=[(NSHTTPURLResponse *)metadata statusCode];
                unsupported=!cloud && attempt==0 && status==501;
                if (networkError) failure=RError([NSString stringWithFormat:@"模型连接失败（网络代码 %ld），继续使用规则。请检查服务和连接。",(long)networkError.code]);
                else if (status!=200) failure=RError([NSString stringWithFormat:@"模型服务返回 HTTP %ld，继续使用规则。请检查模型名称及服务能力。",(long)status]);
                else if (response.length>1024*1024) failure=RError(@"模型响应过大，继续使用规则。");
                else {data=response;failure=nil;}
                dispatch_semaphore_signal(done);
            }];
            [task resume];NSDate *deadline=budget;BOOL stopped=NO;
            while(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC))){if(AMCurrentOperationCancelled() || deadline.timeIntervalSinceNow<=0){[task cancel];failure=[NSError errorWithDomain:@"AMRecognition" code:AMCurrentOperationCancelled() ? NSUserCancelledError:NSURLErrorTimedOut userInfo:@{NSLocalizedDescriptionKey:AMCurrentOperationCancelled() ? @"识别已取消":@"识别超时"}];stopped=YES;break;}}
            if(stopped)break;
            if (!unsupported) break;
            [body removeObjectForKey:@"format"]; request.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
        }
        [session invalidateAndCancel];
    }
    if(AMCurrentOperationCancelled() || budget.timeIntervalSinceNow<=0){if(error)*error=[NSError errorWithDomain:@"AMRecognition" code:AMCurrentOperationCancelled() ? NSUserCancelledError:NSURLErrorTimedOut userInfo:@{NSLocalizedDescriptionKey:AMCurrentOperationCancelled() ? @"识别已取消":@"识别超时"}];return nil;}
    if(data.length>1024*1024){if(error)*error=RError(@"模型响应过大");return nil;}
    if (failure || !data) { if(error)*error=failure ?: RError(@"模型响应为空。"); return nil; }
    id envelope=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]; if (![envelope isKindOfClass:NSDictionary.class]) { if(error)*error=RError(@"模型响应不是JSON对象。"); return nil; }
    id choices=envelope[@"choices"]; id first=[choices isKindOfClass:NSArray.class] && [choices count] ? choices[0] : nil;
    id message=cloud ? ([first isKindOfClass:NSDictionary.class] ? first[@"message"] : nil) : envelope[@"message"];
    NSString *content=[message isKindOfClass:NSDictionary.class] ? message[@"content"] : nil;
    id object=SSRecognitionJSONObject(content,!cloud);
    if ([object isKindOfClass:NSArray.class]) return object; // Strict JSON arrays from compatible local services are also validated.
    if (![object isKindOfClass:NSDictionary.class] || ![object[@"activities"] isKindOfClass:NSArray.class]) { if(error)*error=RError(@"模型未返回有效结构化结果，继续使用规则。"); return nil; }
    return object[@"activities"];
}
@end
NSString *SSRecognitionCacheKey(NSString *repository,NSString *path,NSString *blob,NSCalendar *calendar,NSDictionary *settings) {
    NSMutableDictionary *cacheSettings=NSMutableDictionary.dictionary;
    NSArray *fields=[settings[@"mode"] isEqual:@"rules"] ? @[@"mode",@"courseTemplate"]:@[@"mode",@"endpoint",@"model",@"modelDigest",@"courseTemplate"];
    for(NSString *field in fields)if(settings[field])cacheSettings[field]=settings[field];
    NSString *configuration=[[NSJSONSerialization dataWithJSONObject:cacheSettings options:NSJSONWritingSortedKeys error:NULL] base64EncodedStringWithOptions:0];
    return [NSString stringWithFormat:@"recognition-v10|%@|%@|%@|%@|%@|%@|%@",repository.lowercaseString,path,blob,calendar.timeZone.name,RHash(configuration ?: @""),[settings[@"mode"] isEqual:@"rules"] ? @"rules-v8":AMCoursePromptVersion(),AMCourseValidationVersion()];
}
NSArray *SSCachedRecognition(NSString *repository,NSString *path,NSString *blob,NSCalendar *calendar,NSDictionary *settings,NSMutableDictionary *cache) {
    NSString *key=SSRecognitionCacheKey(repository,path,blob,calendar,settings);
    if ([cache[key] isKindOfClass:NSArray.class]) return cache[key];
    {
        NSMutableDictionary *legacy=settings.mutableCopy;for(NSString *field in @[@"forceRecognition",@"manualLocal",@"localAutomatic",@"manualCloud",@"cacheOnly"])[legacy removeObjectForKey:field];
        NSString *configuration=[[NSJSONSerialization dataWithJSONObject:legacy options:NSJSONWritingSortedKeys error:NULL] base64EncodedStringWithOptions:0];
        NSString *old=[NSString stringWithFormat:@"recognition-v9|%@|%@|%@|%@|%@|%@|%@",repository,path,blob,calendar.timeZone.name,RHash(configuration ?: @""),AMCoursePromptVersion(),AMCourseValidationVersion()];
        if([cache[old] isKindOfClass:NSArray.class]){cache[key]=cache[old];return cache[key];}
    }
    return nil;
}
NSArray *SSRecognizeDocument(NSString *text, NSString *repository, NSString *path, NSString *blob, NSCalendar *calendar, NSDictionary *settings, NSMutableDictionary *cache, NSError **error) {
    return SSRecognizeDocumentWithClient(text,repository,path,blob,calendar,settings,cache,SSRecognitionClient.new,error);
}
NSArray *SSRecognizeDocumentWithClient(NSString *text, NSString *repository, NSString *path, NSString *blob, NSCalendar *calendar, NSDictionary *settings, NSMutableDictionary *cache, SSRecognitionClient *client, NSError **error) {
    text=RCanonicalText(text);
    NSString *key=SSRecognitionCacheKey(repository,path,blob,calendar,settings);
    if(![settings[@"forceRecognition"] boolValue]){NSArray *saved=SSCachedRecognition(repository,path,blob,calendar,settings,cache);if(saved)return saved;}
    NSMutableArray *found=NSMutableArray.array; for (NSDictionary *record in SSDiscoveriesFromDocument(text,repository,path,blob,NSDate.date,calendar)) [found addObject:SSEnrichDiscovery(record)];
    NSDictionary *template=settings[@"courseTemplate"];
    if ([template isKindOfClass:NSDictionary.class] && template.count && SSValidateCourseTemplate(template,NULL)) {
        NSString *title=TemplateField(text,template[@"titlePattern"]), *summary=TemplateField(text,template[@"contentPattern"]), *deadline=TemplateField(text,template[@"deadlinePattern"]);
        if (!found.count && title.length && !RMatch(path,@"exam|quiz|example|reference|changelog|考试|测验")) {
            NSMutableDictionary *record=[@{@"id":[NSString stringWithFormat:@"%@|%@|template|%@",repository.lowercaseString,path,RHash(title)],@"repository":repository,@"path":path,@"blobSHA":blob,@"line":@1,@"title":title,@"sourceTitle":title,@"kind":@"assignment",@"kindReason":@"课程模板提取，需确认类型",@"snippet":text,@"modelOnly":@YES,@"needsDate":@YES,@"needsTime":@YES,@"recognizer":@"template-v1"} mutableCopy];
            if (deadline.length) { NSArray *parsed=SSAssignmentsFromDocument([@"# 作业\n截止：" stringByAppendingString:deadline],repository,path,blob,NSDate.date,calendar); if(parsed.count==1)for(NSString *field in @[@"due",@"dateOnly",@"clock",@"needsDate",@"needsTime",@"relative",@"relativeToken",@"warnings",@"timeZone",@"dateText",@"deadlineText"])if(parsed[0][field])record[field]=parsed[0][field];record[@"line"]=@([[text substringToIndex:[text rangeOfString:deadline].location] componentsSeparatedByString:@"\n"].count); }
            [found addObject:SSEnrichDiscovery(record)];
        }
        if (found.count==1) {NSMutableDictionary *record=[found[0] mutableCopy];if(title.length)record[@"suggestedTitle"]=title;if(summary.length)record[@"summary"]=summary;found[0]=record;}
    }
    NSError *failure=nil;NSDictionary *report=nil;
    NSString *stateKey=[@"recognition-state|" stringByAppendingString:key];NSDictionary *prior=cache[stateKey];
    if (![settings[@"mode"] isEqual:@"rules"]) {
        NSMutableDictionary *request=settings.mutableCopy;request[@"requestDeadline"]=[NSDate dateWithTimeIntervalSinceNow:70];
        id output=[client extract:text settings:request error:&failure];
        if(output)report=SSModelValidationReport(output,text,repository,path,blob,calendar);
        BOOL formatFailure=!output && ([failure.localizedDescription containsString:@"未返回有效结构化结果"] || [failure.localizedDescription containsString:@"响应不是JSON对象"]);
        if([settings[@"mode"] isEqual:@"local"] && ((report && ![report[@"complete"] boolValue]) || formatFailure) && !AMCurrentOperationCancelled() && [request[@"requestDeadline"] timeIntervalSinceNow]>0){
            request[@"repairIssues"]=report[@"issues"] ?: @[RIssue(0,@"activities",@"format",@"返回有效JSON活动列表")];request[@"previousActivities"]=output ?: @[];request[@"acceptedIndices"]=report[@"acceptedIndices"] ?: @[];
            NSError *repairFailure=nil;id corrected=[client extract:text settings:request error:&repairFailure];
            if([corrected isKindOfClass:NSArray.class]){
                if([output isKindOfClass:NSArray.class] && [output count]){
                    if([corrected count]==[output count]){NSMutableArray *merged=[output mutableCopy];NSSet *accepted=[NSSet setWithArray:report[@"acceptedIndices"] ?: @[]];for(NSUInteger i=0;i<[output count];i++)if(![accepted containsObject:@(i)])merged[i]=corrected[i];output=merged;}
                }else output=corrected;
                report=SSModelValidationReport(output,text,repository,path,blob,calendar);failure=nil;
            }else if(repairFailure)failure=repairFailure;
        }
        if(report && ![report[@"complete"] boolValue] && !failure)failure=RValidationError(report);
        if(failure && [prior[@"records"] count]){NSMutableDictionary *retained=NSMutableDictionary.dictionary;for(NSDictionary *record in prior[@"records"])retained[record[@"id"]]=record;for(NSDictionary *record in report[@"records"] ?: @[])retained[record[@"id"]]=record;NSMutableDictionary *combined=[report mutableCopy] ?: NSMutableDictionary.dictionary;combined[@"records"]=[[retained.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"id"] compare:b[@"id"]];}] copy];report=combined;}
        for(NSDictionary *record in report[@"records"] ?: @[]){NSUInteger index=[found indexOfObjectPassingTest:^BOOL(NSDictionary *item,NSUInteger i,BOOL *stop){return [item[@"id"] isEqual:record[@"id"]];}];if(index==NSNotFound)[found addObject:record];else found[index]=record;}
        NSMutableArray *issues=[report[@"issues"] mutableCopy] ?: NSMutableArray.array;
        if(failure && !issues.count)[issues addObject:RIssue(0,@"request",failure.code==NSUserCancelledError ? @"cancelled":@"request",failure.localizedDescription)];
        cache[stateKey]=@{@"records":report[@"records"] ?: @[],@"issues":issues,@"complete":@(!failure && [report[@"complete"] boolValue]),@"state":failure.code==NSUserCancelledError ? @"cancelled":failure ? ([report[@"records"] count] ? @"partial":@"failed"):@"completed",@"model":settings[@"model"] ?: @"",@"prompt":AMCoursePromptVersion(),@"validation":AMCourseValidationVersion()};
    }
    // Completion never depends on whether a caller requested NSError details.
    if(!failure)cache[key]=found;
    if(failure && error)*error=failure;
    return found;
}

#import "SSSkill.inc"

#import "AMQuick.inc"

#include "AMPreflight.inc"

#include "AMOnlineReview.inc"
