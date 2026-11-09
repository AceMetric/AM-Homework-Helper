- (NSDictionary *)preflightWorkingFile:(NSString *)file root:(NSString *)root {
    int descriptor=open(root.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);if(descriptor<0)return @{@"problem":@"作业文件夹无法读取",@"version":@"unreadable"};
    NSArray *parts=file.pathComponents;for(NSUInteger i=0;i+1<parts.count;i++){int next=openat(descriptor,[parts[i] fileSystemRepresentation],O_RDONLY|O_DIRECTORY|O_NOFOLLOW);int reason=errno;close(descriptor);descriptor=next;if(descriptor<0)return reason==ENOENT ? @{@"deleted":@YES,@"version":@"deleted"}:@{@"problem":@"符号链接或无法读取的目录已排除",@"version":@"unsafe"};}
    int fd=openat(descriptor,file.lastPathComponent.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_NONBLOCK);int reason=errno;close(descriptor);if(fd<0)return reason==ENOENT ? @{@"deleted":@YES,@"version":@"deleted"}:@{@"problem":@"符号链接或无法读取的文件已排除",@"version":@"unsafe"};
    struct stat info;if(fstat(fd,&info)!=0 || !S_ISREG(info.st_mode)){close(fd);return @{@"problem":@"非普通文件未读取",@"version":@"unsafe"};}
    if(info.st_size<0 || info.st_size>64*1024*1024){close(fd);return @{@"problem":@"文件超过64 MB读取限制",@"version":@"oversized"};}
    NSMutableData *data=NSMutableData.data;char buffer[8192];ssize_t count;while((count=read(fd,buffer,sizeof(buffer)))>0){if(data.length+(NSUInteger)count>64*1024*1024){close(fd);return @{@"problem":@"文件在读取时增长，超过64 MB读取限制",@"version":@"oversized"};}[data appendBytes:buffer length:(NSUInteger)count];}close(fd);if(count<0)return @{@"problem":@"文件无法完整读取",@"version":@"unreadable"};return @{@"data":data,@"mode":(info.st_mode&0111) ? @"100755":@"100644"};
}
- (NSDictionary *)assignmentCheckScopeForCourse:(NSDictionary *)course scope:(NSString *)scope error:(NSError **)error {
    NSString *teacher=course[@"teacherCommit"],*root=course[@"path"];
    if(!AMPeerPath(scope) || SSSensitivePath(scope) || !AMPeerSHA(teacher) || ![self validateCourse:course error:error]){
        if(error && !*error)*error=GitError(@"缺少已核验的老师版本或明确的作业目录。");
        return nil;
    }
    SSGitResult *headResult=[self checked:@[@"rev-parse",@"--verify",@"HEAD^{commit}"] in:root token:nil error:error];
    if(!headResult)return nil;
    NSString *head=Trim([self string:headResult]);
    // Criss-cross merges can have several equally valid ancestors. Ask the user in that case.
    SSGitResult *common=[self run:@[@"merge-base",@"--all",teacher,head] in:root token:nil error:error];
    if(!common)return nil;
    NSArray *ancestors=NonemptyParts([self string:common],@"\n");
    if(common.status!=0 || ancestors.count!=1 || !AMPeerSHA(ancestors.firstObject)){
        if(error)*error=GitError(@"老师版本与本地分支没有可唯一确定的共同历史。");
        return nil;
    }
    NSString *base=ancestors.firstObject;
    __block NSError *diffError=nil;
    SSGitResult *(^diff)(NSString *)=^SSGitResult *(NSString *commit){
        return [self checked:@[@"--literal-pathspecs",@"diff",@"--no-ext-diff",@"--no-textconv",@"--no-renames",@"--name-status",@"-z",commit,@"--",scope] in:root token:nil error:&diffError];
    };
    SSGitResult *work=diff(base),*tip=[base isEqual:teacher] ? work:(work ? diff(teacher):nil);
    if(!work || !tip){if(error)*error=diffError;return nil;}
    SSGitResult *newFiles=[self checked:@[@"--literal-pathspecs",@"ls-files",@"--others",@"--exclude-standard",@"-z",@"--",scope] in:root token:nil error:error];
    if(!newFiles)return nil;
    NSArray *current=NonemptyParts([self string:tip],@"\0"),*changed=NonemptyParts([self string:work],@"\0");
    if(current.count%2 || changed.count%2){if(error)*error=GitError(@"作业文件清单不完整。");return nil;}
    NSMutableSet *againstTeacher=NSMutableSet.set;
    for(NSUInteger i=1;i<current.count;i+=2)[againstTeacher addObject:current[i]];
    NSMutableOrderedSet *answers=NSMutableOrderedSet.orderedSet,*deleted=NSMutableOrderedSet.orderedSet;
    NSArray *untracked=NonemptyParts([self string:newFiles],@"\0");
    NSSet *newSet=[NSSet setWithArray:untracked];
    for(NSUInteger i=0;i<changed.count;i+=2){
        NSString *file=changed[i+1];if(!AMPeerInScope(file,scope))continue;
        if([changed[i] isEqual:@"D"] && ![newSet containsObject:file]){[deleted addObject:file];continue;}
        // A teacher-only update already present locally is still a template.
        if([againstTeacher containsObject:file])[answers addObject:file];
    }
    for(NSString *file in untracked)if(AMPeerInScope(file,scope))[answers addObject:file];
    SSGitResult *end=[self checked:@[@"rev-parse",@"--verify",@"HEAD^{commit}"] in:root token:nil error:error];
    if(!end)return nil;
    if(![head isEqual:Trim([self string:end])]){if(error)*error=GitError(@"分支在整理文件时发生变化，请重新确认范围。");return nil;}
    return @{@"scope":scope,@"head":head,@"teacher":teacher,@"base":base,@"answers":answers.array,@"deleted":deleted.array};
}
- (BOOL)checkReviewHead:(NSString *)head course:(NSDictionary *)course error:(NSError **)error {
    NSString *root=course[@"path"];
    SSGitResult *current=[self checked:@[@"rev-parse",@"HEAD"] in:root token:nil error:error];
    if(current && [head isEqual:Trim([self string:current])])return YES;
    if(current && error)*error=GitError(@"本地提交版本已变化，请重新核对文件范围。");
    return NO;
}
- (NSDictionary *)preflightSnapshotForCourse:(NSDictionary *)course paths:(NSArray *)paths error:(NSError **)error {
    BOOL local=[course[@"preflightLocal"] boolValue] || [course[@"preflightMode"] isEqual:@"working"];
    if(!local && (![self validateCourse:course error:error] || ![self submissionBranch:course error:error]))return nil;
    if(!paths.count || paths.count>256){if(error)*error=GitError(@"请选择1至256个文件后再检查。其它文件未检查。");return nil;}
    NSDictionary *scope=course[@"assignmentCheckScope"];
    BOOL bound=scope!=nil;
    if(bound && ![course[@"preflightPreview"] boolValue]){
        NSDictionary *latest=[self assignmentCheckScopeForCourse:course scope:scope[@"scope"] error:error];
        if(!latest)return nil;
        if(![latest isEqual:scope]){if(error)*error=GitError(@"作业范围或版本已变化，请返回文件范围重新确认。");return nil;}
    }
    SSGitResult *head=local && !bound ? nil:[self checked:@[@"rev-parse",@"HEAD"] in:course[@"path"] token:nil error:error];if((!local || bound) && !head)return nil;
    NSString *headSHA=head ? Trim([self string:head]):@"local";
    if(bound && ![scope[@"head"] isEqual:headSHA]){
        if(error)*error=GitError(@"本地提交版本已变化，请返回文件范围重新确认。");
        return nil;
    }
    for(NSString *path in paths)if(bound && !AMPeerInScope(path,scope[@"scope"])){
        if(error)*error=GitError(@"所选文件超出已确认的作业范围。");return nil;
    }
    SSGitResult *tree=local ? nil:[self checked:@[@"ls-tree",@"-r",@"-z",Trim([self string:head])] in:course[@"path"] token:nil error:error];if(!local && !tree)return nil;
    NSMutableDictionary *entries=NSMutableDictionary.dictionary,*files=NSMutableDictionary.dictionary;NSMutableSet *selected=[NSMutableSet setWithArray:paths];
    for(NSString *line in NonemptyParts(local ? @"" : [self string:tree],@"\0")){NSRange tab=[line rangeOfString:@"\t"];if(tab.location==NSNotFound)continue;NSArray *fields=NonemptyParts([line substringToIndex:tab.location],@" ");if(fields.count==3)entries[[line substringFromIndex:tab.location+1]]=@{@"mode":fields[0],@"oid":fields[2]};}
    NSString *root=local ? [course[@"path"] stringByStandardizingPath]:[course[@"path"] stringByResolvingSymlinksInPath];
    NSDictionary *(^read)(NSString *,BOOL)=^NSDictionary *(NSString *file,BOOL working){
        if(![file isKindOfClass:NSString.class] || !file.length || [file hasPrefix:@"/"] || [[file pathComponents] containsObject:@".."] || SSSensitivePath(file))return @{@"path":file ?: @"",@"problem":@"敏感或不安全文件已排除",@"version":@"excluded"};
        if(local && AMPreflightExcludedReason(file))return @{@"path":file,@"problem":AMPreflightExcludedReason(file),@"version":@"excluded"};
        NSData *data=nil;NSString *mode=@"100644",*stamp=nil;
        if(working){NSString *before=AMPreflightFileStamp([NSURL fileURLWithPath:root],file);NSDictionary *read=[self preflightWorkingFile:file root:root];stamp=AMPreflightFileStamp([NSURL fileURLWithPath:root],file);if(![before isEqual:stamp])return @{@"path":file,@"problem":@"文件在读取时发生变化，请等待保存完成后复查",@"version":@"changed",@"stamp":stamp};if(!read[@"data"]){NSMutableDictionary *problem=read.mutableCopy;problem[@"path"]=file;problem[@"stamp"]=stamp;return problem;}data=read[@"data"];mode=read[@"mode"];
        }else{NSDictionary *object=entries[file];if(!object)return nil;if(![@[@"100644",@"100755"] containsObject:object[@"mode"]])return @{@"path":file,@"problem":@"引用对象不是普通文件，未读取",@"version":object[@"oid"]};mode=object[@"mode"];
            SSGitResult *size=[self checked:@[@"cat-file",@"-s",object[@"oid"]] in:root token:nil error:NULL];if(!size || Trim([self string:size]).longLongValue>5*1024*1024)return @{@"path":file,@"problem":@"引用文件过大或无法读取",@"version":object[@"oid"]};
            SSGitResult *blob=[self checked:@[@"cat-file",@"blob",object[@"oid"]] in:root token:nil error:NULL];data=blob.data;
        }
        if(!data)return @{@"path":file,@"problem":@"文件无法读取",@"version":@"unreadable"};
        BOOL training=SSValidatedTrainingData(data);BOOL gzip=data.length>=2 && ((const unsigned char *)data.bytes)[0]==0x1f && ((const unsigned char *)data.bytes)[1]==0x8b;
        if((gzip || [file.pathExtension.lowercaseString isEqual:@"gz"]) && !training)return @{@"path":file,@"problem":@"压缩文件不是可核验的 IDX 训练数据",@"version":@"unsupported-archive"};
        if(data.length>5*1024*1024 && !training)return @{@"path":file,@"problem":@"非训练数据超过5 MB检查限制",@"version":@"oversized"};
        if(training){NSMutableDictionary *entry=[@{@"path":file,@"mode":mode,@"version":AMPreflightHash(data),@"trainingData":@YES,@"bytes":@(data.length)} mutableCopy];if(stamp)entry[@"stamp"]=stamp;return entry;}
        if(SSContainsSecret(data))return @{@"path":file,@"problem":@"文件含疑似凭据，禁止交给助手",@"version":@"secret"};
        NSMutableDictionary *entry=[@{@"path":file,@"mode":mode,@"data":data,@"version":AMPreflightHash(data)} mutableCopy];if(stamp)entry[@"stamp"]=stamp;NSString *ext=file.pathExtension.lowercaseString;
        if([@[@"png",@"jpg",@"jpeg",@"heic",@"tiff",@"tif",@"gif",@"bmp",@"webp"] containsObject:ext])entry[@"image"]=@YES;
        else if([ext isEqual:@"ipynb"] && ![course[@"preflightSafetyOnly"] boolValue]){
            NSDictionary *notebook=AMPreflightNotebook(data,file);
            if(notebook[@"problem"])entry[@"notebookOmissions"]=@[notebook[@"problem"]];
            else {entry[@"text"]=notebook[@"text"];entry[@"notebookOmissions"]=notebook[@"omissions"];entry[@"notebookImages"]=notebook[@"images"];}
        }
        else {NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];if(text)entry[@"text"]=text;}
        return entry;
    };
    NSUInteger total=0,acceptedImages=0;
    for(NSString *path in paths){
        if(self.readsCancellable && self.cancelledReads){if(error)*error=GitError(@"检查已取消。");return nil;}
        NSMutableDictionary *entry=[read(path,YES) mutableCopy];
        total+=[entry[@"data"] length];if(total>64*1024*1024){if(error)*error=GitError(@"检查材料超过64 MB，请减少选择后分批检查。");return nil;}
        files[path]=entry;
        NSMutableDictionary *accepted=NSMutableDictionary.dictionary;
        NSMutableArray *omissions=[entry[@"notebookOmissions"] mutableCopy];
        NSDictionary *assets=entry[@"notebookImages"];
        for(NSString *key in [assets.allKeys sortedArrayUsingSelector:@selector(compare:)]){
            NSDictionary *asset=assets[key];NSUInteger bytes=[asset[@"data"] length];
            if(acceptedImages+paths.count>=256 || total+bytes>64*1024*1024){
                [omissions addObject:[NSString stringWithFormat:@"第 %@ 单元格的图片超出材料额度",asset[@"cell"]]];
                continue;
            }
            files[key]=asset;accepted[key]=asset;total+=bytes;acceptedImages++;
        }
        if(omissions){entry[@"notebookOmissions"]=omissions;entry[@"notebookImages"]=accepted;}
    }
    for(NSString *path in paths)if([@[@"md",@"markdown",@"mdx"] containsObject:path.pathExtension.lowercaseString])for(NSDictionary *ref in AMPreflightImageReferences(files[path][@"text"] ?: @"")){NSString *asset=AMPreflightResolveImage(path,ref[@"reference"]);if(asset && !files[asset]){if(files.count>=256){if(error)*error=GitError(@"包括引用图片在内超过256个文件，请分批检查。");return nil;}if(self.readsCancellable && self.cancelledReads){if(error)*error=GitError(@"检查已取消。");return nil;}NSDictionary *entry=[course[@"preflightExcluded"] containsObject:asset] ? @{@"path":asset,@"version":@"excluded",@"problem":@"图片已从检查范围排除，未检查"}:read(asset,local || [selected containsObject:asset]);if(entry){total+=[entry[@"data"] length];if(total>64*1024*1024){if(error)*error=GitError(@"引用图片使材料超过64 MB，请分批检查。");return nil;}files[asset]=entry;}}}
    if(files.count>256){if(error)*error=GitError(@"包括引用图片在内超过256个文件，请分批检查。");return nil;}
    NSMutableDictionary *feedbackStamps=NSMutableDictionary.dictionary;
    for(NSString *path in course[@"preflightFeedbackVersions"]){
        NSDictionary *file=read(path,YES);
        if(![file[@"version"] isEqual:course[@"preflightFeedbackVersions"][path]] || !file[@"stamp"]){
            if(error)*error=GitError(@"老师评语副本已变化，请返回文件范围重新确认。");return nil;
        }
        feedbackStamps[path]=file[@"stamp"];
    }
    if(bound){
        SSGitResult *end=[self checked:@[@"rev-parse",@"HEAD"] in:root token:nil error:error];
        if(!end)return nil;
        if(![headSHA isEqual:Trim([self string:end])]){if(error)*error=GitError(@"检查期间分支发生变化，请重新确认范围。");return nil;}
    }
    NSMutableString *stamp=[NSMutableString stringWithFormat:@"%@|%@|%@|%@|%@|%@",course[@"fork"],course[@"branch"],headSHA,scope[@"teacher"] ?: @"",scope[@"scope"] ?: @"",course[@"teacherCommit"] ?: @""];
    NSMutableArray *versions=NSMutableArray.array;
    for(NSString *file in [files.allKeys sortedArrayUsingSelector:@selector(compare:)])
        [versions addObject:@[file,files[file][@"version"],files[file][@"mode"] ?: @"",@([selected containsObject:file])]];
    [stamp appendString:AMPeerHash(versions)];
    [stamp appendString:AMPeerHash(@[course[@"preflightRoles"] ?: @{},course[@"preflightOmissions"] ?: @[]])];
    return @{@"mode":local ? @"working":@"submission",@"head":headSHA,@"repository":course[@"fork"] ?: @"",@"branch":course[@"branch"] ?: @"",@"paths":paths.copy,@"files":files,@"reviewRoles":course[@"preflightRoles"] ?: @{},@"scopeOmissions":course[@"preflightOmissions"] ?: @[],@"localRoot":root,@"feedbackStamps":feedbackStamps,@"version":AMPreflightHash([stamp dataUsingEncoding:NSUTF8StringEncoding])};
}
- (BOOL)validatePreflightIndex:(NSArray *)paths course:(NSDictionary *)course error:(NSError **)error {
    NSDictionary *snapshot=self.expectedSubmissionSnapshot;if(!snapshot)return YES;
    SSGitResult *head=[self checked:@[@"rev-parse",@"HEAD"] in:course[@"path"] token:nil error:error];
    BOOL ok=head && [Trim([self string:head]) isEqual:snapshot[@"head"]] && [snapshot[@"repository"] isEqual:course[@"fork"]] && [snapshot[@"branch"] isEqual:course[@"branch"]] && [[NSSet setWithArray:paths] isEqual:[NSSet setWithArray:snapshot[@"paths"]]];
    if(ok)for(NSString *file in paths){NSDictionary *expected=snapshot[@"files"][file];SSGitResult *entry=[self checked:@[@"ls-files",@"--stage",@"-z",@"--",file] in:course[@"path"] token:nil error:error];if(!entry){ok=NO;break;}
        if([expected[@"deleted"] boolValue]){if(entry.data.length)ok=NO;}
        else {NSArray *lines=NonemptyParts([self string:entry],@"\0");if(lines.count!=1){ok=NO;break;}NSArray *fields=NonemptyParts([[lines[0] componentsSeparatedByString:@"\t"] firstObject],@" ");if(fields.count<3 || ![fields[0] isEqual:expected[@"mode"]]){ok=NO;break;}SSGitResult *blob=[self checked:@[@"cat-file",@"blob",fields[1]] in:course[@"path"] token:nil error:error];if(!blob || ![AMPreflightHash(blob.data) isEqual:expected[@"version"]])ok=NO;}
        if(!ok)break;
    }
    if(!ok && error)*error=[NSError errorWithDomain:@"AMPreflight" code:2 userInfo:@{NSLocalizedDescriptionKey:@"文件或分支在检查后发生变化，请重新检查。",@"SSPreflightStale":@YES}];return ok;
}

