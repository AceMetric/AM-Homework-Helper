- (void)enhanceRecognition:(id)sender {
    NSDictionary *course=[self course].copy;if(!course || ![course[@"path"] length]){[self status:@"请选择已关联本机文件夹的课程，再增强识别。" ];return;}
    NSDictionary *settings=SSRecognitionSettings();BOOL cloud=[settings[@"mode"] isEqual:@"cloud"];
    if([settings[@"mode"] isEqual:@"rules"] || (cloud && ![settings[@"cloudCourses"] containsObject:course[@"fork"]])){[self status:@"请先在设置中配置识别服务，并选择允许增强的课程。免费规则识别仍可用。" ];return;}
    if(self.hasUnsavedReview && ![self resolveUnsavedReview])return;
    [self work:@"准备老师材料与本机识别结果…" forCourse:course operation:^id(NSError **error){self.git.recognitionSettings=@{@"mode":@"rules"};NSMutableDictionary *cache=[SSReadPlist(@"scan-cache.plist") mutableCopy] ?: NSMutableDictionary.dictionary;return [self.git scanCourse:course cache:cache error:error];} completion:^(NSDictionary *scan,NSError *error){
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
        [self work:@"增强识别所选材料…" forCourse:course operation:^id(NSError **failure){NSMutableDictionary *cache=[SSReadPlist(@"scan-cache.plist") mutableCopy] ?: NSMutableDictionary.dictionary;NSDictionary *result=[self.git enhanceScan:scan course:course settings:approved paths:selected cache:cache];SSWritePlist(@"scan-cache.plist",cache,NULL);return result;} completion:^(NSDictionary *result,NSError *failure){
            if(!result){[self showError:failure];return;}
            if(self.hasUnsavedReview){if(!self.deferredScans)self.deferredScans=NSMutableDictionary.dictionary;self.deferredScans[course[@"fork"]]=result;[self status:@"增强结果已准备好；当前审核草稿保留，结束编辑后接入。" ];return;}
            self.candidates[course[@"fork"]]=[self retainingSkill:self.candidates[course[@"fork"]] current:result[@"candidates"] documents:result[@"documents"]];self.materials[course[@"fork"]]=result[@"materials"] ?: @[];if(!self.preview)SSWritePlist(@"discoveries.plist",[self discoveryEnvelope],NULL);[self refreshPresentation];
            [self status:[result[@"recognitionMessages"] count] ? [NSString stringWithFormat:@"部分增强未完成；规则结果和草稿保留。%@",[result[@"recognitionMessages"] componentsJoinedByString:@"；"]]:@"增强结果已进入待审核；请核对日期与内容。" ];
        }];
    }];
}
