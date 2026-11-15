// The embedded form is an adapter over the same submission session as the sheet.
// It never stages files, reads credentials, or performs a second Git transaction.
@implementation AMSubmissionPane
- (instancetype)initWithFrame:(NSRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.all=Button(@"全选",self,@selector(allFiles:),0);
        self.reload=Button(@"刷新",self,@selector(reloadFiles:),0);
        self.scope=[NSButton checkboxWithTitle:@"显示作业范围外改动" target:self action:@selector(scopeChanged:)];
        self.list=NSScrollView.new;self.list.hasVerticalScroller=YES;self.list.drawsBackground=NO;
        self.notes=Text(@"提交说明",13,NSFontWeightMedium,Ink());
        self.message=[NSTextField wrappingLabelWithString:@""];self.message.editable=YES;self.message.selectable=YES;self.message.bordered=YES;self.message.drawsBackground=YES;self.message.delegate=self;
        self.status=Text(@"",12,NSFontWeightRegular,Muted());self.status.maximumNumberOfLines=2;
        self.primary=Button(@"提交并推送",self,@selector(submitFiles:),1);
        self.check=Button(@"AI 检查…",self,@selector(checkFiles:),0);
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 260000
        if(@available(macOS 26.0,*)){self.primary.bezelStyle=NSBezelStyleGlass;self.check.bezelStyle=NSBezelStyleGlass;self.all.bezelStyle=NSBezelStyleGlass;self.reload.bezelStyle=NSBezelStyleGlass;}
#endif
        for(NSView *child in @[self.all,self.reload,self.scope,self.list,self.notes,self.message,self.status,self.primary,self.check])[self addSubview:child];
    }return self;
}
- (BOOL)isFlipped{return YES;}
- (void)layout {
    [super layout];CGFloat w=NSWidth(self.bounds),h=NSHeight(self.bounds);
    self.all.frame=NSMakeRect(0,0,85,28);self.reload.frame=NSMakeRect(MAX(90,w-60),0,60,28);
    self.scope.frame=NSMakeRect(0,34,w,24);self.list.frame=NSMakeRect(0,64,w,MAX(40,h-324));
    self.notes.frame=NSMakeRect(0,MAX(112,h-246),w,22);self.message.frame=NSMakeRect(0,MAX(138,h-218),w,80);
    self.status.frame=NSMakeRect(0,MAX(222,h-130),w,42);self.check.frame=NSMakeRect(0,MAX(260,h-82),w,30);self.primary.frame=NSMakeRect(0,MAX(266,h-42),w,32);
}
- (void)refresh {
    SSSubmissionController *session=self.session;if(!session)return;
    BOOL busy=session.filesPreparing || session.checking || session.submissionInFlight;
    self.all.enabled=self.reload.enabled=self.scope.enabled=!busy;
    self.primary.enabled=!busy && !session.submittedSuccessfully && !session.submissionNeedsVerification && session.submit!=nil && [session chosenPaths].count>0;
    self.message.enabled=!busy;self.check.enabled=!busy && session.embeddedCheck!=nil;
    if(!self.message.currentEditor && ![self.message.stringValue isEqual:session.message.stringValue])self.message.stringValue=session.message.stringValue;
    self.status.stringValue=session.filesPreparing ? @"正在读取本地改动…":(session.submissionInFlight ? @"正在核验并提交…":session.validation.stringValue);
    self.scope.hidden=session.scopeToggle.hidden;self.scope.state=session.scopeToggle.state;
    self.all.title=session.selectAllFilesButton.title;
    if(![self.rows isEqual:session.changes]) {
        // Rebuild only when the change list changes; typing and phase updates retain focus and scroll.
        NSPoint offset=self.list.contentView.bounds.origin;self.rows=session.changes.copy;
        NSView *document=[[NSView alloc] initWithFrame:NSMakeRect(0,0,MAX(100,NSWidth(self.bounds)),self.rows.count*32)];
        NSMutableArray *buttons=NSMutableArray.array;
        for(NSUInteger i=0;i<self.rows.count;i++){
            NSDictionary *row=self.rows[i];NSButton *check=[NSButton checkboxWithTitle:[NSString stringWithFormat:@"%@  %@",row[@"status"] ?: @"",row[@"path"] ?: @""] target:self action:@selector(choose:)];
            check.identifier=row[@"path"];check.toolTip=row[@"path"];check.tag=i;check.frame=NSMakeRect(0,(self.rows.count-i-1)*32,NSWidth(document.bounds),30);check.autoresizingMask=NSViewWidthSizable;check.lineBreakMode=NSLineBreakByTruncatingMiddle;[document addSubview:check];[buttons addObject:check];
        }self.buttons=buttons;self.list.documentView=document;[self.list.contentView scrollToPoint:offset];
    }
    for(NSButton *check in self.buttons){NSUInteger i=check.tag;if(i<session.checks.count){check.state=session.checks[i].state;check.enabled=session.checks[i].enabled && !busy;}}
}
- (void)choose:(NSButton *)sender {
    SSSubmissionController *s=self.session;if(sender.tag<0 || sender.tag>=(NSInteger)s.checks.count)return;
    NSButton *original=s.checks[sender.tag];if(![sender.identifier isEqual:s.changes[sender.tag][@"path"]])return;
    original.state=sender.state;[s selectionChanged:nil];[s saveEmbeddedDraft];[self refresh];
}
- (void)allFiles:(id)sender{[self.session toggleAllFiles:nil];[self.session saveEmbeddedDraft];[self refresh];}
- (void)scopeChanged:(id)sender{self.session.scopeToggle.state=self.scope.state;[self.session toggleScope:nil];[self.session saveEmbeddedDraft];[self refresh];}
- (void)reloadFiles:(id)sender{[self.session refreshFileList:nil];}
- (void)controlTextDidChange:(NSNotification *)note{self.session.message.stringValue=self.message.stringValue;self.session.messageEdited=YES;[self.session saveEmbeddedDraft];}
- (void)checkFiles:(id)sender{if(self.session.embeddedCheck)self.session.embeddedCheck();}
- (void)submitFiles:(id)sender {
    // Commit the current field editor before capturing the safety-check snapshot.
    if(![self.window makeFirstResponder:nil])return;
    self.session.message.stringValue=self.message.stringValue;self.session.closed=NO;[self.session save:nil];[self refresh];
}
@end
