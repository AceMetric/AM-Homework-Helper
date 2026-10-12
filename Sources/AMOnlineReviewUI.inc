// User-triggered online review settings; no material is sent by this window.
@interface AMOnlineSettings:NSWindowController
@property NSSecureTextField *keyField;
@property NSButton *enabled;
@property NSButton *consent;
@property NSTextField *status;
@property NSArray *actions;
@property AMOnlineReviewClient *client;
@end
@implementation AMOnlineSettings
- (instancetype)init {
    DDLFormPanel *panel=[[DDLFormPanel alloc] initWithContentRect:NSMakeRect(0,0,660,550) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    if((self=[super initWithWindow:panel])){
        panel.title=@"在线复核设置";panel.releasedWhenClosed=NO;Surface *root=Box(Canvas(),0);root.frame=NSMakeRect(0,0,660,550);panel.contentView=root;
        Put(root,Text(@"Gemini · 整份作业复核",20,NSFontWeightSemibold,Ink()),24,20,612,32);
        Put(root,Text(@"检查文档、代码、图片与跨文件推导；与老师作业识别设置分开。",13,NSFontWeightRegular,Muted()),24,62,612,26);
        self.enabled=[NSButton checkboxWithTitle:@"启用在线复核（只在我点击时发送）" target:nil action:nil];self.enabled.state=[AMOnlineReviewSettings()[@"enabled"] boolValue];Put(root,self.enabled,24,104,612,28);
        Put(root,Text(@"自己的 Gemini API 密钥 · 留空保留现有密钥",13,NSFontWeightMedium,Ink()),24,146,612,24);
        self.keyField=NSSecureTextField.new;self.keyField.placeholderString=@"仅保存到这台 Mac 的钥匙串";self.keyField.accessibilityLabel=@"Gemini API 密钥";Put(root,self.keyField,24,176,612,32);
        NSTextView *policy=PFText(root,NSMakeRect(24,226,612,130),NO);policy.string=@"使用自己未启用计费的免费项目；软件无法从密钥判断计费状态，不承诺绝对零费用。每天最多20次生成请求，失败重试也计数，额度耗尽后停止。\n\n免费服务可能使用材料改进产品，可能有人审阅。请遵守供应商年龄、地区及用途条件，不发送个人敏感信息或保密材料。每次发送前可预览范围；不会运行代码、自动改答案或提交。";
        self.consent=[NSButton checkboxWithTitle:@"我已了解以上说明，并确认使用符合条件的免费项目" target:nil action:nil];self.consent.state=[AMOnlineReviewSettings()[@"enabled"] boolValue];Put(root,self.consent,24,368,612,26);
        self.status=Text([NSString stringWithFormat:@"模型：gemini-3.8-flash · %lu 个上传副本待清理",(unsigned long)AMOnlineReviewPendingUploads()],12,NSFontWeightRegular,Muted());Put(root,self.status,24,408,612,44);
        NSButton *test=Button(@"测试连接",self,@selector(test:),0);Put(root,test,24,464,100,30);
        NSButton *cleanup=Button(@"重试文件清理",self,@selector(cleanup:),0);Put(root,cleanup,136,464,124,30);
        NSButton *terms=Button(@"服务说明",self,@selector(terms:),0);Put(root,terms,272,464,92,30);
        NSButton *studio=Button(@"获取自己的密钥…",self,@selector(studio:),0);Put(root,studio,376,464,144,30);
        NSButton *close=Button(@"取消",self,@selector(closeSettings:),0);Put(root,close,420,504,92,30);close.keyEquivalent=@"\033";close.keyEquivalentModifierMask=0;
        NSButton *save=Button(@"保存",self,@selector(saveSettings:),1);Put(root,save,524,504,112,30);save.keyEquivalent=@"\r";save.keyEquivalentModifierMask=0;
        self.actions=@[test,cleanup,save,self.enabled,self.consent];__weak typeof(self) owner=self;panel.onCancel=^{[owner closeSettings:nil];};panel.onConfirm=^{[owner saveSettings:nil];};
    }return self;
}
- (void)studio:(id)sender {[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://aistudio.google.com/apikey"]];}
- (void)terms:(id)sender {[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://ai.google.dev/gemini-api/terms"]];}
- (void)closeSettings:(id)sender {self.client.cancelled=YES;[NSApp stopModal];[self.window orderOut:nil];}
- (void)saveSettings:(id)sender {
    if(self.client)return;if(self.enabled.state && !self.consent.state){self.status.stringValue=@"请先阅读并确认服务与免费项目说明。";return;}
    NSError *error=nil;if(!AMOnlineReviewSaveSettings(self.enabled.state==NSControlStateValueOn,self.keyField.stringValue,&error)){self.status.stringValue=error.localizedDescription;self.status.textColor=NSColor.systemRedColor;return;}
    self.keyField.stringValue=@"";[self closeSettings:nil];
}
- (void)test:(id)sender {[self run:NO];}
- (void)cleanup:(id)sender {[self run:YES];}
- (void)run:(BOOL)cleanup {
    if(self.client)return;self.client=AMOnlineReviewClient.new;self.client.forceCleanup=YES;AMOnlineReviewClient *client=self.client;NSString *key=cleanup ? @"":self.keyField.stringValue.copy;
    for(NSControl *button in self.actions)button.enabled=NO;self.keyField.enabled=NO;self.status.stringValue=cleanup ? @"正在清理上传副本…":@"核验密钥与模型访问，不发送作业…";__weak typeof(self) owner=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSError *error=nil;NSUInteger pending=0;BOOL ok=cleanup ? ((pending=[client cleanupWithKey:key error:&error])==0):[client testConnectionWithKey:key error:&error];
        dispatch_async(dispatch_get_main_queue(),^{if(!owner)return;owner.client=nil;for(NSControl *button in owner.actions)button.enabled=YES;owner.keyField.enabled=YES;owner.status.textColor=ok ? Muted():NSColor.systemRedColor;owner.status.stringValue=ok ? (cleanup ? @"已清理已知上传副本。":@"模型可访问。计费状态和免费余额请在 AI Studio 核对。"):(error.localizedDescription ?: [NSString stringWithFormat:@"未完成，仍有%lu个副本待清理。",(unsigned long)pending]);});
    });
}
@end
void AMShowOnlineReviewSettings(NSWindow *parent){AMOnlineSettings *settings=AMOnlineSettings.new;if(parent)[settings.window setFrameOrigin:NSMakePoint(NSMidX(parent.frame)-330,NSMidY(parent.frame)-275)];else [settings.window center];[NSApp runModalForWindow:settings.window];[settings.window orderOut:nil];}
