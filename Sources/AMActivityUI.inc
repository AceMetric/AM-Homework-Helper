// A bounded, session-only presentation ledger. The operation scheduler remains
// the source of truth for running work; no message can unlock a safety check.
static NSString *const AMUIMessagesChanged=@"AMUIMessagesChanged";
static NSMutableSet *AMHiddenActivityOperations(void){static NSMutableSet *hidden;static dispatch_once_t once;dispatch_once(&once,^{hidden=NSMutableSet.set;});return hidden;}
static NSString *AMActivityOperationRevision(NSDictionary *row){return [NSString stringWithFormat:@"%@/%@",row[@"id"],row[@"state"]];}
static NSMutableArray<NSMutableDictionary *> *AMMessageLedger(void) {
    static NSMutableArray *rows;static dispatch_once_t once;dispatch_once(&once,^{rows=NSMutableArray.array;});return rows;
}
void AMPostUIMessage(NSString *scope,NSString *identifier,NSString *text,AMUIMessageSeverity severity,NSString *actionTitle,void (^action)(void)) {
    AMPostUIMessageWithRevision(scope,identifier,text,text,severity,actionTitle,action);
}
void AMPostUIMessageWithRevision(NSString *scope,NSString *identifier,NSString *revision,NSString *text,AMUIMessageSeverity severity,NSString *actionTitle,void (^action)(void)) {
    if(!text.length)return;
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{AMPostUIMessageWithRevision(scope,identifier,revision,text,severity,actionTitle,action);});return;}
    NSMutableArray *rows=AMMessageLedger();NSMutableDictionary *previous=nil;
    for(NSMutableDictionary *row in rows)if([row[@"scope"] isEqual:scope] && [row[@"id"] isEqual:identifier]){previous=row;break;}
    if([previous[@"revision"] isEqual:revision] && [previous[@"severity"] integerValue]==severity){if(action){previous[@"action"]=[action copy];previous[@"actionTitle"]=actionTitle ?: @"查看";}return;}
    if(previous)[rows removeObjectIdenticalTo:previous];
    NSMutableDictionary *row=[@{@"scope":scope ?: @"app",@"id":identifier ?: @"status",@"text":text,@"revision":revision ?: text,@"severity":@(severity),@"date":NSDate.date,@"dismissed":@NO} mutableCopy];
    if(action){row[@"action"]=[action copy];row[@"actionTitle"]=actionTitle ?: @"查看";}
    [rows insertObject:row atIndex:0];while(rows.count>48)[rows removeLastObject];
    [NSNotificationCenter.defaultCenter postNotificationName:AMUIMessagesChanged object:nil];
}
NSArray<NSDictionary *> *AMUIMessages(void){NSMutableArray *result=NSMutableArray.array;for(NSDictionary *row in AMMessageLedger())[result addObject:row.copy];return result.copy;}
void AMDismissUIMessage(NSString *scope,NSString *identifier){for(NSMutableDictionary *row in AMMessageLedger())if([row[@"scope"] isEqual:scope] && [row[@"id"] isEqual:identifier])row[@"dismissed"]=@YES;[NSNotificationCenter.defaultCenter postNotificationName:AMUIMessagesChanged object:nil];}

@interface AMActivityMessageRow:NSView
@property NSDictionary *message;
@end
@implementation AMActivityMessageRow
- (instancetype)initWithMessage:(NSDictionary *)message {
    if((self=[super initWithFrame:NSZeroRect])){
        self.message=message;NSStackView *row=NSStackView.new;row.spacing=8;row.alignment=NSLayoutAttributeTop;row.translatesAutoresizingMaskIntoConstraints=NO;[self addSubview:row];
        NSTextField *label=Text(message[@"text"],13,NSFontWeightRegular,Ink());label.maximumNumberOfLines=0;label.lineBreakMode=NSLineBreakByWordWrapping;label.selectable=YES;[label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];[row addArrangedSubview:label];
        if(message[@"action"]){NSButton *action=Button(message[@"actionTitle"],self,@selector(performMessageAction:),0);if([message[@"actionTitle"] isEqual:@"停止"])AMConfigureStopButton(action,@"停止");[row addArrangedSubview:action];}
        ActionButton *close=Button(@"",self,@selector(dismissMessage:),3);close.symbol=@"xmark";close.accessibilityLabel=@"关闭提示";[row addArrangedSubview:close];
        [NSLayoutConstraint activateConstraints:@[[row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],[row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],[row.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],[row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],[close.widthAnchor constraintGreaterThanOrEqualToConstant:24]]];
    }return self;
}
- (void)dismissMessage:(id)sender{AMDismissUIMessage(self.message[@"scope"],self.message[@"id"]);}
- (void)performMessageAction:(id)sender{void (^action)(void)=self.message[@"action"];if(action)action();}
@end

