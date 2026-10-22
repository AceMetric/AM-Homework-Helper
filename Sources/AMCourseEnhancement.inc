- (NSDictionary *)retainWorkflowResult:(NSDictionary *)result cache:(NSMutableDictionary *)cache error:(NSError **)error {
    NSError *failure=nil;if(!AMScanCacheSave(cache,&failure)){AMCourseOperationContext *context=AMCourseContext(self);context.saveResult=^BOOL(NSError **issue){return AMScanCacheSave(cache,issue);};if(error)*error=AMWorkflowError(@"storage",@"检查结果尚未保存",failure);return result;}
    if(result[@"persistenceIssue"])return AMWorkflowSavedScan(result);
    NSMutableDictionary *clean=result.mutableCopy;for(NSString *key in result)if([result[key] isKindOfClass:NSDictionary.class] && result[key][@"persistenceIssue"])clean[key]=AMWorkflowSavedScan(result[key]);return clean;
}
- (NSDictionary *)workflowDocuments:(NSDictionary *)course paths:(NSArray *)paths fetch:(BOOL)fetch cache:(NSMutableDictionary *)cache error:(NSError **)error {
    AMCourseOperationContext *context=AMCourseContext(self);SSGit *reader=self.git;if(!context)return [reader readCourseDocuments:course paths:paths fetch:fetch cache:cache error:error];
    return AMPerformResourceOperationInTask(context.identifier,NSUUID.UUID.UUIDString,@"核验材料版本",course[@"fork"],@[@"git-write"],100,^BOOL{return context.cancelled;},^id(NSError **failure){return [reader readCourseDocuments:course paths:paths fetch:fetch cache:cache error:failure];},error);
}
- (NSArray *)recognitionFailures {
    NSMutableArray *rows=NSMutableArray.array;
    for(NSString *fork in [self.reports.allKeys sortedArrayUsingSelector:@selector(compare:)]){NSDictionary *report=self.reports[fork];for(NSString *path in [report[@"modelFailures"] allKeys]){NSMutableDictionary *row=[report[@"modelFailures"][path] mutableCopy];row[@"course"]=fork;[rows addObject:row];}}
    return [rows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [[a[@"course"] stringByAppendingString:a[@"path"]] compare:[b[@"course"] stringByAppendingString:b[@"path"]]];}];
}
- (void)postRecognitionSummary {
    NSArray *failures=[self recognitionFailures];if(self.operationID.length){AMDismissUIMessage(@"course-recognition",@"failures");return;}if(!failures.count){AMDismissUIMessage(@"course-recognition",@"failures");return;}
    NSString *revision=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:failures options:NSJSONWritingSortedKeys error:NULL] encoding:NSUTF8StringEncoding];__weak typeof(self) owner=self;
    AMPostUIMessageWithRevision(@"course-recognition",@"failures",revision,[NSString stringWithFormat:@"%lu 份材料未完成增强",(unsigned long)failures.count],AMUIMessageWarning,@"查看",^{[owner showRecognitionFailures:nil];});
}
- (void)showRecognitionFailures:(id)sender {
    NSArray *failures=[self recognitionFailures];if(!failures.count)return;
    NSAlert *alert=NSAlert.new;alert.messageText=[NSString stringWithFormat:@"%lu 份材料未完成增强",(unsigned long)failures.count];NSDictionary *settings=SSRecognitionSettings();BOOL cloud=[settings[@"mode"] isEqual:@"cloud"];
    alert.informativeText=cloud ? [NSString stringWithFormat:@"重试仅发送这些文件到 %@（%@），可能产生费用。",[NSURL URLWithString:settings[@"endpoint"]].host ?: @"所选服务",settings[@"model"] ?: @"模型"]:@"可用结果已保留。重试仅处理以下文件。";
    NSView *accessory=[[NSView alloc] initWithFrame:NSMakeRect(0,0,550,230)];NSPopUpButton *source=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0,202,550,26)];
    NSMutableArray *lines=NSMutableArray.array;for(NSDictionary *row in failures){[source addItemWithTitle:[NSString stringWithFormat:@"%@ · %@",row[@"course"],row[@"path"]]];NSMutableOrderedSet *reasons=NSMutableOrderedSet.orderedSet;for(NSDictionary *issue in row[@"issues"])[reasons addObject:[NSString stringWithFormat:@"%@：%@",issue[@"field"] ?: @"结果",issue[@"reason"] ?: @"未通过核验"]];[lines addObject:[NSString stringWithFormat:@"%@ · %@\n%@",row[@"course"],row[@"path"],[reasons.array componentsJoinedByString:@"；"]]];}
    [accessory addSubview:source];NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,550,190)];scroll.hasVerticalScroller=YES;NSTextView *detail=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,530,190)];detail.editable=NO;detail.font=[NSFont systemFontOfSize:13];detail.string=[lines componentsJoinedByString:@"\n\n"];scroll.documentView=detail;[accessory addSubview:scroll];alert.accessoryView=accessory;
    NSButton *retry=[alert addButtonWithTitle:cloud ? @"发送并重试":@"重试失败项"];retry.enabled=![settings[@"mode"] isEqual:@"rules"] && !self.operationsPaused;[alert addButtonWithTitle:@"查看原文"];[alert addButtonWithTitle:@"关闭"];NSModalResponse choice=[alert runModal];
    if(choice==NSAlertSecondButtonReturn){NSDictionary *row=failures[MAX(0,source.indexOfSelectedItem)];NSDictionary *document=nil;for(NSDictionary *doc in self.reports[row[@"course"]][@"documents"])if([doc[@"path"] isEqual:row[@"path"]] && [doc[@"blobSHA"] isEqual:row[@"blobSHA"]])document=doc;if(!document){[self status:@"原文版本已变化，请重新检查课程"];return;}NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,800,600) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];window.releasedWhenClosed=NO;window.title=[NSString stringWithFormat:@"%@ · %@",row[@"path"],row[@"blobSHA"]];AMDocumentView *view=[[AMDocumentView alloc] initWithFrame:window.contentView.bounds];window.contentView=view;view.markdown=document[@"text"];[view locateLine:1];[window center];[window makeKeyAndOrderFront:nil];objc_setAssociatedObject(self,@selector(showRecognitionFailures:),window,OBJC_ASSOCIATION_RETAIN_NONATOMIC);return;}
    if(choice!=NSAlertFirstButtonReturn)return;
    NSMutableDictionary *byCourse=NSMutableDictionary.dictionary;for(NSDictionary *row in failures){if(!byCourse[row[@"course"]])byCourse[row[@"course"]]=NSMutableArray.array;[byCourse[row[@"course"]] addObject:row[@"path"]];}
    for(NSString *fork in byCourse){NSDictionary *course=[self savedCourse:@{@"fork":fork}].copy,*scan=[self.reports[fork] copy];NSArray *paths=[byCourse[fork] copy];if(!course || !scan)continue;NSMutableDictionary *approved=settings.mutableCopy;approved[@"manualLocal"]=@YES;approved[@"manualCloud"]=@YES;approved[@"forceRecognition"]=@YES;
        [self work:@"重试识别…" forCourse:course requestKey:[NSString stringWithFormat:@"retry|%@|%@",scan[@"commit"],paths] priority:100 kind:AMCourseWorkModel operation:^id(NSError **error){NSMutableDictionary *cache=AMScanCacheLoad(error);if(!cache)return nil;NSDictionary *live=[self workflowDocuments:course paths:paths fetch:YES cache:cache error:error];if(!live)return nil;for(NSString *path in paths){NSDictionary *old=nil,*now=nil;for(NSDictionary *doc in scan[@"documents"])if([doc[@"path"] isEqual:path])old=doc;for(NSDictionary *doc in live[@"documents"])if([doc[@"path"] isEqual:path])now=doc;if(!old || ![old[@"blobSHA"] isEqual:now[@"blobSHA"]]){if(error)*error=[NSError errorWithDomain:@"AMRecognition" code:3 userInfo:@{NSLocalizedDescriptionKey:@"材料版本已变化，请重新检查课程"}];return nil;}}NSDictionary *result=[self.git enhanceScan:scan course:course settings:approved paths:paths cache:cache];return [self retainWorkflowResult:result cache:cache error:error];} completion:^(NSDictionary *result,NSError *error){if(!result){[self showError:error];return;}NSMutableDictionary *reports=self.reports.mutableCopy;reports[fork]=result;self.reports=reports;if(self.hasUnsavedReview){if(!self.deferredScans)self.deferredScans=NSMutableDictionary.dictionary;self.deferredScans[fork]=result;}else {self.candidates[fork]=[self retainingSkill:self.candidates[fork] current:result[@"candidates"] documents:result[@"documents"]];self.materials[fork]=result[@"materials"] ?: @[];}NSError *save=nil;if(!SSWritePlist(@"discoveries.plist",self.discoveryEnvelope,&save))[self showError:save];else {[self updateCheckSummaryForCourse:course];[self status:self.statuses[fork]];}[self postRecognitionSummary];[self refreshPresentation];}];
    }
}
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
        [self work:@"增强识别所选材料…" forCourse:course requestKey:[NSString stringWithFormat:@"%@|%@",scan[@"commit"],[selected sortedArrayUsingSelector:@selector(compare:)]] priority:100 kind:AMCourseWorkModel operation:^id(NSError **failure){NSMutableDictionary *cache=AMScanCacheLoad(failure);if(!cache)return nil;NSDictionary *result=[self.git enhanceScan:scan course:course settings:approved paths:selected cache:cache];return [self retainWorkflowResult:result cache:cache error:failure];} completion:^(NSDictionary *result,NSError *failure){
            if(!result){[self showError:failure];return;}
            NSMutableDictionary *reports=self.reports.mutableCopy ?: NSMutableDictionary.dictionary;reports[course[@"fork"]]=result;self.reports=reports;
            if(self.hasUnsavedReview){if(!self.deferredScans)self.deferredScans=NSMutableDictionary.dictionary;self.deferredScans[course[@"fork"]]=result;[self status:@"增强结果已准备好；当前审核草稿保留，结束编辑后接入。" ];return;}
            self.candidates[course[@"fork"]]=[self retainingSkill:self.candidates[course[@"fork"]] current:result[@"candidates"] documents:result[@"documents"]];self.materials[course[@"fork"]]=result[@"materials"] ?: @[];if(!self.preview){NSError *saveError=nil;if(!SSWritePlist(@"discoveries.plist",[self discoveryEnvelope],&saveError))[self showError:saveError];}[self refreshPresentation];
            [self updateCheckSummaryForCourse:course];[self status:self.statuses[course[@"fork"]]];[self postRecognitionSummary];
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
        [self work:[NSString stringWithFormat:@"增强识别：%@",document[@"path"]] forCourse:course requestKey:scope priority:0 kind:AMCourseWorkModel operation:^id(NSError **error){
            __block NSDictionary *input=nil;dispatch_sync(dispatch_get_main_queue(),^{input=[self.reports[course[@"fork"]] copy];});
            if(![input[@"commit"] isEqual:scan[@"commit"]]){if(error)*error=[NSError errorWithDomain:@"AMOperation" code:1 userInfo:@{NSLocalizedDescriptionKey:@"老师材料已更新，旧版本排队分析已跳过。"}];return nil;}
            NSMutableDictionary *stored=AMScanCacheLoad(error);if(!stored)return nil;
            NSDictionary *current=[self workflowDocuments:course paths:@[document[@"path"]] fetch:NO cache:stored error:error];if(!current)return nil;
            BOOL valid=NO;for(NSDictionary *row in current[@"documents"])if([row[@"blobSHA"] isEqual:document[@"blobSHA"]])valid=YES;
            if(!valid){if(error)*error=[NSError errorWithDomain:@"AMOperation" code:1 userInfo:@{NSLocalizedDescriptionKey:@"排队材料的版本已变化，请重新检查课程。"}];return nil;}
            NSDictionary *result=[self.git enhanceScan:input course:course settings:settings paths:@[document[@"path"]] cache:stored];return [self retainWorkflowResult:result cache:stored error:error];
        } completion:^(NSDictionary *result,NSError *error){
            if(!result){if(error.code!=NSUserCancelledError)[self showError:error];return;}
            if(![self.reports[course[@"fork"]][@"commit"] isEqual:scan[@"commit"]])return;
            NSMutableDictionary *reports=self.reports.mutableCopy;reports[course[@"fork"]]=result;self.reports=reports;
            if(self.hasUnsavedReview){if(!self.deferredScans)self.deferredScans=NSMutableDictionary.dictionary;self.deferredScans[course[@"fork"]]=result;}
            else {self.candidates[course[@"fork"]]=[self retainingSkill:self.candidates[course[@"fork"]] current:result[@"candidates"] documents:result[@"documents"]];self.materials[course[@"fork"]]=result[@"materials"] ?: @[];}
            NSError *saveError=nil;if(!SSWritePlist(@"discoveries.plist",self.discoveryEnvelope,&saveError))[self showError:saveError];
            else {[self updateCheckSummaryForCourse:course];[self status:self.statuses[course[@"fork"]]];}[self postRecognitionSummary];
        }];
    }
}
