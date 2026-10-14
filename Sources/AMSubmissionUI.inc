- (void)submitTask:(NSString *)identifier {
    NSDictionary *task=nil;for(NSDictionary *row in self.tasksProvider ? self.tasksProvider():@[])if([row[@"id"] isEqual:identifier])task=row;
    NSDictionary *course=nil;for(NSDictionary *row in self.courses)if([task[@"courseRepository"] isEqual:row[@"fork"]] || [task[@"sourceRepository"] isEqual:row[@"upstream"]]){course=row;break;}
    if(!course){[self status:@"这份任务未关联 GitHub 课程，请先在任务中选择课程。" ];return;}
    if(![self selectCourseID:course[@"fork"]])return;self.inbox=NO;self.submissionTaskID=identifier;[self commit:nil];
}
- (void)showSubmissionHistory:(NSString *)identifier {
    if(identifier){for(NSDictionary *record in AMSubmissionRecords(NULL))if([record[@"taskIDs"] containsObject:identifier]){if(![self selectCourseID:record[@"repository"]])[self selectCourseID:nil];break;}}
    self.inbox=NO;self.sections.selectedSegment=3;[self refreshPresentation];
}
- (void)submissionAction:(NSString *)action identifier:(NSString *)identifier {
    if([action isEqual:@"refresh-external"] || [action isEqual:@"more-external"]){self.lastExternalDiscovery=nil;[self discoverExternalSubmissions:[action isEqual:@"more-external"]];return;}
    NSDictionary *record=nil;for(NSDictionary *row in AMSubmissionRecords(NULL) ?: @[])if([row[@"id"] isEqual:identifier])record=row;
    NSDictionary *course=record ? [self savedCourse:@{@"fork":record[@"repository"]}].copy:[self course].copy;
    if([action isEqual:@"associate"] && record){[self associateExternalRecord:record];return;}
    if([action isEqual:@"open"]){NSString *commit=record[@"commit"];if(commit.length==40 || commit.length==64)[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://github.com/%@/commit/%@",record[@"repository"],commit]]];return;}
    if(!course){[self status:@"请先选择并关联对应课程。记录仍保留在本机。"];return;}
    if([action isEqual:@"existing"]){
        [self work:@"读取已有提交…" forCourse:course operation:^id(NSError **error){return [self.git recentCommits:course error:error];} completion:^(NSArray *rows,NSError *error){
            if(!rows.count){[self showError:error];return;}NSAlert *alert=NSAlert.new;alert.messageText=@"关联已有提交";alert.informativeText=@"选择当前分支最近50条提交之一，以及要关联的作业（可选）。此操作只读核验，不提交或推送。";
            NSView *accessory=[[NSView alloc] initWithFrame:NSMakeRect(0,0,480,170)];NSPopUpButton *menu=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0,136,480,32)];for(NSDictionary *row in rows)[menu addItemWithTitle:[NSString stringWithFormat:@"%@ · %@",[row[@"commit"] substringToIndex:12],row[@"message"]]];[accessory addSubview:menu];
            NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,480,128)];scroll.hasVerticalScroller=YES;NSMutableArray *checks=NSMutableArray.array;NSView *list=NSView.new;
            for(NSDictionary *task in self.tasksProvider ? self.tasksProvider():@[])if(![task[@"deleted"] boolValue] && ([task[@"courseRepository"] isEqual:course[@"fork"]] || [task[@"sourceRepository"] isEqual:course[@"upstream"]])){NSButton *check=[NSButton checkboxWithTitle:task[@"title"] target:nil action:nil];check.identifier=task[@"id"];[checks addObject:check];}
            list.frame=NSMakeRect(0,0,460,MAX(128,checks.count*28));for(NSUInteger i=0;i<checks.count;i++){NSButton *check=checks[i];check.frame=NSMakeRect(0,NSHeight(list.frame)-(i+1)*28,460,28);[list addSubview:check];}scroll.documentView=list;[accessory addSubview:scroll];alert.accessoryView=accessory;[alert addButtonWithTitle:@"关联并核验"];[alert addButtonWithTitle:@"取消"];if([alert runModal]!=NSAlertFirstButtonReturn)return;
            NSString *commit=rows[menu.indexOfSelectedItem][@"commit"];NSMutableArray *taskIDs=NSMutableArray.array;for(NSButton *check in checks)if(check.state==NSControlStateValueOn)[taskIDs addObject:check.identifier];
            [self work:@"读取提交文件并核验…" forCourse:course operation:^id(NSError **failure){NSDictionary *details=[self.git submissionDetailsForCourse:course commit:commit error:failure];if(!details)return nil;NSMutableDictionary *new=[@{@"id":NSUUID.UUID.UUIDString,@"repository":course[@"fork"],@"branch":course[@"branch"],@"kind":@"existing",@"state":@"local",@"message":details[@"message"],@"commit":commit,@"date":NSDate.date,@"files":details[@"files"],@"taskIDs":taskIDs} mutableCopy];if(!AMStoreSubmission(new,failure))return nil;NSString *token=[self.github accessToken:failure];return token ? [self.git verifySubmission:new course:course token:token retry:NO error:failure]:nil;} completion:^(NSDictionary *value,NSError *failure){if(failure)[self showError:failure];else [self status:AMSubmissionStateLabel(value)];}];
        }];return;
    }
    if(!record)return;
    [self work:@"正在核验个人仓库提交…" forCourse:course operation:^id(NSError **error){NSString *token=[self.github accessToken:error];if(!token)return nil;if([record[@"origin"] isEqual:@"external"]){NSArray *checked=[self.git verifyExternalRecords:@[record] course:course token:token error:error];if(checked.count && AMStoreSubmission(checked[0],error))return checked[0];return nil;}return [self.git verifySubmission:record course:course token:token retry:[action isEqual:@"retry"] error:error];} completion:^(NSDictionary *result,NSError *error){if(error)[self showError:error];else [self status:AMSubmissionStateLabel(result)];}];
}

- (void)recoverSubmissionRecords {
    if(self.preview || !self.connected || self.busy || self.operationsPaused)return;
    NSMutableArray *pending=NSMutableArray.array;for(NSDictionary *record in AMSubmissionRecords(NULL))if([@[@"running",@"uncertain"] containsObject:record[@"state"]] && !record[@"checkedAt"])[pending addObject:record];if(!pending.count)return;
    NSArray *courses=self.courses.copy;
    [self work:@"只读恢复提交记录…" forCourse:nil operation:^id(NSError **error){NSString *token=[self.github accessToken:error];if(!token)return nil;for(NSDictionary *record in pending){for(NSDictionary *course in courses)if([course[@"fork"] isEqual:record[@"repository"]]){NSError *failure=nil;NSDictionary *verified=[self.git verifySubmission:record course:course token:token retry:NO error:&failure];if(!verified){NSMutableDictionary *pendingRecord=record.mutableCopy;pendingRecord[@"checkedAt"]=NSDate.date;pendingRecord[@"state"]=@"uncertain";pendingRecord[@"issue"]=@"verification-pending";AMStoreSubmission(pendingRecord,NULL);}}}return @YES;} completion:^(id result,NSError *error){if(error)[self status:@"未能核验历史提交，可在提交记录中重试；没有重新提交或推送。" ];}];
}
