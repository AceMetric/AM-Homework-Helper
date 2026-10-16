- (void)enhanceRecognition:(id)sender {
    NSDictionary *course=[self course].copy;if(!course || ![course[@"path"] length]){[self status:@"请选择已关联本机文件夹的课程，再增强识别。" ];return;}
    NSDictionary *settings=SSRecognitionSettings();BOOL cloud=[settings[@"mode"] isEqual:@"cloud"];
    if([settings[@"mode"] isEqual:@"rules"] || (cloud && ![settings[@"cloudCourses"] containsObject:course[@"fork"]])){[self status:@"请先在设置中配置识别服务，并选择允许增强的课程。免费规则识别仍可用。" ];return;}
    if(self.hasUnsavedReview && ![self resolveUnsavedReview])return;
    [self work:@"准备老师材料与本机识别结果…" forCourse:course operation:^id(NSError **error){self.git.recognitionSettings=@{@"mode":@"rules"};NSMutableDictionary *cache=AMScanCacheLoad(error);if(!cache)return nil;return [self.git scanCourse:course cache:cache error:error];} completion:^(NSDictionary *scan,NSError *error){
        if(!scan){[self showError:error];return;}
        if(!self.hasUnsavedReview){self.candidates[course[@"fork"]]=[self retainingSkill:self.candidates[course[@"fork"]] current:scan[@"candidates"] documents:scan[@"documents"]];self.materials[course[@"fork"]]=scan[@"materials"] ?: @[];[self refreshPresentation];}
        NSMutableDictionary *files=NSMutableDictionary.dictionary;NSMutableArray *paths=NSMutableArray.array;for(NSDictionary *document in scan[@"documents"]){NSString *path=document[@"path"];if(!path || !document[@"text"])continue;files[path]=@{@"text":document[@"text"],@"version":document[@"blobSHA"] ?: @""};[paths addObject:path];}
        if(!paths.count){[self status:@"未找到可增强的老师文本材料；本机结果保留。" ];return;}
        PFMaterials *preview=[[PFMaterials alloc] initWithSnapshot:@{@"paths":paths,@"files":files} report:@{@"images":@[]} requirements:@""];preview.destination.hidden=YES;preview.window.title=[NSString stringWithFormat:@"确认识别范围 · %@",settings[@"model"] ?: @"模型"];
        for(NSView *view in preview.window.contentView.subviews){if([view.identifier isEqual:@"material-prepare"] && [view isKindOfClass:NSButton.class])[(NSButton *)view setTitle:cloud ? @"发送并增强识别":@"本机增强识别"];if([view.identifier isEqual:@"handoff-hint"] && [view isKindOfClass:NSTextField.class])[(NSTextField *)view setStringValue:cloud ? @"只发送所选老师材料；结果仍需审核，不自动保存任务。":@"仅处理所选老师材料；不下载模型，不发送到云端。"];}
        NSArray *selected=nil;
#ifdef DDL_TESTING
        if(self.recognitionScopeSelector)selected=self.recognitionScopeSelector(preview);
        else
#endif
        {[preview.window center];NSModalResponse response=[NSApp runModalForWindow:preview.window];[preview.window orderOut:nil];if(response!=NSModalResponseOK)return;selected=[preview selectedSnapshot][@"paths"];}
        if(!selected.count){[self status:@"未选择材料，未调用模型。" ];return;}
        NSMutableDictionary *approved=settings.mutableCopy;approved[@"manualCloud"]=@YES;approved[@"manualLocal"]=@YES;approved[@"forceRecognition"]=@YES;
        [self work:@"增强识别所选材料…" forCourse:course requestKey:[NSString stringWithFormat:@"%@|%@",scan[@"commit"],[selected sortedArrayUsingSelector:@selector(compare:)]] priority:100 operation:^id(NSError **failure){NSMutableDictionary *cache=AMScanCacheLoad(failure);if(!cache)return nil;NSDictionary *result=[self.git enhanceScan:scan course:course settings:approved paths:selected cache:cache];return AMScanCacheSave(cache,failure) ? result:nil;} completion:^(NSDictionary *result,NSError *failure){
            if(!result){[self showError:failure];return;}
            NSMutableDictionary *reports=self.reports.mutableCopy ?: NSMutableDictionary.dictionary;reports[course[@"fork"]]=result;self.reports=reports;
            if(self.hasUnsavedReview){if(!self.deferredScans)self.deferredScans=NSMutableDictionary.dictionary;self.deferredScans[course[@"fork"]]=result;[self status:@"增强结果已准备好；当前审核草稿保留，结束编辑后接入。" ];return;}
            self.candidates[course[@"fork"]]=[self retainingSkill:self.candidates[course[@"fork"]] current:result[@"candidates"] documents:result[@"documents"]];self.materials[course[@"fork"]]=result[@"materials"] ?: @[];if(!self.preview)SSWritePlist(@"discoveries.plist",[self discoveryEnvelope],NULL);[self refreshPresentation];
            [self status:[result[@"recognitionMessages"] count] ? [NSString stringWithFormat:@"部分增强未完成；规则结果和草稿保留。%@",[result[@"recognitionMessages"] componentsJoinedByString:@"；"]]:@"增强结果已进入待审核；请核对日期与内容。" ];
        }];
    }];
}

