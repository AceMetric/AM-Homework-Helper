static NSMutableArray *AMTransientCourses;
void AMUseTransientCourses(void){AMTransientCourses=NSMutableArray.array;}
// Course identity is independent of teacher provenance and repository credentials.
static BOOL AMValidCourseCatalog(id rows){
    if(![rows isKindOfClass:NSArray.class])return NO;NSMutableSet *ids=NSMutableSet.set;
    for(id row in rows){if(![row isKindOfClass:NSDictionary.class] || ![row[@"id"] isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:row[@"id"]] || [ids containsObject:row[@"id"]] || ![row[@"name"] isKindOfClass:NSString.class] || ![row[@"name"] length] || [row[@"name"] length]>200)return NO;
        for(NSString *key in row)if(![@[@"id",@"name",@"fork",@"upstream",@"aliases"] containsObject:key] || (![key isEqual:@"aliases"] && ![row[key] isKindOfClass:NSString.class]))return NO;
        if(row[@"aliases"]){if(![row[@"aliases"] isKindOfClass:NSArray.class])return NO;for(id alias in row[@"aliases"])if(![alias isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:alias])return NO;}
        for(NSString *key in @[@"fork",@"upstream"])if(row[key] && !SSCanonicalRepository([@"https://github.com/" stringByAppendingString:row[key]]))return NO;[ids addObject:row[@"id"]];}
    return YES;
}
NSString *AMRepositoryCourseID(NSString *repository){
    NSData *data=[repository.lowercaseString dataUsingEncoding:NSUTF8StringEncoding];unsigned char bytes[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,bytes);bytes[6]=(bytes[6]&15)|0x50;bytes[8]=(bytes[8]&63)|0x80;return [[NSUUID alloc] initWithUUIDBytes:bytes].UUIDString;
}
NSArray *AMStoredCourses(NSError **error){
    if(AMTransientCourses)return AMTransientCourses.copy;
    id rows=SSReadPlist(@"course-catalog.plist");if(!rows && ![NSFileManager.defaultManager fileExistsAtPath:[SSDataDirectory() URLByAppendingPathComponent:@"course-catalog.plist"].path])return @[];
    if(AMValidCourseCatalog(rows))return rows;if(error)*error=[NSError errorWithDomain:@"AMCourses" code:1 userInfo:@{NSLocalizedDescriptionKey:@"课程目录无法读取，原文件已保留"}];return nil;
}
NSArray *AMCourseCatalog(NSArray *repositories){
    NSMutableArray *rows=[AMStoredCourses(NULL) mutableCopy] ?: NSMutableArray.array;
    if(![repositories isKindOfClass:NSArray.class])return rows;
    for(NSDictionary *repository in repositories){NSString *fork=repository[@"fork"];if(!fork.length)continue;NSUInteger index=[rows indexOfObjectPassingTest:^BOOL(NSDictionary *row,NSUInteger i,BOOL *stop){(void)i;(void)stop;return [row[@"fork"] caseInsensitiveCompare:fork]==NSOrderedSame && row[@"fork"]!=nil;}];
        NSMutableDictionary *row=index==NSNotFound ? [@{@"id":AMRepositoryCourseID(fork),@"name":fork.lastPathComponent,@"fork":fork} mutableCopy]:[rows[index] mutableCopy];if(repository[@"upstream"])row[@"upstream"]=repository[@"upstream"];if(index==NSNotFound)[rows addObject:row];else rows[index]=row;}
    if(AMTransientCourses)AMTransientCourses=rows.mutableCopy;return rows;
}
BOOL AMSaveCourseCatalog(NSArray *courses,NSError **error){
    if(!AMStoredCourses(error))return NO;if(!AMValidCourseCatalog(courses)){if(error)*error=[NSError errorWithDomain:@"AMCourses" code:2 userInfo:@{NSLocalizedDescriptionKey:@"课程名称或关联无效"}];return NO;}if(AMTransientCourses){AMTransientCourses=courses.mutableCopy;return YES;}return SSWritePlist(@"course-catalog.plist",courses,error);
}
NSDictionary *AMCourseForTask(NSDictionary *task,NSArray *catalog){
    if(task[@"courseID"]){for(NSDictionary *row in catalog)if(([row[@"id"] isEqual:task[@"courseID"]] || [row[@"aliases"] containsObject:task[@"courseID"]]))return row;return nil;}
    NSMutableArray *matches=NSMutableArray.array;for(NSDictionary *row in catalog)if(([task[@"courseRepository"] length] && [row[@"fork"] isEqual:task[@"courseRepository"]]) || (![task[@"courseRepository"] length] && [task[@"sourceRepository"] length] && [row[@"upstream"] isEqual:task[@"sourceRepository"]]))[matches addObject:row];return matches.count==1 ? matches[0]:nil;
}
NSDictionary *AMCourseForName(NSString *name,NSArray *catalog){
    name=[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];NSMutableArray *matches=NSMutableArray.array;for(NSDictionary *row in catalog)if([row[@"name"] isEqual:name])[matches addObject:row];return matches.count==1 ? matches[0]:nil;
}
NSDictionary *AMNewCourse(NSString *name){name=[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];return @{@"id":NSUUID.UUID.UUIDString,@"name":name ?: @""};}

NSArray *AMCourseDisplayTasks(NSArray *tasks,NSArray *catalog){NSMutableArray *rows=NSMutableArray.array;for(NSDictionary *task in tasks){NSDictionary *course=AMCourseForTask(task,catalog);if(!course){[rows addObject:task];continue;}NSMutableDictionary *copy=task.mutableCopy;copy[@"subject"]=course[@"name"];[rows addObject:copy];}return rows;}
