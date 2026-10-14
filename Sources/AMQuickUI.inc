// Local capture shares task persistence and the course review surface, but never invokes Git.
- (void)loadQuick {
    if(self.quickState)return;
    id stored=self.preview ? nil:SSReadPlist(@"quick-entry.plist");
    self.quickState=[stored isKindOfClass:NSDictionary.class] ? [stored mutableCopy]:[@{@"text":@"",@"entries":@[],@"jobs":@{},@"referenceDate":NSDate.date,@"explicitReference":@NO} mutableCopy];
    if(stored && (![stored isKindOfClass:NSDictionary.class] || ![stored[@"text"] isKindOfClass:NSString.class] || ![stored[@"referenceDate"] isKindOfClass:NSDate.class] || ![stored[@"entries"] isKindOfClass:NSArray.class] || ![stored[@"jobs"] isKindOfClass:NSDictionary.class])){self.quickState=nil;self.notice=@"录入草稿无法读取，原文件已保留。";return;}
    if((self.quickState[@"materials"] && ![self.quickState[@"materials"] isKindOfClass:NSDictionary.class]) || (self.quickState[@"material"] && ![self.quickState[@"material"] isKindOfClass:NSDictionary.class])){self.quickState=nil;self.notice=@"材料草稿无法读取，原文件已保留。";return;}
    for(NSString *key in self.quickState[@"jobs"]){NSDictionary *job=self.quickState[@"jobs"][key];if(![[NSUUID alloc] initWithUUIDString:key] || ![job isKindOfClass:NSDictionary.class] || ![job[@"id"] isEqual:key] || ![job[@"date"] isKindOfClass:NSDate.class] || ![job[@"version"] isKindOfClass:NSString.class] || ![job[@"sourceID"] isKindOfClass:NSString.class]){self.quickState=nil;self.notice=@"识别批次记录无法读取，原文件已保留。";return;}}
    for(id entry in self.quickState[@"entries"]){BOOL valid=[entry isKindOfClass:NSDictionary.class];if(valid)for(NSString *key in @[@"id",@"sourceID",@"version",@"evidence",@"title",@"dateText",@"notes",@"timeZone"])if(![entry[key] isKindOfClass:NSString.class])valid=NO;if(!valid){self.quickState=nil;self.notice=@"录入草稿含异常条目，已保留原文件。";return;}}
    if(!self.preview)[self cleanQuickJobs:NO];
    if(!self.preview && !self.quickTimer){__weak typeof(self) owner=self;self.quickTimer=[NSTimer scheduledTimerWithTimeInterval:3 repeats:YES block:^(NSTimer *t){[owner pollQuickResults];}];}
}
- (BOOL)persistQuick:(NSError **)error {
    return self.preview || (self.quickState && SSWritePlist(@"quick-entry.plist",self.quickState,error));
}
- (NSArray *)quickPendingEntries {
    [self loadQuick];NSMutableArray *result=NSMutableArray.array;
    for(NSDictionary *entry in self.quickState[@"entries"]){BOOL saved=NO;for(NSDictionary *task in [self snapshot])if([task[@"entryID"] isEqual:entry[@"id"]] || ([task[@"entrySourceID"] isEqual:entry[@"sourceID"]] && [task[@"entryEvidence"] isEqual:entry[@"evidence"]])){saved=YES;break;}if(!saved)[result addObject:entry];}return result;
}
- (NSArray *)quickReviewRecords {
    NSMutableArray *rows=NSMutableArray.array;for(NSDictionary *entry in [self quickPendingEntries]){NSMutableDictionary *row=entry.mutableCopy;row[@"sourceType"]=@"local";row[@"blobSHA"]=entry[@"version"];row[@"kind"]=@"assignment";row[@"snippet"]=entry[@"evidence"] ?: @"";row[@"repository"]=@"本机录入";row[@"path"]=@"通知／截图";row[@"line"]=@1;NSError *error=nil;NSDictionary *task=AMQuickTask(entry,&error);row[@"needsDate"]=@(task==nil);row[@"needsTime"]=@(task==nil);if([entry[@"dateText"] length]==10)row[@"dateOnly"]=entry[@"dateText"];if(task)row[@"due"]=task[@"due"];[rows addObject:row];}return rows;
}
- (void)refreshQuick:(NSString *)notice {
    if(self.quickState)self.quickState[@"entries"]=[self quickPendingEntries];
    self.quickUpdating=YES;[self.quickController updateDraft:self.quickState courses:self.courseWindow.courseSnapshots notice:notice ?: @"草稿仅保存在本机。" busy:self.quickBusy];self.quickUpdating=NO;
    [self.courseWindow refreshPresentation];[self renderSidebar];
}
- (void)quickEntry:(id)sender {
    if(self.quickWindow){[self.quickWindow makeKeyAndOrderFront:nil];return;}if(self.window.attachedSheet)return;
    [self loadQuick];if(!self.quickState){[self render];return;}
    self.quickController=AMQuickEntryController.new;__weak typeof(self) owner=self;
    self.quickController.actionHandler=^(NSString *action,NSDictionary *payload){[owner quickAction:action payload:payload];};
    self.quickWindow=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,1000,760) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];self.quickWindow.title=@"快速录入作业";self.quickWindow.contentMinSize=NSMakeSize(650,640);self.quickWindow.delegate=self;self.quickWindow.releasedWhenClosed=NO;self.quickWindow.contentViewController=self.quickController;[self.quickWindow setContentSize:NSMakeSize(1000,760)];
    [self refreshQuick:nil];[self.window beginSheet:self.quickWindow completionHandler:nil];
}
- (void)closeQuick {
    [self.quickPersistTimer invalidate];self.quickPersistTimer=nil;
    if(self.quickWindow.sheetParent)[self.window endSheet:self.quickWindow];[self.quickWindow orderOut:nil];self.quickWindow=nil;self.quickController=nil;
}
- (void)newTaskMenu:(id)sender {NSMenu *menu=NSMenu.new;NSMenuItem *item=[menu addItemWithTitle:@"快速录入作业…" action:@selector(quickEntry:) keyEquivalent:@""];item.target=self;item=[menu addItemWithTitle:@"完整新建任务…" action:@selector(addTask:) keyEquivalent:@""];item.target=self;[menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0,-4) inView:sender];}
- (void)taskSubmissionHistory:(id)sender {NSButton *route=NSButton.new;route.tag=4;[self navigate:route];[self.courseWindow showSubmissionHistory:[self identifierForSender:sender]];}
- (void)submitSelectedTask:(id)sender {NSButton *route=NSButton.new;route.tag=4;[self navigate:route];[self.courseWindow submitTask:[self identifierForSender:sender]];}
- (void)checkSelectedTask:(id)sender {
    // Keep the task and its inspector visible; local review does not navigate or edit a course.
    NSString *identifier=[[self identifierForSender:sender] copy];
    [self.courseWindow checkTask:identifier];
}
- (NSURL *)quickFolder:(NSString *)batch {
    if(![[NSUUID alloc] initWithUUIDString:batch])return nil;NSURL *folder=[[SSDataDirectory().URLByResolvingSymlinksInPath URLByAppendingPathComponent:@"AssistantExchange"] URLByAppendingPathComponent:batch];return [folder.path isEqual:folder.URLByResolvingSymlinksInPath.path] ? folder:nil;
}
- (void)parseQuick {
    NSString *text=self.quickState[@"text"] ?: @"";if(!text.length || text.length>100000){[self refreshQuick:@"请输入最多10万字的通知内容。" ];return;}
    NSDictionary *material=self.quickState[@"material"];if(![material[@"text"] isEqual:text]){NSDictionary *old=material;material=AMQuickMaterial(text,[self.quickState[@"explicitReference"] boolValue] ? self.quickState[@"referenceDate"]:(old[@"referenceDate"] ?: NSDate.date),NSTimeZone.localTimeZone.name);BOOL saved=NO;for(NSDictionary *task in [self snapshot])if([task[@"entrySourceID"] isEqual:old[@"id"]])saved=YES;if(old && !saved){NSMutableDictionary *same=material.mutableCopy;same[@"id"]=old[@"id"];material=same;}}
    if([self.quickState[@"explicitReference"] boolValue] && ![material[@"referenceDate"] isEqual:self.quickState[@"referenceDate"]]){NSMutableDictionary *revised=[AMQuickMaterial(text,self.quickState[@"referenceDate"],material[@"timeZone"]) mutableCopy];revised[@"id"]=material[@"id"];material=revised;}
    BOOL consumed=NO,pending=NO;for(NSDictionary *task in [self snapshot])if([task[@"entrySourceID"] isEqual:material[@"id"]])consumed=YES;
    for(NSDictionary *entry in [self quickPendingEntries])if([entry[@"sourceID"] isEqual:material[@"id"]])pending=YES;
    // A deliberate new capture of already saved text gets its own identity and duplicate preview.
    if(consumed && !pending)material=AMQuickMaterial(text,material[@"referenceDate"],material[@"timeZone"]);
    NSCalendar *cal=[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];cal.timeZone=[NSTimeZone timeZoneWithName:material[@"timeZone"]];
    NSMutableArray *entries=AMQuickParse(text,material[@"id"],material[@"referenceDate"],cal).mutableCopy;
    for(NSMutableDictionary *entry in entries)entry[@"version"]=material[@"version"];
    for(NSUInteger i=0;i<entries.count;i++)for(NSDictionary *old in self.quickState[@"entries"])if([old[@"id"] isEqual:entries[i][@"id"]]){NSMutableDictionary *retained=[entries[i] mutableCopy];for(NSString *field in old[@"editedFields"] ?: ([old[@"edited"] boolValue] ? @[@"title",@"subject",@"notes",@"dateText",@"reminderOffsets"]:@[]))if(old[field])retained[field]=old[field];retained[@"edited"]=old[@"edited"] ?: @NO;retained[@"editedFields"]=old[@"editedFields"] ?: @[];retained[@"selected"]=old[@"selected"] ?: @YES;entries[i]=retained;}
    for(NSDictionary *old in self.quickState[@"entries"])if([old[@"sourceID"] isEqual:material[@"id"]] && [old[@"edited"] boolValue]){BOOL found=NO;for(NSDictionary *entry in entries)if([entry[@"id"] isEqual:old[@"id"]])found=YES;if(!found)[entries addObject:old];}
    for(NSDictionary *old in self.quickState[@"entries"])if(![old[@"sourceID"] isEqual:material[@"id"]])[entries addObject:old];
    NSMutableDictionary *materials=[self.quickState[@"materials"] mutableCopy] ?: NSMutableDictionary.dictionary;materials[material[@"id"]]=material;self.quickState[@"materials"]=materials;
    self.quickState[@"referenceDate"]=material[@"referenceDate"];self.quickState[@"material"]=material;self.quickState[@"entries"]=entries;NSError *error=nil;BOOL saved=[self persistQuick:&error];[self refreshQuick:saved ? [NSString stringWithFormat:@"识别 %lu 项；缺日期或时间的内容保留为草稿。",(unsigned long)entries.count]:@"草稿保存失败，输入保留，请重试。"];
}
- (void)quickOCR:(NSImage *)image {
    if(!image)return;NSString *operation=AMOperationBegin(@"截图识别",@"快速录入",NO,nil);NSString *before=[self.quickState[@"text"] copy];self.quickBusy=YES;[self refreshQuick:@"正在本机识别截图文字…"];__weak typeof(self) owner=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;NSDictionary *ocr=DDLOCRResultFromImage(image,&error);NSString *text=ocr[@"text"];dispatch_async(dispatch_get_main_queue(),^{AMOperationFinish(operation,text.length ? @"success":@"failed",text.length ? @"截图识别完成，请核对日期和数字":@"未识别出文字");owner.quickBusy=NO;if(![owner.quickState[@"text"] isEqual:before]){[owner refreshQuick:@"识别期间输入已修改，未覆盖。请重新选择截图。" ];return;}if(!text.length){[owner refreshQuick:@"截图未识别出文字，请换一张更清晰的截图或直接粘贴。" ];return;}owner.quickState[@"text"]=text;NSMutableArray *warnings=NSMutableArray.array;for(NSDictionary *item in ocr[@"uncertain"])[warnings addObject:[NSString stringWithFormat:@"第 %@ 行：%@",item[@"line"],item[@"text"]]];[owner.quickController setOCRPreview:image warnings:warnings.count ? [@"请对照原图核对数字或日期：\n" stringByAppendingString:[warnings componentsJoinedByString:@"\n"]]:@"请对照原图核对日期、数字和符号；OCR 不能保证全部识别正确。"];[owner refreshQuick:nil];[owner parseQuick];});});
}
- (void)prepareQuickSkill {
    [self parseQuick];NSDictionary *material=self.quickState[@"material"];if(!material || ![material[@"text"] isEqual:self.quickState[@"text"]])return;
    NSAlert *alert=NSAlert.new;alert.messageText=@"交给助手识别";alert.informativeText=@"仅导出以下文字，不包含截图元数据、任务库、账户或课程仓库。复制指令后由你交给助手。";NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,520,200)];NSTextView *text=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,500,200)];text.string=material[@"text"];text.editable=NO;scroll.documentView=text;scroll.hasVerticalScroller=YES;alert.accessoryView=scroll;[alert addButtonWithTitle:@"准备并复制指令"];[alert addButtonWithTitle:@"取消"];if([alert runModal]!=NSAlertFirstButtonReturn)return;
    for(NSDictionary *job in [self.quickState[@"jobs"] allValues])if([job[@"sourceID"] isEqual:material[@"id"]] && [job[@"version"] isEqual:material[@"version"]] && ![job[@"received"] boolValue] && [NSFileManager.defaultManager fileExistsAtPath:[self quickFolder:job[@"id"]].path]){[self quickJobAction:@"copy" batch:job[@"id"]];[self refreshQuick:@"相同材料已经在等待助手，已复制原批次指令。" ];return;}
    NSString *batch=NSUUID.UUID.UUIDString;NSURL *folder=[self quickFolder:batch];NSError *error=nil;
    NSDictionary *doc=@{@"sourceID":material[@"id"],@"version":material[@"version"],@"text":material[@"text"],@"timeZone":material[@"timeZone"],@"referenceDate":[NSISO8601DateFormatter.new stringFromDate:material[@"referenceDate"]]};
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"format":@"am-local-context-v1",@"batchID":batch,@"documents":@[doc]} options:0 error:&error];
    NSString *skill=[NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"am-homework-extract" ofType:@"md"] encoding:NSUTF8StringEncoding error:&error];
    BOOL ok=folder && data && skill && [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error];
    if(ok)ok=[data writeToURL:[folder URLByAppendingPathComponent:@"materials.local.json"] options:NSDataWritingAtomic error:&error] && [skill writeToURL:[folder URLByAppendingPathComponent:@"SKILL.md"] atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if(!ok){[self refreshQuick:@"材料包创建失败，请检查本机存储后重试。" ];return;}
    for(NSString *name in @[@"materials.local.json",@"SKILL.md"])[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:[folder URLByAppendingPathComponent:name].path error:NULL];
    NSMutableDictionary *jobs=[self.quickState[@"jobs"] mutableCopy];jobs[batch]=@{@"id":batch,@"version":material[@"version"],@"sourceID":material[@"id"],@"state":@"等待助手",@"message":@"结果返回后自动接回待审核。",@"date":NSDate.date,@"count":@1,@"courses":@[@"本机通知"]};self.quickState[@"jobs"]=jobs;
    if(![self persistQuick:&error]){[self refreshQuick:@"批次记录未保存，请重试。" ];return;}
    NSString *instruction=[NSString stringWithFormat:@"请按 %@/SKILL.md 分析同目录 materials.local.json，仅处理该材料包，将完整结果先写 results.local.json.tmp，再原子改名为 results.local.json。不要读取其他资料或执行 Git 操作。",folder.path];[NSPasteboard.generalPasteboard clearContents];[NSPasteboard.generalPasteboard setString:instruction forType:NSPasteboardTypeString];[self refreshQuick:@"指令已复制，交给助手后无需手动导入。可继续编辑，结果不会覆盖你的修改。"];
}
- (void)receiveQuickResult:(NSDictionary *)result batch:(NSDictionary *)batch {
    NSMutableDictionary *previous=self.quickState;self.quickState=previous.mutableCopy;
    NSError *error=nil;NSDictionary *material=self.quickState[@"materials"][batch[@"sourceID"]] ?: self.quickState[@"material"];
    BOOL unchanged=![batch[@"sourceID"] isEqual:self.quickState[@"material"][@"id"]] || ([self.quickState[@"text"] isEqual:material[@"text"]] && (![self.quickState[@"explicitReference"] boolValue] || [self.quickState[@"referenceDate"] isEqual:material[@"referenceDate"]]));
    NSDictionary *validated=unchanged ? AMQuickValidateResult(result,material,batch,&error):nil;NSMutableDictionary *jobs=[self.quickState[@"jobs"] mutableCopy],*job=[batch mutableCopy];
    if(!validated){job[@"state"]=@"需处理";job[@"message"]=error.localizedDescription ?: @"材料已变化，请重新交给助手。";}
    else {NSMutableArray *entries=[self.quickState[@"entries"] mutableCopy];for(NSDictionary *new in validated[@"entries"]){NSUInteger existing=[entries indexOfObjectPassingTest:^BOOL(NSDictionary *old,NSUInteger i,BOOL *stop){return [old[@"id"] isEqual:new[@"id"]] || ([old[@"sourceID"] isEqual:new[@"sourceID"]] && ([old[@"evidence"] containsString:new[@"evidence"]] || [new[@"evidence"] containsString:old[@"evidence"]]));}];BOOL saved=NO;for(NSDictionary *task in [self snapshot])if([task[@"entrySourceID"] isEqual:new[@"sourceID"]] && ([task[@"entryEvidence"] containsString:new[@"evidence"]] || [new[@"evidence"] containsString:task[@"entryEvidence"]]))saved=YES;if(saved)continue;if(existing==NSNotFound)[entries addObject:new];else if(![entries[existing][@"edited"] boolValue]){NSMutableDictionary *replacement=new.mutableCopy;replacement[@"id"]=entries[existing][@"id"];entries[existing]=replacement;}}
        self.quickState[@"entries"]=entries;job[@"state"]=[validated[@"issues"] count] ? @"部分接回":@"已接回";job[@"message"]=[validated[@"issues"] count] ? [validated[@"issues"] componentsJoinedByString:@"；"]:@"建议已进入待审核作业。";
    }
    job[@"received"]=@YES;jobs[batch[@"id"]]=job;NSMutableDictionary *old=self.quickState;self.quickState=old.mutableCopy;self.quickState[@"jobs"]=jobs;
    self.quickUpdating=YES;BOOL ok=[self persistQuick:&error];self.quickUpdating=NO;if(!ok)self.quickState=previous;[self refreshQuick:ok ? job[@"message"]:@"结果保存失败，保留原草稿，稍后重试。"];
}
- (void)pollQuickResults {
    if(self.quickBusy || self.preview || !self.quickState )return;
    for(NSDictionary *job in [self.quickState[@"jobs"] allValues]){if([job[@"received"] boolValue])continue;NSURL *url=[[self quickFolder:job[@"id"]] URLByAppendingPathComponent:@"results.local.json"];if(!url || ![NSFileManager.defaultManager fileExistsAtPath:url.path])continue;NSError *error=nil;NSDictionary *result=SSSkillReadResult(url,&error);if(result)[self receiveQuickResult:result batch:job];else{NSMutableDictionary *jobs=[self.quickState[@"jobs"] mutableCopy],*failed=job.mutableCopy;failed[@"state"]=@"需处理";failed[@"message"]=@"结果文件格式无效，请让助手修正后重试接回。";failed[@"received"]=@YES;jobs[job[@"id"]]=failed;self.quickState[@"jobs"]=jobs;[self persistQuick:NULL];[self refreshQuick:failed[@"message"]];}}
}
- (void)saveQuick {
    NSMutableArray *valid=NSMutableArray.array,*issues=NSMutableArray.array;NSUInteger duplicates=0;
    for(NSDictionary *entry in [self quickPendingEntries])if([entry[@"selected"] boolValue]){NSError *error=nil;NSDictionary *task=AMQuickTask(entry,&error);if(!task){[issues addObject:[NSString stringWithFormat:@"%@：%@",entry[@"title"],error.localizedDescription]];continue;}for(NSDictionary *old in [self snapshot])if([old[@"title"] isEqual:task[@"title"]] && [old[@"due"] isEqual:task[@"due"]]){duplicates++;break;}[valid addObject:task];}
    if(!valid.count){[self refreshQuick:issues.count ? [issues componentsJoinedByString:@"\n"]:@"没有可保存的选中作业。" ];return;}
    NSInteger answer=NSAlertFirstButtonReturn;if(issues.count || duplicates){NSAlert *alert=NSAlert.new;alert.messageText=[NSString stringWithFormat:@"确认加入 %lu 项作业？",(unsigned long)valid.count];alert.informativeText=[NSString stringWithFormat:@"%@\n%lu 项需补全，保留草稿。%lu 项可能重复。",[[valid valueForKey:@"title"] componentsJoinedByString:@"、"],(unsigned long)issues.count,(unsigned long)duplicates];[alert addButtonWithTitle:duplicates ? @"跳过重复并保存":@"确认保存"];[alert addButtonWithTitle:@"取消"];if(duplicates)[alert addButtonWithTitle:@"仍然全部添加"];answer=[alert runModal];if(answer==NSAlertSecondButtonReturn)return;}
    NSMutableArray *next=[[self snapshot] mutableCopy];NSMutableSet *saved=NSMutableSet.set;for(NSDictionary *task in valid){BOOL duplicate=NO;for(NSDictionary *old in [self snapshot])if([old[@"title"] isEqual:task[@"title"]] && [old[@"due"] isEqual:task[@"due"]])duplicate=YES;if(duplicate && answer==NSAlertFirstButtonReturn)continue;[next addObject:task];[saved addObject:task[@"entryID"]];}
    NSError *error=nil;if(![self replaceTasks:next action:@"快速录入" error:&error]){[self refreshQuick:@"整批未能保存，草稿和选择已保留，请重试。" ];return;}
    NSMutableArray *remaining=NSMutableArray.array;for(NSDictionary *entry in self.quickState[@"entries"])if(![saved containsObject:entry[@"id"]])[remaining addObject:entry];self.quickState[@"entries"]=remaining;self.quickUpdating=YES;[self persistQuick:NULL];self.quickUpdating=NO;[self refreshQuick:[NSString stringWithFormat:@"已保存 %lu 项；未完成的条目仍为草稿。",(unsigned long)saved.count]];[self render];
}
- (void)quickAction:(NSString *)action payload:(NSDictionary *)payload {
    if(self.quickUpdating || !self.quickState)return;[self.quickState addEntriesFromDictionary:payload];
    if([action isEqual:@"draft"]){[self.quickPersistTimer invalidate];__weak typeof(self) owner=self;self.quickPersistTimer=[NSTimer scheduledTimerWithTimeInterval:.4 repeats:NO block:^(NSTimer *timer){NSError *error=nil;if(![owner persistQuick:&error])[owner.quickController setNotice:@"草稿保存失败，请重试。" busy:owner.quickBusy];else [owner pollQuickResults];}];return;}
    NSError *error=nil;if(![self persistQuick:&error]){[self.quickController setNotice:@"草稿未保存，操作已暂停，请检查本机存储。" busy:NO];return;}
    if([action isEqual:@"close"]){[self closeQuick];return;}
    if([action isEqual:@"source-changed"]){[self parseQuick];return;}
    if([action isEqual:@"parse"])[self parseQuick];else if([action isEqual:@"save"])[self saveQuick];else if([action isEqual:@"skill"])[self prepareQuickSkill];
    else if([action isEqual:@"paste"]){NSString *text=[NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];if(text.length){self.quickState[@"text"]=text;[self refreshQuick:nil];[self parseQuick];}else [self quickOCR:[[NSImage alloc] initWithPasteboard:NSPasteboard.generalPasteboard]];}
    else if([action isEqual:@"image"]){NSOpenPanel *panel=NSOpenPanel.openPanel;panel.allowedContentTypes=@[UTTypeImage];panel.allowsMultipleSelection=NO;if([panel runModal]==NSModalResponseOK)[self quickOCR:[[NSImage alloc] initWithContentsOfURL:panel.URL]];}
    else if([action isEqual:@"import"]){NSOpenPanel *panel=NSOpenPanel.openPanel;panel.allowedContentTypes=@[UTTypeJSON];if([panel runModal]!=NSModalResponseOK)return;NSDictionary *result=SSSkillReadResult(panel.URL,&error);NSDictionary *job=self.quickState[@"jobs"][result[@"batchID"] ?: @""];if(result && job)[self receiveQuickResult:result batch:job];else [self refreshQuick:@"结果不属于本机待处理批次，请重新交给助手。" ];}
}

