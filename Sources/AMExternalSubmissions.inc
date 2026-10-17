- (void)discoverExternalSubmissions:(BOOL)loadMore {
    if(self.preview || self.operationsPaused || self.busy || self.discoveringExternal)return;
    if(!loadMore && self.lastExternalDiscovery && -self.lastExternalDiscovery.timeIntervalSinceNow<60)return;
    if(!self.externalOffsets)self.externalOffsets=NSMutableDictionary.dictionary;
    NSArray *courses=loadMore && [self course] ? @[[self course].copy]:self.courses.copy;
    NSDictionary *offsets=self.externalOffsets.copy;self.discoveringExternal=YES;self.lastExternalDiscovery=NSDate.date;[self refreshPresentation];
    dispatch_async(self.queue,^{
        NSMutableArray *failures=NSMutableArray.array;NSMutableDictionary *advanced=NSMutableDictionary.dictionary;NSError *tokenError=nil;NSString *token=self.connected ? [self.github accessToken:&tokenError]:nil;
        for(NSDictionary *course in courses){if(![course[@"path"] length])continue;NSError *error=nil;SSGit *reader=SSGit.new;reader.identityVerifier=self.git.identityVerifier;reader.teacherCredentialProvider=self.git.teacherCredentialProvider;reader.readsCancellable=YES;
            NSUInteger offset=loadMore ? [offsets[course[@"fork"]] unsignedIntegerValue]:0;NSArray *rows=[reader externalCommits:course offset:offset error:&error];if(!rows){[failures addObject:[NSString stringWithFormat:@"%@：%@",course[@"name"] ?: @"课程",error.localizedDescription ?: @"读取失败"]];continue;}
            NSArray *stored=AMSubmissionRecords(&error);if(!stored){[failures addObject:error.localizedDescription];break;}for(NSDictionary *classified in [reader classifyExternalRecords:stored course:course])AMStoreSubmission(classified,NULL);stored=AMSubmissionRecords(&error);if(!stored)continue;NSMutableArray *pending=NSMutableArray.array;
            for(NSDictionary *row in rows){NSDictionary *existing=nil;for(NSDictionary *old in stored)if([old[@"repository"] isEqual:course[@"fork"]] && [old[@"branch"] isEqual:course[@"branch"]] && [old[@"commit"] isEqual:row[@"commit"]]){existing=old;break;}
                if(existing){if([existing[@"origin"] isEqual:@"external"])[pending addObject:existing];continue;}
                NSMutableDictionary *record=row.mutableCopy;record[@"id"]=NSUUID.UUID.UUIDString;record[@"repository"]=course[@"fork"];record[@"branch"]=course[@"branch"];record[@"state"]=@"uncertain";record[@"taskIDs"]=@[];if(!AMStoreSubmission(record,&error)){[failures addObject:error.localizedDescription];continue;}[pending addObject:record];
            }
            advanced[course[@"fork"]]=@(MAX([offsets[course[@"fork"]] unsignedIntegerValue],offset+50));
            NSMutableArray *toVerify=NSMutableArray.array;for(NSDictionary *record in pending)if(!record[@"checkedAt"] || -[record[@"checkedAt"] timeIntervalSinceNow]>300)[toVerify addObject:record];
            if(token.length && (toVerify.count || !AMSubmissionBaseline(course,NULL).count)){NSArray *verified=[reader verifyExternalRecords:toVerify course:course token:token error:&error];if(verified){for(NSDictionary *record in verified)AMStoreSubmission(record,NULL);}else if(error)[failures addObject:[NSString stringWithFormat:@"%@：远端暂未核验，保留本机记录。",course[@"name"] ?: @"课程"]];}
        }
        dispatch_async(dispatch_get_main_queue(),^{self.discoveringExternal=NO;[self.externalOffsets addEntriesFromDictionary:advanced];[self refreshPresentation];if(self.verifiedSubmissionsChanged)self.verifiedSubmissionsChanged();if(failures.count && self.sections.selectedSegment==3)[self status:[failures componentsJoinedByString:@"\n"]];});
    });
}
- (void)associateExternalRecord:(NSDictionary *)record {
    NSAlert *alert=NSAlert.new;alert.messageText=@"关联作业";alert.informativeText=AMSubmissionAutoCompletionEnabled() ? @"核验已推送后，将自动完成关联作业。":@"选择对应作业。";NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,460,180)];scroll.hasVerticalScroller=YES;NSMutableArray *checks=NSMutableArray.array;
    for(NSDictionary *task in self.tasksProvider ? self.tasksProvider():@[])if(![task[@"deleted"] boolValue] && AMTaskBelongsToCourse(task,[self savedCourse:@{@"fork":record[@"repository"]}] ?: @{@"fork":record[@"repository"]})){NSButton *check=[NSButton checkboxWithTitle:task[@"title"] target:nil action:nil];check.identifier=task[@"id"];check.state=[record[@"taskIDs"] containsObject:check.identifier] ? NSControlStateValueOn:NSControlStateValueOff;[checks addObject:check];}
    NSView *list=[[NSView alloc] initWithFrame:NSMakeRect(0,0,440,MAX(180,checks.count*28))];for(NSUInteger i=0;i<checks.count;i++){NSButton *check=checks[i];check.frame=NSMakeRect(0,NSHeight(list.frame)-(i+1)*28,440,28);[list addSubview:check];}scroll.documentView=list;alert.accessoryView=scroll;[alert addButtonWithTitle:@"保存关联"];[alert addButtonWithTitle:@"取消"];if([alert runModal]!=NSAlertFirstButtonReturn)return;
    NSMutableArray *links=NSMutableArray.array;for(NSButton *check in checks)if(check.state==NSControlStateValueOn)[links addObject:check.identifier];NSError *error=nil;if(!AMAssociateSubmission(record[@"id"],links,&error))[self status:error.localizedDescription];else if(self.verifiedSubmissionsChanged)self.verifiedSubmissionsChanged();[self refreshPresentation];
}
