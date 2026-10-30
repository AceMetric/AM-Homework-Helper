- (id)readRepository:(NSString *)repository resource:(NSString *)resource error:(NSError **)error {
    BOOL valid=[repository rangeOfString:@"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$" options:NSRegularExpressionSearch].location!=NSNotFound && [resource isKindOfClass:NSString.class] && ![resource containsString:@".."] && ![resource containsString:@"#"] && ![resource containsString:@"\\"];
    // Explicit read-only surface; neither URLs nor caller-selected HTTP methods are accepted.
    BOOL allowed=NO;for(NSString *prefix in @[@"forks?",@"commits/",@"git/trees/",@"git/blobs/",@"compare/",@"issues/",@"pulls/"])if([resource hasPrefix:prefix])allowed=YES;
    if(!valid || !allowed){if(error)*error=GHError(@"只读仓库请求无效");return nil;}
    return [self api:[NSString stringWithFormat:@"/repos/%@/%@",repository,resource] error:error];
}
- (NSDictionary *)peerForks:(NSDictionary *)course page:(NSUInteger)page error:(NSError **)error {
    if(page<1 || page>100){if(error)*error=GHError(@"仓库列表页码无效");return nil;}
    NSDictionary *teacher=[self readableTeacher:course error:error];if(!teacher)return nil;
    id forks=[self readRepository:course[@"upstream"] resource:[NSString stringWithFormat:@"forks?per_page=100&page=%lu",(unsigned long)page] error:error];if(![forks isKindOfClass:NSArray.class])return nil;
    NSMutableArray *rows=NSMutableArray.array;for(id fork in forks)if([fork isKindOfClass:NSDictionary.class] && [fork[@"full_name"] isKindOfClass:NSString.class] && [fork[@"owner"][@"login"] isKindOfClass:NSString.class])[rows addObject:@{@"repository":fork[@"full_name"],@"repositoryID":fork[@"id"] ?: @0,@"login":fork[@"owner"][@"login"],@"branch":fork[@"default_branch"] ?: @"main",@"state":@"待核验"}];
    return @{@"peers":rows,@"more":@([forks count]==100),@"page":@(page),@"queriedAt":NSDate.date};
}
- (NSDictionary *)peerTree:(NSString *)commit repository:(NSString *)repository error:(NSError **)error {
    if(!AMPeerSHA(commit)){if(error)*error=GHError(@"提交版本无效");return nil;}
    if(self.expectedReadIdentity && ![self.expectedReadIdentity isEqual:self.authenticationIdentity]){if(error)*error=GHError(@"账户已变化，旧读取已停止");return nil;}
    NSString *cacheKey=[NSString stringWithFormat:@"%@|%@",repository,commit];if(self.peerImmutableCache){@synchronized(self.peerImmutableCache){NSDictionary *cached=self.peerImmutableCache[cacheKey];if(cached)return cached;}}
    NSDictionary *details=[self readRepository:repository resource:[@"commits/" stringByAppendingString:commit] error:error];if(![details isKindOfClass:NSDictionary.class])return nil;NSString *tree=details[@"commit"][@"tree"][@"sha"];if(!AMPeerSHA(tree))return nil;
    NSDictionary *result=[self readRepository:repository resource:[NSString stringWithFormat:@"git/trees/%@?recursive=1",tree] error:error];
    if(![result isKindOfClass:NSDictionary.class] || ![result[@"tree"] isKindOfClass:NSArray.class] || [result[@"truncated"] boolValue]){if(error && !*error)*error=GHError(@"文件列表未完整返回，作答状态待核验");return nil;}if(self.peerImmutableCache){@synchronized(self.peerImmutableCache){if(self.peerImmutableCache.count>=64)[self.peerImmutableCache removeAllObjects];self.peerImmutableCache[cacheKey]=result;}}return result;
}
- (NSDictionary *)peerSnapshot:(NSDictionary *)peer teacher:(NSDictionary *)teacher scope:(NSString *)scope error:(NSError **)error {
    if(!AMPeerPath(scope)){if(error)*error=GHError(@"请先选择明确的作业目录");return nil;}
    NSString *(^encode)(NSString *)=^NSString *(NSString *value){return [value stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"]];};
    NSDictionary *repository=[self repository:peer[@"repository"] error:error];if(!repository || ![repository[@"id"] isEqual:peer[@"repositoryID"]] || ![repository[@"parent"][@"id"] isEqual:teacher[@"id"]]){if(error && !*error)*error=GHError(@"仓库关联已变化，作答状态待核验");return nil;}
    NSDictionary *head=[self readRepository:peer[@"repository"] resource:[@"commits/" stringByAppendingString:encode(peer[@"branch"])] error:error];NSString *sha=head[@"sha"];if(!AMPeerSHA(sha))return nil;
    NSDictionary *base=[self readRepository:teacher[@"full_name"] resource:[@"commits/" stringByAppendingString:encode(teacher[@"default_branch"])] error:error];if(!AMPeerSHA(base[@"sha"]))return nil;
    // Pin the peer SHA, not its movable branch. A shared ancestor excludes teacher-only updates.
    NSString *comparison=[NSString stringWithFormat:@"compare/%@...%@:%@",base[@"sha"],encode(peer[@"login"]),sha];
    // compare uses three dots; it is composed here, never passed through a user path.
    NSString *token=[self accessToken:error];if(!token)return nil;
    NSDictionary *compare=[self requestURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://api.github.com/repos/%@/%@",teacher[@"full_name"],comparison]] form:nil token:token error:error];NSString *ancestor=compare[@"merge_base_commit"][@"sha"];if(!AMPeerSHA(ancestor))return nil;
    NSDictionary *current=[self peerTree:sha repository:peer[@"repository"] error:error],*original=current ? [self peerTree:ancestor repository:peer[@"repository"] error:error]:nil;if(!original)return nil;
    NSMutableDictionary *baseline=NSMutableDictionary.dictionary;for(NSDictionary *file in original[@"tree"])if([file[@"type"] isEqual:@"blob"] && AMPeerInScope(file[@"path"],scope))baseline[file[@"path"]]=file[@"sha"];
    NSMutableArray *files=NSMutableArray.array;BOOL changed=NO;
    for(NSDictionary *file in current[@"tree"])if([file[@"type"] isEqual:@"blob"] && AMPeerInScope(file[@"path"],scope) && AMPeerSHA(file[@"sha"])){
        BOOL different=![baseline[file[@"path"]] isEqual:file[@"sha"]];changed|=different;[files addObject:@{@"path":file[@"path"],@"sha":file[@"sha"],@"size":file[@"size"] ?: @0,@"changed":@(different)}];[baseline removeObjectForKey:file[@"path"]];
    }
    // 绑定这一份作业的老师材料，而不是老师仓库的全局 HEAD；其他作业更新不使评分失效。
    NSDictionary *teacherTree=[base[@"sha"] isEqual:ancestor] ? original:[self peerTree:base[@"sha"] repository:teacher[@"full_name"] error:error];if(!teacherTree)return nil;NSMutableArray *teacherFiles=NSMutableArray.array;
    for(NSDictionary *file in teacherTree[@"tree"])if([file[@"type"] isEqual:@"blob"] && (AMPeerInScope(file[@"path"],scope) || [file[@"path"] isEqual:teacher[@"sourcePath"]]))[teacherFiles addObject:file];
    // Deletion alone does not establish an answer. All files remain available on explicit selection.
    return @{@"commit":sha,@"teacherCommit":base[@"sha"],@"teacherVersion":AMPeerAnswerVersion(@{@"files":teacherFiles}),@"baseline":ancestor,@"scope":scope,@"files":files,@"state":changed ? @"发现作答":@"未发现作答",@"queriedAt":NSDate.date};
}
- (NSData *)peerBlob:(NSString *)sha repository:(NSString *)repository error:(NSError **)error {
    if(!AMPeerSHA(sha)){if(error)*error=GHError(@"文件版本无效");return nil;}
    NSDictionary *blob=[self readRepository:repository resource:[@"git/blobs/" stringByAppendingString:sha] error:error];
    if(![blob isKindOfClass:NSDictionary.class] || ![blob[@"sha"] isEqual:sha] || ![blob[@"encoding"] isEqual:@"base64"] || [blob[@"size"] unsignedLongLongValue]>20*1024*1024 || ![blob[@"content"] isKindOfClass:NSString.class]){if(error && !*error)*error=GHError(@"文件过大或不可读取，请在 GitHub 查看");return nil;}
    NSData *bytes=[[NSData alloc] initWithBase64EncodedString:blob[@"content"] options:NSDataBase64DecodingIgnoreUnknownCharacters];if(bytes.length!=[blob[@"size"] unsignedLongLongValue]){if(error)*error=GHError(@"文件未完整返回");return nil;}return bytes;
}
