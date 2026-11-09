// Completion decisions are committed with tasks and submission records.
static NSString *AMCompletionPath(id value){
    if(![value isKindOfClass:NSString.class] || ![value length] || [value hasPrefix:@"/"] || [value containsString:@"\\"] || SSSensitivePath(value))return nil;
    for(NSString *part in [value componentsSeparatedByString:@"/"])if(!part.length || [@[@".",@".."] containsObject:part])return nil;return value;
}
// Resolve the catalog once per calculation; matching itself must never touch disk.
static BOOL AMTaskBelongsToCourseInCatalog(NSDictionary *task,NSDictionary *course,NSArray *catalog){
    if(!course)return NO;
    if(task[@"courseID"]){NSDictionary *linked=AMCourseForTask(task,catalog);NSString *identifier=course[@"courseID"] ?: course[@"id"] ?: ([course[@"fork"] length] ? AMRepositoryCourseID(course[@"fork"]):@"");return [task[@"courseID"] length] && ([task[@"courseID"] isEqual:identifier] || ([linked[@"fork"] length] && [linked[@"fork"] isEqual:course[@"fork"]]));}
    if([task[@"courseRepository"] length])return [task[@"courseRepository"] isEqual:course[@"fork"]];
    return [task[@"sourceRepository"] length] && [task[@"sourceRepository"] isEqual:course[@"upstream"]];
}
BOOL AMTaskBelongsToCourse(NSDictionary *task,NSDictionary *course){return AMTaskBelongsToCourseInCatalog(task,course,task[@"courseID"] ? AMCourseCatalog(course[@"fork"] ? @[course]:@[]):@[]);}
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
static NSString *AMCompletionFileKey(NSDictionary *record,NSString *file){return [NSString stringWithFormat:@"%@|%@|%@",record[@"repository"],record[@"branch"],file];}
static NSArray *AMCompletionMatches(NSDictionary *record,NSArray *tasks,NSDictionary *tasksByID,NSDictionary *fileLinks){
    NSMutableSet *ids=NSMutableSet.set;
    if([record[@"taskIDs"] count]){for(NSString *identifier in record[@"taskIDs"])if(tasksByID[identifier])[ids addObject:identifier];return ids.allObjects;}
    NSMutableSet *sources=NSMutableSet.set;for(NSDictionary *task in tasks)if(AMCompletionPath(task[@"sourcePath"]))[sources addObject:task[@"sourcePath"]];
    for(NSString *file in record[@"completionFiles"] ?: @[]){
        if(!AMCompletionPath(file) || !AMCompletionAnswerFile(file) || !file.stringByDeletingLastPathComponent.length || [sources containsObject:file])continue;
        NSMutableSet *bound=NSMutableSet.set;
        for(NSString *identifier in fileLinks[AMCompletionFileKey(record,file)]){NSDictionary *task=tasksByID[identifier];if(task && ![task[@"deleted"] boolValue] && ![task[@"archived"] boolValue])[bound addObject:identifier];}
        if(bound.count==1){[ids unionSet:bound];continue;}if(bound.count>1)continue;
        NSMutableSet *folderMatches=NSMutableSet.set;NSUInteger longest=0;
        for(NSDictionary *task in tasks){if([task[@"deleted"] boolValue] || [task[@"archived"] boolValue])continue;NSString *source=AMCompletionPath(task[@"sourcePath"]),*folder=AMCompletionFolder(source);
            if(!folder.length || [folder isEqual:@"."] || [file isEqual:source] || ![file hasPrefix:[folder stringByAppendingString:@"/"]])continue;
            if(folder.length>longest){[folderMatches removeAllObjects];longest=folder.length;}if(folder.length==longest)[folderMatches addObject:task[@"id"]];
        }if(folderMatches.count==1)[ids unionSet:folderMatches];
    }return ids.allObjects;
}
static NSDictionary *AMCompletionPlanWithCatalog(NSArray *tasks,NSArray *records,NSArray *courses,NSSet *deferred,NSArray *catalog){
    NSMutableDictionary *courseIndex=NSMutableDictionary.dictionary,*taskIndex=NSMutableDictionary.dictionary,*fileLinks=NSMutableDictionary.dictionary;
    for(NSDictionary *course in courses){NSString *key=AMCompletionCourseKey(course);NSMutableArray *members=NSMutableArray.array;NSMutableDictionary *byID=NSMutableDictionary.dictionary;
        for(NSDictionary *task in tasks)if(AMTaskBelongsToCourseInCatalog(task,course,catalog)){[members addObject:task];byID[task[@"id"]]=task;}
        courseIndex[key]=course;taskIndex[key]=@{@"tasks":members,@"byID":byID};
    }
    // Build explicit file associations once, rather than scanning all history for every file.
    for(NSDictionary *record in records)for(NSString *file in record[@"files"]){NSString *key=AMCompletionFileKey(record,file);NSMutableSet *links=fileLinks[key] ?: NSMutableSet.set;[links addObjectsFromArray:record[@"taskIDs"] ?: @[]];fileLinks[key]=links;}
    NSMutableArray *nextTasks=[[NSArray alloc] initWithArray:tasks copyItems:YES].mutableCopy,*nextRecords=NSMutableArray.array,*completed=NSMutableArray.array;
    NSMutableDictionary *identityDecisions=NSMutableDictionary.dictionary;
    for(NSDictionary *record in records){NSString *key=AMCompletionIdentity(record);NSMutableDictionary *all=identityDecisions[key] ?: NSMutableDictionary.dictionary;for(NSString *identifier in record[@"completionDecisions"]){NSDictionary *decision=record[@"completionDecisions"][identifier];if(!all[identifier] || [decision[@"state"] isEqual:@"dismissed"])all[identifier]=decision;}identityDecisions[key]=all;}
    for(NSDictionary *record in records){NSMutableDictionary *next=record.mutableCopy;[nextRecords addObject:next];NSString *courseKey=AMCompletionCourseKey(@{@"fork":record[@"repository"],@"branch":record[@"branch"]});NSDictionary *course=courseIndex[courseKey];
        if(!course || ![record[@"completionFiles"] count] || ![record[@"state"] isEqual:@"confirmed"] || !AMCompletionHash(record[@"commit"]) || !AMCompletionHash(record[@"remoteCommit"]) || ![record[@"checkedAt"] isKindOfClass:NSDate.class] || ![@[@"submission",@"existing"] containsObject:record[@"kind"]])continue;
        if(course[@"completionEpoch"] && ![(record[@"completionEpoch"] ?: @"initial") isEqual:course[@"completionEpoch"]])continue;
        if([record[@"teacherHistoryExcluded"] boolValue] || (([record[@"kind"] isEqual:@"existing"] || [record[@"origin"] isEqual:@"external"]) && ![record[@"teacherHistoryKnown"] boolValue]))continue;
        if([record[@"origin"] isEqual:@"external"] && [record[@"completionEligibility"] isEqual:@"new"] && course[@"completionAnchor"] && ![record[@"completionAnchor"] isEqual:course[@"completionAnchor"]]){next[@"completionStatus"]=@"historical";continue;}
        if(![@[@"new",@"associated"] containsObject:record[@"completionEligibility"]]){next[@"completionStatus"]=@"historical";continue;}
        NSMutableArray *matched=[AMCompletionMatches(record,taskIndex[courseKey][@"tasks"],taskIndex[courseKey][@"byID"],fileLinks) mutableCopy];
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
NSDictionary *AMSubmissionCompletionPlan(NSArray *tasks,NSArray *records,NSArray *courses,NSSet *deferred){return AMCompletionPlanWithCatalog(tasks,records,courses,deferred,AMCourseCatalog(courses));}
NSDictionary *AMPrepareSubmissionCompletions(NSArray *previous,NSArray *courses,NSSet *deferred,NSArray *series,NSError **error){
    NSDictionary *settings;NSArray *records,*catalog,*storedTasks,*storedSeries;NSDictionary *overrides;
    @synchronized(NSFileManager.defaultManager){settings=AMSubmissionAutomation(error);records=AMSubmissionRecords(error);NSArray *stored=AMStoredCourses(error);if(!stored)return nil;catalog=AMCourseCatalogFromSnapshot(stored,courses);overrides=SSCalendarOverrides();storedTasks=SSReadPlist(@"tasks.plist") ?: @[];storedSeries=SSRecurrenceSeries(error);}
    if(!settings || !records || !storedSeries)return nil;
    NSMutableArray *verifiedCourses=NSMutableArray.array;
    for(NSDictionary *course in courses){NSMutableDictionary *copy=course.mutableCopy;copy[@"completionAnchor"]=settings[@"baselines"][AMCompletionCourseKey(course)][@"anchor"] ?: @"";copy[@"completionEpoch"]=settings[@"epoch"] ?: @"initial";[verifiedCourses addObject:copy];}
    NSMutableArray *freshness=NSMutableArray.array;for(NSDictionary *record in records)if(-[record[@"checkedAt"] timeIntervalSinceNow]>300)[freshness addObject:record[@"id"]];
    NSDictionary *input=@{@"storedTasks":storedTasks,@"storedSeries":storedSeries,@"expired":freshness,@"tasks":previous,@"records":records,@"courses":verifiedCourses,@"catalog":catalog,@"series":series,@"overrides":overrides,@"settings":settings,@"deferred":deferred};
    // One bounded cache, including edit ownership and source versions. No history of task bodies.
    static NSDictionary *lastInput,*lastPlan;static NSObject *cacheLock;static dispatch_once_t once;dispatch_once(&once,^{cacheLock=NSObject.new;});
    NSDictionary *plan;
    @synchronized(cacheLock){plan=[lastInput isEqual:input] ? lastPlan:nil;}
    if(!plan){plan=[settings[@"enabled"] boolValue] ? AMCompletionPlanWithCatalog(previous,records,verifiedCourses,deferred,catalog):@{@"tasks":previous,@"records":records,@"completedIDs":@[]};
        NSArray *tasks=plan[@"tasks"];
        if([plan[@"completedIDs"] count]){NSCalendar *calendar=[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];calendar.timeZone=[NSTimeZone timeZoneWithName:@"Asia/Shanghai"];tasks=DDLMaterializeRecurringTasks(tasks,series,[calendar startOfDayForDate:NSDate.date],[calendar dateByAddingUnit:NSCalendarUnitDay value:90 toDate:NSDate.date options:0],overrides,error);if(!tasks)return nil;NSMutableDictionary *copy=plan.mutableCopy;copy[@"tasks"]=tasks;plan=copy;}
        // 课程页使用同一份提交快照，渲染时按任务与分支查找，避免重新读提交历史。
        NSMutableDictionary *assignments=NSMutableDictionary.dictionary,*verified=NSMutableDictionary.dictionary;
        for(NSDictionary *record in plan[@"records"]){
            if([record[@"teacherHistoryExcluded"] boolValue])continue;
            for(NSString *taskID in record[@"taskIDs"]){
                NSArray *key=@[record[@"repository"],record[@"branch"],taskID];
                if(!assignments[key] || [record[@"date"] compare:assignments[key][@"date"]]!=NSOrderedAscending)assignments[key]=record;
                NSDate *date=record[@"verifiedAt"] ?: record[@"confirmedAt"];
                if(date && (!verified[key] || [date compare:verified[key][@"time"]]==NSOrderedDescending))
                    verified[key]=@{@"commit":record[@"commit"] ?: @"",@"time":date,@"state":record[@"state"] ?: @""};
            }
        }
        for(NSArray *key in verified){
            NSMutableDictionary *row=[assignments[key] mutableCopy];
            row[@"lastVerified"]=verified[key];assignments[key]=row;
        }
        NSMutableDictionary *indexed=plan.mutableCopy;
        indexed[@"assignments"]=assignments.copy;
        plan=indexed;
        @synchronized(cacheLock){lastInput=input;lastPlan=plan;}
    }
    return @{@"input":input,@"plan":plan};
}
NSDictionary *AMCommitSubmissionCompletions(NSDictionary *prepared,NSArray *current,NSSet *deferred,NSArray *series,NSError **error){
    NSDictionary *input=prepared[@"input"],*plan=prepared[@"plan"];
    // This short commit runs on the UI event queue: editing cannot start between its guard
    // and publication. Only persistence is locked; matching and recurrence run off-thread.
    if(![current isEqual:input[@"tasks"]] || ![series isEqual:input[@"series"]])return @{@"stale":@YES};
    for(NSString *identifier in plan[@"completedIDs"])if([deferred containsObject:identifier])return @{@"stale":@YES};
    NSMutableArray *expired=NSMutableArray.array;for(NSDictionary *record in input[@"records"])if(-[record[@"checkedAt"] timeIntervalSinceNow]>300)[expired addObject:record[@"id"]];if(![expired isEqual:input[@"expired"]])return @{@"stale":@YES};
    @synchronized(NSFileManager.defaultManager){
        if(![(SSReadPlist(@"tasks.plist") ?: @[]) isEqual:input[@"storedTasks"]] || ![SSRecurrenceSeries(error) isEqual:input[@"storedSeries"]] || ![AMSubmissionRecords(error) isEqual:input[@"records"]] || ![AMSubmissionAutomation(error) isEqual:input[@"settings"]] || ![SSCalendarOverrides() isEqual:input[@"overrides"]] || ![AMCourseCatalog(input[@"courses"]) isEqual:input[@"catalog"]])return (error && *error) ? nil:@{@"stale":@YES};
        if([plan[@"completedIDs"] count]){if(!AMStoreSchedule(current,plan[@"tasks"],plan[@"records"],series,input[@"overrides"],error))return nil;}
        else if(![input[@"records"] isEqual:plan[@"records"]] && !SSWritePlist(@"submission-records.plist",plan[@"records"],error))return nil;
    }
    return @{@"tasks":plan[@"tasks"],@"completedIDs":plan[@"completedIDs"],@"assignments":plan[@"assignments"] ?: @{}};
}
NSDictionary *AMApplySubmissionCompletions(NSArray *previous,NSArray *courses,NSSet *deferred,NSArray *series,NSDictionary *overrides,NSError **error){
    NSDictionary *prepared=AMPrepareSubmissionCompletions(previous,courses,deferred,series,error);if(prepared && ![overrides isEqual:prepared[@"input"][@"overrides"]])return @{@"stale":@YES};return prepared ? AMCommitSubmissionCompletions(prepared,previous,deferred,series,error):nil;
}
BOOL AMSaveTasksWithSubmissionDecisions(NSArray *previous,NSArray *tasks,NSArray *series,NSDictionary *overrides,NSError **error){
    @synchronized(NSFileManager.defaultManager){NSArray *records=AMSubmissionRecords(error);if(!records)return NO;NSMutableArray *nextRecords=[[NSArray alloc] initWithArray:records copyItems:YES].mutableCopy;
        for(NSDictionary *old in previous)if([old[@"completed"] boolValue] && old[@"completionEvidence"]){NSDictionary *now=nil;for(NSDictionary *t in tasks)if([t[@"id"] isEqual:old[@"id"]]){now=t;break;}if(!now || [now[@"completed"] boolValue])continue;
            NSDictionary *e=old[@"completionEvidence"];for(NSUInteger i=0;i<nextRecords.count;i++){NSDictionary *record=nextRecords[i];if(![record[@"repository"] isEqual:e[@"repository"]] || ![record[@"branch"] isEqual:e[@"branch"]] || ![record[@"commit"] isEqual:e[@"commit"]])continue;NSMutableDictionary *r=record.mutableCopy,*decisions=[r[@"completionDecisions"] mutableCopy] ?: NSMutableDictionary.dictionary;decisions[old[@"id"]]=@{@"state":@"dismissed",@"date":NSDate.date};r[@"completionDecisions"]=decisions;nextRecords[i]=r;}
        }
        return AMStoreSchedule(previous,tasks,nextRecords,series,overrides,error);
    }
}
