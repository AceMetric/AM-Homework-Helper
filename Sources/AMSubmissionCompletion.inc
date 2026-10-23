// Completion decisions are committed with tasks and submission records.
static NSString *AMCompletionPath(id value){
    if(![value isKindOfClass:NSString.class] || ![value length] || [value hasPrefix:@"/"] || [value containsString:@"\\"] || SSSensitivePath(value))return nil;
    for(NSString *part in [value componentsSeparatedByString:@"/"])if(!part.length || [@[@".",@".."] containsObject:part])return nil;return value;
}
BOOL AMTaskBelongsToCourse(NSDictionary *task,NSDictionary *course){if(!course)return NO;if(task[@"courseID"]){NSArray *catalog=AMCourseCatalog(course[@"fork"] ? @[course]:@[]);NSDictionary *linked=AMCourseForTask(task,catalog);NSString *identifier=course[@"courseID"] ?: course[@"id"] ?: ([course[@"fork"] length] ? AMRepositoryCourseID(course[@"fork"]):@"");return [task[@"courseID"] length] && ([task[@"courseID"] isEqual:identifier] || ([linked[@"fork"] length] && [linked[@"fork"] isEqual:course[@"fork"]]));}if([task[@"courseRepository"] length])return [task[@"courseRepository"] isEqual:course[@"fork"]];return [task[@"sourceRepository"] length] && [task[@"sourceRepository"] isEqual:course[@"upstream"]];}
static NSString *AMCompletionIdentity(NSDictionary *record){return [NSString stringWithFormat:@"%@|%@|%@",[record[@"repository"] lowercaseString],record[@"branch"],record[@"commit"] ?: @""];}
static BOOL AMCompletionAnswerFile(NSString *file){
    for(NSString *component in file.pathComponents)if([component hasPrefix:@"."] || [@[@"node_modules",@"build",@"dist",@"vendor",@"__pycache__"] containsObject:component.lowercaseString])return NO;
    NSString *name=file.lastPathComponent.lowercaseString;
    // Teacher statements and repository metadata do not prove an answer was submitted.
    if([@[@"readme.md",@"readme",@"readme.txt",@"license",@"license.md",@".gitignore",@".gitattributes",@"requirements.txt",@"package-lock.json"] containsObject:name] || [name hasPrefix:@"."])return NO;
    return YES;
}
static NSString *AMCompletionFolder(NSString *source){
    NSArray *parts=[source componentsSeparatedByString:@"/"];for(NSUInteger i=0;i+1<parts.count;i++)if([parts[i] rangeOfString:@"^(assignment|project)[-_ ]?[0-9a-z]+$" options:NSRegularExpressionSearch|NSCaseInsensitiveSearch].location!=NSNotFound)return [[parts subarrayWithRange:NSMakeRange(0,i+1)] componentsJoinedByString:@"/"];
    return source.stringByDeletingLastPathComponent;
}
static NSArray *AMCompletionMatches(NSDictionary *record,NSDictionary *course,NSArray *tasks,NSArray *records){
    NSMutableSet *ids=NSMutableSet.set;
    if([record[@"taskIDs"] count]){for(NSDictionary *task in tasks)if([record[@"taskIDs"] containsObject:task[@"id"]] && AMTaskBelongsToCourse(task,course))[ids addObject:task[@"id"]];return ids.allObjects;}
    NSMutableSet *sources=NSMutableSet.set;for(NSDictionary *task in tasks)if(AMTaskBelongsToCourse(task,course) && AMCompletionPath(task[@"sourcePath"]))[sources addObject:task[@"sourcePath"]];
    for(NSString *file in record[@"completionFiles"] ?: @[]){if(!AMCompletionPath(file) || !AMCompletionAnswerFile(file) || !file.stringByDeletingLastPathComponent.length || [sources containsObject:file])continue;NSMutableSet *bound=NSMutableSet.set;
        for(NSDictionary *old in records)if([old[@"repository"] isEqual:record[@"repository"]] && [old[@"branch"] isEqual:record[@"branch"]] && [old[@"files"] containsObject:file])for(NSDictionary *task in tasks)if(AMTaskBelongsToCourse(task,course) && ![task[@"deleted"] boolValue] && ![task[@"archived"] boolValue] && [old[@"taskIDs"] containsObject:task[@"id"]])[bound addObject:task[@"id"]];
        if(bound.count==1){[ids unionSet:bound];continue;}if(bound.count>1)continue;
        NSMutableSet *folderMatches=NSMutableSet.set;NSUInteger longest=0;
        for(NSDictionary *task in tasks){if(!AMTaskBelongsToCourse(task,course) || [task[@"deleted"] boolValue] || [task[@"archived"] boolValue])continue;NSString *source=AMCompletionPath(task[@"sourcePath"]);NSString *folder=AMCompletionFolder(source);
            if(!AMCompletionAnswerFile(file) || !folder.length || [folder isEqual:@"."] || [file isEqual:source] || ![file hasPrefix:[folder stringByAppendingString:@"/"]])continue;
            if(folder.length>longest){[folderMatches removeAllObjects];longest=folder.length;}if(folder.length==longest)[folderMatches addObject:task[@"id"]];
        }if(folderMatches.count==1)[ids unionSet:folderMatches];
    }return ids.allObjects;
}
NSDictionary *AMSubmissionCompletionPlan(NSArray *tasks,NSArray *records,NSArray *courses,NSSet *deferred){
    NSMutableArray *nextTasks=[[NSArray alloc] initWithArray:tasks copyItems:YES].mutableCopy,*nextRecords=NSMutableArray.array,*completed=NSMutableArray.array;
    NSMutableDictionary *identityDecisions=NSMutableDictionary.dictionary;
    for(NSDictionary *record in records){NSString *key=AMCompletionIdentity(record);NSMutableDictionary *all=identityDecisions[key] ?: NSMutableDictionary.dictionary;for(NSString *identifier in record[@"completionDecisions"]){NSDictionary *decision=record[@"completionDecisions"][identifier];if(!all[identifier] || [decision[@"state"] isEqual:@"dismissed"])all[identifier]=decision;}identityDecisions[key]=all;}
    for(NSDictionary *record in records){NSMutableDictionary *next=record.mutableCopy;[nextRecords addObject:next];NSDictionary *course=nil;for(NSDictionary *c in courses)if([c[@"fork"] isEqual:record[@"repository"]] && [c[@"branch"] isEqual:record[@"branch"]]){course=c;break;}
        if(!course || ![record[@"completionFiles"] count] || ![record[@"state"] isEqual:@"confirmed"] || !AMCompletionHash(record[@"commit"]) || !AMCompletionHash(record[@"remoteCommit"]) || ![record[@"checkedAt"] isKindOfClass:NSDate.class] || ![@[@"submission",@"existing"] containsObject:record[@"kind"]])continue;
        if(course[@"completionEpoch"] && ![(record[@"completionEpoch"] ?: @"initial") isEqual:course[@"completionEpoch"]])continue;
        if([record[@"teacherHistoryExcluded"] boolValue] || (([record[@"kind"] isEqual:@"existing"] || [record[@"origin"] isEqual:@"external"]) && ![record[@"teacherHistoryKnown"] boolValue]))continue;
        if([record[@"origin"] isEqual:@"external"] && [record[@"completionEligibility"] isEqual:@"new"] && course[@"completionAnchor"] && ![record[@"completionAnchor"] isEqual:course[@"completionAnchor"]]){next[@"completionStatus"]=@"historical";continue;}
        if(![@[@"new",@"associated"] containsObject:record[@"completionEligibility"]]){next[@"completionStatus"]=@"historical";continue;}
        NSMutableArray *matched=[AMCompletionMatches(record,course,nextTasks,records) mutableCopy];
        if(![record[@"taskIDs"] count]){NSUInteger owners=0;for(NSDictionary *c in courses)if([c[@"upstream"] isEqual:course[@"upstream"]])owners++;if(owners>1)for(NSDictionary *task in nextTasks)if(![task[@"courseRepository"] length])[matched removeObject:task[@"id"]];}
        if(!matched.count){next[@"completionStatus"]=@"waiting";continue;}
        NSMutableDictionary *decisions=identityDecisions[AMCompletionIdentity(record)];BOOL waiting=NO,applied=NO;NSMutableOrderedSet *links=[NSMutableOrderedSet orderedSetWithArray:record[@"taskIDs"]];
        for(NSUInteger i=0;i<nextTasks.count;i++){NSDictionary *task=nextTasks[i];NSString *identifier=task[@"id"];if(![matched containsObject:identifier] || decisions[identifier])continue;
            if([task[@"completed"] boolValue] || [task[@"deleted"] boolValue] || [task[@"archived"] boolValue]){decisions[identifier]=@{@"state":@"ignored",@"date":NSDate.date};continue;}
            if([deferred containsObject:identifier] || -[record[@"checkedAt"] timeIntervalSinceNow]>300){waiting=YES;continue;}
            NSMutableDictionary *done=[DDLTaskCompletion(task,YES) mutableCopy];done[@"completionEvidence"]=@{@"recordID":record[@"id"],@"repository":record[@"repository"],@"branch":record[@"branch"],@"commit":record[@"commit"],@"verifiedAt":record[@"checkedAt"]};nextTasks[i]=done;
            decisions[identifier]=@{@"state":@"completed",@"date":NSDate.date};[completed addObject:identifier];[links addObject:identifier];applied=YES;
        }
        next[@"taskIDs"]=links.array;next[@"completionDecisions"]=decisions.copy;BOOL hasCompletion=applied;for(NSDictionary *decision in decisions.allValues)if([decision[@"state"] isEqual:@"completed"])hasCompletion=YES;next[@"completionStatus"]=waiting ? @"deferred":(hasCompletion ? @"completed":@"ignored");
    }
    return @{@"tasks":nextTasks,@"records":nextRecords,@"completedIDs":completed};
}
NSDictionary *AMApplySubmissionCompletions(NSArray *previous,NSArray *courses,NSSet *deferred,NSArray *series,NSDictionary *overrides,NSError **error){
    @synchronized(NSFileManager.defaultManager){NSDictionary *settings=AMSubmissionAutomation(error);NSArray *records=AMSubmissionRecords(error);if(!settings || !records)return nil;
        if(![settings[@"enabled"] boolValue])return @{@"tasks":previous,@"completedIDs":@[]};
        NSMutableArray *verifiedCourses=NSMutableArray.array;for(NSDictionary *course in courses){NSDictionary *baseline=AMSubmissionBaseline(course,error);if(!baseline)return nil;NSMutableDictionary *copy=course.mutableCopy;copy[@"completionAnchor"]=baseline[@"anchor"] ?: @"";copy[@"completionEpoch"]=settings[@"epoch"] ?: @"initial";[verifiedCourses addObject:copy];}
        NSDictionary *plan=AMSubmissionCompletionPlan(previous,records,verifiedCourses,deferred);NSArray *tasks=plan[@"tasks"];
        if([plan[@"completedIDs"] count]){NSCalendar *calendar=[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];calendar.timeZone=[NSTimeZone timeZoneWithName:@"Asia/Shanghai"];tasks=DDLMaterializeRecurringTasks(tasks,series,[calendar startOfDayForDate:NSDate.date],[calendar dateByAddingUnit:NSCalendarUnitDay value:90 toDate:NSDate.date options:0],overrides,error);if(!tasks || !AMStoreSchedule(previous,tasks,plan[@"records"],series,overrides,error))return nil;}
        else if(![records isEqual:plan[@"records"]] && !SSWritePlist(@"submission-records.plist",plan[@"records"],error))return nil;
        return @{@"tasks":tasks,@"completedIDs":plan[@"completedIDs"]};
    }
}
BOOL AMSaveTasksWithSubmissionDecisions(NSArray *previous,NSArray *tasks,NSArray *series,NSDictionary *overrides,NSError **error){
    @synchronized(NSFileManager.defaultManager){NSArray *records=AMSubmissionRecords(error);if(!records)return NO;NSMutableArray *nextRecords=[[NSArray alloc] initWithArray:records copyItems:YES].mutableCopy;
        for(NSDictionary *old in previous)if([old[@"completed"] boolValue] && old[@"completionEvidence"]){NSDictionary *now=nil;for(NSDictionary *t in tasks)if([t[@"id"] isEqual:old[@"id"]]){now=t;break;}if(!now || [now[@"completed"] boolValue])continue;
            NSDictionary *e=old[@"completionEvidence"];for(NSUInteger i=0;i<nextRecords.count;i++){NSDictionary *record=nextRecords[i];if(![record[@"repository"] isEqual:e[@"repository"]] || ![record[@"branch"] isEqual:e[@"branch"]] || ![record[@"commit"] isEqual:e[@"commit"]])continue;NSMutableDictionary *r=record.mutableCopy,*decisions=[r[@"completionDecisions"] mutableCopy] ?: NSMutableDictionary.dictionary;decisions[old[@"id"]]=@{@"state":@"dismissed",@"date":NSDate.date};r[@"completionDecisions"]=decisions;nextRecords[i]=r;}
        }
        return AMStoreSchedule(previous,tasks,nextRecords,series,overrides,error);
    }
}