- (NSString *)preflightRequirementsForCourse:(NSDictionary *)course tasks:(NSArray *)tasks verifiedLines:(NSArray **)verifiedLines {
    NSMutableOrderedSet *trusted=NSMutableOrderedSet.orderedSet;
    NSMutableArray *blocks=NSMutableArray.array;for(NSDictionary *task in tasks){NSString *blob=task[@"sourceBlobSHA"],*text=nil;
        if([blob isKindOfClass:NSString.class] && [blob rangeOfString:@"^[a-f0-9]{40,64}$" options:NSRegularExpressionSearch].location!=NSNotFound && [self validateCourse:course error:NULL]){
            SSGitResult *size=[self run:@[@"cat-file",@"-s",blob] in:course[@"path"] token:nil error:NULL];if(size.status==0 && Trim([self string:size]).longLongValue<=384*1024){SSGitResult *r=[self run:@[@"cat-file",@"blob",blob] in:course[@"path"] token:nil error:NULL];if(r.status==0 && !SSContainsSecret(r.data))text=[[NSString alloc] initWithData:r.data encoding:NSUTF8StringEncoding];}
        }
        if(text.length){
            [blocks addObject:[NSString stringWithFormat:@"老师原文：%@ · %@ · %@\n%@",task[@"sourceRepository"] ?: @"",task[@"sourcePath"] ?: @"",blob,text]];
            // Only the pinned teacher blob can attest that the text itself
            // contains the question. Linked media still needs explicit coverage.
            if(verifiedLines && [task[@"sourceRepository"] isEqual:course[@"upstream"]] &&
               [task[@"sourcePath"] length] && ![text containsString:@"]("] &&
               ![text localizedCaseInsensitiveContainsString:@"<img"] &&
               ![text localizedCaseInsensitiveContainsString:@"https://"]){
                NSString *path=task[@"sourcePath"];
                NSDictionary *verified=[self assignmentWorkbenchTeacherPreview:course path:path error:NULL][@"files"][path];
                if([verified[@"version"] isEqual:blob])for(NSString *line in [text componentsSeparatedByString:@"\n"]){
                    NSString *trim=Trim(line);
                    if(trim.length && ![trim hasPrefix:@"#"])[trusted addObject:trim];
                }
            }
        }
        else if([task[@"entryEvidence"] length])[blocks addObject:[NSString stringWithFormat:@"录入通知：%@\n%@",task[@"title"],task[@"entryEvidence"]]];
        else [blocks addObject:[NSString stringWithFormat:@"关联摘要（未取得完整题目，请核对）：%@\n%@\n%@",task[@"title"],task[@"sourceSummary"] ?: @"",task[@"sourceRequirements"] ?: @""]];
    }if(verifiedLines)*verifiedLines=trusted.array;return [blocks componentsJoinedByString:@"\n\n"];
}

