- (void)discoverExternalSubmissions:(BOOL)loadMore {NSArray *courses=[self course] ? @[[self course].copy]:[[NSArray alloc] initWithArray:self.courses copyItems:YES];[self discoverExternalSubmissions:loadMore forCourses:courses manual:loadMore];}
- (void)discoverExternalSubmissions:(BOOL)loadMore forCourses:(NSArray *)courses {[self discoverExternalSubmissions:loadMore forCourses:courses manual:loadMore];}
- (void)discoverExternalSubmissions:(BOOL)loadMore forCourses:(NSArray *)requested manual:(BOOL)manual {
    if(self.preview || self.operationsPaused || self.busy || self.discoveringExternal)return;
    NSDictionary *authentication=_github.authenticationIdentity ?: @{};
    if(!self.externalPolling){id saved=SSReadPlist(@"submission-history-polling.plist");self.externalPolling=[saved isKindOfClass:NSDictionary.class] ? [saved mutableCopy]:NSMutableDictionary.dictionary;}
    NSMutableArray *courses=NSMutableArray.array,*identities=NSMutableArray.array;NSDate *blockedRetry=nil;
    for(NSDictionary *course in requested){if(![course[@"path"] length])continue;NSString *key=AMHistoryPollingKey(course,authentication);[identities addObject:key];NSDate *limited=AMHistoryServerRetry(self.externalPolling[key]);if(manual && [limited isKindOfClass:NSDate.class] && limited.timeIntervalSinceNow>0){blockedRetry=limited;continue;}if(manual || AMHistoryPollDue(self.externalPolling[key],NSDate.date))[courses addObject:course.copy];}if(!courses.count){if(blockedRetry)[self status:[NSString stringWithFormat:@"请在 %@ 后重试",DDLFormatDate(blockedRetry,@"HH:mm")]];return;}
    NSString *presentationKey=[@"submission-history|" stringByAppendingString:AMPreflightHash([NSJSONSerialization dataWithJSONObject:[identities sortedArrayUsingSelector:@selector(compare:)] options:0 error:NULL])];
    if(!self.externalOffsets)self.externalOffsets=NSMutableDictionary.dictionary;
    NSDictionary *offsets=self.externalOffsets.copy;self.discoveringExternal=YES;self.lastExternalDiscovery=NSDate.date;[self refreshPresentation];
    SSGitHub *api=SSGitHub.new;api.authType=_github.authType;api.clientID=_github.clientID;api.installationURL=_github.installationURL;
#ifdef DDL_TESTING
    if(self.externalAPIFactory)api=self.externalAPIFactory();
#endif
    self.externalAPI=api;NSProgress *cancellation=[NSProgress progressWithTotalUnitCount:1];self.discoveryCancellation=cancellation;__weak typeof(self) owner=self;
    NSString *operation=AMOperationBeginWithExitPolicy(@"核验提交记录",[self course][@"fork"] ?: @"所有课程",YES,NO,^{[cancellation cancel];api.requestsCancelled=YES;[owner.externalReader cancelCurrentOperation];});AMOperationSetPresentationKey(operation,presentationKey);
    dispatch_async(self.externalQueue,^{
        NSThread.currentThread.threadDictionary[@"AMOperationCancellation"]=[^BOOL{return cancellation.cancelled;} copy];
        __block AMCourseOperationContext *problemContext=nil;NSMutableArray *failures=NSMutableArray.array;NSMutableDictionary *advanced=NSMutableDictionary.dictionary,*pollFailures=NSMutableDictionary.dictionary;NSError *tokenError=nil;NSString *token=self.connected ? [api accessToken:&tokenError]:nil;
        if(self.connected && !token.length && !tokenError)tokenError=AMWorkflowError(@"login",@"请重新登录后核验提交记录",nil);
        for(NSDictionary *course in courses){if(cancellation.cancelled)break;NSString *pollKey=AMHistoryPollingKey(course,authentication);if(![course[@"path"] length])continue;AMOperationProgress(operation,@"读取提交记录",[courses indexOfObject:course],courses.count);NSError *error=nil;SSGit *reader=SSGit.new;
#ifdef DDL_TESTING
            if(self.externalReaderFactory)reader=self.externalReaderFactory(course);
#endif
            reader.identityVerifier=^NSDictionary *(NSDictionary *snapshot,NSError **failure){return [api verifyCourse:snapshot error:failure];};reader.teacherCredentialProvider=[@[@"oauth",@"githubCLI"] containsObject:api.authType] ? ^NSString *(NSDictionary *snapshot,NSError **failure){if(![api readableTeacher:snapshot error:failure])return nil;return [api accessToken:failure];}:nil;reader.progress=^(NSString *stage){AMOperationProgress(operation,stage,0,0);};reader.readsCancellable=YES;reader.commandTimeout=15;self.externalReader=reader;if(cancellation.cancelled){[reader cancelCurrentOperation];break;}
            NSUInteger offset=loadMore ? [offsets[course[@"fork"]] unsignedIntegerValue]:0;NSArray *rows=[reader externalCommits:course offset:offset error:&error];if(!rows){problemContext=AMCourseOperationContext.new;problemContext.owner=self;problemContext.course=course;problemContext.authenticationIdentity=authentication;problemContext.api=api;problemContext.failure=error ?: AMWorkflowError(@"directory",@"无法读取课程文件",nil);[failures addObject:[NSString stringWithFormat:@"%@：%@",course[@"name"] ?: @"课程",error.localizedDescription ?: @"读取失败"]];pollFailures[pollKey]=problemContext.failure;continue;}
            NSArray *stored=AMSubmissionRecords(&error);if(!stored){problemContext=AMCourseFailureContext(self,course,api,authentication,error,nil);[failures addObject:error.localizedDescription];pollFailures[pollKey]=error;break;}for(NSDictionary *classified in [reader classifyExternalRecords:stored course:course])if(!AMStoreSubmission(classified,&error)){problemContext=AMCourseFailureContext(self,course,api,authentication,error,classified);[failures addObject:error.localizedDescription];}stored=AMSubmissionRecords(&error);if(!stored){error=error ?: AMWorkflowError(@"storage",@"无法读取提交记录",nil);pollFailures[pollKey]=error;problemContext=AMCourseFailureContext(self,course,api,authentication,error,nil);[failures addObject:error.localizedDescription];continue;}NSMutableArray *pending=NSMutableArray.array;
            for(NSDictionary *row in rows){NSDictionary *existing=nil;for(NSDictionary *old in stored)if([old[@"repository"] isEqual:course[@"fork"]] && [old[@"branch"] isEqual:course[@"branch"]] && [old[@"commit"] isEqual:row[@"commit"]]){existing=old;break;}
                if(existing){if([existing[@"origin"] isEqual:@"external"])[pending addObject:existing];continue;}
                NSMutableDictionary *record=row.mutableCopy;record[@"id"]=NSUUID.UUID.UUIDString;record[@"repository"]=course[@"fork"];record[@"branch"]=course[@"branch"];record[@"state"]=@"uncertain";record[@"taskIDs"]=@[];if(!AMStoreSubmission(record,&error)){problemContext=AMCourseFailureContext(self,course,api,authentication,error,record);[failures addObject:error.localizedDescription];continue;}[pending addObject:record];
            }
            advanced[course[@"fork"]]=@(MAX([offsets[course[@"fork"]] unsignedIntegerValue],offset+50));
            NSMutableArray *toVerify=NSMutableArray.array;for(NSDictionary *record in pending)if(!record[@"checkedAt"] || -[record[@"checkedAt"] timeIntervalSinceNow]>300)[toVerify addObject:record];
            if(token.length && (toVerify.count || !AMSubmissionBaseline(course,NULL).count)){AMOperationProgress(operation,@"核验远端提交",0,0);reader.commandTimeout=180;
                NSArray *verified=AMPerformResourceOperationInTask(operation,[@"history-verify:" stringByAppendingString:course[@"fork"]],@"核验提交记录",course[@"fork"],AMRepositoryResources(course,@"fetch"),-10,^BOOL{return cancellation.cancelled;},^id(NSError **problem){return [reader verifyExternalRecords:toVerify course:course token:token error:problem];},&error);if(verified){for(NSDictionary *record in verified)if(!AMStoreSubmission(record,&error)){problemContext=AMCourseOperationContext.new;problemContext.owner=self;problemContext.course=course;problemContext.authenticationIdentity=authentication;problemContext.api=api;problemContext.failure=AMWorkflowError(@"storage",@"核验记录尚未保存",error);problemContext.record=record;[failures addObject:@"核验记录尚未保存"];}}else {error=error ?: AMWorkflowError(@"verification-pending",@"未能核验提交记录",nil);problemContext=AMCourseOperationContext.new;problemContext.owner=self;problemContext.course=course;problemContext.authenticationIdentity=authentication;problemContext.api=api;problemContext.failure=error;[failures addObject:[NSString stringWithFormat:@"%@：远端暂未核验，保留本机记录。",course[@"name"] ?: @"课程"]];}}
            if(error){pollFailures[pollKey]=error;[advanced removeObjectForKey:course[@"fork"]];}
        }
        [NSThread.currentThread.threadDictionary removeObjectForKey:@"AMOperationCancellation"];
        dispatch_async(dispatch_get_main_queue(),^{
            self.externalReader=nil;self.externalAPI=nil;self.discoveryCancellation=nil;
            for(NSDictionary *course in courses){NSString *key=AMHistoryPollingKey(course,authentication);self.externalPolling[key]=AMHistoryPollResult(self.externalPolling[key],pollFailures[key] ?: tokenError,cancellation.cancelled,NSDate.date);}
            // This optional cache contains hashed bindings and retry times, not course text or credentials.
            if(self.externalPolling.count>128){NSMutableSet *keys=NSMutableSet.set;for(NSDictionary *course in self.courses)[keys addObject:AMHistoryPollingKey(course,authentication)];for(NSString *key in self.externalPolling.allKeys.copy)if(![keys containsObject:key])[self.externalPolling removeObjectForKey:key];}
            SSWritePlist(@"submission-history-polling.plist",self.externalPolling,NULL);
            AMOperationFinish(operation,cancellation.cancelled ? @"cancelled":((failures.count || tokenError) ? @"failed":@"success"),cancellation.cancelled ? @"已停止":(failures.count ? @"提交记录尚未核验":(token.length ? @"核验完成":@"本机记录已读取，远端未核验")));
            self.discoveringExternal=NO;[self.externalOffsets addEntriesFromDictionary:advanced];[self refreshPresentation];if(self.verifiedSubmissionsChanged)self.verifiedSubmissionsChanged();
            if(!cancellation.cancelled && !failures.count && !tokenError){
                for(NSString *key in self.workflowFailures.allKeys.copy){AMCourseOperationContext *old=self.workflowFailures[key];if([old.noticeKey hasPrefix:presentationKey]){if(self.workflowNoticeContext==old){self.workflowNotice.hidden=YES;self.workflowNoticeContext=nil;}[self.workflowFailures removeObjectForKey:key];}}
            }
            if(!cancellation.cancelled && (failures.count || tokenError)){
                AMCourseOperationContext *context=problemContext ?: AMCourseOperationContext.new;context.owner=self;context.identifier=operation;context.api=api;context.authenticationIdentity=authentication;context.stage=@"核验提交记录";context.failure=context.failure ?: tokenError ?: AMWorkflowError(@"storage",@"提交记录未完成",nil);
                NSMutableDictionary *problem=[AMWorkflowProblem(context.failure,context.stage,context.record) mutableCopy];
                if(!context.record){problem[@"title"]=[AMWorkflowIssue(context.failure) isEqual:@"timeout"] ? @"提交记录核验超时":problem[@"title"];problem[@"effect"]=@"现有记录保留";}
                if(context.course)problem[@"details"]=[NSString stringWithFormat:@"%@\n后台重试：%@",problem[@"details"],DDLFormatDate(self.externalPolling[AMHistoryPollingKey(context.course,authentication)][@"next"],@"HH:mm")];
                context.problem=problem;context.noticeKey=[NSString stringWithFormat:@"%@|%@|%@",presentationKey,problem[@"issue"],problem[@"command"]];
                if(!self.workflowFailures)self.workflowFailures=NSMutableDictionary.dictionary;
                for(NSString *key in self.workflowFailures.allKeys.copy)if([self.workflowFailures[key].noticeKey hasPrefix:presentationKey])[self.workflowFailures removeObjectForKey:key];
                self.workflowFailures[operation]=context;
                [self showWorkflowProblem:context retry:^id(NSError **failure){dispatch_async(dispatch_get_main_queue(),^{[self discoverExternalSubmissions:loadMore forCourses:courses manual:YES];});return @YES;} message:@"核验提交记录" scope:@"history-recovery" priority:100 completion:^(id value,NSError *failure){if(failure)[self showError:failure];}];
                if([problem[@"command"] isEqual:@"retry"]){__weak AMCourseOperationContext *weakContext=context;context.recovery=^{SSCourseController *self=owner;AMCourseOperationContext *current=weakContext;if(self && current && [self workflowRecoveryAllowed:current])[self discoverExternalSubmissions:loadMore forCourses:courses manual:YES];};AMOperationSetResult(operation,[NSString stringWithFormat:@"%@ · %@",problem[@"title"],problem[@"effect"]],[NSString stringWithFormat:@"%@\n%@",problem[@"details"],[failures componentsJoinedByString:@"\n"]],YES,@"重试",context.recovery);if(self.workflowNoticeContext==context)self.workflowNotice.performRecovery=context.recovery;}
                AMOperationSetWorkflowResult(operation,context.problem[@"result"],context.problem[@"issue"],context.stage);
            }
        });
    });
}
- (void)associateExternalRecord:(NSDictionary *)record {
    NSAlert *alert=NSAlert.new;alert.messageText=@"关联作业";alert.informativeText=AMSubmissionAutoCompletionEnabled() ? @"核验已推送后，将自动完成关联作业。":@"选择对应作业。";NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,460,180)];scroll.hasVerticalScroller=YES;NSMutableArray *checks=NSMutableArray.array;
    for(NSDictionary *task in self.tasksProvider ? self.tasksProvider():@[])if(![task[@"deleted"] boolValue] && AMTaskBelongsToCourse(task,[self savedCourse:@{@"fork":record[@"repository"]}] ?: @{@"fork":record[@"repository"]})){NSButton *check=[NSButton checkboxWithTitle:task[@"title"] target:nil action:nil];check.identifier=task[@"id"];check.state=[record[@"taskIDs"] containsObject:check.identifier] ? NSControlStateValueOn:NSControlStateValueOff;[checks addObject:check];}
    NSView *list=[[NSView alloc] initWithFrame:NSMakeRect(0,0,440,MAX(180,checks.count*28))];for(NSUInteger i=0;i<checks.count;i++){NSButton *check=checks[i];check.frame=NSMakeRect(0,NSHeight(list.frame)-(i+1)*28,440,28);[list addSubview:check];}scroll.documentView=list;alert.accessoryView=scroll;[alert addButtonWithTitle:@"保存关联"];[alert addButtonWithTitle:@"取消"];if([alert runModal]!=NSAlertFirstButtonReturn)return;
    NSMutableArray *links=NSMutableArray.array;for(NSButton *check in checks)if(check.state==NSControlStateValueOn)[links addObject:check.identifier];NSError *error=nil;if(!AMAssociateSubmission(record[@"id"],links,&error))[self status:error.localizedDescription];else if(self.verifiedSubmissionsChanged)self.verifiedSubmissionsChanged();[self refreshPresentation];
}
