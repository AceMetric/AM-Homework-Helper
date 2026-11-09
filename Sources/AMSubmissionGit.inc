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
- (NSArray *)externalCommits:(NSDictionary *)course offset:(NSUInteger)offset error:(NSError **)error {
    self.historyCompletionFiles=nil;
    if(![self validateCourse:course error:error] || offset>100000)return nil;
    NSString *root=course[@"path"];
    NSDictionary *snapshot=offset ? self.externalHistorySnapshot:nil;
    if(!snapshot){
        NSString *ref=[@"refs/heads/" stringByAppendingString:course[@"branch"]];
        SSGitResult *tip=[self checked:@[@"rev-parse",@"--verify",[ref stringByAppendingString:@"^{commit}"]] in:root token:nil error:error];
        if(!tip)return nil;
        NSString *upstream=AMPeerSHA(course[@"teacherCommit"]) ? course[@"teacherCommit"]:
            [@"refs/remotes/upstream/" stringByAppendingString:course[@"upstreamBranch"] ?: course[@"branch"]];
        SSGitResult *teacher=[self run:@[@"rev-parse",@"--verify",[upstream stringByAppendingString:@"^{commit}"]] in:root token:nil error:NULL];
        snapshot=@{@"head":Trim([self string:tip]),@"teacher":teacher && teacher.status==0 ? Trim([self string:teacher]):@""};
    }
    NSMutableArray *args=[@[@"log",@"-50",[NSString stringWithFormat:@"--skip=%lu",(unsigned long)offset],@"--no-show-signature",@"--format=%H%x00%ct%x00%P%x00%s",snapshot[@"head"]] mutableCopy];
    BOOL known=AMPeerSHA(snapshot[@"teacher"]);
    if(known)[args addObject:[@"^" stringByAppendingString:snapshot[@"teacher"]]];
    [args addObject:@"--"];
    SSGitResult *result=[self checked:args in:root token:nil error:error];
    if(!result)return nil;

    NSMutableArray *metadata=NSMutableArray.array;
    NSMutableDictionary *paths=NSMutableDictionary.dictionary,*completion=NSMutableDictionary.dictionary;
    NSMutableString *input=NSMutableString.string;
    for(NSString *line in NonemptyParts([self string:result],@"\n")){
        NSArray *fields=[line componentsSeparatedByString:@"\0"];
        if(fields.count!=4 || !AMPeerSHA(fields[0]) || SSContainsSecret([fields[3] dataUsingEncoding:NSUTF8StringEncoding]))continue;
        [metadata addObject:fields];
        paths[fields[0]]=NSMutableOrderedSet.orderedSet;
        if(NonemptyParts(fields[2],@" ").count<=1)completion[fields[0]]=NSMutableOrderedSet.orderedSet;
        [input appendFormat:@"%@\n",fields[0]];
    }
    if(input.length){
        // Status tokens delimit each path, including paths that look like a commit ID.
        SSGitResult *changes=[self run:@[@"diff-tree",@"--stdin",@"--root",@"-m",@"--always",@"-r",@"--name-status",@"-z"] input:[input dataUsingEncoding:NSUTF8StringEncoding] in:root token:nil error:error];
        if(!changes || changes.status!=0){
            if(changes && error && !*error)*error=GitError(@"无法批量读取此页的文件变更，请重试。");
            return nil;
        }
        NSArray *fields=[[self string:changes] componentsSeparatedByString:@"\0"];
        NSMutableOrderedSet *current=nil,*answerPaths=nil;
        NSUInteger headers=0;
        NSMutableSet *seen=NSMutableSet.set;
        for(NSUInteger i=0;i<fields.count;){
            NSString *field=fields[i++];
            if(!field.length && i==fields.count)break;
            if(paths[field]){current=paths[field];answerPaths=completion[field];[seen addObject:field];headers++;continue;}
            unichar status=field.length ? [field characterAtIndex:0]:0;
            NSUInteger count=(status=='R' || status=='C') ? 2:1;
            if(!current || !status || [@"ACDMRTUXB" rangeOfString:[field substringToIndex:1]].location==NSNotFound || i+count>=fields.count){
                if(error)*error=GitError(@"此页文件变更不完整，请重试。");
                return nil;
            }
            // Git's name-only output shows the destination for detected copies and renames.
            NSString *path=fields[i+count-1];i+=count;
            if(!SSSensitivePath(path) && ![path hasPrefix:@"/"] && ![[path componentsSeparatedByString:@"/"] containsObject:@".."]){
                [current addObject:path];
                if([@"AMRT" rangeOfString:[field substringToIndex:1]].location!=NSNotFound)[answerPaths addObject:path];
            }
        }
        if(headers<metadata.count || seen.count!=metadata.count){
            if(error)*error=GitError(@"此页缺少提交的文件变更，请重试。");
            return nil;
        }
    }
    NSMutableArray *rows=NSMutableArray.array;
    for(NSArray *p in metadata){
        NSArray *parents=NonemptyParts(p[2],@" ");
        [rows addObject:@{@"commit":p[0],@"message":SSRedactedText(p[3]),@"date":[NSDate dateWithTimeIntervalSince1970:[p[1] doubleValue]],@"files":[paths[p[0]] array],@"kind":parents.count>1 ? @"merge":@"existing",@"origin":@"external",@"teacherHistoryKnown":@(known)}];
    }
    NSMutableDictionary *answers=NSMutableDictionary.dictionary;
    for(NSArray *p in metadata)answers[p[0]]=[completion[p[0]] array] ?: @[];
    self.historyCompletionFiles=answers.copy;
    self.externalHistorySnapshot=snapshot;
    return rows;
}

