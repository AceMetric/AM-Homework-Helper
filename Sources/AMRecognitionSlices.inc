// Structural chunks carry global line numbers. Fences, display math and table
// rows are indivisible; an oversized atom is reported rather than truncated.
NSArray *SSRecognitionSlices(NSString *text,NSString *path) {
    NSArray *lines=[RCanonicalText(text) componentsSeparatedByString:@"\n"];NSMutableArray *atoms=NSMutableArray.array,*slices=NSMutableArray.array;NSUInteger start=0;NSString *fence=nil;BOOL math=NO;
    for(NSUInteger i=0;i<lines.count;i++){NSString *trim=RTrim(lines[i]);BOOL marker=[trim hasPrefix:@"```"] || [trim hasPrefix:@"~~~"];if(marker){NSString *token=[trim substringToIndex:3];if(!fence)fence=token;else if([fence isEqual:token])fence=nil;}
        if(!fence && [trim hasPrefix:@"\\["])math=![trim containsString:@"\\]"];else if(!fence && [trim hasPrefix:@"\\]"])math=NO;
        if(!fence && [trim hasPrefix:@"$$"]){NSUInteger occurrences=[[trim componentsSeparatedByString:@"$$"] count]-1;if(occurrences%2)math=!math;}
        BOOL boundary=!fence && !math && (!trim.length || i+1==lines.count || [trim hasPrefix:@"|"] || (i+1<lines.count && [RTrim(lines[i+1]) hasPrefix:@"#"]));
        if(boundary){[atoms addObject:@{ @"start":@(start+1),@"end":@(i+1),@"text":[[lines subarrayWithRange:NSMakeRange(start,i-start+1)] componentsJoinedByString:@"\n"]}];start=i+1;}
    }
    if(start<lines.count)[atoms addObject:@{@"start":@(start+1),@"end":@(lines.count),@"text":[[lines subarrayWithRange:NSMakeRange(start,lines.count-start)] componentsJoinedByString:@"\n"]}];
    NSMutableDictionary *current=nil;NSArray *activities=SSSourceAnalysis(text,path)[@"activities"];
    for(NSDictionary *atom in atoms){if([atom[@"text"] length]>6000){if(current){[slices addObject:current];current=nil;}[slices addObject:@{@"start":atom[@"start"],@"end":atom[@"end"],@"text":atom[@"text"],@"uncovered":@YES}];continue;}
        (void)activities;
        if(current && ([current[@"text"] length]+[atom[@"text"] length]+1>6000)){[slices addObject:current];current=nil;}
        if(!current)current=[@{@"start":atom[@"start"],@"end":atom[@"end"],@"text":atom[@"text"]} mutableCopy];else{current[@"end"]=atom[@"end"];current[@"text"]=[current[@"text"] stringByAppendingFormat:@"\n%@",atom[@"text"]];}}
    if(current)[slices addObject:current];return slices;
}
static NSString *RLinesQuote(id range,NSArray *lines,NSUInteger lower,NSUInteger upper){
    if(![range isKindOfClass:NSArray.class] || [range count]!=2 || !RLineNumber(range[0]) || !RLineNumber(range[1]))return nil;NSInteger start=[range[0] integerValue],end=[range[1] integerValue];if(start<(NSInteger)lower || end<start || end>(NSInteger)upper || end>(NSInteger)lines.count)return nil;return [[lines subarrayWithRange:NSMakeRange(start-1,end-start+1)] componentsJoinedByString:@"\n"];
}
static NSArray *RHydrateActivities(id output,NSString *text,NSUInteger lower,NSUInteger upper){
    if(![output isKindOfClass:NSArray.class])return output;NSArray *lines=[text componentsSeparatedByString:@"\n"];NSMutableArray *result=NSMutableArray.array;
    for(id value in output){if(![value isKindOfClass:NSDictionary.class]){[result addObject:value];continue;}NSMutableDictionary *item=[value mutableCopy];NSMutableArray *rangeIssues=NSMutableArray.array;
        for(NSArray *pair in @[@[@"evidenceLines",@"evidence"],@[@"summaryLines",@"summaryEvidence"],@[@"requirementsLines",@"requirementsEvidence"],@[@"deadlineLines",@"deadlineEvidence"]])if(item[pair[0]]){id span=item[pair[0]];NSString *quote=RLinesQuote(span,lines,lower,upper);item[pair[1]]=quote ?: @"";if(!quote && (![span isKindOfClass:NSArray.class] || [span count]!=0))[rangeIssues addObject:pair[0]];if([pair[0] isEqual:@"evidenceLines"] && quote){item[@"startLine"]=span[0];item[@"endLine"]=span[1];}}
        // An item may not claim text from a different chunk, even if the quote
        // occurs elsewhere in the original document.
        if(!item[@"startLine"] && [item[@"evidence"] isKindOfClass:NSString.class]){NSString *span=[[lines subarrayWithRange:NSMakeRange(lower-1,upper-lower+1)] componentsJoinedByString:@"\n"];if([span rangeOfString:item[@"evidence"] options:NSLiteralSearch].location==NSNotFound)item[@"evidence"]=@"";}
        if(item[@"startLine"] && ([item[@"startLine"] integerValue]<(NSInteger)lower || [item[@"endLine"] integerValue]>(NSInteger)upper))item[@"evidence"]=@"";
        if([item[@"subtasks"] isKindOfClass:NSArray.class]){NSMutableArray *children=NSMutableArray.array;for(id child in item[@"subtasks"]){if(![child isKindOfClass:NSDictionary.class]){[children addObject:child];continue;}NSMutableDictionary *copy=[child mutableCopy];if(copy[@"lines"])copy[@"evidence"]=RLinesQuote(copy[@"lines"],lines,lower,upper) ?: @"";[children addObject:copy];}item[@"subtasks"]=children;}if(rangeIssues.count)item[@"_rangeIssues"]=rangeIssues;[result addObject:item];
    }return result;
}
static NSArray *RMergeModelRecords(NSArray *records){
    NSMutableArray *ordered=NSMutableArray.array;NSMutableDictionary *index=NSMutableDictionary.dictionary;
    for(NSDictionary *record in records){NSString *key=record[@"id"];NSMutableDictionary *existing=index[key];if(!existing){existing=record.mutableCopy;index[key]=existing;[ordered addObject:existing];continue;}
        NSMutableArray *children=[existing[@"suggestedSubtasks"] mutableCopy] ?: NSMutableArray.array;for(NSDictionary *child in record[@"suggestedSubtasks"] ?: @[]){BOOL seen=NO;for(NSDictionary *old in children)if([old[@"sourceKey"] isEqual:child[@"sourceKey"]])seen=YES;if(!seen)[children addObject:child];}existing[@"suggestedSubtasks"]=children;
        for(NSString *field in @[@"summary",@"submissionRequirements"])if(![existing[field] length] && [record[field] length])existing[field]=record[field];
    }return ordered;
}
static NSDictionary *RLocalSlices(NSString *text,NSString *repository,NSString *path,NSString *blob,NSCalendar *calendar,NSDictionary *settings,NSMutableDictionary *cache,SSRecognitionClient *client,NSError **error){
    NSString *key=SSRecognitionCacheKey(repository,path,blob,calendar,settings);NSMutableDictionary *request=settings.mutableCopy;NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:RDocumentBudget(text,settings)];if([settings[@"requestDeadline"] isKindOfClass:NSDate.class] && [settings[@"requestDeadline"] compare:deadline]==NSOrderedAscending)deadline=settings[@"requestDeadline"];request[@"requestDeadline"]=deadline;request[@"sourcePath"]=path;request[@"sourceAnalysis"]=SSSourceAnalysis(text,path);BOOL retryPartial=cache[[@"recognition-state|" stringByAppendingString:key]] && ![cache[[@"recognition-state|" stringByAppendingString:key]][@"complete"] boolValue];BOOL repaired=NO;NSMutableArray *records=NSMutableArray.array,*issues=NSMutableArray.array;NSError *lastFailure=nil;
    for(NSDictionary *slice in SSRecognitionSlices(text,path)){
        NSString *sliceKey=[key stringByAppendingFormat:@"|slice:%@-%@",slice[@"start"],slice[@"end"]];NSDictionary *saved=cache[sliceKey];
        if([saved[@"complete"] boolValue] && (![settings[@"forceRecognition"] boolValue] || retryPartial)){[records addObjectsFromArray:saved[@"records"] ?: @[]];continue;}
        if(AMCurrentOperationCancelled() || deadline.timeIntervalSinceNow<=0){lastFailure=[NSError errorWithDomain:@"AMRecognition" code:AMCurrentOperationCancelled() ? NSUserCancelledError:NSURLErrorTimedOut userInfo:@{NSLocalizedDescriptionKey:AMCurrentOperationCancelled() ? @"识别已取消":@"文档识别超时"}];[issues addObject:RIssue(0,@"request",AMCurrentOperationCancelled() ? @"cancelled":@"timeout",lastFailure.localizedDescription)];break;}
        if([slice[@"uncovered"] boolValue]){[issues addObject:RIssue(0,@"source",@"uncovered",[NSString stringWithFormat:@"第 %@—%@ 行的完整代码、公式或段落超过分片上限，未交给模型",slice[@"start"],slice[@"end"]])];continue;}
        request[@"lineOffset"]=@([slice[@"start"] unsignedIntegerValue]-1);[request removeObjectForKey:@"repairIssues"];[request removeObjectForKey:@"previousActivities"];[request removeObjectForKey:@"acceptedIndices"];
        NSError *failure=nil;id output=[client extract:slice[@"text"] settings:request error:&failure];output=RHydrateActivities(output,text,[slice[@"start"] unsignedIntegerValue],[slice[@"end"] unsignedIntegerValue]);NSDictionary *report=output ? SSModelValidationReport(output,text,repository,path,blob,calendar):nil;
        BOOL formatFailure=!output && ([failure.localizedDescription containsString:@"结构化结果"] || [failure.localizedDescription containsString:@"JSON对象"]);
        if(!repaired && ((report && ![report[@"complete"] boolValue]) || formatFailure) && !AMCurrentOperationCancelled() && deadline.timeIntervalSinceNow>0){repaired=YES;request[@"repairIssues"]=report[@"issues"] ?: @[RIssue(0,@"activities",@"format",@"返回有效JSON活动列表")];request[@"previousActivities"]=output ?: @[];request[@"acceptedIndices"]=report[@"acceptedIndices"] ?: @[];
            NSError *repairError=nil;id corrected=[client extract:slice[@"text"] settings:request error:&repairError];corrected=RHydrateActivities(corrected,text,[slice[@"start"] unsignedIntegerValue],[slice[@"end"] unsignedIntegerValue]);if([corrected isKindOfClass:NSArray.class]){if([output isKindOfClass:NSArray.class] && [output count]){if([output count]==[corrected count]){NSMutableArray *merged=[output mutableCopy];NSSet *accepted=[NSSet setWithArray:report[@"acceptedIndices"] ?: @[]];for(NSUInteger i=0;i<[output count];i++)if(![accepted containsObject:@(i)])merged[i]=corrected[i];output=merged;}}else output=corrected;report=SSModelValidationReport(output,text,repository,path,blob,calendar);failure=nil;}else if(repairError)failure=repairError;
        }
        NSArray *valid=report[@"records"] ?: @[];if(failure || ![report[@"complete"] boolValue]){[records addObjectsFromArray:saved[@"records"] ?: @[]];[issues addObjectsFromArray:report[@"issues"] ?: @[]];if(failure){lastFailure=failure;[issues addObject:RIssue(0,@"request",failure.code==NSUserCancelledError ? @"cancelled":failure.code==NSURLErrorTimedOut ? @"timeout":@"request",failure.localizedDescription)];}}
        if(AMCurrentOperationCancelled()){lastFailure=[NSError errorWithDomain:@"AMRecognition" code:NSUserCancelledError userInfo:@{NSLocalizedDescriptionKey:@"识别已取消"}];break;}
        [records addObjectsFromArray:valid];cache[sliceKey]=@{@"records":RMergeModelRecords(valid),@"complete":@(!failure && [report[@"complete"] boolValue])};
        BOOL (^checkpoint)(NSError **)=settings[@"sliceCheckpoint"];if(checkpoint){NSError *saveError=nil;if(!checkpoint(&saveError)){lastFailure=saveError ?: RError(@"识别结果保存失败");[issues addObject:RIssue(0,@"storage",@"save",lastFailure.localizedDescription)];break;}}
    }
    NSDictionary *result=@{@"records":RMergeModelRecords(records),@"issues":issues,@"complete":@(issues.count==0 && !lastFailure)};if(error && (lastFailure || issues.count))*error=lastFailure ?: RValidationError(result);return result;
}
