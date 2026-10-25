- (NSDictionary *)preflightWorkingFile:(NSString *)file root:(NSString *)root {
    int descriptor=open(root.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);if(descriptor<0)return @{@"problem":@"作业文件夹无法读取",@"version":@"unreadable"};
    NSArray *parts=file.pathComponents;for(NSUInteger i=0;i+1<parts.count;i++){int next=openat(descriptor,[parts[i] fileSystemRepresentation],O_RDONLY|O_DIRECTORY|O_NOFOLLOW);int reason=errno;close(descriptor);descriptor=next;if(descriptor<0)return reason==ENOENT ? @{@"deleted":@YES,@"version":@"deleted"}:@{@"problem":@"符号链接或无法读取的目录已排除",@"version":@"unsafe"};}
    int fd=openat(descriptor,file.lastPathComponent.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_NONBLOCK);int reason=errno;close(descriptor);if(fd<0)return reason==ENOENT ? @{@"deleted":@YES,@"version":@"deleted"}:@{@"problem":@"符号链接或无法读取的文件已排除",@"version":@"unsafe"};
    struct stat info;if(fstat(fd,&info)!=0 || !S_ISREG(info.st_mode)){close(fd);return @{@"problem":@"非普通文件未读取",@"version":@"unsafe"};}
    if(info.st_size<0 || info.st_size>64*1024*1024){close(fd);return @{@"problem":@"文件超过64 MB读取限制",@"version":@"oversized"};}
    NSMutableData *data=NSMutableData.data;char buffer[8192];ssize_t count;while((count=read(fd,buffer,sizeof(buffer)))>0){if(data.length+(NSUInteger)count>64*1024*1024){close(fd);return @{@"problem":@"文件在读取时增长，超过64 MB读取限制",@"version":@"oversized"};}[data appendBytes:buffer length:(NSUInteger)count];}close(fd);if(count<0)return @{@"problem":@"文件无法完整读取",@"version":@"unreadable"};return @{@"data":data,@"mode":(info.st_mode&0111) ? @"100755":@"100644"};
}
- (NSDictionary *)preflightSnapshotForCourse:(NSDictionary *)course paths:(NSArray *)paths error:(NSError **)error {
    BOOL local=[course[@"preflightLocal"] boolValue] || [course[@"preflightMode"] isEqual:@"working"];
    if(!local && (![self validateCourse:course error:error] || ![self submissionBranch:course error:error]))return nil;
    if(!paths.count || paths.count>256){if(error)*error=GitError(@"请选择1至256个文件后再检查。其它文件未检查。");return nil;}
    SSGitResult *head=local ? nil:[self checked:@[@"rev-parse",@"HEAD"] in:course[@"path"] token:nil error:error];if(!local && !head)return nil;
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
        else {NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];if(text)entry[@"text"]=text;}
        return entry;
    };
    NSUInteger total=0;
    for(NSString *path in paths){if(self.readsCancellable && self.cancelledReads){if(error)*error=GitError(@"检查已取消。");return nil;}NSDictionary *entry=read(path,YES);total+=[entry[@"data"] length];if(total>64*1024*1024){if(error)*error=GitError(@"检查材料超过64 MB，请减少选择后分批检查。");return nil;}files[path]=entry;}
    for(NSString *path in paths)if([@[@"md",@"markdown",@"mdx"] containsObject:path.pathExtension.lowercaseString])for(NSDictionary *ref in AMPreflightImageReferences(files[path][@"text"] ?: @"")){NSString *asset=AMPreflightResolveImage(path,ref[@"reference"]);if(asset && !files[asset]){if(files.count>=256){if(error)*error=GitError(@"包括引用图片在内超过256个文件，请分批检查。");return nil;}if(self.readsCancellable && self.cancelledReads){if(error)*error=GitError(@"检查已取消。");return nil;}NSDictionary *entry=[course[@"preflightExcluded"] containsObject:asset] ? @{@"path":asset,@"version":@"excluded",@"problem":@"图片已从检查范围排除，未检查"}:read(asset,local || [selected containsObject:asset]);if(entry){total+=[entry[@"data"] length];if(total>64*1024*1024){if(error)*error=GitError(@"引用图片使材料超过64 MB，请分批检查。");return nil;}files[asset]=entry;}}}
    if(files.count>256){if(error)*error=GitError(@"包括引用图片在内超过256个文件，请分批检查。");return nil;}
    NSMutableString *stamp=[NSMutableString stringWithFormat:@"%@|%@|%@",course[@"fork"],course[@"branch"],(local ? @"local":Trim([self string:head]))];for(NSString *file in [files.allKeys sortedArrayUsingSelector:@selector(compare:)])[stamp appendFormat:@"|%@:%@:%@:%d",file,files[file][@"version"],files[file][@"mode"] ?: @"",[selected containsObject:file]];
    return @{@"mode":local ? @"working":@"submission",@"head":local ? @"local":Trim([self string:head]),@"repository":course[@"fork"] ?: @"",@"branch":course[@"branch"] ?: @"",@"paths":paths.copy,@"files":files,@"version":AMPreflightHash([stamp dataUsingEncoding:NSUTF8StringEncoding])};
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

- (NSString *)preflightRequirementsForCourse:(NSDictionary *)course tasks:(NSArray *)tasks {
    NSMutableArray *blocks=NSMutableArray.array;for(NSDictionary *task in tasks){NSString *blob=task[@"sourceBlobSHA"],*text=nil;
        if([blob isKindOfClass:NSString.class] && [blob rangeOfString:@"^[a-f0-9]{40,64}$" options:NSRegularExpressionSearch].location!=NSNotFound && [self validateCourse:course error:NULL]){
            SSGitResult *size=[self run:@[@"cat-file",@"-s",blob] in:course[@"path"] token:nil error:NULL];if(size.status==0 && Trim([self string:size]).longLongValue<=384*1024){SSGitResult *r=[self run:@[@"cat-file",@"blob",blob] in:course[@"path"] token:nil error:NULL];if(r.status==0 && !SSContainsSecret(r.data))text=[[NSString alloc] initWithData:r.data encoding:NSUTF8StringEncoding];}
        }
        if(text.length)[blocks addObject:[NSString stringWithFormat:@"老师原文：%@ · %@ · %@\n%@",task[@"sourceRepository"] ?: @"",task[@"sourcePath"] ?: @"",blob,text]];
        else if([task[@"entryEvidence"] length])[blocks addObject:[NSString stringWithFormat:@"录入通知：%@\n%@",task[@"title"],task[@"entryEvidence"]]];
        else [blocks addObject:[NSString stringWithFormat:@"关联摘要（未取得完整题目，请核对）：%@\n%@\n%@",task[@"title"],task[@"sourceSummary"] ?: @"",task[@"sourceRequirements"] ?: @""]];
    }return [blocks componentsJoinedByString:@"\n\n"];
}
