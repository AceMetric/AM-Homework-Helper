- (NSDictionary *)submissionDetailsForCourse:(NSDictionary *)course commit:(NSString *)commit error:(NSError **)error {
    if(![commit isKindOfClass:NSString.class] || !commit.length || [commit rangeOfString:@"^[a-f0-9]{40,64}$" options:NSRegularExpressionSearch].location==NSNotFound || ![self validateCourse:course error:error] || ![self submissionBranch:course error:error])return nil;
    SSGitResult *files=[self checked:@[@"diff-tree",@"--root",@"-m",@"--no-commit-id",@"--name-only",@"-r",@"-z",commit,@"--"] in:course[@"path"] token:nil error:error];
    SSGitResult *message=[self checked:@[@"log",@"-1",@"--format=%B",commit,@"--"] in:course[@"path"] token:nil error:error];if(!files || !message)return nil;
    return @{@"files":[NSOrderedSet orderedSetWithArray:NonemptyParts([self string:files],@"\0")].array,@"message":Trim([self string:message])};
}
- (NSArray *)recentCommits:(NSDictionary *)course error:(NSError **)error {
    if(![self validateCourse:course error:error] || ![self submissionBranch:course error:error])return nil;
    SSGitResult *result=[self checked:@[@"log",@"-50",@"--format=%H%x00%s",@"HEAD",@"--"] in:course[@"path"] token:nil error:error];if(!result)return nil;
    NSMutableArray *rows=NSMutableArray.array;for(NSString *line in NonemptyParts([self string:result],@"\n")){NSArray *parts=[line componentsSeparatedByString:@"\0"];if(parts.count==2 && !SSContainsSecret([parts[1] dataUsingEncoding:NSUTF8StringEncoding]))[rows addObject:@{@"commit":parts[0],@"message":SSRedactedText(parts[1])}];}return rows;
}
- (NSDictionary *)verifySubmission:(NSDictionary *)record course:(NSDictionary *)course token:(NSString *)token retry:(BOOL)retry error:(NSError **)error {
    if(![record[@"repository"] isEqual:course[@"fork"]] || ![record[@"branch"] isEqual:course[@"branch"]] || ![self authorize:course error:error] || ![self validateCourse:course error:error] || ![self submissionBranch:course error:error])return nil;
    NSMutableDictionary *next=record.mutableCopy;
    NSString *commit=record[@"commit"];
    if(!commit.length && [record[@"before"] length]){
        // Recover only an exact immediate child with matching message and file set.
        SSGitResult *head=[self checked:@[@"rev-parse",@"HEAD"] in:course[@"path"] token:nil error:error];NSString *tip=Trim([self string:head]);
        SSGitResult *parent=[self run:@[@"rev-parse",@"HEAD^"] in:course[@"path"] token:nil error:NULL];
        SSGitResult *msg=[self run:@[@"log",@"-1",@"--format=%B",@"HEAD",@"--"] in:course[@"path"] token:nil error:NULL];
        SSGitResult *files=[self run:@[@"diff-tree",@"--no-commit-id",@"--name-only",@"-r",@"-z",@"HEAD",@"--"] in:course[@"path"] token:nil error:NULL];
        if(head && parent.status==0 && [Trim([self string:parent]) isEqual:record[@"before"]] && [Trim([self string:msg]) isEqual:record[@"message"]] && [[NSSet setWithArray:NonemptyParts([self string:files],@"\0")] isEqual:[NSSet setWithArray:record[@"files"]]]){commit=tip;next[@"commit"]=tip;next[@"state"]=@"local";if(!AMStoreSubmission(next,error))return nil;}
    }
    if(!commit.length){next[@"state"]=@"uncertain";next[@"issue"]=@"local-unresolved";if(!AMStoreSubmission(next,error))return nil;return next;}
    if([commit rangeOfString:@"^[a-f0-9]{40,64}$" options:NSRegularExpressionSearch].location==NSNotFound)return nil;
    NSString *url=[NSString stringWithFormat:@"https://github.com/%@.git",course[@"fork"]];NSString *remote=[self fetch:url branch:course[@"branch"] path:course[@"path"] token:token error:error];if(!remote)return nil;
    SSGitResult *contains=[self run:@[@"merge-base",@"--is-ancestor",commit,remote] in:course[@"path"] token:nil error:error];if(!contains || contains.status>1)return nil;
    next[@"checkedAt"]=NSDate.date;next[@"remoteCommit"]=remote;
    if(contains.status==0){next[@"state"]=@"confirmed";next[@"confirmedAt"]=record[@"confirmedAt"] ?: NSDate.date;[next removeObjectForKey:@"issue"];}
    else if(retry){
        SSGitResult *head=[self checked:@[@"rev-parse",@"HEAD"] in:course[@"path"] token:nil error:error];if(!head || ![Trim([self string:head]) isEqual:commit]){if(error)*error=GitError(@"本地分支已变化，重试不会推送其他提交。请检查后通过课程提交流程处理。");return nil;}
        if(![self pushCourse:course token:token error:error])return nil;
        return [self verifySubmission:next course:course token:token retry:NO error:error];
    }else{next[@"state"]=@"local";next[@"issue"]=record[@"confirmedAt"] ? @"remote-changed":@"not-on-remote";}
    if(!AMStoreSubmission(next,error))return nil;return next;
}
- (NSDictionary *)performRecordedCourse:(NSDictionary *)course kind:(NSString *)kind taskIDs:(NSArray *)taskIDs paths:(NSArray *)paths message:(NSString *)message token:(NSString *)token login:(NSString *)login userID:(NSNumber *)userID error:(NSError **)error {
    if(![course[@"fork"] isKindOfClass:NSString.class] || ![course[@"branch"] isKindOfClass:NSString.class]){if(error)*error=GitError(@"课程目标不完整，请重新关联课程。");return nil;}
    NSMutableDictionary *record=[@{@"id":NSUUID.UUID.UUIDString,@"repository":course[@"fork"],@"branch":course[@"branch"],@"kind":kind,@"state":@"running",@"message":message ?: @"",@"date":NSDate.date,@"files":paths ?: @[],@"taskIDs":taskIDs ?: @[]} mutableCopy];
    if(!AMStoreSubmission(record,error))return nil;
    self.submissionCheckpoint=^BOOL(NSDictionary *fields,NSError **failure){[record addEntriesFromDictionary:fields];return AMStoreSubmission(record,failure);};
    BOOL ok=NO;NSError *failure=nil;
    @try {
        if([kind isEqual:@"submission"])ok=[self commitCourse:course paths:paths message:message login:login userID:userID token:token error:&failure];
        else if([kind isEqual:@"sync"]){NSDictionary *result=[self syncCourse:course token:token error:&failure];ok=[result[@"success"] boolValue];if(result[@"conflicts"]){record[@"issue"]=@"merge-conflict";record[@"conflicts"]=result[@"conflicts"];record[@"mergeHead"]=result[@"mergeHead"];}}
        else if([kind isEqual:@"merge"])ok=[self continueMergeForCourse:course token:token error:&failure];
    }@finally{self.submissionCheckpoint=nil;}
    if(!ok){if([record[@"state"] isEqual:@"running"])record[@"state"]=record[@"commit"] ? @"local":@"failed";record[@"issue"]=record[@"issue"] ?: (failure.userInfo[@"SSIssue"] ?: @"operation-failed");NSError *saveError=nil;if(!AMStoreSubmission(record,&saveError))failure=saveError;if(error)*error=failure;return record;}
    NSDictionary *verified=[self verifySubmission:record course:course token:token retry:NO error:&failure];
    if(!verified){record[@"state"]=@"uncertain";record[@"issue"]=@"verification-pending";NSError *saveError=nil;if(!AMStoreSubmission(record,&saveError))failure=saveError;if(error)*error=failure;return record;}return verified;
}