- (NSArray<NSString *> *)changedTeacherPathsForCourse:(NSDictionary *)course from:(NSString *)oldCommit to:(NSString *)newCommit {
    if(!AMPeerSHA(oldCommit) || !AMPeerSHA(newCommit) || ![self validateCourse:course error:NULL])return nil;
    if([oldCommit isEqual:newCommit])return @[];
    SSGitResult *diff=[self checked:@[@"diff",@"--name-only",@"--no-renames",@"--no-ext-diff",@"--no-textconv",@"-z",oldCommit,newCommit,@"--"]
        in:course[@"path"] token:nil error:NULL];
    return diff ? NonemptyParts([self string:diff],@"\0"):nil;
}

// Workbench reads use the same validated repository and pinned teacher commit as preflight.
- (NSDictionary *)assignmentWorkbenchIndex:(NSDictionary *)course source:(NSString *)source error:(NSError **)error {
    if(!AMPeerPath(source) || SSSensitivePath(source) || ![self validateCourse:course error:error])return nil;
    NSString *scope=source.stringByDeletingLastPathComponent;
    if(!AMPeerPath(scope))scope=source;
    NSString *root=course[@"path"],*teacher=course[@"teacherCommit"];
    SSGitResult *files=[self checked:@[@"--literal-pathspecs",@"ls-files",@"-c",@"-o",@"--exclude-standard",@"-z",@"--",scope] in:root token:nil error:error];
    if(!files)return nil;
    NSMutableOrderedSet *paths=NSMutableOrderedSet.orderedSet;
    for(NSString *path in NonemptyParts([self string:files],@"\0")){
        if(AMPeerInScope(path,scope) && !SSSensitivePath(path))[paths addObject:path];
        if(paths.count>=1000)break;
    }
    NSMutableArray *history=NSMutableArray.array;
    if(AMPeerSHA(teacher)){
        // NUL fields preserve whitespace in paths and commit subjects.
        SSGitResult *log=[self checked:@[@"--literal-pathspecs",@"log",@"-z",@"-50",@"--format=%H%x00%aI%x00%s",teacher,@"--",scope] in:root token:nil error:NULL];
        NSArray *fields=[[self string:log] componentsSeparatedByString:@"\0"];
        for(NSUInteger index=0;index+2<fields.count;index+=3)
            if(AMPeerSHA(fields[index]))[history addObject:@{@"id":fields[index],@"date":fields[index+1],@"title":fields[index+2]}];
    }
    return @{@"paths":[paths.array sortedArrayUsingSelector:@selector(localizedStandardCompare:)],@"teacherHistory":history};
}

