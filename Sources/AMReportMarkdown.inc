NSDictionary *AMPreflightReviewScope(NSDictionary *review){
    NSMutableOrderedSet *excluded=[NSMutableOrderedSet orderedSetWithArray:review[@"excluded"] ?: @[]],*unverified=NSMutableOrderedSet.orderedSet;
    for(NSString *reason in review[@"unverified"] ?: @[]){if([reason containsString:@"用户排除"] || [reason containsString:@"未选择发送"])[excluded addObject:reason];else [unverified addObject:reason];}
    return @{@"excluded":excluded.array,@"unverified":unverified.array};
}
static NSString *PFMarkdownLiteral(NSString *value){
    NSMutableString *text=[(value ?: @"") mutableCopy];
    for(NSString *symbol in @[@"\\",@"`",@"*",@"_",@"[",@"]",@"#",@"<",@">"])[text replaceOccurrencesOfString:symbol withString:[@"\\" stringByAppendingString:symbol] options:0 range:NSMakeRange(0,text.length)];
    return text;
}
static NSString *PFMarkdownCode(NSString *value){
    NSString *fence=@"```";while([value containsString:fence])fence=[fence stringByAppendingString:@"`"];
    return [NSString stringWithFormat:@"%@text\n%@\n%@\n",fence,value ?: @"",fence];
}
static NSString *PFFindingMarkdown(NSDictionary *issue,NSDictionary *snapshot,BOOL nested){
    NSString *path=issue[@"path"] ?: @"",*provider=issue[@"provider"] ?: @"local";
    NSString *location=path.length ? ([issue[@"line"] integerValue]>0 ? [NSString stringWithFormat:@"%@:%@",path,issue[@"line"]]:path):@"检查范围";
    NSMutableString *text=[NSMutableString stringWithFormat:@"%@ %@\n\n**位置**：%@\n\n**来源**：%@\n",nested ? @"###":@"##",PFMarkdownLiteral(issue[@"message"]),PFMarkdownLiteral(location),[provider isEqual:@"assistant"] ? @"在线复核":([provider isEqual:@"coverage"] ? @"检查未覆盖":@"本机检查")];
    if([issue[@"reason"] length])[text appendFormat:@"\n%@ 依据\n\n%@\n",nested ? @"####":@"###",issue[@"reason"]];
    if([issue[@"suggestion"] length])[text appendFormat:@"\n%@ 建议\n\n%@\n",nested ? @"####":@"###",issue[@"suggestion"]];
    if([issue[@"evidence"] length])[text appendFormat:@"\n%@ 原文证据\n\n%@",nested ? @"####":@"###",PFMarkdownCode(issue[@"evidence"])];
    NSString *source=snapshot[@"files"][path][@"text"];
    if(source && [issue[@"line"] integerValue]>0){NSArray *lines=[source componentsSeparatedByString:@"\n"];NSInteger line=[issue[@"line"] integerValue]-1;NSMutableString *context=NSMutableString.string;
        for(NSInteger i=MAX(0,line-2);i<MIN((NSInteger)lines.count,line+3);i++)[context appendFormat:@"%ld  %@\n",(long)i+1,lines[i]];
        if(context.length)[text appendFormat:@"\n%@ 附近原文\n\n%@",nested ? @"####":@"###",PFMarkdownCode(context)];
    }return text;
}
NSString *AMPreflightFindingMarkdown(NSDictionary *issue,NSDictionary *snapshot){return PFFindingMarkdown(issue,snapshot,NO);}
NSString *AMPreflightReportMarkdown(NSDictionary *report,NSDictionary *snapshot,NSDictionary *review){
    NSDictionary *scope=AMPreflightReviewScope(review);
    NSMutableArray *issues=[report[@"issues"] mutableCopy] ?: NSMutableArray.array;[issues addObjectsFromArray:review[@"issues"] ?: @[]];
    NSDictionary *rank=@{@"error":@0,@"warning":@1,@"info":@2};[issues sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [rank[a[@"severity"]] ?: @2 compare:rank[b[@"severity"]] ?: @2];}];
    NSMutableString *text=[NSMutableString stringWithFormat:@"# 检查报告\n\n## 概况\n\n- 建议：%lu 条\n- 在线已检查：%lu 个文件\n- 检查未覆盖：%lu 项\n- 未选择发送：%lu 项\n\n",(unsigned long)issues.count,(unsigned long)[review[@"checked"] count],(unsigned long)[scope[@"unverified"] count],(unsigned long)[scope[@"excluded"] count]];
    if(!review){NSRange end=[text rangeOfString:@"\n- 在线已检查："];if(end.location!=NSNotFound)[text deleteCharactersInRange:NSMakeRange(end.location,text.length-end.location)];[text appendString:@"\n- 在线复核：尚未进行\n\n"];}
    if(review[@"failure"])[text appendFormat:@"## 在线复核未完成\n\n%@\n\n可继续检查；已有完整结果保留。上传副本可在在线设置管理。\n\n",PFMarkdownLiteral(review[@"failure"][@"reason"])];
    [text appendString:@"## 问题与建议\n\n"];
    if(!issues.count)[text appendString:@"本次已检查范围内未发现建议。\n\n"];
    for(NSDictionary *issue in issues)[text appendFormat:@"%@\n",PFFindingMarkdown(issue,snapshot,YES)];
    [text appendString:@"## 本机覆盖范围\n\n"];for(NSDictionary *row in report[@"coverage"])[text appendFormat:@"- %@%@%@\n",PFMarkdownLiteral(row[@"path"]),[row[@"path"] length] ? @"：":@"",PFMarkdownLiteral(row[@"status"])];
    for(NSString *field in @[@"unverified",@"excluded"]){[text appendFormat:@"\n## %@\n\n",[field isEqual:@"unverified"] ? @"检查未覆盖":@"未选择发送"];NSArray *reasons=scope[field];if(!reasons.count)[text appendString:(!review && [field isEqual:@"unverified"]) ? @"尚未进行在线复核。\n":@"无。\n"];for(NSString *reason in reasons)[text appendFormat:@"- %@\n",PFMarkdownLiteral(reason)];}
    return text;
}
