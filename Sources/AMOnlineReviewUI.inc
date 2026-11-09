// Only user actions send synthetic tests or selected coursework.
@interface AMOnlineSettings:NSWindowController
@property NSSecureTextField *keyField;
@property NSButton *enabled;
@property NSButton *consent;
@property NSTextField *status;
@property NSTextField *accessStatus;
@property NSTextField *generationStatus;
@property NSPopUpButton *models;
@property NSArray *actions;
@property AMOnlineReviewClient *client;
@property AMOperationView *progressView;
@end
@implementation AMOnlineSettings
- (void)configureRates:(id)sender {
    NSDictionary *profile=AMOnlineReviewProfile(),*rates=AMOnlineReviewRates(profile);
    NSAlert *alert=NSAlert.new;alert.messageText=@"当前模型的用量与费用";
    alert.informativeText=[NSString stringWithFormat:@"%@\n%@\n填写每百万 token 的单价。估算按填写的输入单价计算，不含缓存折扣。",
        profile[@"model"],AMOnlineReviewUsageLabel(profile)];
    NSPopUpButton *currency=NSPopUpButton.new;[currency addItemsWithTitles:@[@"USD",@"CNY"]];
    if(rates[@"currency"])[currency selectItemWithTitle:rates[@"currency"]];
    NSTextField *input=NSTextField.new,*output=NSTextField.new;
    input.placeholderString=@"输入单价";output.placeholderString=@"输出单价";
    input.stringValue=[rates[@"input"] stringValue] ?: @"";output.stringValue=[rates[@"output"] stringValue] ?: @"";
    NSStackView *fields=[NSStackView stackViewWithViews:@[currency,input,output]];
    [input.widthAnchor constraintEqualToConstant:120].active=YES;[output.widthAnchor constraintEqualToConstant:120].active=YES;
    alert.accessoryView=fields;[alert addButtonWithTitle:@"保存"];[alert addButtonWithTitle:@"取消"];
    if([alert runModal]!=NSAlertFirstButtonReturn)return;
    NSDictionary *values=@{};
    if(input.stringValue.length || output.stringValue.length){
        NSScanner *inputRate=[NSScanner scannerWithString:input.stringValue],*outputRate=[NSScanner scannerWithString:output.stringValue];
        double first=0,second=0;
        if(![inputRate scanDouble:&first] || !inputRate.isAtEnd || ![outputRate scanDouble:&second] || !outputRate.isAtEnd){
            self.status.stringValue=@"请输入两个有效的单价。";return;
        }
        values=@{@"currency":currency.titleOfSelectedItem,@"input":@(first),@"output":@(second)};
    }
    NSError *error=nil;
    if(!AMOnlineReviewSaveRates(profile,values,&error)){self.status.stringValue=error.localizedDescription;return;}
    self.status.stringValue=AMOnlineReviewUsageLabel(profile);
}
- (void)configureProvider:(NSString *)provider {
    BOOL deep=[provider isEqual:@"deepseek"];
    NSDictionary *profile=AMOnlineReviewProfile();
    BOOL matching=[profile[@"provider"] isEqual:provider];
    NSAlert *alert=NSAlert.new;alert.messageText=deep ? @"配置 DeepSeek 官方接口":@"配置 OpenAI 兼容接口";
    alert.informativeText=@"保存后将使用这个供应商。密钥保存在本机钥匙串，发送作业前仍需确认材料。";
    NSTextField *endpoint=NSTextField.new;endpoint.placeholderString=@"https://服务地址/v1";endpoint.stringValue=matching ? profile[@"endpoint"]:@"";
    NSTextField *model=NSTextField.new;model.placeholderString=@"模型名称";model.stringValue=matching ? profile[@"model"]:(deep ? @"deepseek-flash":@"");
    NSSecureTextField *key=NSSecureTextField.new;key.placeholderString=@"API 密钥（留空保留此地址的密钥）";
    NSButton *vision=[NSButton checkboxWithTitle:@"该模型支持图片" target:nil action:nil];vision.state=matching && [profile[@"vision"] boolValue];
    NSButton *json=[NSButton checkboxWithTitle:@"该接口支持 JSON 模式" target:nil action:nil];json.state=deep || (matching && [profile[@"json"] boolValue]);json.enabled=!deep;
    NSButton *enabled=[NSButton checkboxWithTitle:@"启用在线检查" target:nil action:nil];enabled.state=matching ? [profile[@"enabled"] boolValue]:YES;
    NSStackView *fields=NSStackView.new;fields.orientation=NSUserInterfaceLayoutOrientationVertical;fields.alignment=NSLayoutAttributeLeading;fields.spacing=8;
    for(NSView *field in @[endpoint,model,key,vision,json,enabled]){
        if(deep && field==endpoint)continue;
        [fields addArrangedSubview:field];
        if([field isKindOfClass:NSTextField.class])[field.widthAnchor constraintEqualToConstant:400].active=YES;
    }
    alert.accessoryView=fields;[alert addButtonWithTitle:@"保存"];[alert addButtonWithTitle:@"取消"];
    if([alert runModal]!=NSAlertFirstButtonReturn)return;
    NSError *error=nil;
    if(!AMOnlineReviewSaveCompatible(provider,endpoint.stringValue,model.stringValue,key.stringValue,vision.state==NSControlStateValueOn,
        json.state==NSControlStateValueOn,enabled.state==NSControlStateValueOn,&error)){self.status.stringValue=error.localizedDescription;return;}
    self.status.stringValue=[NSString stringWithFormat:@"已切换到 %@ · %@",AMOnlineReviewProfile()[@"endpoint"],model.stringValue];
}
- (void)configureDeepSeek:(id)sender {[self configureProvider:@"deepseek"];}
- (void)configureCompatible:(id)sender {[self configureProvider:@"compatible"];}
- (void)testProvider:(id)sender {
    NSDictionary *profile=AMOnlineReviewProfile();
    if(![profile[@"enabled"] boolValue]){self.status.stringValue=@"请先保存并启用供应商配置。";return;}
    if(self.client)return;
    AMOnlineReviewClient *client=AMOnlineReviewClient.new;self.client=client;
    self.status.stringValue=@"正在发送一条连接测试请求…";
    __weak typeof(self) owner=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSError *error=nil;BOOL success=[client testProvider:profile error:&error];
        dispatch_async(dispatch_get_main_queue(),^{
            if(owner.client!=client)return;
            owner.client=nil;owner.status.stringValue=success ? @"连接与 JSON 生成正常":(error.localizedDescription ?: @"测试未完成");
        });
    });
}
- (instancetype)init {
    DDLFormPanel *panel=[[DDLFormPanel alloc] initWithContentRect:NSMakeRect(0,0,760,690) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    if((self=[super initWithWindow:panel])){panel.title=@"在线复核设置";panel.contentMinSize=NSMakeSize(720,600);panel.releasedWhenClosed=NO;Surface *root=Box(Canvas(),0);panel.contentView=root;
        NSStackView *stack=NSStackView.new;stack.orientation=NSUserInterfaceLayoutOrientationVertical;stack.alignment=NSLayoutAttributeLeading;stack.spacing=12;NSScrollView *form=AMScrollableForm(stack);form.translatesAutoresizingMaskIntoConstraints=NO;[root addSubview:form];
        [NSLayoutConstraint activateConstraints:@[[form.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:24],[form.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-24],[form.topAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.topAnchor constant:24]]];
        NSDictionary *active=AMOnlineReviewProfile();
        [stack addArrangedSubview:Text([NSString stringWithFormat:@"在线检查 · %@",active[@"model"]],20,NSFontWeightSemibold,Ink())];
        [stack addArrangedSubview:[NSStackView stackViewWithViews:@[
            Button(@"配置 DeepSeek…",self,@selector(configureDeepSeek:),0),
            Button(@"配置兼容接口…",self,@selector(configureCompatible:),0),
            Button(@"测试当前供应商",self,@selector(testProvider:),0),
            Button(@"用量与费用…",self,@selector(configureRates:),0)]]];
        [stack addArrangedSubview:Text(@"Gemini 配置",15,NSFontWeightSemibold,Ink())];
        self.enabled=[NSButton checkboxWithTitle:@"启用在线复核（只在我点击时发送）" target:nil action:nil];self.enabled.state=[active[@"provider"] isEqual:@"gemini"] && [active[@"enabled"] boolValue];[stack addArrangedSubview:self.enabled];
        [stack addArrangedSubview:Text(@"API 密钥（留空保留）",13,NSFontWeightMedium,Ink())];self.keyField=NSSecureTextField.new;AMConfigureSingleLineField(self.keyField);self.keyField.placeholderString=@"只保存到本机钥匙串";[stack addArrangedSubview:self.keyField];[self.keyField.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;
        NSStackView *modelRow=[NSStackView stackViewWithViews:@[Text(@"复核模型",13,NSFontWeightMedium,Ink())]];self.models=NSPopUpButton.new;[self.models addItemWithTitle:AMOnlineReviewCurrentModel()];[modelRow addArrangedSubview:self.models];NSButton *catalog=Button(@"获取可用模型",self,@selector(loadModels:),0);[modelRow addArrangedSubview:catalog];[stack addArrangedSubview:modelRow];
        NSTextField *policy=Text(@"仅发送确认材料。使用自己的免费项目，软件无法核验计费状态；每天最多20次生成请求（含失败和重试）。\n免费服务可能使用材料改进产品并由人工审阅，请遵守年龄、地区及用途条件，勿发送敏感或保密材料。",12,NSFontWeightRegular,Muted());policy.maximumNumberOfLines=0;policy.lineBreakMode=NSLineBreakByWordWrapping;[stack addArrangedSubview:policy];[policy.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;
        self.consent=[NSButton checkboxWithTitle:@"我已了解说明，并确认使用符合条件的免费项目" target:nil action:nil];self.consent.state=self.enabled.state;[stack addArrangedSubview:self.consent];
        self.accessStatus=Text(@"账户／模型访问：尚未测试",12,NSFontWeightMedium,Ink());self.generationStatus=Text(@"实际生成：尚未测试；可访问不代表能生成报告",12,NSFontWeightMedium,Ink());[stack addArrangedSubview:self.accessStatus];[stack addArrangedSubview:self.generationStatus];
        NSButton *test=Button(@"检查模型访问",self,@selector(test:),0),*text=Button(@"测试文本生成",self,@selector(testText:),0),*image=Button(@"测试图片生成",self,@selector(testImage:),0);[stack addArrangedSubview:[NSStackView stackViewWithViews:@[test,text,image]]];
        self.status=Text(@"",12,NSFontWeightRegular,Muted());self.status.maximumNumberOfLines=0;self.status.lineBreakMode=NSLineBreakByWordWrapping;self.status.selectable=YES;[stack addArrangedSubview:self.status];[self.status.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;[self updateUploads];
        self.progressView=[[AMOperationView alloc] initWithFrame:NSZeroRect];[self.progressView.heightAnchor constraintEqualToConstant:70].active=YES;[stack addArrangedSubview:self.progressView];[self.progressView.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;
        NSButton *cleanup=Button(@"清理上传副本",self,@selector(cleanup:),0),*terms=Button(@"服务说明",self,@selector(terms:),0),*studio=Button(@"获取自己的密钥…",self,@selector(studio:),0);[stack addArrangedSubview:[NSStackView stackViewWithViews:@[cleanup,terms,studio]]];
        NSButton *close=Button(@"取消",self,@selector(closeSettings:),0),*save=Button(@"保存",self,@selector(saveSettings:),1);NSStackView *footer=[NSStackView stackViewWithViews:@[close,save]];footer.spacing=12;footer.translatesAutoresizingMaskIntoConstraints=NO;[root addSubview:footer];[NSLayoutConstraint activateConstraints:@[[footer.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-24],[footer.bottomAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.bottomAnchor constant:-20],[form.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-16]]];close.keyEquivalent=@"\033";close.keyEquivalentModifierMask=0;save.keyEquivalent=@"\r";save.keyEquivalentModifierMask=0;
        self.actions=@[test,text,image,cleanup,catalog,save,self.enabled,self.consent,self.models];__weak typeof(self) owner=self;root.onAppearanceChange=^{AMRefreshViewAppearance(owner.window.contentView);};panel.onCancel=^{[owner closeSettings:nil];};panel.onConfirm=^{[owner saveSettings:nil];};
    }return self;
}
- (void)updateUploads{NSDictionary *counts=AMOnlineReviewUploadSummary();self.status.stringValue=[NSString stringWithFormat:@"可复用 %@ · 待清理 %@ · 已到期 %@。生成测试只发送合成样例，每次消耗1次本机额度。",counts[@"reusable"],counts[@"pending"],counts[@"expired"]];}
- (void)studio:(id)sender{[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://aistudio.google.com/apikey"]];}
- (void)terms:(id)sender{[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://ai.google.dev/gemini-api/terms"]];}
- (void)closeSettings:(id)sender{self.client.cancelled=YES;[NSApp stopModal];[self.window orderOut:nil];}
- (void)saveSettings:(id)sender{if(self.client)return;NSError *error=nil;if(self.enabled.state && !self.consent.state){self.status.stringValue=@"请先阅读并确认服务说明。";return;}if(!AMOnlineReviewSaveSettings(self.enabled.state==NSControlStateValueOn,self.keyField.stringValue,&error) || !AMOnlineReviewSelectModel(self.models.titleOfSelectedItem,&error)){self.status.stringValue=error.localizedDescription;return;}self.keyField.stringValue=@"";[self closeSettings:nil];}
- (void)test:(id)sender{[self run:@"access"];}
- (void)testText:(id)sender{[self run:@"text"];}
- (void)testImage:(id)sender{[self run:@"image"];}
- (void)loadModels:(id)sender{[self run:@"models"];}
- (void)cleanup:(id)sender{[self run:@"cleanup"];}
- (void)run:(NSString *)mode{if(self.client)return;BOOL generation=[@[@"text",@"image"] containsObject:mode];if(generation && !self.consent.state){self.status.stringValue=@"请先确认服务说明；测试仅发送合成样例，计入每日上限。";return;}
    self.client=AMOnlineReviewClient.new;AMOnlineReviewClient *client=self.client;client.model=self.models.titleOfSelectedItem;client.forceCleanup=YES;NSString *key=self.keyField.stringValue.copy;for(NSControl *control in self.actions)control.enabled=NO;self.keyField.enabled=NO;__weak AMOnlineReviewClient *weakClient=client;client.operationID=AMOperationBegin([mode isEqual:@"cleanup"] ? @"清理上传副本":@"在线服务测试",client.model,YES,^{weakClient.cancelled=YES;});self.progressView.operationID=client.operationID;__weak typeof(self) owner=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSError *error=nil;NSArray *models=nil;BOOL ok=NO;if([mode isEqual:@"models"]){models=[client modelsWithKey:key error:&error];ok=models!=nil;}else if([mode isEqual:@"cleanup"])ok=[client cleanupWithKey:key error:&error]==0;else if(generation)ok=[client testGenerationWithKey:key image:[mode isEqual:@"image"] error:&error];else ok=[client testConnectionWithKey:key error:&error];AMOperationFinish(client.operationID,ok ? @"success":@"failed",ok ? @"测试完成":error.localizedDescription ?: @"测试未完成");
        dispatch_async(dispatch_get_main_queue(),^{if(!owner)return;owner.client=nil;for(NSControl *control in owner.actions)control.enabled=YES;owner.keyField.enabled=YES;if(models){NSString *chosen=owner.models.titleOfSelectedItem;[owner.models removeAllItems];[owner.models addItemWithTitle:chosen];for(NSDictionary *row in models)if(![row[@"id"] isEqual:chosen])[owner.models addItemWithTitle:row[@"id"]];}
            if(generation)owner.generationStatus.stringValue=ok ? @"实际生成：合成样例成功（不代表真实作业复核质量）":@"实际生成：未完成";else if([mode isEqual:@"access"])owner.accessStatus.stringValue=ok ? @"账户／模型访问：可访问（尚不能证明生成可用）":@"账户／模型访问：未完成";[owner updateUploads];if(!ok){owner.status.stringValue=error.localizedDescription ?: @"操作未完成，可重试。";owner.status.textColor=NSColor.systemOrangeColor;}
        });
    });
}
@end
void AMShowOnlineReviewSettings(NSWindow *parent){AMOnlineSettings *settings=AMOnlineSettings.new;[settings.window center];[NSApp runModalForWindow:settings.window];[settings.window orderOut:nil];}
