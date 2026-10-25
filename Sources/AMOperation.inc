#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
NSNotificationName const AMOperationsChanged=@"AMOperationsChanged";
static NSMutableDictionary *AMOperationRows,*AMOperationCancels,*AMScheduledJobs;
static NSUInteger AMJobSequence;
static NSObject *AMOperationLock(void){static NSObject *lock;static dispatch_once_t once;dispatch_once(&once,^{lock=NSObject.new;AMOperationRows=NSMutableDictionary.dictionary;AMOperationCancels=NSMutableDictionary.dictionary;AMScheduledJobs=NSMutableDictionary.dictionary;});return lock;}
static void AMOperationNotify(void){dispatch_async(dispatch_get_main_queue(),^{[NSNotificationCenter.defaultCenter postNotificationName:AMOperationsChanged object:nil];});}
static NSString *AMResourceIdentity(NSString *claim){return [claim hasPrefix:@"read|"] ? [claim substringFromIndex:5]:claim;}
static BOOL AMResourceConflicts(NSString *a,NSString *b){return [AMResourceIdentity(a) isEqual:AMResourceIdentity(b)] && !([a hasPrefix:@"read|"] && [b hasPrefix:@"read|"]);}
static NSString *AMResourceHash(NSString *value){NSData *data=[value dataUsingEncoding:NSUTF8StringEncoding];unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);NSMutableString *text=NSMutableString.string;for(NSUInteger i=0;i<sizeof(digest);i++)[text appendFormat:@"%02x",digest[i]];return text;}
static NSString *AMResourceLocation(NSString *path){struct stat info;if(stat(path.fileSystemRepresentation,&info)==0)return [NSString stringWithFormat:@"%llu:%llu",(unsigned long long)info.st_dev,(unsigned long long)info.st_ino];return path;}
static NSString *AMRepositoryPointer(NSString *path){int fd=open(path.fileSystemRepresentation,O_RDONLY|O_NONBLOCK|O_CLOEXEC);if(fd<0)return nil;struct stat info;char bytes[4096];ssize_t count=-1;if(fstat(fd,&info)==0 && S_ISREG(info.st_mode) && info.st_size>0 && info.st_size<(off_t)sizeof(bytes))count=read(fd,bytes,sizeof(bytes));close(fd);return count>0 ? [[[NSString alloc] initWithBytes:bytes length:(NSUInteger)count encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]:nil;}
NSArray *AMRepositoryResources(NSDictionary *course,NSString *access){
    NSString *root=[course[@"path"] stringByResolvingSymlinksInPath].stringByStandardizingPath;if(!root.length)return @[];
    NSString *git=[root stringByAppendingPathComponent:@".git"];BOOL directory=NO;
    if([NSFileManager.defaultManager fileExistsAtPath:git isDirectory:&directory] && !directory){NSString *line=AMRepositoryPointer(git);if([line hasPrefix:@"gitdir: "]){NSString *target=[line substringFromIndex:8];git=target.isAbsolutePath ? target:[root stringByAppendingPathComponent:target];}}
    git=git.stringByResolvingSymlinksInPath.stringByStandardizingPath;
    NSString *common=git,*target=AMRepositoryPointer([git stringByAppendingPathComponent:@"commondir"]);if(target.length)common=(target.isAbsolutePath ? target:[git stringByAppendingPathComponent:target]).stringByResolvingSymlinksInPath.stringByStandardizingPath;
    NSString *metadata=[@"repository:" stringByAppendingString:AMResourceHash(AMResourceLocation(common))],*worktree=[@"worktree:" stringByAppendingString:AMResourceHash(AMResourceLocation(root))];
    if([access isEqual:@"read"])return @[[ @"read|" stringByAppendingString:worktree]];
    if([access isEqual:@"fetch"])return @[metadata];
    return @[metadata,worktree];
}
NSInteger AMCurrentOperationPriority(void){NSString *parent=NSThread.currentThread.threadDictionary[@"AMOperationParent"];@synchronized(AMOperationLock()){return parent && AMScheduledJobs[parent] ? [AMScheduledJobs[parent][@"priority"] integerValue]:100;}}
static void AMOperationWait(NSMutableDictionary *row,NSArray *blockers){
    if(!blockers.count){[row removeObjectForKey:@"blockedBy"];[row removeObjectForKey:@"waitReason"];[row removeObjectForKey:@"waitDetails"];[row removeObjectForKey:@"waitingAt"];return;}
    NSMutableArray *ids=NSMutableArray.array,*details=NSMutableArray.array;BOOL repository=NO;for(NSString *claim in row[@"resources"]){NSString *resource=AMResourceIdentity(claim);if([resource hasPrefix:@"repository:"] || [resource hasPrefix:@"worktree:"])repository=YES;}NSString *reason=repository ? @"等待仓库操作完成…":@"排队中";
    for(NSDictionary *blocker in blockers){if([ids containsObject:blocker[@"id"]])continue;[ids addObject:blocker[@"id"]];NSString *kind=blocker[@"kind"] ?: @"操作";[details addObject:[NSString stringWithFormat:@"%@ · %@",[blocker[@"target"] lastPathComponent] ?: @"",kind]];if(!repository)continue;if([kind containsString:@"合并"] || [kind containsString:@"同步"])reason=@"等待课程同步完成…";else if([kind containsString:@"提交"] || [kind containsString:@"推送"])reason=@"等待另一项提交完成…";else if([kind containsString:@"获取老师"])reason=@"等待老师更新完成…";}
    if(![row[@"blockedBy"] isEqual:ids])row[@"waitingAt"]=NSDate.date;row[@"blockedBy"]=ids;row[@"waitReason"]=[row[@"resources"] containsObject:@"limit:background-course"] ? @"等待其他课程检查…":reason;row[@"waitDetails"]=[details componentsJoinedByString:@"\n"];
}
static void AMOperationPump(void){
    NSMutableArray *launch=NSMutableArray.array;
    @synchronized(AMOperationLock()){
        NSArray *ordered=[AMScheduledJobs.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){NSComparisonResult priority=[b[@"priority"] compare:a[@"priority"]];return priority==NSOrderedSame ? [a[@"sequence"] compare:b[@"sequence"]]:priority;}];
        NSMutableArray *waiting=NSMutableArray.array;
        for(NSMutableDictionary *job in ordered){
            NSMutableDictionary *row=AMOperationRows[job[@"id"]];if(![row[@"state"] isEqual:@"queued"])continue;
            NSMutableArray *blockers=NSMutableArray.array;
            for(NSString *resource in job[@"resources"]){NSUInteger capacity=[resource isEqual:@"limit:background-course"] ? 2:1;NSMutableArray *owners=NSMutableArray.array;
                for(NSDictionary *active in ordered){NSDictionary *other=AMOperationRows[active[@"id"]];if(![other[@"state"] isEqual:@"running"] || [active[@"resourcesReleased"] boolValue])continue;for(NSString *held in active[@"resources"])if(AMResourceConflicts(resource,held)){[owners addObject:other];break;}}
                if(owners.count>=capacity)[blockers addObjectsFromArray:owners];
                // Do not let new readers or low priority work starve a queued writer.
                if(capacity==1)for(NSDictionary *pending in waiting)for(NSString *held in pending[@"resources"])if(AMResourceConflicts(resource,held)){[blockers addObject:AMOperationRows[pending[@"id"]]];break;}
            }
            AMOperationWait(row,blockers);NSMutableDictionary *parent=row[@"parent"] ? AMOperationRows[row[@"parent"]]:nil;if(parent){AMOperationWait(parent,blockers);}
            if(blockers.count){[waiting addObject:job];continue;}
            row[@"state"]=@"running";row[@"stage"]=row[@"kind"];row[@"runningAt"]=NSDate.date;row[@"cancellable"]=@(job[@"cancel"]!=nil && [job[@"cancellableWhileRunning"] boolValue]);[launch addObject:job];
        }
    }
    for(NSDictionary *job in launch)dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
        void(^start)(NSString *)=job[@"start"];
        @try{start(job[@"id"]);}@catch(NSException *exception){AMOperationFinish(job[@"id"],@"failed",SSRedactedText(exception.reason ?: @"后台任务未完成"));}
    }});
    if(launch.count)AMOperationNotify();
}
NSString *AMOperationBegin(NSString *kind,NSString *target,BOOL cancellable,void (^cancel)(void)){return AMOperationBeginWithExitPolicy(kind,target,cancellable,YES,cancel);}
NSString *AMOperationBeginWithExitPolicy(NSString *kind,NSString *target,BOOL cancellable,BOOL blocksExit,void (^cancel)(void)){
    NSString *key=NSUUID.UUID.UUIDString;@synchronized(AMOperationLock()){
        AMOperationRows[key]=[@{@"id":key,@"kind":kind,@"target":target ?: @"",@"stage":kind,@"started":NSDate.date,@"state":@"running",@"completed":@0,@"total":@0,@"cancellable":@(cancellable),@"blocksExit":@(blocksExit)} mutableCopy];
        NSString *parent=NSThread.currentThread.threadDictionary[@"AMOperationParent"];if(parent && AMOperationRows[parent])AMOperationRows[key][@"parent"]=parent;
        if(cancel && cancellable)AMOperationCancels[key]=[cancel copy];
        if(AMOperationRows.count>80){NSArray *sorted=[AMOperationRows.allValues sortedArrayUsingComparator:^NSComparisonResult(id a,id b){return [a[@"started"] compare:b[@"started"]];}];for(NSDictionary *row in sorted)if(AMOperationRows.count>80 && ![@[@"running",@"queued"] containsObject:row[@"state"]])[AMOperationRows removeObjectForKey:row[@"id"]];}
    }AMOperationNotify();return key;
}
NSString *AMOperationEnqueue(NSString *key,NSString *kind,NSString *target,NSArray *resources,NSInteger priority,void (^start)(NSString *),void (^cancel)(BOOL)){return AMOperationSchedule(key,kind,target,resources,priority,cancel!=nil,start,cancel);}
NSString *AMOperationSchedule(NSString *key,NSString *kind,NSString *target,NSArray *resources,NSInteger priority,BOOL cancellableWhileRunning,void (^start)(NSString *),void (^cancel)(BOOL)){
    NSString *identifier;
    @synchronized(AMOperationLock()){
        for(NSMutableDictionary *job in AMScheduledJobs.allValues)if([job[@"key"] isEqual:key]){if(priority>[job[@"priority"] integerValue])job[@"priority"]=@(priority);return job[@"id"];}
        identifier=AMOperationBegin(kind,target,NO,nil);
        NSMutableDictionary *job=[@{@"id":identifier,@"key":key,@"resources":resources.copy,@"priority":@(priority),@"cancellableWhileRunning":@(cancellableWhileRunning),@"sequence":@(AMJobSequence++),@"start":[start copy]} mutableCopy];if(cancel)job[@"cancel"]=[cancel copy];AMScheduledJobs[identifier]=job;
        NSMutableDictionary *row=AMOperationRows[identifier];row[@"resources"]=resources.copy;row[@"state"]=@"queued";row[@"stage"]=@"排队中，等待当前操作安全结束";row[@"cancellable"]=@YES;
    }AMOperationNotify();AMOperationPump();return identifier;
}
void AMOperationReleaseResources(NSString *identifier){if(!identifier)return;@synchronized(AMOperationLock()){AMScheduledJobs[identifier][@"resourcesReleased"]=@YES;}AMOperationPump();}
void AMOperationSetWorkflowResult(NSString *identifier,NSString *result,NSString *issue,NSString *stage){if(!identifier)return;@synchronized(AMOperationLock()){NSMutableDictionary *row=AMOperationRows[identifier];row[@"workflowResult"]=result;row[@"workflowIssue"]=issue;row[@"workflowStage"]=stage ?: @"";if([result isEqual:@"completed"] && [@[@"failed",@"cancelled"] containsObject:row[@"state"]]){row[@"state"]=@"success";row[@"stage"]=@"结果已保存";}}AMOperationNotify();}
void AMOperationSetPresentationKey(NSString *identifier,NSString *key){@synchronized(AMOperationLock()){if(key.length)AMOperationRows[identifier][@"presentationKey"]=key;}AMOperationNotify();}
void AMOperationProgress(NSString *identifier,NSString *stage,NSInteger completed,NSInteger total){if(!identifier)return;@synchronized(AMOperationLock()){NSMutableDictionary *row=AMOperationRows[identifier];if(![row[@"state"] isEqual:@"running"])return;row[@"stage"]=[row[@"cancelRequested"] boolValue] ? @"正在停止":(stage ?: @"");row[@"completed"]=@(MAX(0,completed));row[@"total"]=@(MAX(0,total));}AMOperationNotify();}
void AMOperationFinish(NSString *identifier,NSString *state,NSString *message){if(!identifier)return;@synchronized(AMOperationLock()){
    NSMutableDictionary *row=AMOperationRows[identifier];if(!row || ![@[@"running",@"queued"] containsObject:row[@"state"]])return;
    AMOperationWait(row,@[]);if(row[@"parent"])AMOperationWait(AMOperationRows[row[@"parent"]],@[]);
    [AMScheduledJobs removeObjectForKey:identifier];row[@"state"]=state;row[@"stage"]=message ?: @"";row[@"finished"]=NSDate.date;row[@"cancellable"]=@NO;[AMOperationCancels removeObjectForKey:identifier];
}AMOperationNotify();AMOperationPump();}
void AMOperationSetResult(NSString *identifier,NSString *summary,NSString *details,BOOL warning,NSString *actionTitle,void (^action)(void)){
    @synchronized(AMOperationLock()){NSMutableDictionary *row=AMOperationRows[identifier];if(!row)return;row[@"summary"]=summary ?: @"";row[@"details"]=details ?: @"";row[@"warning"]=@(warning);if(action){row[@"recoveryTitle"]=actionTitle ?: @"查看";row[@"recovery"]=[action copy];}else {[row removeObjectForKey:@"recovery"];[row removeObjectForKey:@"recoveryTitle"];}}
    AMOperationNotify();
}
void AMOperationCancel(NSString *identifier){
    void(^cancel)(void)=nil;void(^scheduledCancel)(BOOL)=nil;BOOL queued=NO;
    @synchronized(AMOperationLock()){
        NSMutableDictionary *row=AMOperationRows[identifier];queued=[row[@"state"] isEqual:@"queued"];
        if(!queued && (![row[@"state"] isEqual:@"running"] || ![row[@"cancellable"] boolValue]))return;
        scheduledCancel=AMScheduledJobs[identifier][@"cancel"];
        if(queued){ // Finish under the same lock so a competing pump cannot launch it.
            AMOperationFinish(identifier,@"cancelled",@"已取消排队，未执行操作");
        }else{
            cancel=AMOperationCancels[identifier];[AMOperationCancels removeObjectForKey:identifier];
            if(cancel || scheduledCancel){row[@"cancellable"]=@NO;row[@"cancelRequested"]=@YES;row[@"stage"]=@"正在停止";if(scheduledCancel)[AMScheduledJobs[identifier] removeObjectForKey:@"cancel"];}
        }
    }
    if(scheduledCancel)scheduledCancel(queued);else if(cancel)cancel();AMOperationNotify();
}
NSUInteger AMQueuedOperationCount(void){NSUInteger count=0;@synchronized(AMOperationLock()){for(NSDictionary *row in AMOperationRows.allValues)if([row[@"state"] isEqual:@"queued"])count++;}return count;}
void AMCancelQueuedOperations(void){
    NSMutableArray *callbacks=NSMutableArray.array;
    @synchronized(AMOperationLock()){
        // Mark the whole batch before releasing resources; cancelling one at a
        // time would allow the pump to start another item being cancelled.
        for(NSMutableDictionary *row in AMOperationRows.allValues)if([row[@"state"] isEqual:@"queued"]){NSString *key=row[@"id"];id cancel=AMScheduledJobs[key][@"cancel"];if(cancel)[callbacks addObject:cancel];[AMScheduledJobs removeObjectForKey:key];[AMOperationCancels removeObjectForKey:key];row[@"state"]=@"cancelled";row[@"stage"]=@"已取消排队，未执行操作";row[@"finished"]=NSDate.date;row[@"cancellable"]=@NO;}
    }
    for(void(^cancel)(BOOL) in callbacks)cancel(YES);AMOperationNotify();AMOperationPump();
}
NSArray *AMOperations(void){@synchronized(AMOperationLock()){NSMutableArray *rows=NSMutableArray.array;for(NSDictionary *row in AMOperationRows.allValues)[rows addObject:row.copy];return [rows sortedArrayUsingComparator:^NSComparisonResult(id a,id b){return [b[@"started"] compare:a[@"started"]];}];}}
NSArray *AMExitBlockingOperations(void){NSMutableArray *rows=NSMutableArray.array;for(NSDictionary *row in AMOperations())if([@[@"running",@"queued"] containsObject:row[@"state"]] && (!row[@"blocksExit"] || [row[@"blocksExit"] boolValue]))[rows addObject:row];return rows;}
static NSMutableDictionary *AMModelWaiters;
AMCancellationCheck AMCurrentCancellationCheck(void){return NSThread.currentThread.threadDictionary[@"AMOperationCancellation"];}
BOOL AMCurrentOperationCancelled(void){AMCancellationCheck stop=AMCurrentCancellationCheck();return stop && stop();}
id AMPerformModelOperation(NSString *key,NSString *target,BOOL manual,BOOL (^cancelled)(void),id (^perform)(NSError **),NSError **error){return AMPerformResourceOperation([@"model|" stringByAppendingString:key],@"分析材料",target,@[@"model-service"],manual ? 100:0,cancelled,perform,error);}
id AMPerformResourceOperation(NSString *key,NSString *kind,NSString *target,NSArray *resources,NSInteger priority,BOOL (^cancelled)(void),id (^perform)(NSError **),NSError **error){
    NSString *ancestor=NSThread.currentThread.threadDictionary[@"AMOperationParent"];BOOL covered=resources.count>0;
    @synchronized(AMOperationLock()){NSDictionary *held=ancestor ? AMScheduledJobs[ancestor]:nil;if(!held || [held[@"resourcesReleased"] boolValue])covered=NO;for(NSString *claim in resources){BOOL found=NO;for(NSString *owned in held[@"resources"])if([AMResourceIdentity(claim) isEqual:AMResourceIdentity(owned)] && (![owned hasPrefix:@"read|"] || [claim hasPrefix:@"read|"]))found=YES;if(!found)covered=NO;}}
    if(covered){if(cancelled && cancelled()){if(error)*error=[NSError errorWithDomain:@"AMOperation" code:NSUserCancelledError userInfo:@{NSLocalizedDescriptionKey:@"已停止"}];return nil;}return perform(error);}
    dispatch_semaphore_t done=dispatch_semaphore_create(0);__block id result=nil;__block NSError *failure=nil;BOOL create=NO;__block NSMutableDictionary *request;
    void(^receive)(id,NSError *)=^(id value,NSError *problem){result=value;failure=problem;dispatch_semaphore_signal(done);};
    @synchronized(AMOperationLock()){
        if(!AMModelWaiters)AMModelWaiters=NSMutableDictionary.dictionary;
        NSMutableDictionary *entry=AMModelWaiters[key];if(!entry){entry=[@{@"listeners":NSMutableArray.array} mutableCopy];AMModelWaiters[key]=entry;create=YES;}
        [entry[@"listeners"] addObject:[receive copy]];request=entry;if(entry[@"operation"])AMOperationRows[entry[@"operation"]][@"requests"]=@([entry[@"listeners"] count]);
        if(priority>0 && entry[@"operation"]){NSMutableDictionary *job=AMScheduledJobs[entry[@"operation"]];if(job && priority>[job[@"priority"] integerValue])job[@"priority"]=@(priority);}
    }
    if(create){
        void(^deliver)(id,NSError *)=^(id value,NSError *problem){NSArray *listeners;@synchronized(AMOperationLock()){listeners=[request[@"listeners"] copy];if(AMModelWaiters[key]==request)[AMModelWaiters removeObjectForKey:key];}for(void(^listener)(id,NSError *) in listeners)listener(value,problem);};
        NSString *operation=AMOperationEnqueue(key,kind,target,resources,priority,^(NSString *identifier){
            NSError *problem=nil;id value=nil;BOOL stop=NO;@synchronized(AMOperationLock()){stop=[request[@"cancelRequested"] boolValue];}
            if(stop || (cancelled && cancelled()))problem=[NSError errorWithDomain:@"AMOperation" code:NSUserCancelledError userInfo:@{NSLocalizedDescriptionKey:@"分析已取消"}];
            else {NSMutableDictionary *thread=NSThread.currentThread.threadDictionary;id previous=thread[@"AMOperationCancellation"],parent=thread[@"AMOperationParent"];thread[@"AMOperationParent"]=identifier;thread[@"AMOperationCancellation"]=[^BOOL{BOOL requested;@synchronized(AMOperationLock()){requested=[request[@"cancelRequested"] boolValue];}return requested || (cancelled && cancelled());} copy];@try{value=perform(&problem);}@catch(NSException *exception){problem=[NSError errorWithDomain:@"AMOperation" code:1 userInfo:@{NSLocalizedDescriptionKey:SSRedactedText(exception.reason ?: @"模型分析未完成")}];}@finally{if(previous)thread[@"AMOperationCancellation"]=previous;else [thread removeObjectForKey:@"AMOperationCancellation"];if(parent)thread[@"AMOperationParent"]=parent;else [thread removeObjectForKey:@"AMOperationParent"];}}
            @synchronized(AMOperationLock()){stop=[request[@"cancelRequested"] boolValue];}
            if(stop && !problem)problem=[NSError errorWithDomain:@"AMOperation" code:NSUserCancelledError userInfo:@{NSLocalizedDescriptionKey:@"分析已取消，服务已发出的请求可能消耗额度"}];
            AMOperationFinish(identifier,problem.code==NSUserCancelledError ? @"cancelled":(problem ? @"failed":@"success"),problem.localizedDescription ?: @"材料分析完成");deliver(problem ? nil:value,problem);
        },^(BOOL beforeStart){if(beforeStart){NSError *problem=[NSError errorWithDomain:@"AMOperation" code:NSUserCancelledError userInfo:@{NSLocalizedDescriptionKey:@"已取消排队，未执行操作"}];deliver(nil,problem);}else{@synchronized(AMOperationLock()){request[@"cancelRequested"]=@YES;}}});
        @synchronized(AMOperationLock()){request[@"operation"]=operation;AMOperationRows[operation][@"requests"]=@([request[@"listeners"] count]);}
    }
    while(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC))!=0)if(cancelled && cancelled()){
        NSString *identifier;@synchronized(AMOperationLock()){identifier=AMModelWaiters[key][@"operation"];}
        if(identifier)AMOperationCancel(identifier);
    }
    if(failure && error)*error=failure;return result;
}

id AMPerformResourceOperationInTask(NSString *task,NSString *key,NSString *kind,NSString *target,NSArray *resources,NSInteger priority,BOOL (^cancelled)(void),id (^perform)(NSError **),NSError **error){
    NSMutableDictionary *thread=NSThread.currentThread.threadDictionary;id previous=thread[@"AMOperationParent"];thread[@"AMOperationParent"]=task;
    @try{return AMPerformResourceOperation(key,kind,target,resources,priority,cancelled,perform,error);}@finally{if(previous)thread[@"AMOperationParent"]=previous;else [thread removeObjectForKey:@"AMOperationParent"];}
}