@interface AMActivityController:NSViewController
@property NSStackView *body;
@property NSArray *rowKeys;
@property NSScrollView *scroll;
@property NSButton *allButton;
@property(weak) NSPopover *popover;
@end
@implementation AMActivityController
- (void)loadView {
    Surface *root=Box(nil,0);root.frame=NSMakeRect(0,0,440,140);self.view=root;
    self.body=[NSStackView stackViewWithViews:@[]];self.body.orientation=NSUserInterfaceLayoutOrientationVertical;self.body.alignment=NSLayoutAttributeLeading;self.body.spacing=8;
    self.scroll=AMScrollableForm(self.body);[root addSubview:self.scroll];
    self.allButton=Button(@"查看全部后台任务…",self,@selector(showAll:),0);[self.allButton sizeToFit];[root addSubview:self.allButton];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:AMUIMessagesChanged object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:AMOperationsChanged object:nil];[self refresh];
}
- (void)refresh {
    NSMutableArray *messages=NSMutableArray.array,*operations=NSMutableArray.array,*keys=NSMutableArray.array;
    for(NSDictionary *message in AMUIMessages())if(![message[@"dismissed"] boolValue]){[messages addObject:message];[keys addObject:@[message[@"scope"],message[@"id"],message[@"date"]]];}
    for(NSDictionary *op in AMPresentedOperations())if([@[@"queued",@"running",@"failed"] containsObject:op[@"state"]] && ![AMHiddenActivityOperations() containsObject:AMActivityOperationRevision(op)]){[operations addObject:op];[keys addObject:@[op[@"id"],op[@"state"]]];}
    if([keys isEqual:self.rowKeys])return;self.rowKeys=keys;
    for(NSView *child in self.body.arrangedSubviews.copy){[self.body removeArrangedSubview:child];[child removeFromSuperview];}
    for(NSDictionary *op in operations){
        AMOperationView *view=[[AMOperationView alloc] initWithFrame:NSMakeRect(0,0,430,76)];view.operationID=op[@"id"];
        ActionButton *hide=Button(@"",self,@selector(hideOperation:),3);hide.symbol=@"xmark";hide.identifier=AMActivityOperationRevision(op);hide.accessibilityLabel=@"隐藏此操作的进度";
        NSStackView *row=[NSStackView stackViewWithViews:@[view,hide]];row.alignment=NSLayoutAttributeTop;row.spacing=8;[self.body addArrangedSubview:row];[row.widthAnchor constraintEqualToAnchor:self.body.widthAnchor].active=YES;[view.heightAnchor constraintEqualToConstant:76].active=YES;[row.heightAnchor constraintEqualToConstant:76].active=YES;[hide.widthAnchor constraintEqualToConstant:24].active=YES;[view.widthAnchor constraintEqualToAnchor:row.widthAnchor constant:-32].active=YES;
    }
    for(NSDictionary *message in messages){AMActivityMessageRow *view=[[AMActivityMessageRow alloc] initWithMessage:message];[self.body addArrangedSubview:view];[view.widthAnchor constraintEqualToAnchor:self.body.widthAnchor].active=YES;}
    if(!messages.count && !operations.count)[self.body addArrangedSubview:Text(@"暂无活动",13,NSFontWeightRegular,Muted())];
    // Size from the rows, never from the scroll view's previous viewport.
    CGFloat width=440,bodyWidth=width-32;
    self.scroll.frame=NSMakeRect(16,16,bodyWidth,300);
    [self.scroll layoutSubtreeIfNeeded];[self.body layoutSubtreeIfNeeded];
    CGFloat contentHeight=MAX(28,ceil(self.body.fittingSize.height));
    CGFloat visibleHeight=MIN(300,contentHeight),height=visibleHeight+68;
    self.preferredContentSize=NSMakeSize(width,height);self.view.frame=NSMakeRect(0,0,width,height);
    self.popover.contentSize=self.preferredContentSize;
    self.scroll.frame=NSMakeRect(16,16,bodyWidth,visibleHeight);
    self.allButton.frame=NSMakeRect(16,height-40,MIN(bodyWidth,self.allButton.fittingSize.width),28);
    [self.scroll layoutSubtreeIfNeeded];

}
- (void)hideOperation:(NSButton *)sender{[AMHiddenActivityOperations() addObject:sender.identifier];[NSNotificationCenter.defaultCenter postNotificationName:AMUIMessagesChanged object:nil];}
- (void)showAll:(id)sender{AMShowOperations(self.view.window);}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
@end
@interface AMActivityButton:NSButton
@property NSTimer *refreshTimer;
@property NSPopover *activityPopover;
@end
@implementation AMActivityButton
- (instancetype)initWithFrame:(NSRect)frame {
    if((self=[super initWithFrame:frame])){self.title=@"活动";self.bezelStyle=NSBezelStyleRounded;self.imagePosition=NSImageLeft;self.target=self;self.action=@selector(showActivity:);self.accessibilityLabel=@"活动与提示";[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:AMUIMessagesChanged object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:AMOperationsChanged object:nil];__weak typeof(self) owner=self;self.refreshTimer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){[owner refresh];}];[self refresh];}return self;
}
- (void)refresh {
    NSUInteger active=0;BOOL failed=NO;for(NSDictionary *op in AMPresentedOperations()){if([@[@"queued",@"running"] containsObject:op[@"state"]])active++;if([op[@"state"] isEqual:@"failed"] && ![AMHiddenActivityOperations() containsObject:AMActivityOperationRevision(op)])failed=YES;}
    NSDictionary *latest=nil,*warning=nil;for(NSDictionary *message in AMUIMessages())if(![message[@"dismissed"] boolValue]){if(!latest)latest=message;if(!warning && [message[@"severity"] integerValue]>=AMUIMessageWarning)warning=message;}
    BOOL recent=latest && [latest[@"severity"] integerValue]==AMUIMessageSuccess && -[latest[@"date"] timeIntervalSinceNow]<4;NSString *symbol=active ? @"arrow.triangle.2.circlepath":(failed || warning!=nil ? @"exclamationmark.circle":recent ? @"checkmark.circle":@"clock");
    self.image=[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];self.toolTip=active ? [NSString stringWithFormat:@"%lu 项后台操作",(unsigned long)active]:(warning[@"text"] ?: latest[@"text"] ?: @"活动与最近记录");self.accessibilityValue=self.toolTip;
}
- (void)showActivity:(id)sender{if(self.activityPopover.shown){[self.activityPopover close];return;}self.activityPopover=NSPopover.new;self.activityPopover.behavior=NSPopoverBehaviorTransient;AMActivityController *controller=AMActivityController.new;self.activityPopover.contentViewController=controller;controller.popover=self.activityPopover;self.activityPopover.contentSize=controller.preferredContentSize;[self.activityPopover showRelativeToRect:self.bounds ofView:self preferredEdge:NSRectEdgeMaxY];}
- (void)dealloc{[self.refreshTimer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
@end
NSToolbarItem *AMActivityToolbarItem(NSString *identifier){NSToolbarItem *item=[[NSToolbarItem alloc] initWithItemIdentifier:identifier];item.label=@"活动";item.visibilityPriority=NSToolbarItemVisibilityPriorityHigh;AMActivityButton *button=[[AMActivityButton alloc] initWithFrame:NSZeroRect];[button sizeToFit];item.view=button;NSMenuItem *overflow=[[NSMenuItem alloc] initWithTitle:@"活动与后台任务…" action:@selector(showAll:) keyEquivalent:@""];AMActivityController *controller=AMActivityController.new;objc_setAssociatedObject(item,@selector(showAll:),controller,OBJC_ASSOCIATION_RETAIN_NONATOMIC);overflow.target=controller;item.menuFormRepresentation=overflow;return item;}
