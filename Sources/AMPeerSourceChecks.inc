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
