// One structure pass feeds both course discovery and local quick entry. Blocks
// retain original lines; a blank paragraph is never an activity boundary.
static BOOL AMActivityHeading(NSString *title) {
    return !GenericTitle(title) && !Match(title,@"schedule|^assignments$|(?:作业|任务)(?:列表|清单|目录)$") && !Match(title,@"^作业(?:目标|内容|要求|说明|结构|选题|目的|提交|评分|提示|格式)|^(?:submission|requirements?|instructions?|objectives?|deliverables?|deadline|due)(?:\\b|$)") && Match(title,@"作业|实验报告|实验[ _:#-]*[0-9一二三四五六七八九十]+|课程项目|homework|assignment|problem[ _-]*set|worksheet|coursework|\\blab\\b|\\bproject\\b|考试|exam|quiz|课堂|in.class");
}
static NSArray *AMTableCells(NSString *line) {
    NSString *value=AMTrim(line);if([value hasPrefix:@"|"])value=[value substringFromIndex:1];if([value hasSuffix:@"|"])value=[value substringToIndex:value.length-1];
    NSMutableArray *cells=NSMutableArray.array;NSMutableString *cell=NSMutableString.string;BOOL escaped=NO;NSUInteger ticks=0;
    for(NSUInteger i=0;i<value.length;i++){unichar c=[value characterAtIndex:i];if(c=='`' && !escaped)ticks^=1;if(c=='|' && !escaped && !ticks){[cells addObject:AMTrim(cell)];[cell setString:@""];}else [cell appendFormat:@"%C",c];escaped=(c=='\\' && !escaped);}[cells addObject:AMTrim(cell)];return cells;
}
NSArray *SSActivityBlocks(NSString *text,NSString *path,BOOL local) {
    NSArray *lines=[[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] componentsSeparatedByString:@"\n"];NSMutableArray *blocks=NSMutableArray.array,*starts=NSMutableArray.array;NSMutableIndexSet *tableLines=NSMutableIndexSet.indexSet;BOOL fence=NO;NSString *context=@"";NSUInteger ownerDepth=0;
    for(NSUInteger i=0;i<lines.count;i++){NSString *line=AMTrim(lines[i]);if(Match(line,@"^(?:```|~~~)")){fence=!fence;continue;}if(fence)continue;
        if(i+1<lines.count && [line containsString:@"|"] && Match(AMTrim(lines[i+1]),@"^\\|?\\s*:?-{3,}:?\\s*\\|")){
            NSArray *columns=AMTableCells(line);NSInteger title=-1;NSMutableIndexSet *dates=NSMutableIndexSet.indexSet;
            for(NSUInteger c=0;c<columns.count;c++){if(Match(columns[c],@"作业|任务|名称|标题|assignment|homework|title|activity|project|^name$"))title=c;if(AMDeadlineCue(columns[c]) || Match(columns[c],@"日期|时间|^date$|^time$"))[dates addIndex:c];}
            if(title>=0 && dates.count){[tableLines addIndex:i];[tableLines addIndex:++i];while(i+1<lines.count && [lines[i+1] containsString:@"|"] && AMTrim(lines[i+1]).length){i++;[tableLines addIndex:i];NSArray *cells=AMTableCells(lines[i]);if((NSUInteger)title>=cells.count)continue;NSString *name=CleanTitle(cells[title]);if(!name.length)continue;
                NSString *category=Match(context,@"考试|exam|quiz|test") ? @"Exam":Match(context,@"课堂|in.class|classroom") ? @"In-class task":@"Assignment";
                NSMutableArray *body=[NSMutableArray arrayWithObject:[NSString stringWithFormat:@"# %@: %@",category,name]],*deadline=NSMutableArray.array;
                for(NSUInteger c=0;c<MIN(columns.count,cells.count);c++)if(c!=(NSUInteger)title && [cells[c] length]){if([dates containsIndex:c])[deadline addObject:cells[c]];else [body addObject:[NSString stringWithFormat:@"%@: %@",columns[c],cells[c]]];}
                if(deadline.count)[body addObject:[@"截止: " stringByAppendingString:[deadline componentsJoinedByString:@" "]]];
                [blocks addObject:@{@"text":[body componentsJoinedByString:@"\n"],@"raw":lines[i],@"title":name,@"line":@(i+1),@"endLine":@(i+1),@"structure":@"table-row",@"activityBoundary":@YES}];}continue;}
        }
        BOOL markdown=Match(line,@"^#{1,6}\\s+");BOOL numbered=Match(line,@"^[0-9一二三四五六七八九十]+[、.)）]\\s*.+(?:作业|assignment|homework|project)") || (local && Match(line,@"^[0-9一二三四五六七八九十]+[、.)）]\\s*.+(?:报告|论文)"));
        if(markdown){NSUInteger depth=0;while(depth<line.length && [line characterAtIndex:depth]=='#')depth++;NSString *heading=CleanTitle(line);if(!ownerDepth || depth<=ownerDepth)context=heading;if(AMActivityHeading(heading) && (!ownerDepth || depth<=ownerDepth)){ownerDepth=depth;[starts addObject:@(i)];}}
        else if(numbered && !ownerDepth)[starts addObject:@(i)];
    }
    // A root project owns its generic/numerical subsections. Only explicit peer
    // activity headings split it; fenced examples and paragraphs stay together.
    if(!starts.count)[starts addObject:@0];else if([starts.firstObject unsignedIntegerValue]>0)[starts insertObject:@0 atIndex:0];
    for(NSUInteger n=0;n<starts.count;n++){NSUInteger start=[starts[n] unsignedIntegerValue],end=n+1<starts.count ? [starts[n+1] unsignedIntegerValue]:lines.count;NSMutableArray *body=NSMutableArray.array;for(NSUInteger i=start;i<end;i++)[body addObject:[tableLines containsIndex:i] ? @"":lines[i]];NSString *raw=[body componentsJoinedByString:@"\n"];if(!AMTrim(raw).length || (tableLines.count && !AMTrim(Replace(raw,@"(?m)^\\s*#{1,6}[^\\n]*$",@"")).length))continue;
        NSString *title=DocumentTitle(body,path);if(local && !Match(AMTrim(body.firstObject),@"^#") && (Match(AMTrim(body.firstObject),@"^[0-9一二三四五六七八九十]+[、.)）]") || AMActivityHeading(CleanTitle(body.firstObject))))title=CleanTitle(body.firstObject);
        [blocks addObject:@{@"text":raw,@"raw":raw,@"title":title,@"line":@(start+1),@"endLine":@(end),@"structure":@"section",@"activityBoundary":@(AMActivityHeading(title) && Match(AMTrim(body.firstObject),@"^(?:#{1,6}\\s+|[0-9一二三四五六七八九十]+[、.)）]|(?:Assignment|Homework|Project|Lab)\\b|作业[一二三四五六七八九十0-9])"))}];
    }
    return [blocks sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"line"] compare:b[@"line"]];}];
}
BOOL SSSeparateSubmission(NSString *text){NSString *positive=Replace(text,@"(?:无需|不必|不用|不需要|不应)(?:再|另行|另外|再次|额外)?\\s*(?:独立|单独)\\s*提交|\\b(?:do not need to|do not|don't|need not|not required to)\\s+submit[^\\n.。]{0,40}\\bseparately\\b|\\bno\\s+separate\\s+submissions?\\b",@"");return Match(positive,@"独立\\s*提交|单独\\s*提交|\\bseparate\\s+submissions?\\b|\\bsubmit[^\\n.。]{0,40}\\bseparately\\b");}
NSString *SSProseText(NSString *text){NSMutableArray *lines=NSMutableArray.array;BOOL fence=NO;for(NSString *raw in [text componentsSeparatedByString:@"\n"]){NSString *trim=AMTrim(raw);if([trim hasPrefix:@"```"] || [trim hasPrefix:@"~~~"]){fence=!fence;[lines addObject:@""];continue;}[lines addObject:fence ? @"":raw];}return [lines componentsJoinedByString:@"\n"];}
NSDictionary *SSSourceAnalysis(NSString *text,NSString *path) {
    NSString *canonical=[[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    NSMutableArray *activities=NSMutableArray.array;NSArray *blocks=SSActivityBlocks(canonical,path,NO);
    for(NSDictionary *block in blocks){NSMutableDictionary *copy=block.mutableCopy;NSString *body=block[@"raw"];NSString *role=@"requirements";NSString *prose=SSProseText(body);NSString *firstHeading=@"";for(NSString *raw in [prose componentsSeparatedByString:@"\n"])if(AMTrim(raw).length){firstHeading=CleanTitle(raw);break;}

        if(Match(firstHeading,@"^(?:参考资料|参考答案|示例|教材|reference|examples?|solutions?)(?:\\b|$)") || Match(prose,@"(?m)^\\s*(?:学生答案|我的解答|student (?:answer|solution)|my solution)\\s*[:：]"))role=@"reference";
        if(Match(prose,@"(?m)^\\s*(?:本(?:次|周)(?:不布置|没有|无)(?:新)?作业|(?:本次|本周)?(?:作业|任务).{0,12}(?:已取消|取消提交)|(?:assignment|homework).{0,12}(?:cancelled|canceled)|no (?:homework|assignment)(?: is)? assigned)"))role=@"cancelled";
        if(Match(block[@"title"],@"(?:已取消|[（(](?:已取消|取消|cancelled|canceled)[）)])$") && AMActivityHeading(block[@"title"]))role=@"cancelled";
        if(Match(path.lastPathComponent,@"^assignment(?:[-_]?[0-9]+)?\\.md$") && Match(prose,@"(?m)^#{1,6}\\s*(?:解答|答案|Solution|Answer)\\b|我的解答|我的答案"))role=@"answer";
        NSString *nonlinks=Replace(body,@"(?m)^\\s*(?:#{1,6}[^\\n]*|[-*+]?\\s*\\[[^\\]]+\\]\\([^)]+\\)|[| :\\-]+)\\s*$",@"");if(!AMTrim(nonlinks).length)role=@"index";
        copy[@"prose"]=prose;copy[@"role"]=role;NSMutableArray *requirements=NSMutableArray.array,*dates=NSMutableArray.array,*links=NSMutableArray.array;NSUInteger line=[block[@"line"] unsignedIntegerValue];
        BOOL relationFence=NO;for(NSString *raw in [body componentsSeparatedByString:@"\n"]){NSString *trim=AMTrim(raw);if([trim hasPrefix:@"```"] || [trim hasPrefix:@"~~~"]){relationFence=!relationFence;line++;continue;}if(relationFence){line++;continue;}if(Match(raw,@"提交|命名|格式|submit|deliverable|filename"))[requirements addObject:@(line)];if(AMDeadlineCue(raw))[dates addObject:@(line)];for(NSTextCheckingResult *link in [Regex(@"\\[[^\\]\\n]+\\]\\(([^)\\n]+)\\)") matchesInString:raw options:0 range:NSMakeRange(0,raw.length)]){NSString *target=[[Group(raw,link,1) componentsSeparatedByString:@"#"] firstObject];target=[target stringByRemovingPercentEncoding] ?: target;if(!target.length || [target hasPrefix:@"/"] || [target containsString:@":"] || [target containsString:@"?"])continue;NSString *joined=[[[[@"/" stringByAppendingString:path] stringByDeletingLastPathComponent] stringByAppendingPathComponent:target] stringByStandardizingPath];if([joined hasPrefix:@"/"])[links addObject:@{@"path":[joined substringFromIndex:1],@"line":@(line),@"relationship":Match(raw,@"完成|解答|实现|运行|附件|所附|\\bcomplete\\b|\\bsolve\\b|\\bimplement\\b|\\battached\\b") ? @"part":@"reference"}];}line++;}copy[@"requirementsLines"]=requirements;copy[@"deadlineLines"]=dates;copy[@"links"]=links;[activities addObject:copy];
    }return @{@"text":canonical,@"activities":activities,@"version":@"source-analysis-v1"};
}
NSString *SSActivityAnchor(NSDictionary *block,NSUInteger count) {
    NSTextCheckingResult *number=[Regex(@"(?:assignment|homework|problem[ _-]*set|worksheet|lab|project|作业)\\s*[-_:# ]*([0-9一二三四五六七八九十]+)") firstMatchInString:block[@"title"] options:0 range:NSMakeRange(0,[block[@"title"] length])];
    if(number)return [@"number:" stringByAppendingString:Group(block[@"title"],number,1)];
    if(count==1)return @"document";
    NSString *body=Replace(block[@"raw"],@"(?m)^\\s*#.*$|^.*(?:截止|deadline|due|submit by|no later than).*$",@"");body=Replace(body,@"\\s+",@" ");NSData *data=[body dataUsingEncoding:NSUTF8StringEncoding];unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);NSMutableString *hash=NSMutableString.string;for(NSUInteger i=0;i<12;i++)[hash appendFormat:@"%02x",digest[i]];return hash;
}
NSArray *SSDiscoveriesFromDocument(NSString *text,NSString *repository,NSString *path,NSString *blobSHA,NSDate *now,NSCalendar *calendar) {
    if(!text.length || !repository.length || !path.length)return @[];NSArray *blocks=SSSourceAnalysis(text,path)[@"activities"];NSMutableArray *result=NSMutableArray.array;NSMutableDictionary *anchors=NSMutableDictionary.dictionary;
    for(NSDictionary *block in blocks){if(![block[@"role"] isEqual:@"requirements"])continue;BOOL table=[block[@"structure"] isEqual:@"table-row"];NSArray *parsed=LegacyDiscoveries(block[@"text"],repository,path,blobSHA,now,calendar);BOOL independent=SSSeparateSubmission(block[@"prose"] ?: block[@"raw"]);
        if(!independent){NSMutableArray *grouped=NSMutableArray.array;NSMutableDictionary *parent=nil;for(NSDictionary *row in parsed){if(![row[@"kind"] isEqual:@"assignment"]){[grouped addObject:row];continue;}if(!parent){parent=row.mutableCopy;parent[@"mergedLegacyIDs"]=NSMutableArray.array;[grouped addObject:parent];}else{[parent[@"mergedLegacyIDs"] addObject:row[@"id"]];if([row[@"dateText"] length] && [parent[@"dateText"] length]){BOOL same=YES;for(NSString *field in @[@"due",@"dateOnly",@"relativeToken",@"clock",@"needsDate",@"needsTime"])if(![(parent[field] ?: NSNull.null) isEqual:row[field] ?: NSNull.null])same=NO;if(!same){[parent removeObjectForKey:@"due"];parent[@"needsDate"]=@YES;parent[@"requiresReview"]=@YES;parent[@"warnings"]=@[@"同一作业有不同截止说明，请核对适用日期"];}}else if([row[@"dateText"] length]){for(NSString *field in @[@"due",@"dateOnly",@"relativeToken",@"clock",@"needsDate",@"needsTime",@"dateText",@"warnings",@"line"])if(row[field])parent[field]=row[field];}}}parsed=grouped;}
        for(NSDictionary *item in parsed){NSMutableDictionary *copy=item.mutableCopy;NSUInteger offset=[block[@"line"] unsignedIntegerValue]-1;copy[@"line"]=@(table ? offset+1:[item[@"line"] unsignedIntegerValue]+offset);copy[@"sectionLine"]=block[@"line"];copy[@"endLine"]=block[@"endLine"];copy[@"structure"]=block[@"structure"];copy[@"parserVersion"]=@"structure-v4/date-v8";if(!independent && [copy[@"kind"] isEqual:@"assignment"] && AMActivityHeading(block[@"title"]))copy[@"title"]=copy[@"sourceTitle"]=block[@"title"];if(independent)copy[@"requiresReview"]=@YES;copy[@"snippet"]=block[@"raw"];if(table){copy[@"title"]=copy[@"sourceTitle"]=block[@"title"];if([copy[@"dateText"] length])copy[@"dateText"]=block[@"raw"];}
        NSString *anchor=SSActivityAnchor(block,blocks.count);NSString *identity=[NSString stringWithFormat:@"%@|%@|activity:%@",repository.lowercaseString,path,anchor];NSUInteger ordinal=[anchors[identity] unsignedIntegerValue]+1;anchors[identity]=@(ordinal);copy[@"relationText"]=block[@"prose"] ?: block[@"raw"];copy[@"sourceLinks"]=block[@"links"] ?: @[];copy[@"sourceRef"]=@{@"activity":anchor,@"startLine":block[@"line"],@"endLine":block[@"endLine"],@"role":block[@"role"]};copy[@"legacyIDs"]=[@[item[@"id"]] arrayByAddingObjectsFromArray:item[@"mergedLegacyIDs"] ?: @[]];[copy removeObjectForKey:@"mergedLegacyIDs"];copy[@"id"]=ordinal==1 ? identity:[identity stringByAppendingFormat:@":%lu",(unsigned long)ordinal];copy[@"fieldEvidence"]=@{@"titleLine":block[@"line"],@"deadlineLine":copy[@"line"]};
        // Newly associated table/English dates always require review first.
        if(table || AMHas(copy[@"dateText"] ?: @"",AMMonthPattern()))copy[@"requiresReview"]=@YES;[result addObject:copy];}}
    return result;
}
static BOOL AMSourceAliasesOverlap(NSDictionary *a,NSDictionary *b) {
    NSMutableSet *identities=[NSMutableSet setWithArray:a[@"legacyIDs"] ?: @[]];if(a[@"id"])[identities addObject:a[@"id"]];
    if(b[@"id"] && [identities containsObject:b[@"id"]])return YES;for(NSString *alias in b[@"legacyIDs"] ?: @[])if([identities containsObject:alias])return YES;return NO;
}
NSArray *SSReconcileDiscoveryIDs(NSArray *previous,NSArray *current) {
    NSMutableArray *result=NSMutableArray.array;NSMutableSet *claimed=NSMutableSet.set;
    for(NSDictionary *record in current){NSMutableArray *matches=NSMutableArray.array,*oldFile=NSMutableArray.array,*newFile=NSMutableArray.array;for(NSDictionary *old in previous)if([old[@"repository"] isEqual:record[@"repository"]] && [old[@"path"] isEqual:record[@"path"]]){[oldFile addObject:old];if(AMSourceAliasesOverlap(old,record))[matches addObject:old];}for(NSDictionary *row in current)if([row[@"repository"] isEqual:record[@"repository"]] && [row[@"path"] isEqual:record[@"path"]])[newFile addObject:row];
        // Alias migration must be one-to-one. Two new activities can share a
        // legacy title; neither may silently claim the same confirmed task.
        if(matches.count==1){NSDictionary *old=matches[0];NSUInteger contenders=0;for(NSDictionary *row in newFile)if(AMSourceAliasesOverlap(old,row))contenders++;if(contenders>1 || [claimed containsObject:old[@"id"]])[matches removeAllObjects];}
        if(!matches.count && oldFile.count==1 && newFile.count==1 && ![claimed containsObject:oldFile[0][@"id"]] && [oldFile[0][@"kind"] isEqual:record[@"kind"]])[matches addObject:oldFile[0]];
        NSMutableDictionary *copy=record.mutableCopy;if(matches.count==1){NSDictionary *old=matches[0];[claimed addObject:old[@"id"]];NSMutableOrderedSet *aliases=[NSMutableOrderedSet orderedSetWithArray:record[@"legacyIDs"] ?: @[]];[aliases addObjectsFromArray:old[@"legacyIDs"] ?: @[]];[aliases addObject:record[@"id"]];copy[@"id"]=old[@"id"];[aliases removeObject:copy[@"id"]];copy[@"legacyIDs"]=aliases.array;}else if(oldFile.count){copy[@"identityUncertain"]=@YES;copy[@"requiresReview"]=@YES;}[result addObject:copy];
    }return result;
}
