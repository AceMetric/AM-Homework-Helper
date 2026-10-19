#pragma once
#import <Foundation/Foundation.h>
// Display values only. Scheduling, evidence and persisted reports keep their originals.
static inline NSString *AMShortActivityText(NSString *text) {
    NSMutableString *value=[(text ?: @"") mutableCopy];
    NSRegularExpression *paths=[NSRegularExpression regularExpressionWithPattern:@"[^\\s：:]+/[^\\s]+" options:0 error:NULL];
    for(NSTextCheckingResult *match in [[paths matchesInString:value options:0 range:NSMakeRange(0,value.length)] reverseObjectEnumerator]) {
        NSString *path=[value substringWithRange:match.range];NSArray *parts=path.pathComponents;NSString *shortPath=parts.count>1 ? [[parts subarrayWithRange:NSMakeRange(parts.count-2,2)] componentsJoinedByString:@"/"]:path;[value replaceCharactersInRange:match.range withString:shortPath];
    }
    return value;
}
static inline NSDictionary *AMActivityPresentation(NSDictionary *row) {
    NSString *state=row[@"state"] ?: @"",*target=row[@"target"] ?: @"",*kind=row[@"kind"] ?: @"操作",*stage=row[@"stage"] ?: @"";
    BOOL queued=[state isEqual:@"queued"],running=[state isEqual:@"running"],stopping=running && [row[@"cancelRequested"] boolValue];
    NSString *shortKind=[AMShortActivityText(kind) stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"… ."]];
    NSString *heading=target.length ? [NSString stringWithFormat:@"%@ · %@",target.lastPathComponent,shortKind]:shortKind;
    NSString *phase=queued ? @"排队中":stopping ? @"正在停止":AMShortActivityText((!queued && !running && [row[@"summary"] length]) ? row[@"summary"]:stage);
    if([phase isEqual:kind] || !phase.length)phase=running ? @"进行中":@"已结束";
    NSString *action=(queued || running) ? ([row[@"cancellable"] boolValue] && !stopping ? (queued ? @"取消排队":@"停止"):@""):@"关闭记录";
    NSMutableArray *details=[NSMutableArray arrayWithObjects:[NSString stringWithFormat:@"操作：%@",kind],nil];
    if(target.length)[details addObject:[NSString stringWithFormat:@"目标：%@",target]];
    [details addObject:queued ? @"状态：排队中，等待占用资源的操作结束":[NSString stringWithFormat:@"阶段：%@",stage]];
    if([row[@"details"] length])[details addObject:row[@"details"]];
    return @{@"heading":heading,@"phase":phase,@"action":action,@"details":[details componentsJoinedByString:@"\n"],@"active":@(queued || running)};
}
static inline NSDictionary *AMCourseCheckPresentation(NSDictionary *scan,NSUInteger pending) {
    NSMutableArray *brief=NSMutableArray.array,*details=NSMutableArray.array;
    if([scan[@"error"] length])return @{@"summary":@"检查失败",@"details":scan[@"detail"] ?: scan[@"error"],@"warning":@YES};
    if(pending)[brief addObject:[NSString stringWithFormat:@"%lu 项待审核",(unsigned long)pending]];
    NSUInteger exams=0,classroom=0,unknown=0;
    for(NSDictionary *material in scan[@"materials"]){if([material[@"kind"] isEqual:@"exam"])exams++;else if([material[@"kind"] isEqual:@"classroom"])classroom++;else unknown++;}
    if(exams)[brief addObject:[NSString stringWithFormat:@"%lu 项考试",(unsigned long)exams]];
    if(classroom)[brief addObject:[NSString stringWithFormat:@"%lu 项课上任务",(unsigned long)classroom]];
    if(unknown)[brief addObject:[NSString stringWithFormat:@"%lu 项类型待确认",(unsigned long)unknown]];
    NSUInteger failed=[scan[@"modelFailures"] count],waiting=[scan[@"modelSummary"][@"pending"] unsignedIntegerValue];
    if(failed)[brief addObject:[NSString stringWithFormat:@"%lu 份材料未完成增强",(unsigned long)failed]];
    else if([scan[@"recognitionMessages"] count])[brief addObject:@"部分材料检查未完成"];
    if(waiting)[brief addObject:[NSString stringWithFormat:@"%lu 份材料待增强",(unsigned long)waiting]];
    if(!brief.count)[brief addObject:@"无新增作业"];
    [details addObject:[NSString stringWithFormat:@"课后作业：%lu 项\n待审核：%lu 项",(unsigned long)[scan[@"candidates"] count],(unsigned long)pending]];
    if(exams)[details addObject:[NSString stringWithFormat:@"考试：%lu 项",(unsigned long)exams]];
    if(classroom)[details addObject:[NSString stringWithFormat:@"课上任务：%lu 项",(unsigned long)classroom]];
    if(unknown)[details addObject:[NSString stringWithFormat:@"类型待确认：%lu 项",(unsigned long)unknown]];
    NSDictionary *counts=scan[@"scanSummary"];
    for(NSArray *pair in @[@[@"new",@"新增材料"],@[@"changed",@"变化材料"],@[@"reused",@"复用材料"],@[@"read",@"读取材料"]])if([counts[pair[0]] unsignedIntegerValue])[details addObject:[NSString stringWithFormat:@"%@：%@ 份",pair[1],counts[pair[0]]]];
    if([scan[@"skipped"] count])[details addObject:[NSString stringWithFormat:@"跳过文件：%lu 个\n%@",(unsigned long)[scan[@"skipped"] count],[scan[@"skipped"] componentsJoinedByString:@"\n"]]];
    for(NSString *path in [[scan[@"modelFailures"] allKeys] sortedArrayUsingSelector:@selector(compare:)]){
        NSDictionary *failure=scan[@"modelFailures"][path];NSMutableArray *reasons=NSMutableArray.array;for(NSDictionary *issue in failure[@"issues"] ?: @[])[reasons addObject:issue[@"reason"] ?: @"未通过核验"];
        [details addObject:[NSString stringWithFormat:@"未完成增强：%@\n%@",path,[reasons componentsJoinedByString:@"\n"]]];
    }
    if([scan[@"recognitionMessages"] count])[details addObject:[scan[@"recognitionMessages"] componentsJoinedByString:@"\n"]];
    return @{@"summary":[brief componentsJoinedByString:@" · "],@"details":[details componentsJoinedByString:@"\n"],@"warning":@(failed>0 || [scan[@"recognitionMessages"] count]>0)};
}
