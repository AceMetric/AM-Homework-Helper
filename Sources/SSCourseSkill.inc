- (NSDictionary *)discoveryEnvelope:(NSDictionary *)candidates materials:(NSDictionary *)materials progress:(NSDictionary *)progress batches:(NSDictionary *)batches {
    return @{@"candidates":candidates,@"materials":materials,@"skillProgress":progress,@"skillBatches":batches};
}
- (NSDictionary *)discoveryEnvelope {return [self discoveryEnvelope:self.candidates materials:self.materials progress:self.skillProgress batches:self.skillBatches];}
- (NSArray *)chooseSkillCourses:(BOOL *)all {
    NSAlert *alert=NSAlert.new;alert.messageText=@"交给助手识别";alert.informativeText=@"勾选课程，一次导出老师材料。导出的原文只留本机；交给云端助手时会由该服务处理。不包含个人任务、答案或凭据。";
    NSStackView *rows=NSStackView.new;rows.orientation=NSUserInterfaceLayoutOrientationVertical;rows.alignment=NSLayoutAttributeLeading;rows.spacing=8;
    NSMutableArray *checks=NSMutableArray.array;
    for(NSDictionary *course in self.courses){NSButton *check=[NSButton checkboxWithTitle:[course[@"fork"] lastPathComponent] target:nil action:nil];check.identifier=course[@"fork"];check.enabled=[course[@"path"] length]>0;check.state=check.enabled && ![course[@"enabled"] isEqual:@NO] ? NSControlStateValueOn:NSControlStateValueOff;check.toolTip=check.enabled ? course[@"fork"] : @"先关联本地文件夹";[rows addArrangedSubview:check];[checks addObject:check];}
    NSButton *full=[NSButton checkboxWithTitle:@"导出全部材料（默认只导出新增或变化）" target:nil action:nil];[rows addArrangedSubview:full];
    rows.frame=NSMakeRect(0,0,460,MAX(100,rows.arrangedSubviews.count*32));NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,480,MIN(260,NSHeight(rows.frame)))];scroll.hasVerticalScroller=YES;scroll.documentView=rows;alert.accessoryView=scroll;
    [alert addButtonWithTitle:@"检查并导出"];[alert addButtonWithTitle:@"取消"];if([alert runModal]!=NSAlertFirstButtonReturn)return nil;
    NSMutableArray *selected=NSMutableArray.array;for(NSButton *check in checks)if(check.enabled && check.state==NSControlStateValueOn)for(NSDictionary *course in self.courses)if([course[@"fork"] isEqual:check.identifier])[selected addObject:course.copy];
    *all=full.state==NSControlStateValueOn;return selected;
}
- (NSDictionary *)readSkillCourses:(NSArray *)courses {
    self.git.recognitionSettings=@{@"mode":@"rules"};NSMutableDictionary *scans=NSMutableDictionary.dictionary;
    for(NSDictionary *course in courses){if(![course[@"path"] length])continue;NSError *failure=nil;NSDictionary *scan=[self.git scanCourse:course cache:NSMutableDictionary.dictionary error:&failure];scans[course[@"fork"]]=scan ?: @{@"error":failure.localizedDescription ?: @"无法读取老师内容"};}
    return scans;
}
- (void)exportSkillContext:(id)sender {
    if(self.preview || self.busy || self.operationsPaused)return;BOOL all=NO;NSArray *courses=[self chooseSkillCourses:&all];if(!courses)return;if(!courses.count){[self status:@"请选择至少一门已关联文件夹的课程。"];return;}
    NSDictionary *progress=self.skillProgress.copy;
    [self work:@"正在读取所选课程的老师材料…" forCourse:nil operation:^id(NSError **error){NSDictionary *scans=[self readSkillCourses:courses];NSMutableDictionary *exported=[SSSkillExport(courses,scans,progress,all) mutableCopy];exported[@"scans"]=scans;return exported;} completion:^(NSDictionary *exported,NSError *error){
        if(!exported){[self showError:error];return;}NSMutableArray *issues=NSMutableArray.array;for(NSDictionary *course in courses)if(exported[@"scans"][course[@"fork"]][@"error"])[issues addObject:[NSString stringWithFormat:@"%@：%@",course[@"fork"],exported[@"scans"][course[@"fork"]][@"error"]]];
        if(![exported[@"context"][@"documents"] count]){[self status:issues.count ? [issues componentsJoinedByString:@"；"] : @"没有尚未识别的新增或变化材料，可选择导出全部。"];return;}
        if(issues.count){NSAlert *warning=NSAlert.new;warning.messageText=@"部分课程无法读取";warning.informativeText=[issues componentsJoinedByString:@"\n"];[warning addButtonWithTitle:@"导出其余课程"];[warning addButtonWithTitle:@"取消"];if([warning runModal]!=NSAlertFirstButtonReturn)return;}
        NSOpenPanel *panel=NSOpenPanel.openPanel;panel.canChooseFiles=NO;panel.canChooseDirectories=YES;panel.canCreateDirectories=YES;panel.title=@"选择材料包保存位置（仅留本机）";
        [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse answer){if(answer!=NSModalResponseOK)return;NSError *failure=nil;NSString *batch=exported[@"context"][@"batchID"];NSURL *folder=[panel.URL URLByAppendingPathComponent:[@"AM-assistant-" stringByAppendingString:batch] isDirectory:YES];
            NSString *skill=[NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"am-homework-extract" ofType:@"md"] encoding:NSUTF8StringEncoding error:&failure];
            BOOL ok=skill && [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:NO attributes:nil error:&failure];
            NSData *json=[NSJSONSerialization dataWithJSONObject:exported[@"context"] options:NSJSONWritingPrettyPrinted error:&failure];if(ok)ok=[json writeToURL:[folder URLByAppendingPathComponent:@"materials.local.json"] options:NSDataWritingAtomic error:&failure];if(ok)ok=[skill writeToURL:[folder URLByAppendingPathComponent:@"SKILL.md"] atomically:YES encoding:NSUTF8StringEncoding error:&failure];
            NSString *instructions=@"请按同目录 SKILL.md 分析 materials.local.json 中所有课程的材料，保留 batchID、courseID 和文件来源，生成 results.local.json。然后在 AM Helper 的“导入助手结果…”中一次导入审核。课程原文不要上传到公开仓库。\n";
            if(ok)ok=[instructions writeToURL:[folder URLByAppendingPathComponent:@"使用说明.txt"] atomically:YES encoding:NSUTF8StringEncoding error:&failure];
            NSMutableDictionary *batches=self.skillBatches.mutableCopy;batches[batch]=exported[@"manifest"];if(ok)ok=SSWritePlist(@"discoveries.plist",[self discoveryEnvelope:self.candidates materials:self.materials progress:self.skillProgress batches:batches],&failure);
            if(!ok){[self showError:failure];return;}self.skillBatches=batches;
            NSString *prompt=[NSString stringWithFormat:@"读取 %@ 中的 SKILL.md 和 materials.local.json，分析所有课程，生成同目录 results.local.json。仅生成提取建议，不修改应用任务库或执行课程 Git 操作。",folder.path];
            NSAlert *ready=NSAlert.new;ready.messageText=@"材料包已准备好";ready.informativeText=[NSString stringWithFormat:@"共 %lu 份老师文档。复制指令交给助手，再一次导入结果；尚未导入的材料下次仍会保留。",(unsigned long)[exported[@"context"][@"documents"] count]];[ready addButtonWithTitle:@"复制指令并显示材料包"];[ready addButtonWithTitle:@"完成"];if([ready runModal]==NSAlertFirstButtonReturn){[NSPasteboard.generalPasteboard clearContents];[NSPasteboard.generalPasteboard setString:prompt forType:NSPasteboardTypeString];[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[folder]];}[self status:@"多课程材料包已导出，等待助手识别后统一导入。"]; }];
    }];
}
- (void)importSkillResults:(id)sender {
    if(self.preview || self.busy || self.operationsPaused)return;if(self.hasUnsavedReview && ![self resolveUnsavedReview])return;
    NSOpenPanel *panel=NSOpenPanel.openPanel;panel.title=@"导入助手结果（自动分配课程）";panel.canChooseDirectories=NO;panel.allowsMultipleSelection=NO;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse answer){if(answer!=NSModalResponseOK)return;NSNumber *size=nil;[panel.URL getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];if(!size || size.unsignedIntegerValue>8*1024*1024){[self status:@"无法读取文件，或文件超过8 MB。"];return;}
        NSData *data=[NSData dataWithContentsOfURL:panel.URL];id result=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        if(![result isKindOfClass:NSDictionary.class]){[self status:@"请选择助手生成的结果 JSON。"];return;}
        NSString *legacy=nil;if([result[@"format"] isEqual:@"am-course-results-v1"]){NSMutableArray *matches=NSMutableArray.array;for(NSDictionary *course in self.courses){BOOL compatible=YES;for(id doc in [result[@"documents"] isKindOfClass:NSArray.class] ? result[@"documents"] : @[])if(![doc isKindOfClass:NSDictionary.class] || ![doc[@"repository"] isEqual:course[@"upstream"]])compatible=NO;if(compatible && [course[@"path"] length])[matches addObject:course[@"fork"]];}
            if(matches.count==1)legacy=matches.firstObject;else if(matches.count>1){NSAlert *pick=NSAlert.new;pick.messageText=@"选择旧版结果所属课程";NSPopUpButton *menu=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0,0,340,32)];[menu addItemsWithTitles:matches];pick.accessoryView=menu;[pick addButtonWithTitle:@"核验"];[pick addButtonWithTitle:@"取消"];if([pick runModal]!=NSAlertFirstButtonReturn)return;legacy=menu.titleOfSelectedItem;}}
        NSArray *courses=[[NSArray alloc] initWithArray:self.courses copyItems:YES];NSDictionary *batches=self.skillBatches.copy;
        [self work:@"正在核验多课程结果与老师原文…" forCourse:nil operation:^id(NSError **error){return SSSkillValidateBatch(result,courses,[self readSkillCourses:courses],batches,legacy,error);} completion:^(NSDictionary *validated,NSError *error){if(!validated){[self showError:error];return;}
            NSAlert *preview=NSAlert.new;preview.messageText=@"确认导入助手识别建议";NSMutableArray *lines=NSMutableArray.array;for(NSString *fork in [validated[@"counts"] allKeys])[lines addObject:[NSString stringWithFormat:@"%@：%lu 份文档，%lu 项建议",fork,(unsigned long)[validated[@"counts"][fork] unsignedIntegerValue],(unsigned long)[validated[@"records"][fork] count]]];[lines addObjectsFromArray:validated[@"issues"]];preview.informativeText=lines.count ? [lines componentsJoinedByString:@"\n"] : @"结果未包含可导入文档。";[preview addButtonWithTitle:@"导入有效结果"];[preview addButtonWithTitle:@"取消"];if([preview runModal]!=NSAlertFirstButtonReturn || ![validated[@"progress"] count])return;
            NSMutableDictionary *candidates=self.candidates.mutableCopy,*materials=self.materials.mutableCopy,*progress=self.skillProgress.mutableCopy;[progress addEntriesFromDictionary:validated[@"progress"]];
            for(NSString *fork in validated[@"records"]){NSMutableDictionary *byID=NSMutableDictionary.dictionary;for(NSDictionary *record in [(candidates[fork] ?: @[]) arrayByAddingObjectsFromArray:materials[fork] ?: @[]])byID[record[@"id"]]=record;for(NSDictionary *record in validated[@"records"][fork])byID[record[@"id"]]=record;NSMutableArray *assignments=NSMutableArray.array,*other=NSMutableArray.array;for(NSDictionary *record in byID.allValues){if([record[@"kind"] isEqual:@"assignment"])[assignments addObject:record];else[other addObject:record];}candidates[fork]=SSConsolidateAssignments(assignments);materials[fork]=SSGroupMaterials(other);}
            NSError *failure=nil;if(!SSWritePlist(@"discoveries.plist",[self discoveryEnvelope:candidates materials:materials progress:progress batches:self.skillBatches],&failure)){[self showError:failure];return;}
            self.candidates=candidates;self.materials=materials;self.skillProgress=progress;for(NSString *fork in validated[@"counts"])self.statuses[fork]=@"助手结果已核验，作业建议进入待审核清单。";[self status:@"已导入有效结果并更新增量进度；未直接加入任务。"]; }];
    }];
}
