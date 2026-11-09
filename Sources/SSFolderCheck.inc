// Independent local checking has its own scope and never edits course binding.
- (void)closeCheckScope {
    self.checkScopeGeneration++;self.checkPreviewGeneration++;
    if(self.checkScopeWindow.sheetParent)[self.window endSheet:self.checkScopeWindow];
    [self.checkScopeWindow orderOut:nil];self.checkScopeWindow=nil;self.checkScope=nil;AMOperationFinish(self.checkScopeOperation,@"cancelled",@"文件整理已取消");self.checkScopeOperation=nil;
}
- (void)showCheckWorkspace {if(self.checkScopeWindow)[self.checkScopeWindow makeKeyAndOrderFront:nil];else [self status:@"还没有打开的检查工作区；请选择任务，再点击“检查作业文件…”。"];}
- (void)checkTask:(NSString *)identifier {
    if(self.checkScopeWindow){[self showCheckWorkspace];return;}
    NSString *blocked=[self taskCheckBlockReason];if(blocked){[self showTaskCheckProblem:blocked];return;}
    NSDictionary *task=nil,*linked=nil;for(NSDictionary *row in self.tasksProvider ? self.tasksProvider():@[])if([row[@"id"] isEqual:identifier])task=row.copy;
    if(!task){[self showTaskCheckProblem:@"这项任务已不存在，请重新选择任务。"];return;}
    for(NSDictionary *row in self.courses)if(AMTaskBelongsToCourse(task,row)){if(linked){linked=nil;break;}linked=row.copy;}
    NSString *source=task[@"sourcePath"],*scope=source.stringByDeletingLastPathComponent;
    BOOL automatic=[linked[@"path"] length] && AMPeerPath(scope) && !SSSensitivePath(scope) &&
        [task[@"sourceRepository"] length] && [task[@"sourceRepository"] isEqual:linked[@"upstream"]];
    if(automatic)for(NSDictionary *other in self.tasksProvider ? self.tasksProvider():@[]){
        if([other[@"deleted"] boolValue] || [other[@"id"] isEqual:identifier] || !AMTaskBelongsToCourse(other,linked))continue;
        NSString *otherSource=other[@"sourcePath"],*otherScope=otherSource.stringByDeletingLastPathComponent;
        if(AMPeerInScope(otherScope,scope) || AMPeerInScope(scope,otherScope)){automatic=NO;break;}
    }
    [self prepareCheckScopeForTask:task course:linked scope:automatic ? scope:nil reason:@"无法自动确定独立的作业目录，请确认范围。"];
}
- (void)prepareCheckScopeForTask:(NSDictionary *)task course:(NSDictionary *)linked scope:(NSString *)assignmentScope reason:(NSString *)reason {
    NSString *identifier=task[@"id"];
    NSArray<NSURL *> *urls=nil;
    if(assignmentScope)urls=@[[NSURL fileURLWithPath:linked[@"path"]]];
    else {
        NSOpenPanel *picker=NSOpenPanel.openPanel;picker.canChooseDirectories=YES;picker.canChooseFiles=YES;picker.allowsMultipleSelection=YES;
        picker.message=reason ?: @"选择作业文件夹或具体文件。";picker.prompt=@"核对检查范围";
        if([linked[@"path"] length])picker.directoryURL=[NSURL fileURLWithPath:linked[@"path"]];
        if([picker runModal]!=NSModalResponseOK)return;
        urls=picker.URLs;
    }
    if(!urls.count)return;NSNumber *directory=nil;[urls.firstObject getResourceValue:&directory forKey:NSURLIsDirectoryKey error:NULL];BOOL folder=directory.boolValue;if(folder && urls.count!=1){[self showTaskCheckProblem:@"请选择一个作业文件夹，或多个具体文件；多个文件夹请分次检查。"];return;}
    for(NSURL *url in urls){NSNumber *isDirectory=nil;[url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL];if(isDirectory.boolValue!=folder){[self showTaskCheckProblem:@"文件夹和具体文件请分别选择，避免扩大读取范围。"];return;}}
    // Common parent is an explicit local boundary, independent of Git configuration.
    NSString *root=folder ? urls.firstObject.path.stringByStandardizingPath:urls.firstObject.path.stringByDeletingLastPathComponent.stringByStandardizingPath;
    if(!folder)for(NSURL *url in urls){NSString *parent=url.path.stringByDeletingLastPathComponent.stringByStandardizingPath;while(![parent isEqual:root] && ![parent hasPrefix:[root stringByAppendingString:@"/"]] && ![root isEqual:@"/"])root=root.stringByDeletingLastPathComponent;}
    NSString *blocked=[self taskCheckBlockReason];if(blocked){[self showTaskCheckProblem:blocked];return;}
    NSMutableDictionary *course=linked.mutableCopy ?: NSMutableDictionary.dictionary;course[@"path"]=assignmentScope ? root.stringByResolvingSymlinksInPath:root;course[@"preflightMode"]=@"working";course[@"preflightLocal"]=@YES;
    self.checkScope=AMCheckScopeController.new;self.checkScopeWindow=AMMakeCheckWorkspace(self.window);self.checkScopeWindow.title=@"检查整份作业 · 文件范围";self.checkScopeWindow.contentViewController=self.checkScope;
    __weak typeof(self) owner=self;
    self.checkScope.actionHandler=^(NSDictionary *request){
        if([request[@"action"] isEqual:@"refresh"] && assignmentScope){[owner closeCheckScope];[owner checkTask:identifier];return;}
        if([request[@"action"] isEqual:@"cancel"]){[owner closeCheckScope];return;}
        if([request[@"action"] isEqual:@"preview"]){NSString *path=request[@"selected"];NSDictionary *record=nil;for(NSDictionary *row in owner.checkScopeRecords)if([row[@"path"] isEqual:path])record=row;if(![record[@"selectable"] boolValue])return;NSUInteger version=++owner.checkPreviewGeneration;NSMutableDictionary *previewCourse=course.mutableCopy;previewCourse[@"preflightPreview"]=@YES;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{SSGit *reader=SSGit.new;NSDictionary *snapshot=[reader preflightSnapshotForCourse:previewCourse paths:@[path] error:NULL];dispatch_async(dispatch_get_main_queue(),^{if(owner.checkPreviewGeneration!=version || !owner.checkScope)return;AMDocumentView *preview=[[AMDocumentView alloc] initWithFrame:NSMakeRect(0,0,600,460)];[preview loadSnapshot:snapshot ?: @{} path:path];[owner.checkScope setPreview:preview];});});return;}
        if(![request[@"action"] isEqual:@"check"] || ![request[@"paths"] count])return;
        if(owner.operationsPaused || (owner.busy && !owner.git.readsCancellable)){[owner.checkScope setProgress:@"正在写入课程文件或准备退出，请等待结束后再开始检查。"];return;}
        NSArray *paths=[request[@"paths"] copy];NSMutableArray *changes=NSMutableArray.array;for(NSString *path in paths)[changes addObject:@{@"path":path,@"status":@"当前本机文件",@"sensitive":@(SSSensitivePath(path))}];
        NSSet *selection=[NSSet setWithArray:paths];
        NSMutableArray *excluded=NSMutableArray.array,*omissions=NSMutableArray.array;
        NSMutableDictionary *feedbackVersions=NSMutableDictionary.dictionary;
        for(NSDictionary *row in owner.checkScopeRecords)if(![selection containsObject:row[@"path"]]){
            if([row[@"image"] boolValue]) [excluded addObject:row[@"path"]];
            if(row[@"feedbackVersion"])feedbackVersions[row[@"path"]]=row[@"feedbackVersion"];
            if(![row[@"verifiedFeedback"] boolValue] && !SSSensitivePath(row[@"path"])){
                NSString *why=[row[@"reason"] length] ? row[@"reason"]:@"未选择";
                [omissions addObject:@{@"path":row[@"path"],@"status":[row[@"deleted"] boolValue] ? why:[@"未覆盖：" stringByAppendingString:why]}];
            }
        }
        course[@"preflightFeedbackVersions"]=feedbackVersions;course[@"preflightExcluded"]=excluded;course[@"preflightOmissions"]=omissions;
        AMCheckScopeController *scopeController=owner.checkScope;NSWindow *scope=owner.checkScopeWindow;owner.checkScopeGeneration++;
        owner.submission=[[SSSubmissionController alloc] initWithCourse:course changes:changes];owner.submission.checkOnly=YES;owner.submission.message.hidden=YES;
        [owner.submission configureTasks:@[task] selected:@[identifier]];
        NSView *reportRoot=owner.submission.window.contentView;owner.submission.window=scope;scope.contentView=reportRoot;reportRoot.frame=NSMakeRect(0,0,NSWidth(scope.contentView.bounds),NSHeight(scope.contentView.bounds));reportRoot.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;scope.title=@"检查整份作业 · 检查报告";
        [owner configurePreflight:owner.submission course:course tasks:@[task]];
        for(NSButton *check in owner.submission.checks)if(check.enabled)check.state=NSControlStateValueOn;owner.submission.draftBaseline=[owner.submission draftValues];
        owner.submission.finished=^{owner.submission=nil;[owner closeCheckScope];};
        owner.submission.backToScope=^{SSSubmissionController *report=owner.submission;report.finished=nil;[report cancel:nil];owner.submission=nil;((AMCheckWindow *)scope).onConfirm=nil;((AMCheckWindow *)scope).onCancel=^{[owner closeCheckScope];};scope.contentViewController=scopeController;scope.title=@"检查整份作业 · 文件范围";[scope makeKeyAndOrderFront:nil];};
        owner.submission.readPreview=^(NSString *path,void(^ready)(NSString *)){ready(@"当前本机文件，只读检查；不创建提交或推送。");};
        ((AMCheckWindow *)scope).onConfirm=^{[owner.submission save:nil];};((AMCheckWindow *)scope).onCancel=^{[owner.submission cancel:nil];};[owner.submission save:nil];[scope makeKeyAndOrderFront:nil];
    };
    [self.checkScopeWindow makeKeyAndOrderFront:nil];NSUInteger generation=++self.checkScopeGeneration;self.checkScopeOperation=AMOperationBegin(@"整理作业文件",root.lastPathComponent,YES,^{[owner closeCheckScope];});
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSError *error=nil;NSArray *records=nil;
        NSDictionary *binding=nil;
        if(assignmentScope){
            SSGit *git=SSGit.new;git.readsCancellable=YES;git.commandDeadline=[NSDate dateWithTimeIntervalSinceNow:15];
            BOOL (^cancelled)(void)=^BOOL{return !owner || owner.checkScopeGeneration!=generation;};
            binding=AMPerformResourceOperation(NSUUID.UUID.UUIDString,@"确定作业范围",linked[@"fork"],AMRepositoryResources(linked,@"read"),100,cancelled,^id(NSError **failure){
                NSThread.currentThread.threadDictionary[@"AMOperationCancellation"]=[cancelled copy];
                @try{return [git assignmentCheckScopeForCourse:linked scope:assignmentScope error:failure];}
                @finally{[NSThread.currentThread.threadDictionary removeObjectForKey:@"AMOperationCancellation"];}
            },&error);
            if(binding){
                NSURL *base=[NSURL fileURLWithPath:course[@"path"]];
                NSDictionary *confirmed=SSReadPlist(@"assignment-feedback-confirmed.plist");
                NSString *feedbackKey=AMPeerHash(@[linked[@"fork"] ?: @"",linked[@"forkID"] ?: @0,linked[@"branch"] ?: @"",task[@"sourcePath"] ?: @""]);
                NSDictionary *versions=[confirmed isKindOfClass:NSDictionary.class] ? confirmed[feedbackKey]:nil;
                NSMutableArray *rows=NSMutableArray.array;
                for(NSDictionary *item in AMPreflightListSelectedFiles(base,binding[@"answers"])){
                    NSMutableDictionary *row=item.mutableCopy;
                    NSString *path=row[@"path"],*known=versions[path];
                    if(known && [row[@"selectable"] boolValue]){
                        NSDictionary *file=[git preflightSnapshotForCourse:course paths:@[path] error:NULL][@"files"][path];
                        BOOL matches=[known isEqual:file[@"version"]];
                        row[@"verifiedFeedback"]=@(matches);
                        row[@"selectable"]=@(!matches);
                        row[@"defaultSelected"]=@NO;
                        row[@"reason"]=matches ? @"已确认的老师评语":@"与已确认评语不同，请核对后选择";
                        if(matches)row[@"feedbackVersion"]=known;
                    }
                    [rows addObject:row];
                }
                for(NSString *path in binding[@"deleted"])if(!SSSensitivePath(path))[rows addObject:@{@"path":path,@"selectable":@NO,@"deleted":@YES,@"reason":@"已删除"}];
                records=rows;
            }
        }else if(folder){NSDictionary *listing=AMPreflightListFolder([NSURL fileURLWithPath:root],^BOOL{return !owner || owner.checkScopeGeneration!=generation;},^(NSUInteger count){dispatch_async(dispatch_get_main_queue(),^{if(owner.checkScopeGeneration==generation){AMOperationProgress(owner.checkScopeOperation,@"整理文件夹",count,0);[owner.checkScope setProgress:[NSString stringWithFormat:@"已整理 %lu 项…",(unsigned long)count]];}});},&error);records=listing[@"files"] ?: @[];}
        else{NSMutableArray *paths=NSMutableArray.array;NSString *prefix=[root isEqual:@"/"] ? @"/" : [root stringByAppendingString:@"/"];for(NSURL *url in urls)if([url.path hasPrefix:prefix])[paths addObject:[url.path substringFromIndex:prefix.length]];records=AMPreflightListSelectedFiles([NSURL fileURLWithPath:root],paths);}
        dispatch_async(dispatch_get_main_queue(),^{if(!owner || owner.checkScopeGeneration!=generation)return;
            if(assignmentScope && !binding){
                [owner closeCheckScope];
                [owner prepareCheckScopeForTask:task course:linked scope:nil reason:[NSString stringWithFormat:@"%@ 请手动确认文件范围。",error.localizedDescription ?: @"未能自动确定作业范围。"]];
                return;
            }
            if(binding)course[@"assignmentCheckScope"]=binding;
            [owner.checkScope setRefreshAvailable:binding!=nil];
            owner.checkScopeRecords=records;AMOperationFinish(owner.checkScopeOperation,error ? @"failed":@"success",error.localizedDescription ?: @"文件范围已准备好");[owner.checkScope update:records busy:NO notice:error.localizedDescription ?: (binding ? @"已选相对老师版本有改动的答卷，包括此前提交的答案。":@"核对文件范围后开始；未检查项已列出。")] ;});
    });
}