- (NSDictionary *)assignmentWorkbenchTeacherPreview:(NSDictionary *)course path:(NSString *)path error:(NSError **)error {
    NSString *teacher=course[@"teacherCommit"],*root=course[@"path"];
    if(!AMPeerSHA(teacher) || !AMPeerPath(path) || SSSensitivePath(path) || ![self validateCourse:course error:error])return nil;
    SSGitResult *tree=[self checked:@[@"--literal-pathspecs",@"ls-tree",@"-l",teacher,@"--",path] in:root token:nil error:error];
    NSString *entry=[self string:tree];
    NSRange separator=[entry rangeOfString:@"\t"];
    if(separator.location==NSNotFound)return nil;
    NSArray *fields=NonemptyParts([entry substringToIndex:separator.location],@" ");
    if(fields.count!=4 || ![@[@"100644",@"100755"] containsObject:fields[0]] || !AMPeerSHA(fields[2]) || [fields[3] longLongValue]>1024*1024)return nil;
    SSGitResult *blob=[self checked:@[@"cat-file",@"blob",fields[2]] in:root token:nil error:error];
    NSString *content=[[NSString alloc] initWithData:blob.data encoding:NSUTF8StringEncoding];
    if(!content || [content rangeOfString:@"\0"].location!=NSNotFound || SSContainsSecret(blob.data))return nil;
    return @{@"files":@{path:@{@"text":content,@"version":fields[2]}}};
}