// Only additions and modifications can provide completion evidence; deleted answers cannot.
- (NSArray *)completionFiles:(NSDictionary *)course commit:(NSString *)commit error:(NSError **)error {
    NSArray *batched=self.historyCompletionFiles[commit];if(batched)return batched;
    SSGitResult *result=[self checked:@[@"diff-tree",@"--root",@"--no-commit-id",@"--name-only",@"-r",@"-z",@"--diff-filter=AMRT",commit,@"--"] in:course[@"path"] token:nil error:error];if(!result)return nil;
    NSMutableArray *safe=NSMutableArray.array;for(NSString *path in NonemptyParts([self string:result],@"\0"))if(!SSSensitivePath(path) && ![path hasPrefix:@"/"] && ![[path componentsSeparatedByString:@"/"] containsObject:@".."]) [safe addObject:path];return [NSOrderedSet orderedSetWithArray:safe].array;
}
// Cached teacher refs can lag a terminal fast-forward. Fetch only the validated
// upstream through its existing read-only credential route before inferring ownership.
- (NSDictionary *)completionSourceCourse:(NSDictionary *)course {
    NSMutableDictionary *source=course.mutableCopy;source[@"completionTeacherFresh"]=@NO;if(course[@"teacherCommit"])source[@"completionPriorTeacherCommit"]=course[@"teacherCommit"];
    NSString *url=[self teacherURL:course path:course[@"path"] error:NULL];NSString *branch=url ? [self teacherBranch:url course:course error:NULL]:nil;
    if(branch && [self teacherRequest:@[@"fetch",@"--no-tags",@"--",url,[@"refs/heads/" stringByAppendingString:branch]] course:course error:NULL]){SSGitResult *tip=[self checked:@[@"rev-parse",@"FETCH_HEAD"] in:course[@"path"] token:nil error:NULL];if(tip){source[@"teacherCommit"]=Trim([self string:tip]);source[@"completionTeacherFresh"]=@YES;}}
    return source;
}
// A user association never turns a teacher commit or merge into an answer submission.
- (void)classifyCompletionOwnership:(NSMutableDictionary *)record course:(NSDictionary *)course {
    NSString *teacher=course[@"teacherCommit"];
    if(![teacher isKindOfClass:NSString.class] || [teacher rangeOfString:@"^[a-f0-9]{40,64}$" options:NSRegularExpressionSearch].location==NSNotFound){NSString *ref=[@"refs/remotes/upstream/" stringByAppendingString:course[@"upstreamBranch"] ?: course[@"branch"]];SSGitResult *tip=[self run:@[@"rev-parse",@"--verify",ref] in:course[@"path"] token:nil error:NULL];teacher=tip.status==0 ? Trim([self string:tip]):nil;}
    SSGitResult *parents=[self run:@[@"rev-list",@"--parents",@"-n",@"1",record[@"commit"],@"--"] in:course[@"path"] token:nil error:NULL];BOOL merge=parents.status!=0 || NonemptyParts(Trim([self string:parents]),@" ").count>2;
    SSGitResult *ancestor=teacher ? [self run:@[@"merge-base",@"--is-ancestor",record[@"commit"],teacher] in:course[@"path"] token:nil error:NULL]:nil;
    BOOL priorTeacher=NO;NSString *prior=course[@"completionPriorTeacherCommit"];if(prior && ![prior isEqual:teacher]){SSGitResult *old=[self run:@[@"merge-base",@"--is-ancestor",record[@"commit"],prior] in:course[@"path"] token:nil error:NULL];priorTeacher=old && old.status==0;}
    BOOL fresh=!course[@"completionTeacherFresh"] || [course[@"completionTeacherFresh"] boolValue];record[@"teacherHistoryKnown"]=@(fresh && ancestor && ancestor.status<=1);record[@"teacherHistoryExcluded"]=@([record[@"teacherHistoryExcluded"] boolValue] || merge || priorTeacher || (ancestor && ancestor.status==0));
}
- (NSArray *)verifyExternalRecords:(NSArray *)records course:(NSDictionary *)course token:(NSString *)token error:(NSError **)error {
    NSTimeInterval savedTimeout=self.commandTimeout;NSDate *savedDeadline=self.commandDeadline;NSTimeInterval budget=savedTimeout>0 ? MIN(savedTimeout,180):180;self.commandDeadline=[NSDate dateWithTimeIntervalSinceNow:budget];if(savedDeadline && [savedDeadline compare:self.commandDeadline]==NSOrderedAscending)self.commandDeadline=savedDeadline;
    @try{self.commandTimeout=15;
    if(![self authorize:course error:error] || ![self validateCourse:course error:error])return nil;
    self.commandTimeout=budget;NSString *remote=[self fetch:[NSString stringWithFormat:@"https://github.com/%@.git",course[@"fork"]] branch:course[@"branch"] path:course[@"path"] token:token error:error];if(!remote)return nil;self.commandTimeout=15;
    NSDictionary *automation=AMSubmissionAutomation(error),*baseline=AMSubmissionBaseline(course,error);if(!automation || !baseline)return nil;NSString *epoch=automation[@"epoch"] ?: @"initial";
    BOOL reset=!baseline.count;
    if(!reset){SSGitResult *ancestry=[self run:@[@"merge-base",@"--is-ancestor",baseline[@"tip"],remote] in:course[@"path"] token:nil error:error];if(!ancestry)return nil;reset=ancestry.status!=0;}
    NSString *anchor=reset ? remote:baseline[@"anchor"];
    self.commandTimeout=budget;NSDictionary *source=records.count ? [self completionSourceCourse:course]:course;self.commandTimeout=15;
    NSMutableArray *verified=NSMutableArray.array;
    for(NSDictionary *record in records){if(![record[@"repository"] isEqual:course[@"fork"]] || ![record[@"branch"] isEqual:course[@"branch"]])continue;NSString *commit=record[@"commit"];if(![commit isKindOfClass:NSString.class] || [commit rangeOfString:@"^[a-f0-9]{40,64}$" options:NSRegularExpressionSearch].location==NSNotFound)continue;
        SSGitResult *contains=[self run:@[@"merge-base",@"--is-ancestor",commit,remote] in:course[@"path"] token:nil error:error];if(!contains || contains.status>1)return nil;NSMutableDictionary *next=record.mutableCopy;self.lastWorkflowRecord=next;next[@"checkedAt"]=NSDate.date;next[@"remoteCommit"]=remote;next[@"completionAnchor"]=anchor;next[@"completionEpoch"]=[record[@"completionEligibility"] isEqual:@"associated"] ? (record[@"completionEpoch"] ?: @"initial"):epoch;[self classifyCompletionOwnership:next course:source];next[@"state"]=contains.status==0 ? @"confirmed":@"local";
        if(![record[@"completionEligibility"] isEqual:@"associated"]){
            SSGitResult *historical=[self run:@[@"merge-base",@"--is-ancestor",commit,anchor] in:course[@"path"] token:nil error:error];if(!historical || historical.status>1)return nil;
            next[@"completionEligibility"]=AMSubmissionAutoCompletionEnabled() && historical.status==1 ? @"new":@"historical";
        }
        NSArray *completion=[self completionFiles:course commit:commit error:error];if(!completion)return nil;next[@"completionFiles"]=[completion filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *file,NSDictionary *bindings){return [record[@"files"] containsObject:file];}]];
        if(contains.status==0){next[@"confirmedAt"]=record[@"confirmedAt"] ?: NSDate.date;next[@"verifiedAt"]=next[@"checkedAt"];[next removeObjectForKey:@"issue"];}else next[@"issue"]=record[@"confirmedAt"] ? @"remote-changed":@"not-on-remote";[verified addObject:next];
    }if(!AMStoreSubmissionBaseline(course,@{@"anchor":anchor,@"tip":remote},baseline,epoch,error))return nil;return verified;
    }@finally{self.commandTimeout=savedTimeout;self.commandDeadline=savedDeadline;}
}
- (NSArray *)classifyExternalRecords:(NSArray *)records course:(NSDictionary *)course {
    NSString *teacher=course[@"teacherCommit"];if(![self validateCourse:course error:NULL] || ![teacher isKindOfClass:NSString.class] || [teacher rangeOfString:@"^[a-f0-9]{40,64}$" options:NSRegularExpressionSearch].location==NSNotFound)return @[];
    NSMutableArray *result=NSMutableArray.array;for(NSDictionary *record in records)if([record[@"origin"] isEqual:@"external"] && ![record[@"teacherHistoryKnown"] boolValue] && [record[@"repository"] isEqual:course[@"fork"]] && [record[@"branch"] isEqual:course[@"branch"]]){
        SSGitResult *ancestor=[self run:@[@"merge-base",@"--is-ancestor",record[@"commit"],teacher] in:course[@"path"] token:nil error:NULL];if(!ancestor || ancestor.status>1)continue;NSMutableDictionary *copy=record.mutableCopy;copy[@"teacherHistoryKnown"]=@YES;copy[@"teacherHistoryExcluded"]=@([record[@"teacherHistoryExcluded"] boolValue] || ancestor.status==0);[result addObject:copy];
    }
    return result;
}
- (NSDictionary *)verifySubmission:(NSDictionary *)record course:(NSDictionary *)course token:(NSString *)token retry:(BOOL)retry error:(NSError **)error {
    if(![record[@"repository"] isEqual:course[@"fork"]] || ![record[@"branch"] isEqual:course[@"branch"]] || ![self authorize:course error:error] || ![self validateCourse:course error:error] || ![self submissionBranch:course error:error])return nil;
    NSMutableDictionary *next=record.mutableCopy;self.lastWorkflowRecord=next;
    NSString *commit=record[@"commit"];
    if(!commit.length && [record[@"before"] length]){
        // Recover only an exact immediate child with matching message and file set.
        SSGitResult *head=[self checked:@[@"rev-parse",@"HEAD"] in:course[@"path"] token:nil error:error];NSString *tip=Trim([self string:head]);
        if(head && [tip isEqual:record[@"before"]]){next[@"state"]=@"failed";next[@"issue"]=@"not-committed";self.lastWorkflowRecord=next;if(!AMStoreSubmission(next,error))return nil;return next;}
        SSGitResult *parent=[self run:@[@"rev-parse",@"HEAD^"] in:course[@"path"] token:nil error:NULL];
        SSGitResult *msg=[self run:@[@"log",@"-1",@"--format=%B",@"HEAD",@"--"] in:course[@"path"] token:nil error:NULL];
        SSGitResult *files=[self run:@[@"diff-tree",@"--no-commit-id",@"--name-only",@"-r",@"-z",@"HEAD",@"--"] in:course[@"path"] token:nil error:NULL];
        if(head && parent && msg && files && parent.status==0 && msg.status==0 && files.status==0 && [Trim([self string:parent]) isEqual:record[@"before"]] && [Trim([self string:msg]) isEqual:record[@"message"]] && [[NSSet setWithArray:NonemptyParts([self string:files],@"\0")] isEqual:[NSSet setWithArray:record[@"files"]]]){commit=tip;next[@"commit"]=tip;next[@"state"]=@"local";next[@"issue"]=@"index-recovery-needed";if(!AMStoreSubmission(next,error))return nil;}
    }
    if(!commit.length){next[@"state"]=@"uncertain";next[@"issue"]=@"local-unresolved";self.lastWorkflowRecord=next;if(!AMStoreSubmission(next,error))return nil;return next;}
    if([commit rangeOfString:@"^[a-f0-9]{40,64}$" options:NSRegularExpressionSearch].location==NSNotFound)return nil;
    NSString *url=[NSString stringWithFormat:@"https://github.com/%@.git",course[@"fork"]];NSString *remote=[self fetch:url branch:course[@"branch"] path:course[@"path"] token:token error:error];if(!remote)return nil;
    SSGitResult *contains=[self run:@[@"merge-base",@"--is-ancestor",commit,remote] in:course[@"path"] token:nil error:error];if(!contains || contains.status>1)return nil;
    NSArray *completion=[self completionFiles:course commit:commit error:error];if(!completion)return nil;next[@"completionFiles"]=[completion filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *file,NSDictionary *bindings){return [record[@"files"] containsObject:file];}]];
    NSDictionary *source=[record[@"kind"] isEqual:@"existing"] || [record[@"origin"] isEqual:@"external"] ? [self completionSourceCourse:course]:course;[self classifyCompletionOwnership:next course:source];
    next[@"checkedAt"]=NSDate.date;next[@"remoteCommit"]=remote;
    if(contains.status==0){next[@"state"]=@"confirmed";next[@"confirmedAt"]=record[@"confirmedAt"] ?: NSDate.date;next[@"verifiedAt"]=next[@"checkedAt"];[next removeObjectForKey:@"issue"];}
    else if(retry){
        SSGitResult *head=[self checked:@[@"rev-parse",@"HEAD"] in:course[@"path"] token:nil error:error];if(!head || ![Trim([self string:head]) isEqual:commit]){if(error)*error=GitError(@"本地分支已变化，重试不会推送其他提交。请检查后通过课程提交流程处理。");return nil;}
        // An explicit retry may reconcile our interrupted temporary index. A
        // read-only verification never changes the worktree or its index.
        // The interrupted commit used a temporary index. Reconcile only when the
        // real index is still exactly the previously verified, untouched base tree.
        // Foreign staged changes and shared lock files are never removed.
        if([next[@"issue"] isEqual:@"index-recovery-needed"]){
            SSGitResult *tip=[self checked:@[@"rev-parse",@"HEAD"] in:course[@"path"] token:nil error:error];if(!tip)return nil;
            if([Trim([self string:tip]) isEqual:commit]){SSGitResult *unchanged=[self run:@[@"diff",@"--cached",@"--quiet",record[@"before"],@"--"] in:course[@"path"] token:nil error:error];if(!unchanged)return nil;
                if(unchanged.status==0){NSMutableArray *reset=[@[@"reset",@"--quiet",commit,@"--"] mutableCopy];[reset addObjectsFromArray:record[@"files"]];if(![self checked:reset in:course[@"path"] token:nil error:error])return nil;}
            }[next removeObjectForKey:@"issue"];if(!AMStoreSubmission(next,error))return nil;
        }
        if(![self pushCourse:course expectedHead:commit token:token error:error])return nil;
        return [self verifySubmission:next course:course token:token retry:NO error:error];
    }else{next[@"state"]=@"local";next[@"issue"]=record[@"confirmedAt"] ? @"remote-changed":@"not-on-remote";}
    next[@"workflowResult"]=[next[@"state"] isEqual:@"confirmed"] ? @"completed":([next[@"state"] isEqual:@"local"] ? @"needs-action":@"uncertain");next[@"workflowStage"]=@"verify";self.lastWorkflowRecord=next;if(!AMStoreSubmission(next,error))return nil;return next;
}
- (NSDictionary *)performRecordedCourse:(NSDictionary *)course kind:(NSString *)kind taskIDs:(NSArray *)taskIDs paths:(NSArray *)paths message:(NSString *)message token:(NSString *)token login:(NSString *)login userID:(NSNumber *)userID error:(NSError **)error {
    if(![course[@"fork"] isKindOfClass:NSString.class] || ![course[@"branch"] isKindOfClass:NSString.class]){if(error)*error=GitError(@"课程目标不完整，请重新关联课程。");return nil;}
    if([kind isEqual:@"submission"])for(NSDictionary *pending in AMSubmissionRecords(NULL))if([pending[@"repository"] isEqual:course[@"fork"]] && [pending[@"branch"] isEqual:course[@"branch"]] && [pending[@"before"] length] && ![pending[@"commit"] length] && [@[@"running",@"uncertain"] containsObject:pending[@"state"]] && [[NSSet setWithArray:paths] intersectsSet:[NSSet setWithArray:pending[@"files"]]]){
        NSDictionary *resolved=[self verifySubmission:pending course:course token:token retry:NO error:NULL];if(![resolved[@"state"] isEqual:@"failed"]){if(error)*error=[NSError errorWithDomain:@"SSGit" code:2 userInfo:@{NSLocalizedDescriptionKey:@"此前提交的结果需要核验，请在提交记录中继续；未再次创建提交。",@"SSPendingPush":@YES}];return nil;}
    }
    if([kind isEqual:@"submission"])for(NSDictionary *pending in AMSubmissionRecords(NULL))if([pending[@"repository"] isEqual:course[@"fork"]] && [pending[@"branch"] isEqual:course[@"branch"]] && [pending[@"commit"] length] && [@[@"running",@"local",@"uncertain"] containsObject:pending[@"state"]] && [[NSSet setWithArray:paths] intersectsSet:[NSSet setWithArray:pending[@"files"]]]){self.lastWorkflowRecord=pending;if(error)*error=AMWorkflowError(@"verification-pending",@"已有本地提交，请先核验推送",nil);return nil;}
    NSMutableDictionary *record=[@{@"id":NSUUID.UUID.UUIDString,@"repository":course[@"fork"],@"branch":course[@"branch"],@"kind":kind,@"state":@"running",@"workflowStage":@"prepare",@"workflowResult":@"needs-action",@"message":message ?: @"",@"date":NSDate.date,@"files":paths ?: @[],@"taskIDs":taskIDs ?: @[]} mutableCopy];
    record[@"completionEpoch"]=AMSubmissionAutomation(NULL)[@"epoch"] ?: @"initial";
    record[@"completionEligibility"]=[kind isEqual:@"submission"] && AMSubmissionAutoCompletionEnabled() ? @"new":@"historical";
    if([kind isEqual:@"submission"] && self.submissionReviewSummary)record[@"review"]=self.submissionReviewSummary;
    self.lastWorkflowRecord=record;if(!AMStoreSubmission(record,error))return nil;
    self.submissionCheckpoint=^BOOL(NSDictionary *fields,NSError **failure){[record addEntriesFromDictionary:fields];return AMStoreSubmission(record,failure);};
    BOOL ok=NO;NSError *failure=nil;
    @try {
        if([kind isEqual:@"submission"])ok=[self commitCourse:course paths:paths message:message login:login userID:userID token:token error:&failure];
        else if([kind isEqual:@"sync"]){NSDictionary *result=[self syncCourse:course token:token error:&failure];ok=[result[@"success"] boolValue];if(result[@"conflicts"]){record[@"issue"]=@"merge-conflict";record[@"conflicts"]=result[@"conflicts"];record[@"mergeHead"]=result[@"mergeHead"];}}
        else if([kind isEqual:@"merge"])ok=[self continueMergeForCourse:course token:token error:&failure];
    }@finally{self.submissionCheckpoint=nil;self.expectedSubmissionSnapshot=nil;self.submissionReviewSummary=nil;}
    if(!ok){if([record[@"state"] isEqual:@"running"])record[@"state"]=record[@"commit"] ? @"local":([record[@"before"] length] ? @"uncertain":@"failed");record[@"issue"]=record[@"issue"] ?: AMWorkflowIssue(failure);record[@"workflowResult"]=([record[@"commit"] length] || [record[@"before"] length]) ? @"uncertain":([AMWorkflowIssue(failure) isEqual:@"cancelled"] ? @"cancelled":@"failed");record[@"workflowStage"]=record[@"commit"] ? @"push":(record[@"before"] ? @"commit":([record[@"localUpdated"] boolValue] ? @"merge":@"prepare"));NSError *saveError=nil;if(!AMStoreSubmission(record,&saveError))failure=saveError;if(error)*error=failure;return record;}
    NSDictionary *verified=[self verifySubmission:record course:course token:token retry:NO error:&failure];
    if(!verified){if([self.lastWorkflowRecord[@"state"] isEqual:@"confirmed"]){if(error)*error=failure;return self.lastWorkflowRecord;}record[@"state"]=@"uncertain";record[@"issue"]=@"verification-pending";NSError *saveError=nil;if(!AMStoreSubmission(record,&saveError))failure=saveError;if(error)*error=failure;return record;}return verified;
}
