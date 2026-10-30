- (void)controlTextDidChange:(NSNotification *)notification {if(notification.object==self.message)self.messageEdited=YES;}
- (void)updateDefaultMessage {
    if(self.messageEdited)return;NSArray *paths=[self chosenPaths];if(!paths.count)return;
    if(self.message.stringValue.length && ![self.message.stringValue isEqual:self.generatedMessage]){self.messageEdited=YES;return;}
    NSSet *selected=[NSSet setWithArray:paths];NSUInteger added=0,removed=0,modified=0;for(NSDictionary *change in self.allFileChanges ?: self.changes)if([selected containsObject:change[@"path"]]){NSString *status=change[@"status"] ?: @"";if([status containsString:@"A"] || [status containsString:@"?"])added++;else if([status containsString:@"D"])removed++;else modified++;}
    NSString *name=nil;NSArray *taskIDs=[self chosenTasks];if(taskIDs.count==1)for(NSDictionary *task in self.relatedTasks)if([task[@"id"] isEqual:taskIDs[0]])name=task[@"title"];
    NSMutableArray *counts=NSMutableArray.array;if(added)[counts addObject:[NSString stringWithFormat:@"新增%lu",(unsigned long)added]];if(modified)[counts addObject:[NSString stringWithFormat:@"修改%lu",(unsigned long)modified]];if(removed)[counts addObject:[NSString stringWithFormat:@"删除%lu",(unsigned long)removed]];
    self.generatedMessage=[NSString stringWithFormat:@"提交%@：%@个文件",name.length ? name:@"作业",[counts componentsJoinedByString:@"、"]];self.message.stringValue=self.generatedMessage;
}
- (void)taskScopeChanged:(id)sender {
    // 只有明确来源目录才缩小文件范围；手动任务或根目录来源不凭名称猜归属。
    NSArray *chosen=[self chosenTasks];NSMutableOrderedSet *paths=NSMutableOrderedSet.orderedSet;BOOL ambiguous=NO;
    for(NSDictionary *task in self.relatedTasks)if([chosen containsObject:task[@"id"]]){NSString *source=task[@"sourcePath"];NSString *folder=[source stringByDeletingLastPathComponent];if(!source.length || !folder.length || [folder hasPrefix:@"/"] || [folder.pathComponents containsObject:@".."])ambiguous=YES;else [paths addObject:folder];}
    self.scopePaths=ambiguous ? @[]:paths.array;self.scopeToggle.hidden=!self.scopePaths.count;if(!self.scopePaths.count)self.scopeToggle.state=NSControlStateValueOff;[self replaceFileChanges:self.allFileChanges ?: self.changes ?: @[]];[self selectionChanged:nil];
}
- (void)toggleScope:(id)sender {[self replaceFileChanges:self.allFileChanges ?: @[]];[self selectionChanged:nil];}
- (void)fileActions:(NSButton *)sender {
    NSMenu *menu=NSMenu.new;for(NSArray *entry in @[@[@"添加文件…",@"addAttachments:"],@[@"粘贴图片…",@"pasteAttachment:"],@[@"复制图片引用",@"copyAttachmentReference:"],@[@"在编辑器中打开…",@"editExternalFile:"],@[@"打开终端",@"openAssignmentTerminal:"]]){NSMenuItem *item=[menu addItemWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:@""];item.target=self;}[menu popUpMenuPositioningItem:nil atLocation:NSZeroPoint inView:sender];
}
- (NSString *)attachmentScope {
    return self.scopePaths.count==1 ? self.scopePaths.firstObject:nil;
}
- (BOOL)importPasteboard:(NSPasteboard *)pasteboard {
    NSArray *urls=[pasteboard readObjectsForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}];NSData *image=nil;if(!urls.count){image=[pasteboard dataForType:NSPasteboardTypePNG];if(!image){NSData *tiff=[pasteboard dataForType:NSPasteboardTypeTIFF];if(tiff){NSBitmapImageRep *rep=[NSBitmapImageRep imageRepWithData:tiff];image=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];}}}return [self importURLs:urls ?: @[] image:image];
}
- (BOOL)importURLs:(NSArray *)urls image:(NSData *)image {
    // 确认写入目标后才复制。复制/创建使用不覆盖语义，避免确认后发生同名文件竞争。
    NSString *scope=[self attachmentScope];if(!scope){self.filesValidation.stringValue=@"请先关联一份有明确目录的作业，再添加附件";return NO;}
    if(!urls.count && !image)return NO;NSAlert *confirm=NSAlert.new;confirm.messageText=@"添加到作业目录";confirm.informativeText=[NSString stringWithFormat:@"%@\n%@\n不会自动修改Markdown或提交文件。",scope,image ? @"粘贴的图片":[[urls valueForKey:@"lastPathComponent"] componentsJoinedByString:@"\n"]];[confirm addButtonWithTitle:@"添加"];[confirm addButtonWithTitle:@"取消"];if([confirm runModal]!=NSAlertFirstButtonReturn)return NO;
    NSURL *root=[NSURL fileURLWithPath:self.course[@"path"]];NSMutableArray *sources=urls.mutableCopy;if(image)[sources addObject:NSNull.null];BOOL added=NO;
    for(id source in sources){NSString *name=source==NSNull.null ? [NSString stringWithFormat:@"image-%@.png",DDLFormatDate(NSDate.date,@"yyyyMMdd-HHmmss")]:[source lastPathComponent];NSString *destinationScope=scope;
        if(source==NSNull.null){NSURL *folder=[root URLByAppendingPathComponent:scope];NSURL *assets=[folder URLByAppendingPathComponent:@"assets"];if(![assets.path isEqual:assets.URLByResolvingSymlinksInPath.path]){self.filesValidation.stringValue=@"图片目录含符号链接，未写入";return NO;}NSError *directoryError=nil;if(![NSFileManager.defaultManager createDirectoryAtURL:assets withIntermediateDirectories:NO attributes:nil error:&directoryError] && ![NSFileManager.defaultManager fileExistsAtPath:assets.path]){self.filesValidation.stringValue=directoryError.localizedDescription;return NO;}destinationScope=[scope stringByAppendingPathComponent:@"assets"];}
        NSError *error=nil;NSURL *target=AMAttachmentDestination(root,destinationScope,name,&error);
        if(!target && [NSFileManager.defaultManager fileExistsAtPath:[[root URLByAppendingPathComponent:destinationScope] URLByAppendingPathComponent:name].path]){NSAlert *rename=NSAlert.new;rename.messageText=@"文件已存在，请改名";NSTextField *field=[NSTextField textFieldWithString:name];field.frame=NSMakeRect(0,0,320,28);rename.accessoryView=field;[rename addButtonWithTitle:@"添加"];[rename addButtonWithTitle:@"取消"];if([rename runModal]!=NSAlertFirstButtonReturn)continue;name=field.stringValue;error=nil;target=AMAttachmentDestination(root,destinationScope,name,&error);}
        if(!target){self.filesValidation.stringValue=error.localizedDescription;return NO;}
        BOOL saved=NO;if(source==NSNull.null)saved=[image writeToURL:target options:NSDataWritingWithoutOverwriting error:&error];else{NSURL *url=source;NSNumber *regular=nil;[url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:&error];if(!regular.boolValue || ![url.path isEqual:url.URLByResolvingSymlinksInPath.path])error=AMAttachmentError(@"只支持普通文件，不复制目录或符号链接");else saved=[NSFileManager.defaultManager copyItemAtURL:url toURL:target error:&error];}
        if(!saved){self.filesValidation.stringValue=error.localizedDescription;return NO;}added=YES;NSString *relative=[destinationScope substringFromIndex:scope.length];if([relative hasPrefix:@"/"])relative=[relative substringFromIndex:1];relative=relative.length ? [relative stringByAppendingPathComponent:name]:name;self.attachmentReference=[NSString stringWithFormat:@"![%@](<%@>)",[name stringByDeletingPathExtension],relative];
    }if(added && self.refreshFiles)self.refreshFiles();return added;
}
- (void)addAttachments:(id)sender {NSOpenPanel *panel=NSOpenPanel.openPanel;panel.allowsMultipleSelection=YES;panel.canChooseDirectories=NO;if([panel runModal]==NSModalResponseOK)[self importURLs:panel.URLs image:nil];}
- (void)pasteAttachment:(id)sender {[self importPasteboard:NSPasteboard.generalPasteboard];}
- (void)copyAttachmentReference:(id)sender {if(self.attachmentReference.length){[NSPasteboard.generalPasteboard clearContents];[NSPasteboard.generalPasteboard setString:self.attachmentReference forType:NSPasteboardTypeString];self.filesValidation.stringValue=@"图片引用已复制";}}
- (NSURL *)assignmentURL {NSString *scope=[self attachmentScope];return [NSURL fileURLWithPath:scope.length ? [self.course[@"path"] stringByAppendingPathComponent:scope]:self.course[@"path"]];}
- (void)editExternalFile:(id)sender {NSOpenPanel *panel=NSOpenPanel.openPanel;panel.directoryURL=[NSURL fileURLWithPath:@"/Applications"];panel.allowedContentTypes=@[UTTypeApplication];if([panel runModal]!=NSModalResponseOK)return;NSURL *url=self.previewPath.length ? [NSURL fileURLWithPath:[self.course[@"path"] stringByAppendingPathComponent:self.previewPath]]:[self assignmentURL];[NSWorkspace.sharedWorkspace openURLs:@[url] withApplicationAtURL:panel.URL configuration:NSWorkspaceOpenConfiguration.configuration completionHandler:nil];}
- (void)openAssignmentTerminal:(id)sender {NSURL *app=[NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.apple.Terminal"];if(app)[NSWorkspace.sharedWorkspace openURLs:@[[self assignmentURL]] withApplicationAtURL:app configuration:NSWorkspaceOpenConfiguration.configuration completionHandler:nil];}
