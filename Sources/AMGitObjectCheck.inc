// Read the complete outgoing range in two batches rather than starting several
// Git processes per object. Every object and tree name still passes inspection.
- (BOOL)checkObjects:(NSString *)range path:(NSString *)path error:(NSError **)error {
    SSGitResult *objects=[self checked:@[@"rev-list",@"--objects",@"--no-object-names",range] in:path token:nil error:error];if(!objects)return NO;
    NSArray *shas=NonemptyParts([self string:objects],@"\n");if(shas.count>4000){if(error)*error=GitError(@"待推送范围过大，无法完整检查；请先人工检查历史。");return NO;}if(!shas.count)return YES;
    NSData *input=[[[shas componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    SSGitResult *metadata=[self run:@[@"cat-file",@"--batch-check"] input:input in:path token:nil error:error];if(!metadata)return NO;
    NSArray *lines=NonemptyParts([self string:metadata],@"\n");if(metadata.status || lines.count!=shas.count){if(error)*error=GitError(@"无法完整读取待推送对象，已停止推送。");return NO;}
    NSMutableArray *entries=NSMutableArray.array;NSMutableDictionary *blobs=NSMutableDictionary.dictionary;NSMutableSet *compressedObjects=NSMutableSet.set;NSUInteger total=0;
    for(NSUInteger i=0;i<lines.count;i++){
        NSArray *fields=NonemptyParts(lines[i],@" ");BOOL valid=fields.count==3 && [fields[0] isEqual:shas[i]] && [@[@"blob",@"tree",@"commit",@"tag"] containsObject:fields[1]];
        if(!valid || [fields[2] rangeOfString:@"^[0-9]{1,10}$" options:NSRegularExpressionSearch].location==NSNotFound){if(error)*error=GitError(@"待推送对象信息不完整，已停止推送。");return NO;}
        NSUInteger size=[fields[2] longLongValue];total+=size;
        if(size>64*1024*1024 || total>256*1024*1024){if(error)*error=GitError(@"待推送文件或历史超出安全检查上限；已停止推送。");return NO;}
        [entries addObject:@{@"oid":fields[0],@"kind":fields[1],@"size":@(size),@"header":lines[i]}];
    }
    if(self.progress)self.progress([NSString stringWithFormat:@"检查待推送历史：0／%lu 个对象",(unsigned long)entries.count]);
    SSGitResult *batch=[self run:@[@"cat-file",@"--batch"] input:input in:path token:nil error:error];if(!batch)return NO;
    if(batch.status || batch.data.length>total+entries.count*160){if(error)*error=GitError(@"待推送对象读取失败，未执行推送。");return NO;}
    const unsigned char *bytes=batch.data.bytes;NSUInteger offset=0,index=0;
    for(NSDictionary *entry in entries){
        if(self.operationCancelled || AMCurrentOperationCancelled() || (self.readsCancellable && self.cancelledReads)){if(error)*error=GitError(@"安全检查已终止，未继续推送。");return NO;}
        const unsigned char *newline=offset<batch.data.length ? memchr(bytes+offset,'\n',MIN((NSUInteger)160,batch.data.length-offset)):NULL;
        NSUInteger headerSize=newline ? (NSUInteger)(newline-bytes-offset):0,size=[entry[@"size"] unsignedIntegerValue];
        NSString *header=newline ? [[NSString alloc] initWithBytes:bytes+offset length:headerSize encoding:NSUTF8StringEncoding]:nil;
        if(![header isEqual:entry[@"header"]] || offset+headerSize+1+size>=batch.data.length){if(error)*error=GitError(@"待推送对象截断或版本不匹配，未执行推送。");return NO;}
        offset+=headerSize+1;NSData *data=[batch.data subdataWithRange:NSMakeRange(offset,size)];offset+=size;
        if(bytes[offset++]!='\n'){if(error)*error=GitError(@"待推送对象边界无效，未执行推送。");return NO;}
        if([entry[@"kind"] isEqual:@"tree"]){
            const unsigned char *tree=data.bytes;NSUInteger cursor=0,oidBytes=[entry[@"oid"] length]/2;
            while(cursor<size){const unsigned char *end=memchr(tree+cursor,0,size-cursor);NSUInteger length=end ? (NSUInteger)(end-tree-cursor):0;
                NSString *name=end ? [[NSString alloc] initWithBytes:tree+cursor length:length encoding:NSUTF8StringEncoding]:nil;NSRange separator=[name rangeOfString:@" "];
                if(!end || !name || separator.location==NSNotFound || !oidBytes || cursor+length+1+oidBytes>size){if(error)*error=GitError(@"目录对象无法完整核对，未执行推送。");return NO;}
                if(SSSensitivePath([name substringFromIndex:NSMaxRange(separator)])){if(error)*error=GitError(@"待推送历史包含敏感文件或压缩包；请先处理后重试。");return NO;}
                NSString *file=[name substringFromIndex:NSMaxRange(separator)];if([file.pathExtension.lowercaseString isEqual:@"gz"]){NSMutableString *oid=NSMutableString.string;for(NSUInteger n=0;n<oidBytes;n++)[oid appendFormat:@"%02x",tree[cursor+length+1+n]];[compressedObjects addObject:oid];}
                cursor+=length+1+oidBytes;
            }
        }else if([entry[@"kind"] isEqual:@"blob"]){
            blobs[entry[@"oid"]]=data;BOOL gzip=data.length>=2 && ((const unsigned char *)data.bytes)[0]==0x1f && ((const unsigned char *)data.bytes)[1]==0x8b;
            if((gzip || data.length>5*1024*1024) && !SSValidatedTrainingData(data)){if(error)*error=GitError(@"待推送压缩文件或大文件不是可核验的训练数据");return NO;}
            if(SSContainsSecret(data)){if(error)*error=GitError(@"待推送提交历史含疑似凭据，已停止推送");return NO;}
        }else if(SSContainsSecret(data)){if(error)*error=GitError(@"待推送提交历史含疑似凭据；已停止推送，请先移除并轮换真实凭据。");return NO;}
        index++;if(self.progress && (index%16==0 || index==entries.count))self.progress([NSString stringWithFormat:@"检查待推送历史：%lu／%lu 个对象",(unsigned long)index,(unsigned long)entries.count]);
    }
    if(offset!=batch.data.length){if(error)*error=GitError(@"待推送对象数量不匹配，未执行推送。");return NO;}
    for(NSString *oid in compressedObjects)if(blobs[oid] && !SSValidatedTrainingData(blobs[oid])){if(error)*error=GitError(@"待推送压缩文件不是可核验的 IDX 训练数据");return NO;}
    return YES;
}
