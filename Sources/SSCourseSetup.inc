// Included in SSCourseController. Background work uses the existing serial queue.
- (void)presentCourseSetup {
    if(self.setupWindow.sheetParent)return;
    self.setupWorkspace=AMSetupController.new;self.setupWindow=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,720,560) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];self.setupWindow.title=@"开始使用 AM Helper";self.setupWindow.contentViewController=self.setupWorkspace;
    __weak typeof(self) weakSelf=self;self.setupWorkspace.actionHandler=^(NSDictionary *request){[weakSelf handleSetupAction:request];};
    [self updateCourseSetup:@"已有课程可重新核验并继续关联，不会删除任务或覆盖文件。"];[self.window beginSheet:self.setupWindow completionHandler:nil];
}
- (void)updateCourseSetup:(NSString *)message {
    [self.setupWorkspace updateRecords:self.setupRecords ?: @[] step:self.setupStep busy:self.busy message:message ?: @""];
    [self.setupWorkspace updateContext:@{@"code":self.loginChallenge[@"user_code"] ?: @"",@"provider":self.github.authType ?: @"githubCLI"}];
    if(!self.preview && self.setupStep<4 && self.setupWindow){NSError *error=nil;NSDictionary *prior=SSReadPlist(@"onboarding.plist");BOOL complete=[prior[@"completed"] boolValue];if(!SSWritePlist(@"onboarding.plist",@{@"version":@2,@"step":@(self.setupStep),@"records":self.setupRecords ?: @[],@"selected":self.setupSelection ?: @[],@"completed":@(complete)},&error))[self.setupWorkspace updateRecords:self.setupRecords ?: @[] step:self.setupStep busy:self.busy message:@"引导进度未能保存，已关联课程仍保留；请检查本机数据目录。"];}
}
- (void)closeCourseSetup {if(self.setupWindow.sheetParent)[self.window endSheet:self.setupWindow];[self.setupWindow orderOut:nil];self.setupWorkspace=nil;self.setupWindow=nil;self.guided=NO;}
- (BOOL)saveConfiguredCourse:(NSDictionary *)course error:(NSError **)error {
    NSMutableArray *next=self.courses.mutableCopy;NSUInteger index=[next indexOfObjectPassingTest:^BOOL(NSDictionary *item,NSUInteger idx,BOOL *stop){return [item[@"fork"] isEqual:course[@"fork"]];}];
    if(index==NSNotFound)[next addObject:course.mutableCopy];else next[index]=course.mutableCopy;
    if(!self.preview && !SSWritePlist(@"courses.plist",next,error))return NO;self.courses=next;return YES;
}
- (void)handleSetupAction:(NSDictionary *)request {
    NSString *action=request[@"action"];
    if([action isEqual:@"copyCode"] && [self.loginChallenge[@"user_code"] length]){[NSPasteboard.generalPasteboard clearContents];[NSPasteboard.generalPasteboard setString:self.loginChallenge[@"user_code"] forType:NSPasteboardTypeString];return;}
    if([action isEqual:@"openLogin"] && self.loginChallenge){[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://github.com/login/device"]];return;}
    if([action isEqual:@"close"] && self.loginActive){[self cancelLogin:nil];[self closeCourseSetup];return;}
    if(self.busy || self.operationsPaused)return;
    self.setupSelection=request[@"selected"] ?: self.setupSelection;
    if(self.setupStep==2){NSDictionary *paths=request[@"paths"];for(NSMutableDictionary *row in self.setupRecords)if(paths[row[@"fork"]] && ![paths[row[@"fork"]] isEqual:row[@"path"]]){row[@"path"]=paths[row[@"fork"]];row[@"ready"]=@NO;}}
    if([action isEqual:@"close"] && self.setupStep==4){if(!self.preview){NSMutableDictionary *progress=[SSReadPlist(@"onboarding.plist") mutableCopy] ?: NSMutableDictionary.dictionary;progress[@"tipsCompleted"]=@YES;SSWritePlist(@"onboarding.plist",progress,NULL);}[self closeCourseSetup];return;}
    if([action isEqual:@"login"]){[self login:nil];return;}
    if([action isEqual:@"back"]){self.setupStep=MAX(0,self.setupStep-1);if(self.setupStep==1){[self addFork:nil];return;}[self updateCourseSetup:@"返回不会删除已保存的课程和任务。"];return;}
    if([action isEqual:@"finish"]){if(!self.preview){NSError *error=nil;NSMutableDictionary *progress=[SSReadPlist(@"onboarding.plist") mutableCopy] ?: NSMutableDictionary.dictionary;progress[@"completed"]=@YES;if(!SSWritePlist(@"onboarding.plist",progress,&error)){[self updateCourseSetup:error.localizedDescription];return;}}self.setupStep=4;[self updateCourseSetup:@"配置完成，未就绪课程可稍后继续。"];return;}
    if([action isEqual:@"result"]){NSString *fork=request[@"course"];[self closeCourseSetup];[self selectCourseID:fork];if(self.onboardingNavigation)self.onboardingNavigation(NO);return;}
    if([action isEqual:@"restart"]){self.setupStep=self.connected ? 1:0;[self updateCourseSetup:@""];if(self.connected)[self addFork:nil];return;}
    if([action isEqual:@"courses"] || [action isEqual:@"review"]){if(!self.preview){NSMutableDictionary *progress=[SSReadPlist(@"onboarding.plist") mutableCopy] ?: NSMutableDictionary.dictionary;progress[@"tipsCompleted"]=@YES;SSWritePlist(@"onboarding.plist",progress,NULL);}[self closeCourseSetup];if(self.onboardingNavigation)self.onboardingNavigation([action isEqual:@"review"]);return;}
    if([action isEqual:@"reload"]){[self closeCourseSetup];[self addFork:nil];return;}
    if([action isEqual:@"close"]){[self updateCourseSetup:@"进度已保存，下次可以继续。"];[self closeCourseSetup];return;}
    if([action isEqual:@"check"]){NSMutableArray *ready=NSMutableArray.array;for(NSDictionary *row in self.setupRecords){NSDictionary *course=[self savedCourse:row];if([row[@"ready"] boolValue] && [course[@"path"] length])[ready addObject:course.copy];}if(!ready.count){[self updateCourseSetup:@"请先关联至少一门可读取的课程。"];return;}self.setupStep=3;self.firstCheckRunning=YES;[self scanCourses:ready];[self updateCourseSetup:@"首次检查中，请等待；不会重复启动检查。"];return;}
    if([action isEqual:@"select"] || [action isEqual:@"retry"]){
        NSArray *ids=request[@"selected"];if([action isEqual:@"retry"])ids=[self.setupRecords valueForKey:@"fork"];if(!ids.count)return;
        NSMutableArray *chosen=NSMutableArray.array;for(NSDictionary *fork in self.availableForks)if([ids containsObject:fork[@"full_name"]])[chosen addObject:fork];
        if(!chosen.count)return;[self work:@"正在核验课程及私有老师仓库…" forCourse:nil operation:^id(NSError **error){
            NSMutableArray *result=NSMutableArray.array;
            for(NSDictionary *fork in chosen){NSString *name=fork[@"full_name"];NSError *issue=nil;NSDictionary *details=[self.github repository:name error:&issue],*parent=details[@"parent"];NSMutableDictionary *row=[@{@"fork":name} mutableCopy];
                if(details[@"id"] && parent[@"id"] && details[@"owner"][@"id"] && [parent[@"full_name"] length]){
                    NSDictionary *old=[self savedCourse:row];NSMutableDictionary *course=[old mutableCopy] ?: NSMutableDictionary.dictionary;
                    [course addEntriesFromDictionary:@{@"enabled":old[@"enabled"] ?: @YES,@"fork":name,@"upstream":parent[@"full_name"],@"forkID":old[@"forkID"] ?: details[@"id"],@"upstreamID":old[@"upstreamID"] ?: parent[@"id"],@"ownerID":old[@"ownerID"] ?: details[@"owner"][@"id"],@"branch":old[@"branch"] ?: details[@"default_branch"] ?: @"main",@"upstreamBranch":parent[@"default_branch"] ?: @"main",@"upstreamURL":parent[@"clone_url"] ?: @"",@"timeZone":old[@"timeZone"] ?: NSTimeZone.localTimeZone.name}];
                    row[@"upstream"]=parent[@"full_name"];
                    if([self.github readableTeacher:course error:&issue]){row[@"course"]=course;row[@"path"]=course[@"path"] ?: @"";row[@"status"]=@"权限已通过，请关联本地目录。";if([course[@"path"] length] && [self.git linkCourse:course error:&issue]){course[@"connectionAuth"]=self.github.authType;row[@"ready"]=@YES;row[@"status"]=@"已复用原目录，老师仓库读取正常。";}}
                }
                if(!row[@"course"]){row[@"invalid"]=@YES;row[@"status"]=issue.localizedDescription ?: @"缺少可核验的老师上游，无法添加课程。";row[@"detail"]=issue.userInfo[@"SSDetail"] ?: @"";row[@"issue"]=issue.userInfo[@"SSIssue"] ?: @"permission";NSString *owner=[parent[@"full_name"] componentsSeparatedByString:@"/"].firstObject;if([row[@"issue"] isEqual:@"sso"] && owner.length)row[@"helpURL"]=[NSString stringWithFormat:@"https://github.com/orgs/%@/sso",owner];}
                [result addObject:row];
            }return result;
        } completion:^(NSArray *rows,NSError *error){
            self.setupRecords=[rows mutableCopy] ?: NSMutableArray.array;self.setupStep=2;
            for(NSMutableDictionary *row in self.setupRecords)if(row[@"course"]){NSError *saveError=nil;if(![self saveConfiguredCourse:row[@"course"] error:&saveError]){row[@"invalid"]=@YES;row[@"ready"]=@NO;row[@"status"]=@"配置保存失败，请重试；原课程配置已保留。";}}
            [self refreshCourses];[self updateCourseSetup:@"选择课程总文件夹可批量匹配；权限失败可处理后重新检测。"];
        }];[self updateCourseSetup:@"正在核验所选课程…"];return;
    }
    if([action isEqual:@"find"]){
        NSOpenPanel *panel=NSOpenPanel.openPanel;panel.canChooseFiles=NO;panel.canChooseDirectories=YES;panel.message=@"选择课程总文件夹；仅检查该目录和下两层的 Git 身份。";if([panel runModal]!=NSModalResponseOK)return;NSString *root=panel.URL.path;NSArray *courses=self.setupRecords.copy;
        [self work:@"正在匹配已有课程目录…" forCourse:nil operation:^id(NSError **error){return [self.git matchingDirectories:root courses:courses];} completion:^(NSDictionary *matches,NSError *error){for(NSMutableDictionary *row in self.setupRecords){NSArray *paths=matches[row[@"fork"]] ?: @[];row[@"matches"]=paths;if(paths.count==1){if(![row[@"path"] isEqual:paths.firstObject])row[@"ready"]=@NO;row[@"path"]=paths.firstObject;}else if(paths.count>1){row[@"path"]=@"";row[@"ready"]=@NO;row[@"status"]=@"找到多个对应仓库，请选择使用的目录。";}}[self updateCourseSetup:@"匹配完成。请核对后点“关联选定目录”。"]; }];[self updateCourseSetup:@"正在检查目录身份…"];return;
    }
    if([action isEqual:@"folder"]){NSOpenPanel *panel=NSOpenPanel.openPanel;panel.canChooseFiles=NO;panel.canChooseDirectories=YES;if([panel runModal]!=NSModalResponseOK)return;for(NSMutableDictionary *row in self.setupRecords)if([row[@"fork"] isEqual:request[@"course"]]){row[@"path"]=panel.URL.path;row[@"ready"]=@NO;row[@"matches"]=@[panel.URL.path];}[self updateCourseSetup:@"目录已选中，关联前将核验仓库身份。"];return;}
    if([action isEqual:@"link"] || [action isEqual:@"download"]){
        BOOL downloading=[action isEqual:@"download"];NSString *root=nil;
        if(downloading){NSOpenPanel *panel=NSOpenPanel.openPanel;panel.canChooseFiles=NO;panel.canChooseDirectories=YES;panel.message=@"为未关联课程选择一次下载位置；已有文件夹不会被覆盖。";if([panel runModal]!=NSModalResponseOK)return;root=panel.URL.path;}
        NSMutableArray *rows=NSMutableArray.array;NSDictionary *paths=request[@"paths"];
        for(NSDictionary *source in self.setupRecords){NSMutableDictionary *row=source.mutableCopy;if(paths[row[@"fork"]]){if(![paths[row[@"fork"]] isEqual:row[@"path"]])row[@"ready"]=@NO;row[@"path"]=paths[row[@"fork"]];}[rows addObject:row];}
        [self work:downloading ? @"正在下载并关联课程…":@"正在批量关联课程…" forCourse:nil operation:^id(NSError **error){
            for(NSMutableDictionary *row in rows){if([row[@"invalid"] boolValue])continue;NSMutableDictionary *course=[[self savedCourse:row] mutableCopy];if(!course)continue;NSError *issue=nil;NSString *path=row[@"path"];
                if(downloading && [row[@"ready"] boolValue])continue;
                if(downloading && !path.length){path=[root stringByAppendingPathComponent:[course[@"fork"] lastPathComponent]];course[@"path"]=path;NSString *token=[self.github accessToken:&issue];if(!token || ![self.git cloneFork:course into:path token:token error:&issue]){row[@"status"]=issue.localizedDescription ?: @"下载失败";continue;}}
                if(!path.length){row[@"status"]=@"尚未选择目录，可以稍后关联。";row[@"ready"]=@NO;continue;}course[@"path"]=path;row[@"path"]=path;row[@"ready"]=@NO;
                if(![self.git linkCourse:course error:&issue]){row[@"status"]=issue.localizedDescription;row[@"detail"]=issue.userInfo[@"SSDetail"] ?: issue.localizedDescription;continue;}
                course[@"connectionAuth"]=self.github.authType;row[@"course"]=course;row[@"path"]=path;row[@"ready"]=@YES;row[@"status"]=@"已关联，老师仓库读取正常。";
            }return rows;
        } completion:^(NSArray *result,NSError *error){self.setupRecords=[result mutableCopy];NSUInteger ready=0;for(NSMutableDictionary *row in self.setupRecords)if([row[@"ready"] boolValue]){NSError *issue=nil;if([self saveConfiguredCourse:row[@"course"] error:&issue])ready++;else{row[@"ready"]=@NO;row[@"status"]=@"保存失败，已有配置未覆盖，请重试。";}}self.setupStep=2;[self refreshCourses];[self updateCourseSetup:[NSString stringWithFormat:@"%lu 门课程可开始检查；未完成课程可稍后继续。",(unsigned long)ready]];}];[self updateCourseSetup:@"正在逐门验证与保存…"];return;
    }
}
