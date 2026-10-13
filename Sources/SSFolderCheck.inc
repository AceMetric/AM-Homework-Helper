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
    for(NSDictionary *row in self.courses)if([task[@"courseRepository"] isEqual:row[@"fork"]] || [task[@"sourceRepository"] isEqual:row[@"upstream"]]){linked=row.copy;break;}
    // A folder is the normal starting point; files remain available in this
    // same native picker, without a preceding mode-selection dialog.
    NSOpenPanel *picker=NSOpenPanel.openPanel;picker.canChooseDirectories=YES;picker.canChooseFiles=YES;picker.allowsMultipleSelection=YES;
    picker.message=@"选择作业文件夹（包含子文件夹），也可选择具体文件；下一步核对范围。";picker.prompt=@"核对检查范围";
    if([linked[@"path"] length])picker.directoryURL=[NSURL fileURLWithPath:linked[@"path"]];if([picker runModal]!=NSModalResponseOK)return;
    NSArray<NSURL *> *urls=picker.URLs;if(!urls.count)return;NSNumber *directory=nil;[urls.firstObject getResourceValue:&directory forKey:NSURLIsDirectoryKey error:NULL];BOOL folder=directory.boolValue;if(folder && urls.count!=1){[self showTaskCheckProblem:@"请选择一个作业文件夹，或多个具体文件；多个文件夹请分次检查。"];return;}
    for(NSURL *url in urls){NSNumber *isDirectory=nil;[url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL];if(isDirectory.boolValue!=folder){[self showTaskCheckProblem:@"文件夹和具体文件请分别选择，避免扩大读取范围。"];return;}}
    // Common parent is an explicit local boundary, independent of Git configuration.
    NSString *root=folder ? picker.URL.path.stringByStandardizingPath:urls.firstObject.path.stringByDeletingLastPathComponent.stringByStandardizingPath;
    if(!folder)for(NSURL *url in urls){NSString *parent=url.path.stringByDeletingLastPathComponent.stringByStandardizingPath;while(![parent isEqual:root] && ![parent hasPrefix:[root stringByAppendingString:@"/"]] && ![root isEqual:@"/"])root=root.stringByDeletingLastPathComponent;}
    blocked=[self taskCheckBlockReason];if(blocked){[self showTaskCheckProblem:blocked];return;}
    NSMutableDictionary *course=linked.mutableCopy ?: NSMutableDictionary.dictionary;course[@"path"]=root;course[@"preflightMode"]=@"working";course[@"preflightLocal"]=@YES;
    self.checkScope=AMCheckScopeController.new;self.checkScopeWindow=AMMakeCheckWorkspace(self.window);self.checkScopeWindow.title=@"检查作业文件 · 文件范围";self.checkScopeWindow.contentViewController=self.checkScope;
    __weak typeof(self) owner=self;
    self.checkScope.actionHandler=^(NSDictionary *request){
        if([request[@"action"] isEqual:@"cancel"]){[owner closeCheckScope];return;}
        if([request[@"action"] isEqual:@"preview"]){NSString *path=request[@"selected"];NSDictionary *record=nil;for(NSDictionary *row in owner.checkScopeRecords)if([row[@"path"] isEqual:path])record=row;if(![record[@"selectable"] boolValue])return;NSUInteger version=++owner.checkPreviewGeneration;NSDictionary *previewCourse=course.copy;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{SSGit *reader=SSGit.new;NSDictionary *snapshot=[reader preflightSnapshotForCourse:previewCourse paths:@[path] error:NULL];dispatch_async(dispatch_get_main_queue(),^{if(owner.checkPreviewGeneration!=version || !owner.checkScope)return;AMDocumentView *preview=[[AMDocumentView alloc] initWithFrame:NSMakeRect(0,0,600,460)];[preview loadSnapshot:snapshot ?: @{} path:path];[owner.checkScope setPreview:preview];});});return;}
        if(![request[@"action"] isEqual:@"check"] || ![request[@"paths"] count])return;
        if(owner.operationsPaused || (owner.busy && !owner.git.readsCancellable)){[owner.checkScope setProgress:@"正在写入课程文件或准备退出，请等待结束后再开始检查。"];return;}
        NSArray *paths=[request[@"paths"] copy];NSMutableArray *changes=NSMutableArray.array;for(NSString *path in paths)[changes addObject:@{@"path":path,@"status":@"当前本机文件",@"sensitive":@(SSSensitivePath(path))}];
        NSMutableArray *excluded=NSMutableArray.array;for(NSDictionary *row in owner.checkScopeRecords)if([row[@"image"] boolValue] && ![paths containsObject:row[@"path"]])[excluded addObject:row[@"path"]];course[@"preflightExcluded"]=excluded;
        AMCheckScopeController *scopeController=owner.checkScope;NSWindow *scope=owner.checkScopeWindow;owner.checkScopeGeneration++;
        owner.submission=[[SSSubmissionController alloc] initWithCourse:course changes:changes];owner.submission.checkOnly=YES;owner.submission.message.hidden=YES;
        [owner.submission configureTasks:@[task] selected:@[identifier]];
        NSView *reportRoot=owner.submission.window.contentView;owner.submission.window=scope;scope.contentView=reportRoot;reportRoot.frame=NSMakeRect(0,0,NSWidth(scope.contentView.bounds),NSHeight(scope.contentView.bounds));reportRoot.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;scope.title=@"检查作业文件 · 检查报告";
        [owner configurePreflight:owner.submission course:course tasks:@[task]];
        for(NSButton *check in owner.submission.checks)if(check.enabled)check.state=NSControlStateValueOn;
        owner.submission.finished=^{owner.submission=nil;[owner closeCheckScope];};
        owner.submission.backToScope=^{SSSubmissionController *report=owner.submission;report.finished=nil;[report cancel:nil];owner.submission=nil;((AMCheckWindow *)scope).onConfirm=nil;((AMCheckWindow *)scope).onCancel=^{[owner closeCheckScope];};scope.contentViewController=scopeController;scope.title=@"检查作业文件 · 文件范围";[scope makeKeyAndOrderFront:nil];};
        owner.submission.readPreview=^(NSString *path,void(^ready)(NSString *)){ready(@"当前本机文件，只读检查；不创建提交或推送。");};
        ((AMCheckWindow *)scope).onConfirm=^{[owner.submission save:nil];};((AMCheckWindow *)scope).onCancel=^{[owner.submission cancel:nil];};[owner.submission save:nil];[scope makeKeyAndOrderFront:nil];
    };
    [self.checkScopeWindow makeKeyAndOrderFront:nil];NSUInteger generation=++self.checkScopeGeneration;self.checkScopeOperation=AMOperationBegin(@"整理作业文件",root.lastPathComponent,YES,^{[owner closeCheckScope];});
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSError *error=nil;NSArray *records=nil;
        if(folder){NSDictionary *listing=AMPreflightListFolder([NSURL fileURLWithPath:root],^BOOL{return !owner || owner.checkScopeGeneration!=generation;},^(NSUInteger count){dispatch_async(dispatch_get_main_queue(),^{if(owner.checkScopeGeneration==generation){AMOperationProgress(owner.checkScopeOperation,@"整理文件夹",count,0);[owner.checkScope setProgress:[NSString stringWithFormat:@"已整理 %lu 项…",(unsigned long)count]];}});},&error);records=listing[@"files"] ?: @[];}
        else{NSMutableArray *paths=NSMutableArray.array;NSString *prefix=[root isEqual:@"/"] ? @"/" : [root stringByAppendingString:@"/"];for(NSURL *url in urls)if([url.path hasPrefix:prefix])[paths addObject:[url.path substringFromIndex:prefix.length]];records=AMPreflightListSelectedFiles([NSURL fileURLWithPath:root],paths);}
        dispatch_async(dispatch_get_main_queue(),^{if(owner.checkScopeGeneration!=generation)return;owner.checkScopeRecords=records;AMOperationFinish(owner.checkScopeOperation,error ? @"failed":@"success",error.localizedDescription ?: @"文件范围已准备好");[owner.checkScope update:records busy:NO notice:error.localizedDescription ?: @"核对文件范围后开始；未检查项已列出。"] ;});
    });
}
