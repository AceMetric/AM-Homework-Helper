#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>
// Bounded no-follow read: result files are data, never executable instructions.
NSDictionary *SSSkillReadResult(NSURL *url,NSError **error) {
    int fd=open(url.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_NONBLOCK);struct stat info;
    if(fd<0){if(error)*error=RError(@"无法读取结果文件，请使用普通 JSON 文件。");return nil;}
    if(fstat(fd,&info)!=0 || !S_ISREG(info.st_mode) || info.st_size<2 || info.st_size>8*1024*1024){close(fd);if(error)*error=RError(@"结果须为不超过8 MB的普通 JSON 文件。");return nil;}
    NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)info.st_size];NSUInteger offset=0;
    while(offset<data.length){ssize_t count=read(fd,(char *)data.mutableBytes+offset,data.length-offset);if(count<=0)break;offset+=(NSUInteger)count;}close(fd);
    id result=offset==data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
    if(![result isKindOfClass:NSDictionary.class] || ![result[@"documents"] isKindOfClass:NSArray.class] || [result[@"documents"] count]>1000 || (result[@"batchID"] && ![result[@"batchID"] isKindOfClass:NSString.class])){if(error)*error=RError(@"结果尚未完整或格式无效，请让助手完整写入后重试。");return nil;}
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);NSMutableString *fingerprint=NSMutableString.string;for(NSUInteger i=0;i<sizeof(digest);i++)[fingerprint appendFormat:@"%02x",digest[i]];
    return @{@"result":result,@"fingerprint":fingerprint};
}
// Pure batch exchange: no filesystem, task writes, model calls or Git operations.
NSString *SSSkillProgressKey(NSString *course, NSDictionary *document) {
    return [NSString stringWithFormat:@"%@|%@|%@",course,document[@"repository"],document[@"path"]];
}
NSString *SSSkillVersion(NSDictionary *document) {
    return [NSString stringWithFormat:@"skill-v2|%@|%@",document[@"blobSHA"],document[@"timeZone"] ?: @""];
}
NSDictionary *SSSkillExport(NSArray *courses, NSDictionary *scans, NSDictionary *progress, BOOL all) {
    NSMutableArray *documents=NSMutableArray.array;NSMutableDictionary *manifest=NSMutableDictionary.dictionary;
    for(NSDictionary *course in courses) for(NSDictionary *source in scans[course[@"fork"]][@"documents"] ?: @[]) {
        NSString *key=SSSkillProgressKey(course[@"fork"],source),*version=SSSkillVersion(source);
        if(!all && [progress[key] isEqual:version])continue;
        // Deliberate allowlist: never serialize course paths, credentials or tasks.
        NSMutableDictionary *copy=NSMutableDictionary.dictionary;
        for(NSString *field in @[@"repository",@"path",@"blobSHA",@"text",@"timeZone"])if(source[field])copy[field]=source[field];
        copy[@"courseID"]=course[@"fork"];[documents addObject:copy];manifest[key]=version;
    }
    NSString *batch=NSUUID.UUID.UUIDString;
    return @{@"context":@{@"format":@"am-course-context-v2",@"skillVersion":@3,@"batchID":batch,@"documents":documents},@"manifest":manifest};
}
NSDictionary *SSSkillValidateBatch(id result, NSArray *courses, NSDictionary *scans, NSDictionary *batches, NSString *legacyCourse, NSError **error) {
    BOOL legacy=[result isKindOfClass:NSDictionary.class] && [result[@"format"] isEqual:@"am-course-results-v1"];
    if(![result isKindOfClass:NSDictionary.class] || (!legacy && ![result[@"format"] isEqual:@"am-course-results-v2"]) || ![result[@"documents"] isKindOfClass:NSArray.class] || [result[@"documents"] count]>1000) {if(error)*error=RError(@"识别结果格式无效，未修改发现记录。");return nil;}
    id batchID=result[@"batchID"];NSDictionary *manifest=[batchID isKindOfClass:NSString.class] ? batches[batchID] : nil;
    if(!legacy && ![manifest isKindOfClass:NSDictionary.class]){if(error)*error=RError(@"未找到这份材料包的导出记录，请在这台 Mac 重新导出。");return nil;}
    NSMutableDictionary *records=NSMutableDictionary.dictionary,*progress=NSMutableDictionary.dictionary,*counts=NSMutableDictionary.dictionary;
    NSMutableArray *issues=NSMutableArray.array;NSMutableSet *seen=NSMutableSet.set;
    for(id document in result[@"documents"]){
        if(![document isKindOfClass:NSDictionary.class]){[issues addObject:@"无效文档条目，已排除"];continue;}
        NSString *target=legacy ? legacyCourse : document[@"courseID"];
        NSDictionary *course=nil;for(NSDictionary *candidate in courses)if([target isKindOfClass:NSString.class] && [candidate[@"fork"] isEqual:target]){course=candidate;break;}
        NSString *label=[document[@"path"] isKindOfClass:NSString.class] ? document[@"path"] : @"未知文件";
        if(!course || ![course[@"path"] length] || ![course[@"upstream"] isEqual:document[@"repository"]]){[issues addObject:[label stringByAppendingString:@"：课程未关联或来源不匹配"]];continue;}
        NSDictionary *scan=scans[target];if(!scan || scan[@"error"]){[issues addObject:[label stringByAppendingString:@"：无法重新读取老师来源"]];continue;}
        NSDictionary *live=nil;for(NSDictionary *source in scan[@"documents"])if([source[@"path"] isEqual:document[@"path"]] && [source[@"repository"] isEqual:document[@"repository"]]){live=source;break;}
        NSString *key=SSSkillProgressKey(target,document);
        if([seen containsObject:key]){[issues addObject:[label stringByAppendingString:@"：重复条目，已排除"]];continue;}[seen addObject:key];
        if(!live || ![live[@"blobSHA"] isEqual:document[@"blobSHA"]] || (!legacy && ![manifest[key] isEqual:SSSkillVersion(live)])){[issues addObject:[label stringByAppendingString:@"：版本已变化或不属于此次导出"]];continue;}
        NSError *failure=nil;NSArray *found=SSValidatedSkillResults(@{@"format":@"am-course-results-v1",@"documents":@[document]},@[live],[(scan[@"candidates"] ?: @[]) arrayByAddingObjectsFromArray:scan[@"materials"] ?: @[]],&failure);
        if(!found){[issues addObject:[NSString stringWithFormat:@"%@：%@",label,failure.localizedDescription]];continue;}
        if(!records[target])records[target]=NSMutableArray.array;[records[target] addObjectsFromArray:found];
        progress[key]=SSSkillVersion(live);counts[target]=@([counts[target] unsignedIntegerValue]+1);
    }
    if(!legacy)for(NSString *key in manifest)if(![seen containsObject:key])[issues addObject:@"本批有文档尚未返回结果，增量进度保留，可重新交给助手。"];
    return @{@"records":records,@"progress":progress,@"counts":counts,@"issues":issues};
}
