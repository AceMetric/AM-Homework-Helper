// 子材料重新识别也影响承载它的父候选，必须替换整个机器快照，才能保留新的子任务结果。
- (BOOL)recognitionRecord:(NSDictionary *)record touchesPaths:(NSArray *)paths depth:(NSUInteger)depth {
    if(depth>32)return NO;if([paths containsObject:record[@"path"] ?: @""])return YES;
    for(NSDictionary *child in record[@"attachments"] ?: @[])if([self recognitionRecord:child touchesPaths:paths depth:depth+1])return YES;
    return NO;
}
- (void)recognizeLocal:(id)sender {
    NSDictionary *course=[self course].copy;if(!course || self.preview || self.operationsPaused)return;
    NSMutableDictionary *settings=SSRecognitionSettings().mutableCopy;settings[@"mode"]=@"local";settings[@"manualLocal"]=@YES;settings[@"forceRecognition"]=@YES;
    NSError *invalid=nil;if(!SSValidateRecognitionSettings(settings,&invalid)){[self status:@"请先在设置选择本地模型；可关闭自动分析，仅使用手动识别。"];return;}
    [self work:@"正在准备老师来源文件…" forCourse:course requestKey:@"prepare-source" priority:100 kind:AMCourseWorkScan operation:^id(NSError **error){self.git.recognitionSettings=@{@"mode":@"rules"};NSMutableDictionary *cache=AMScanCacheLoad(error);if(!cache)return nil;return [self.git scanCourse:course cache:cache error:error];} completion:^(NSDictionary *scan,NSError *error){
        if(!scan){[self showError:error];return;}if(self.operationsPaused)return;
        NSArray *documents=[scan[@"documents"] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *doc,NSDictionary *bindings){(void)bindings;return !SSExamOnlySource(doc[@"text"],doc[@"path"]);}]];if(!documents.count){[self status:@"没有可识别的老师文本文件。"];return;}
        NSAlert *choose=NSAlert.new;choose.messageText=@"用本地模型重新识别";choose.informativeText=@"勾选老师来源文件。只重新分析选中文档，不清空其他缓存，也不会自动加入模型新增的作业。";
        NSView *rows=[[NSView alloc] initWithFrame:NSMakeRect(0,0,540,documents.count*28+32)];NSMutableArray *checks=NSMutableArray.array;
        NSButton *all=[NSButton checkboxWithTitle:@"识别全部文件" target:nil action:nil];all.frame=NSMakeRect(0,NSHeight(rows.frame)-28,530,24);[rows addSubview:all];
        for(NSUInteger i=0;i<documents.count;i++){NSButton *check=[NSButton checkboxWithTitle:documents[i][@"path"] target:nil action:nil];check.frame=NSMakeRect(0,NSHeight(rows.frame)-60-i*28,530,24);[checks addObject:check];[rows addSubview:check];}
        NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,560,MIN(300,NSHeight(rows.frame)))];scroll.hasVerticalScroller=YES;scroll.documentView=rows;choose.accessoryView=scroll;[choose addButtonWithTitle:@"重新识别"];[choose addButtonWithTitle:@"取消"];if([choose runModal]!=NSAlertFirstButtonReturn)return;
        NSMutableArray *paths=NSMutableArray.array;for(NSUInteger i=0;i<checks.count;i++)if(all.state==NSControlStateValueOn || [checks[i] state]==NSControlStateValueOn)[paths addObject:documents[i][@"path"]];if(!paths.count){[self status:@"请选择至少一个老师来源文件。"];return;}
        [self work:@"正在用本地模型分析选中文件…" forCourse:course operation:^id(NSError **failure){NSMutableDictionary *cache=AMScanCacheLoad(failure);if(!cache)return nil;NSDictionary *enhanced=[self.git enhanceScan:scan course:course settings:settings paths:paths cache:cache];return AMScanCacheSave(cache,failure) ? enhanced:nil;} completion:^(NSDictionary *enhanced,NSError *failure){
            if(!enhanced){[self showError:failure];return;}NSMutableDictionary *candidates=self.candidates.mutableCopy,*materials=self.materials.mutableCopy;
            NSMutableDictionary *byID=NSMutableDictionary.dictionary;for(NSDictionary *record in candidates[course[@"fork"]] ?: @[])byID[record[@"id"]]=record;
            for(NSDictionary *group in materials[course[@"fork"]] ?: @[])for(NSDictionary *record in group[@"documents"] ?: @[group])byID[record[@"id"]]=record;
            NSMutableArray *fresh=[enhanced[@"candidates"] mutableCopy];for(NSDictionary *group in enhanced[@"materials"])for(NSDictionary *record in group[@"documents"] ?: @[group])[fresh addObject:record];
            // 选中文档按来源范围替换旧机器结果，不能只追加新 ID；草稿和已保存任务另行保留。
            NSMutableArray *oldSelected=NSMutableArray.array;for(NSString *identifier in byID.allKeys)if([self recognitionRecord:byID[identifier] touchesPaths:paths depth:0]){[oldSelected addObject:byID[identifier]];[byID removeObjectForKey:identifier];}
            NSArray *reconciled=SSReconcileDiscoveryIDs(oldSelected,fresh);for(NSDictionary *record in reconciled)if([paths containsObject:record[@"path"]] || !byID[record[@"id"]])byID[record[@"id"]]=record;
            NSMutableArray *assignments=NSMutableArray.array,*other=NSMutableArray.array;for(NSDictionary *record in byID.allValues)if([record[@"kind"] isEqual:@"assignment"])[assignments addObject:record];else[other addObject:record];
            candidates[course[@"fork"]]=SSConsolidateAssignments(assignments);materials[course[@"fork"]]=SSGroupMaterials(other);
            NSError *saveError=nil;if(!SSWritePlist(@"discoveries.plist",[self discoveryEnvelope:candidates materials:materials progress:self.skillProgress batches:self.skillBatches],&saveError)){[self showError:saveError];return;}self.candidates=candidates;self.materials=materials;SSWritePlist(@"recognition-last-result.plist",@{@"course":course[@"fork"],@"date":NSDate.date,@"model":settings[@"model"],@"success":enhanced[@"modelCompleted"] ?: @NO},NULL);
            NSMutableDictionary *reports=self.reports.mutableCopy ?: NSMutableDictionary.dictionary;reports[course[@"fork"]]=enhanced;self.reports=reports;[self updateCheckSummaryForCourse:course];[self status:self.statuses[course[@"fork"]]];[self postRecognitionSummary]; }];
    }];
}
