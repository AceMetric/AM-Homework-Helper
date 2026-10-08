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
    return @{@"context":@{@"format":@"am-course-context-v2",@"batchID":batch,@"documents":documents},@"manifest":manifest};
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
    return @{@"records":records,@"progress":progress,@"counts":counts,@"issues":issues};
}
