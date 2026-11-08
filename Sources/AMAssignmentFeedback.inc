// Feedback is read from immutable Git objects, so a dirty worktree cannot change what is shown.
- (NSArray *)assignmentFeedbackForCourse:(NSDictionary *)course scope:(NSString *)scope login:(NSString *)login remote:(NSString *)remote error:(NSError **)error {
    if(!AMPeerPath(scope) || SSSensitivePath(scope) || ![self validateCourse:course error:error])return nil;
    NSString *root=course[@"path"];
    NSString *originRef=[@"refs/remotes/origin/" stringByAppendingString:course[@"branch"]];
    NSString *upstreamRef=[@"refs/remotes/upstream/" stringByAppendingString:course[@"upstreamBranch"] ?: course[@"branch"]];
    NSString *personal=Trim([self string:[self checked:@[@"rev-parse",@"--verify",originRef] in:root token:nil error:NULL]]);
    if(!AMPeerSHA(personal))personal=remote;
    else if(AMPeerSHA(remote) && ![remote isEqual:personal]){
        SSGitResult *newer=[self run:@[@"merge-base",@"--is-ancestor",personal,remote] in:root token:nil error:NULL];
        if(newer && newer.status==0)personal=remote;
    }
    NSString *teacher=course[@"teacherCommit"];
    if(!AMPeerSHA(teacher))teacher=Trim([self string:[self checked:@[@"rev-parse",@"--verify",upstreamRef] in:root token:nil error:error]]);
    if(!AMPeerSHA(personal) || !AMPeerSHA(teacher)){
        if(error)*error=GitError(@"课程的远端快照不完整，请先更新课程文件后重试。");
        return nil;
    }
    NSArray *arguments=@[@"log",@"-60",@"--no-merges",@"--no-show-signature",@"--no-renames",@"--diff-filter=AM",@"--name-only",@"-z",@"--format=%x1e%H%x1f%an%x1f%ae%x1f%s",personal,[@"^" stringByAppendingString:teacher],@"--",scope];
    SSGitResult *history=[self checked:arguments in:root token:nil error:error];
    if(!history)return nil;
    NSRegularExpression *names=[NSRegularExpression regularExpressionWithPattern:@"^(feedback|reviews?|评语|反馈|批改|点评)([-_ ]?v?[0-9]+)?$" options:NSRegularExpressionCaseInsensitive error:NULL];
    NSRegularExpression *subjects=[NSRegularExpression regularExpressionWithPattern:@"\\b(feedback|review|grading)\\b|评语|评价|反馈|批改|点评|评分" options:NSRegularExpressionCaseInsensitive error:NULL];
    NSString *myName=Trim([self string:[self run:@[@"config",@"--local",@"--get",@"user.name"] in:root token:nil error:NULL]]).lowercaseString;
    NSString *myEmail=Trim([self string:[self run:@[@"config",@"--local",@"--get",@"user.email"] in:root token:nil error:NULL]]).lowercaseString;
    NSMutableSet *seen=NSMutableSet.set;
    NSMutableArray *results=NSMutableArray.array;
    for(NSString *record in [[self string:history] componentsSeparatedByString:@"\x1e"]){
        NSArray *items=[record componentsSeparatedByString:@"\0"];
        NSArray *header=[items.firstObject componentsSeparatedByString:@"\x1f"];
        if(header.count!=4 || !AMPeerSHA(header[0]))continue;
        NSString *author=header[1],*email=[header[2] lowercaseString],*subject=header[3];
        NSString *emailLogin=[email componentsSeparatedByString:@"@"].firstObject;
        if([email hasSuffix:@"@users.noreply.github.com"])emailLogin=[emailLogin componentsSeparatedByString:@"+"].lastObject;
        if((myName.length && [author.lowercaseString isEqual:myName]) || (myEmail.length && [email isEqual:myEmail]))continue;
        if(login.length && ([author caseInsensitiveCompare:login]==NSOrderedSame || [emailLogin caseInsensitiveCompare:login]==NSOrderedSame))continue;
        BOOL mentions=[subjects numberOfMatchesInString:subject options:0 range:NSMakeRange(0,subject.length)]>0;
        for(NSUInteger index=1;index<items.count && results.count<24;index++){
            NSString *path=items[index];
            if([path hasPrefix:@"\n"])path=[path substringFromIndex:1];
            if(!AMPeerInScope(path,scope) || SSSensitivePath(path) || [seen containsObject:path])continue;
            NSString *stem=path.lastPathComponent.stringByDeletingPathExtension;
            if(!mentions && ![names numberOfMatchesInString:stem options:0 range:NSMakeRange(0,stem.length)])continue;
            [seen addObject:path];
            NSString *object=[NSString stringWithFormat:@"%@:%@",header[0],path];
            SSGitResult *present=[self run:@[@"cat-file",@"-e",[NSString stringWithFormat:@"%@:%@",personal,path]] in:root token:nil error:NULL];
            if(!present || present.status!=0)continue;
            SSGitResult *size=[self run:@[@"cat-file",@"-s",object] in:root token:nil error:NULL];
            if(!size || size.status!=0 || [[self string:size] longLongValue]>1024*1024)continue;
            SSGitResult *blob=[self run:@[@"cat-file",@"blob",object] in:root token:nil error:NULL];
            NSString *text=blob && blob.status==0 ? [[NSString alloc] initWithData:blob.data encoding:NSUTF8StringEncoding]:nil;
            if(!text.length || SSContainsSecret(blob.data))continue;
            // Author metadata is evidence for the user to inspect, not proof of teacher identity.
            [results addObject:@{@"path":path,@"commit":header[0],@"author":SSRedactedText(author),@"version":AMPeerHash(@[text]),@"text":text}];
        }
    }
    return results;
}