- (void)cleanQuickJobs:(BOOL)all {
    NSMutableDictionary *jobs=[self.quickState[@"jobs"] mutableCopy];BOOL changed=NO;NSDate *cutoff=[NSDate dateWithTimeIntervalSinceNow:-30*86400];
    for(NSString *batch in jobs.allKeys){NSDictionary *old=jobs[batch];if(![old[@"state"] isEqual:@"已接回"] || [old[@"cleaned"] boolValue] || (!all && [old[@"date"] compare:cutoff]!=NSOrderedAscending))continue;
        NSURL *folder=[self quickFolder:batch];if(folder && (![NSFileManager.defaultManager fileExistsAtPath:folder.path] || [NSFileManager.defaultManager removeItemAtURL:folder error:NULL])){NSMutableDictionary *copy=old.mutableCopy;copy[@"cleaned"]=@YES;jobs[batch]=copy;changed=YES;}}
    if(changed){self.quickState[@"jobs"]=jobs;[self persistQuick:NULL];}
}
- (BOOL)quickJobAction:(NSString *)action batch:(NSString *)batch {
    if([action isEqual:@"clean"]){[self cleanQuickJobs:YES];return NO;}
    NSDictionary *job=self.quickState[@"jobs"][batch];if(!job)return NO;
    NSURL *folder=[self quickFolder:batch];if(!folder)return YES;
    if([action isEqual:@"copy"]){NSString *text=[NSString stringWithFormat:@"按 %@/SKILL.md 识别同目录 materials.local.json；先写 results.local.json.tmp，再原子改名为 results.local.json。",folder.path];[NSPasteboard.generalPasteboard clearContents];[NSPasteboard.generalPasteboard setString:text forType:NSPasteboardTypeString];}
    else if([action isEqual:@"reveal"])[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[folder]];
    else if([action isEqual:@"retry"]){NSMutableDictionary *jobs=[self.quickState[@"jobs"] mutableCopy],*copy=job.mutableCopy;[copy removeObjectForKey:@"received"];copy[@"state"]=@"等待助手";jobs[batch]=copy;self.quickState[@"jobs"]=jobs;if([self persistQuick:NULL])[self pollQuickResults];}
    else if([action isEqual:@"prepare-failed"])[self quickEntry:nil];
    return YES;
}