// Yield the repository lane after each automatic document so a user request can
// take priority without interrupting an already-sent model request.
- (void)enqueueAutomaticEnhancement:(NSDictionary *)scan course:(NSDictionary *)course settings:(NSDictionary *)settings {
    NSDictionary *scoped=SSCourseRecognitionSettings(settings,course);
    if(![scoped[@"mode"] isEqual:@"local"] || (scoped[@"localAutomatic"] && ![scoped[@"localAutomatic"] boolValue]))return;
    NSError *loadError=nil;NSDictionary *cache=AMScanCacheLoad(&loadError);if(!cache){[self showError:loadError];return;}
    for(NSDictionary *document in scan[@"documents"]){
        NSString *completedKey=[NSString stringWithFormat:@"model-complete-v1|%@|%@|%@|%@",[document[@"repository"] lowercaseString],document[@"path"],document[@"blobSHA"],document[@"timeZone"]];
        if(cache[completedKey])continue;
        NSString *scope=[NSString stringWithFormat:@"%@|%@|%@",scan[@"commit"],document[@"path"],document[@"blobSHA"]];
        [self work:@"后台增强识别…" forCourse:course requestKey:scope priority:0 operation:^id(NSError **error){
            __block NSDictionary *input=nil;dispatch_sync(dispatch_get_main_queue(),^{input=[self.reports[course[@"fork"]] copy];});
            if(![input[@"commit"] isEqual:scan[@"commit"]]){if(error)*error=[NSError errorWithDomain:@"AMOperation" code:1 userInfo:@{NSLocalizedDescriptionKey:@"老师材料已更新，旧版本排队分析已跳过。"}];return nil;}
            NSMutableDictionary *stored=AMScanCacheLoad(error);if(!stored)return nil;
            NSDictionary *current=[self.git readCourseDocuments:course paths:@[document[@"path"]] fetch:NO cache:stored error:error];if(!current)return nil;
            BOOL valid=NO;for(NSDictionary *row in current[@"documents"])if([row[@"blobSHA"] isEqual:document[@"blobSHA"]])valid=YES;
            if(!valid){if(error)*error=[NSError errorWithDomain:@"AMOperation" code:1 userInfo:@{NSLocalizedDescriptionKey:@"排队材料的版本已变化，请重新检查课程。"}];return nil;}
            NSDictionary *result=[self.git enhanceScan:input course:course settings:settings paths:@[document[@"path"]] cache:stored];return AMScanCacheSave(stored,error) ? result:nil;
        } completion:^(NSDictionary *result,NSError *error){
            if(!result){if(error.code!=NSUserCancelledError)[self showError:error];return;}
            if(![self.reports[course[@"fork"]][@"commit"] isEqual:scan[@"commit"]])return;
            NSMutableDictionary *reports=self.reports.mutableCopy;reports[course[@"fork"]]=result;self.reports=reports;
            if(self.hasUnsavedReview){if(!self.deferredScans)self.deferredScans=NSMutableDictionary.dictionary;self.deferredScans[course[@"fork"]]=result;}
            else {self.candidates[course[@"fork"]]=[self retainingSkill:self.candidates[course[@"fork"]] current:result[@"candidates"] documents:result[@"documents"]];self.materials[course[@"fork"]]=result[@"materials"] ?: @[];}
            if(!SSWritePlist(@"discoveries.plist",self.discoveryEnvelope,NULL))[self status:@"结果尚未保存，请检查本机数据目录后重试。"];
            else [self status:[result[@"recognitionMessages"] count] ? [result[@"recognitionMessages"] firstObject]:@"新增材料分析完成，结果已接入审核。"];
        }];
    }
}
