// 来源核验与“作答是否有改动”是两件事。离线或评价已更新时保留历史分数，
// 但不把未核验的旧评价放入当前排名，也不按零分处理。
- (NSString *)evaluationKey:(NSDictionary *)row {
    return AMPeerHash(@[row[@"sourceID"] ?: @"",row[@"commit"] ?: @"",row[@"text"] ?: @""]);
}
- (BOOL)evaluationCurrent:(NSDictionary *)row {
    @synchronized(self.evaluationStates){return [self.evaluationStates[[self evaluationKey:row]] isEqual:@"current"];}
}
- (NSDictionary *)evaluationChecks:(NSString *)identifier snapshot:(NSDictionary *)snapshot api:(SSGitHub *)api {
    NSMutableDictionary *states=NSMutableDictionary.dictionary,*trees=NSMutableDictionary.dictionary;
    for(NSDictionary *row in [self savedScores]){
        if(![row[@"repository"] isEqual:identifier] || !AMPeerRecordApplies(row,snapshot) || (!row[@"remoteSources"] && ![@[@"teacher",@"comment",@"llm-external"] containsObject:row[@"kind"]]))continue;
        NSString *key=[self evaluationKey:row];if(states[key])continue;
        states[key]=@"unverified";NSError *error=nil;NSString *repository=row[@"sourceRepository"];
        if(row[@"remoteSources"]){
            BOOL current=YES;
            for(NSDictionary *source in row[@"remoteSources"]){NSString *repo=source[@"repository"],*commit=[repo isEqual:identifier] ? snapshot[@"commit"]:([repo isEqual:self.course[@"upstream"]] ? snapshot[@"teacherCommit"]:nil);if(!AMPeerSHA(commit)){current=NO;break;}
                NSString *cacheKey=[NSString stringWithFormat:@"%@|%@",repo,commit];NSDictionary *tree=trees[cacheKey];if(!tree){tree=[api peerTree:commit repository:repo error:&error];if(tree)trees[cacheKey]=tree;}BOOL found=NO;for(NSDictionary *file in tree[@"tree"])if([file[@"path"] isEqual:source[@"path"]] && [file[@"sha"] isEqual:source[@"sha"]])found=YES;if(!found){current=NO;break;}}
            states[key]=current ? @"current":@"changed";continue;
        }
        if(![repository isKindOfClass:NSString.class])continue;
        if([row[@"sourceKind"] isEqual:@"file"]){
            NSString *head=[repository isEqual:identifier] ? snapshot[@"commit"]:([repository isEqual:self.course[@"upstream"]] ? snapshot[@"teacherCommit"]:nil);
            if(!head){NSDictionary *details=[api repository:repository error:&error];NSString *branch=details[@"default_branch"];if(!branch.length)continue;NSString *encoded=[branch stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"]];NSDictionary *commit=[api readRepository:repository resource:[@"commits/" stringByAppendingString:encoded] error:&error];head=commit[@"sha"];}
            if(!AMPeerSHA(head) || !AMPeerPath(row[@"sourcePath"]))continue;
            NSString *treeKey=[NSString stringWithFormat:@"%@|%@",repository,head];NSDictionary *tree=trees[treeKey];if(!tree){tree=[api peerTree:head repository:repository error:&error];if(tree)trees[treeKey]=tree;}if(!tree)continue;
            states[key]=@"changed";for(NSDictionary *file in tree[@"tree"])if([file[@"path"] isEqual:row[@"sourcePath"]]){states[key]=[file[@"sha"] isEqual:row[@"sourceBlobSHA"]] ? @"current":@"changed";break;}
        }else if([row[@"sourceKind"] isEqual:@"issue-comment"] || [row[@"sourceKind"] isEqual:@"review-comment"] || [row[@"sourceKind"] isEqual:@"review"]){
            NSString *resource=row[@"sourceResource"];if(![resource isKindOfClass:NSString.class])continue;NSDictionary *comment=[api readRepository:repository resource:resource error:&error];NSString *body=[comment isKindOfClass:NSDictionary.class] ? comment[@"body"]:nil;if(![body isKindOfClass:NSString.class])continue;
            NSArray *range=row[@"sourceRange"];if([range isKindOfClass:NSArray.class] && range.count==2){NSUInteger location=[range[0] unsignedIntegerValue],length=[range[1] unsignedIntegerValue];if(location>body.length || length>body.length-location){states[key]=@"changed";continue;}body=[body substringWithRange:NSMakeRange(location,length)];}
            states[key]=[body isEqual:row[@"text"]] ? @"current":@"changed";
        }
    }
    return states;
}

- (NSArray *)discoverEvaluationsForPeer:(NSDictionary *)peer snapshot:(NSDictionary *)snapshot teacher:(NSDictionary *)teacher api:(SSGitHub *)api {
    NSString *repository=teacher[@"full_name"],*commit=snapshot[@"commit"];
    if(!AMPeerSHA(commit) || !repository.length || !peer[@"branch"] || !peer[@"login"])return @[];
    NSString *head=[[NSString stringWithFormat:@"%@:%@",peer[@"login"],peer[@"branch"]] stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"]];
    id pulls=[api readRepository:repository resource:[NSString stringWithFormat:@"pulls?state=all&per_page=10&head=%@",head] error:NULL];
    NSMutableArray *candidates=NSMutableArray.array;
    if([pulls isKindOfClass:NSArray.class])for(NSDictionary *pull in pulls){
        NSNumber *number=pull[@"number"];
        if(![number isKindOfClass:NSNumber.class] || number.integerValue<1 || ![pull[@"head"][@"repo"][@"id"] isEqual:peer[@"repositoryID"]] || ![pull[@"head"][@"sha"] isEqual:commit])continue;
        NSString *prefix=[NSString stringWithFormat:@"pulls/%@",number];
        id files=[api readRepository:repository resource:[prefix stringByAppendingString:@"/files?per_page=100"] error:NULL];
        BOOL exactScope=[files isKindOfClass:NSArray.class] && [files count]>0 && [files count]<100;
        if(exactScope)for(NSDictionary *file in files)if(!AMPeerInScope(file[@"filename"],self.scope))exactScope=NO;
        id reviews=[api readRepository:repository resource:[prefix stringByAppendingString:@"/reviews?per_page=30"] error:NULL];
        if(![reviews isKindOfClass:NSArray.class])continue;
        for(NSDictionary *review in reviews){
            NSNumber *identifier=review[@"id"];NSString *body=review[@"body"],*link=review[@"html_url"],*author=review[@"user"][@"login"];
            if(![identifier isKindOfClass:NSNumber.class] || identifier.integerValue<1 || ![body isKindOfClass:NSString.class] || !body.length || body.length>65536 || SSContainsSecret([body dataUsingEncoding:NSUTF8StringEncoding]) || ![link isKindOfClass:NSString.class] || ![author isKindOfClass:NSString.class])continue;
            if([author caseInsensitiveCompare:peer[@"login"]]==NSOrderedSame)continue;
            [candidates addObject:link];
            // A comment is automatically associated only when it comes from the teacher repository
            // owner and the review and its single-assignment change set both match the pinned answer.
            BOOL teacherOwned=[review[@"author_association"] isEqual:@"OWNER"] || (teacher[@"owner"][@"id"] && [review[@"user"][@"id"] isEqual:teacher[@"owner"][@"id"]]);
            if(!exactScope || !teacherOwned || ![review[@"commit_id"] isEqual:commit])continue;
            BOOL existing=NO;
            for(NSDictionary *old in [self savedScores])if([old[@"sourceID"] isEqual:link] && [old[@"commit"] isEqual:commit] && [old[@"text"] isEqual:body]){existing=YES;break;}
            if(existing)continue;
            NSMutableDictionary *record=[@{@"kind":@"comment",@"repository":peer[@"repository"],@"commit":commit,@"answerVersion":AMPeerAnswerVersion(snapshot),@"text":body,@"author":author,@"sourceID":link,@"sourceKind":@"review",@"sourceRepository":repository,@"sourceResource":[prefix stringByAppendingFormat:@"/reviews/%@",identifier],@"date":NSDate.date,@"sourceVerifiedAt":NSDate.date,@"confirmed":@YES} mutableCopy];
            if(![self saveScore:record.copy error:NULL])continue;
            NSDictionary *numbers=AMPeerTeacherNumbers(body);
            if(numbers[@"score"] && numbers[@"maximum"] && ![numbers[@"ambiguous"] boolValue]){
                record[@"kind"]=@"teacher";record[@"score"]=numbers[@"score"];record[@"maximum"]=numbers[@"maximum"];
                [self saveScore:record.copy error:NULL];
            }
        }
    }
    for(NSDictionary *file in snapshot[@"files"]){
        NSString *path=file[@"path"],*name=path.lastPathComponent.stringByDeletingPathExtension;
        if(!AMPeerInScope(path,self.scope) || [name rangeOfString:@"^(feedback|reviews?|评语|批改)([-_ ]?[0-9]+)?$" options:NSRegularExpressionSearch|NSCaseInsensitiveSearch].location==NSNotFound)continue;
        NSURLComponents *link=[NSURLComponents componentsWithString:[@"https://github.com/" stringByAppendingString:peer[@"repository"]]];
        link.path=[link.path stringByAppendingFormat:@"/blob/%@/%@",commit,path];
        if(link.URL.absoluteString)[candidates addObject:link.URL.absoluteString];
    }
    return candidates;
}
