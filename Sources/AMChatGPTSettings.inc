// All account/keychain/network work runs off the UI thread. This form only
// displays sanitized account metadata and starts explicit user-authorized actions.
@interface AMChatGPTSettings:NSWindowController <NSWindowDelegate>
@property NSPopUpButton *accounts,*recognitionModel,*reviewModel;
@property NSTextField *status,*hourly,*concurrency;
@property NSButton *recognitionConsent;
@property NSArray *catalog;
@property NSUInteger refreshGeneration,modelGeneration;
@end
@implementation AMChatGPTSettings
- (instancetype)init {
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,680,530) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];window.releasedWhenClosed=NO;window.title=@"ChatGPT 登录与模型";
    if((self=[super initWithWindow:window])){window.delegate=self;
        NSStackView *stack=NSStackView.new;stack.orientation=NSUserInterfaceLayoutOrientationVertical;stack.alignment=NSLayoutAttributeLeading;stack.spacing=12;stack.translatesAutoresizingMaskIntoConstraints=NO;[window.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:24],[stack.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor constant:-24],[stack.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:24]]];
        [stack addArrangedSubview:Text(@"使用自己的 ChatGPT 套餐",20,NSFontWeightSemibold,Ink())];
        [stack addArrangedSubview:[NSStackView stackViewWithViews:@[Button(@"Continue with ChatGPT",self,@selector(signIn:),0),Button(@"取消登录",self,@selector(cancelLogin:),0),Button(@"断开连接",self,@selector(signOut:),0)]]];
        self.accounts=NSPopUpButton.new;self.accounts.target=self;self.accounts.action=@selector(selectAccount:);[stack addArrangedSubview:self.accounts];
        self.status=Text(@"正在读取连接状态…",13,NSFontWeightRegular,Muted());self.status.maximumNumberOfLines=3;[stack addArrangedSubview:self.status];
        self.recognitionModel=NSPopUpButton.new;self.reviewModel=NSPopUpButton.new;
        [stack addArrangedSubview:[NSStackView stackViewWithViews:@[Text(@"识别与要求提炼",13,NSFontWeightRegular,Ink()),self.recognitionModel]]];
        [stack addArrangedSubview:[NSStackView stackViewWithViews:@[Text(@"作业内容检查",13,NSFontWeightRegular,Ink()),self.reviewModel,Button(@"刷新可用模型",self,@selector(loadModels:),0)]]];
        self.hourly=NSTextField.new;self.hourly.stringValue=@"60";self.concurrency=NSTextField.new;self.concurrency.stringValue=@"2";[self.hourly.widthAnchor constraintEqualToConstant:80].active=YES;[self.concurrency.widthAnchor constraintEqualToConstant:60].active=YES;
        [stack addArrangedSubview:[NSStackView stackViewWithViews:@[Text(@"每小时最多",13,NSFontWeightRegular,Ink()),self.hourly,Text(@"次，并发",13,NSFontWeightRegular,Ink()),self.concurrency]]];
        self.recognitionConsent=[NSButton checkboxWithTitle:@"使用 ChatGPT 识别课程原文（仍需课程授权）" target:nil action:nil];self.recognitionConsent.state=[SSRecognitionSettings()[@"mode"] isEqual:@"chatgpt"];[stack addArrangedSubview:self.recognitionConsent];
        NSTextField *policy=Text(@"识别默认 Luna，内容检查默认 Terra。普通浏览不发送材料。小时上限由 AM Helper 管理，官方套餐额度另外生效；不会自动切换付费服务。",12,NSFontWeightRegular,Muted());policy.maximumNumberOfLines=0;[stack addArrangedSubview:policy];[policy.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;
        [stack addArrangedSubview:[NSStackView stackViewWithViews:@[Button(@"保存并用于 AI 检查",self,@selector(save:),1),Button(@"管理官方用量",self,@selector(manageUsage:),0),Button(@"完成",self,@selector(closeSettings:),0)]]];
        [self refresh];
    }return self;
}
- (void)refresh {
    NSUInteger generation=++self.refreshGeneration;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSDictionary *status=AMChatGPTStatus(),*preferences=SSReadPlist(@"chatgpt-preferences.plist") ?: @{};NSDictionary *cached=SSReadPlist(@"chatgpt-models.plist") ?: @{};
        dispatch_async(dispatch_get_main_queue(),^{if(generation!=self.refreshGeneration)return;[self.accounts removeAllItems];[self.accounts addItemWithTitle:@"添加新账号／工作区"];for(NSDictionary *account in status[@"accounts"]){[self.accounts addItemWithTitle:account[@"label"]];self.accounts.lastItem.representedObject=account[@"id"];if([account[@"id"] isEqual:status[@"active"]])[self.accounts selectItem:self.accounts.lastItem];}
            self.status.stringValue=[NSString stringWithFormat:@"%@ · 最近一小时 %@/%@ 次",[status[@"connected"] boolValue] ? @"ChatGPT 套餐已连接":@"尚未连接或授权套餐用量",status[@"used"],status[@"hourlyLimit"]];self.hourly.stringValue=[status[@"hourlyLimit"] description];self.concurrency.stringValue=[status[@"concurrency"] description];self.catalog=[cached[@"registration"] isEqual:AMChatGPTProfile(@"recognition")[@"registration"]] ? (cached[@"models"] ?: @[]):@[];[self populateModels:preferences];});});
}
- (void)populateModels:(NSDictionary *)preferences {
    for(NSPopUpButton *picker in @[self.recognitionModel,self.reviewModel]){BOOL recognition=picker==self.recognitionModel;[picker removeAllItems];[picker addItemWithTitle:recognition ? @"自动选择 · Luna / low":@"自动选择 · Terra / medium"];picker.lastItem.representedObject=@"";NSString *selected=preferences[recognition ? @"recognitionModel":@"reviewModel"];
        BOOL found=!selected.length;
        for(NSDictionary *model in self.catalog){[picker addItemWithTitle:model[@"name"]];picker.lastItem.representedObject=model[@"id"];if([model[@"id"] isEqual:selected]){[picker selectItem:picker.lastItem];found=YES;}}
        // Keep an explicit unavailable override visible rather than silently showing Auto.
        if(!found){[picker addItemWithTitle:[selected stringByAppendingString:@" · 当前不可用"]];picker.lastItem.representedObject=selected;[picker selectItem:picker.lastItem];}
    }
}
- (void)signIn:(id)sender {NSString *account=self.accounts.selectedItem.representedObject;self.status.stringValue=@"请在浏览器完成 ChatGPT 登录和套餐授权。";AMChatGPTSignIn(account,^(NSError *error){if(error)self.status.stringValue=error.localizedDescription;else{[self refresh];[self loadModels:nil];}});}
- (void)cancelLogin:(id)sender{AMChatGPTCancelSignIn();self.status.stringValue=@"正在取消登录…";}
- (void)selectAccount:(id)sender{NSString *identifier=self.accounts.selectedItem.representedObject;if(!identifier)return;dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSError *error=nil;BOOL ok=AMChatGPTSelectAccount(identifier,&error);dispatch_async(dispatch_get_main_queue(),^{if(ok){[self refresh];[self loadModels:nil];}else self.status.stringValue=error.localizedDescription;});});}
- (void)signOut:(id)sender{dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSError *error=nil;BOOL ok=AMChatGPTSignOut(&error);dispatch_async(dispatch_get_main_queue(),^{[self refresh];if(!ok)self.status.stringValue=error.localizedDescription;});});}
- (void)loadModels:(id)sender {NSUInteger generation=++self.modelGeneration;NSString *registration=AMChatGPTProfile(@"recognition")[@"registration"];self.status.stringValue=@"正在获取当前账号可用模型…";dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSError *error=nil;NSArray *models=AMChatGPTModels(&error);NSDictionary *preferences=SSReadPlist(@"chatgpt-preferences.plist") ?: @{};dispatch_async(dispatch_get_main_queue(),^{if(generation!=self.modelGeneration || ![registration isEqual:AMChatGPTProfile(@"recognition")[@"registration"]])return;if(!models){self.status.stringValue=error.localizedDescription;return;}self.catalog=models;[self populateModels:preferences];self.status.stringValue=@"模型目录已更新；实际请求仍需账号具备相应权限。";});});}
- (void)save:(id)sender {
    NSInteger limit=self.hourly.integerValue,parallel=self.concurrency.integerValue;NSDictionary *preferences=@{@"hourlyLimit":@(MAX(0,limit)),@"concurrency":@(MAX(0,parallel)),@"recognitionModel":self.recognitionModel.selectedItem.representedObject ?: @"",@"reviewModel":self.reviewModel.selectedItem.representedObject ?: @""};BOOL recognize=self.recognitionConsent.state==NSControlStateValueOn;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSError *error=nil;BOOL ok=AMChatGPTSavePreferences(preferences,&error);if(ok && ![AMChatGPTStatus()[@"connected"] boolValue]){ok=NO;error=[NSError errorWithDomain:@"AMChatGPT" code:401 userInfo:@{NSLocalizedDescriptionKey:@"请先完成 ChatGPT 登录并授权套餐用量。"}];}
        if(ok){NSDictionary *old=AMOnlineReviewSettings();if(![old[@"provider"] isEqual:@"chatgpt"]){NSMutableDictionary *saved=[SSReadPlist(@"online-provider-history.plist") mutableCopy] ?: NSMutableDictionary.dictionary;saved[old[@"provider"] ?: @"gemini"]=old;ok=SSWritePlist(@"online-provider-history.plist",saved,&error);}if(ok)ok=SSWritePlist(@"online-review-settings.plist",@{@"provider":@"chatgpt",@"enabled":@YES},&error);}
        if(ok && recognize){NSMutableDictionary *settings=SSRecognitionSettings().mutableCopy;if(![settings[@"mode"] isEqual:@"chatgpt"])SSWritePlist(@"recognition-before-chatgpt.plist",settings,NULL);settings[@"mode"]=@"chatgpt";settings[@"cloudConsent"]=@YES;ok=SSWritePlist(@"recognition-settings.plist",settings,&error);}
        else if(ok && [SSRecognitionSettings()[@"mode"] isEqual:@"chatgpt"]){NSDictionary *before=SSReadPlist(@"recognition-before-chatgpt.plist") ?: @{@"mode":@"rules"};ok=SSWritePlist(@"recognition-settings.plist",before,&error);}
        dispatch_async(dispatch_get_main_queue(),^{self.status.stringValue=ok ? @"已保存。作业材料仍在每次检查前确认。":error.localizedDescription;});
    });
}
- (void)closeSettings:(id)sender{[self.window close];}
- (void)windowWillClose:(NSNotification *)note{self.refreshGeneration++;self.modelGeneration++;AMChatGPTCancelSignIn();if(NSApp.modalWindow==self.window)[NSApp stopModal];}
- (void)manageUsage:(id)sender{[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://chatgpt.com/settings/usage"]];}
@end
