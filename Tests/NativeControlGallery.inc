// Local interactive gallery. Actual Liquid Glass appearance is reviewed by the user.
@interface AMNativeControlGallery:NSWindowController
@property NSTextField *selectionLabel;
@end
@implementation AMNativeControlGallery
- (instancetype)init {
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,820,600) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    if((self=[super initWithWindow:window])){
        window.title=@"原生控件样例";window.releasedWhenClosed=NO;window.contentMinSize=NSMakeSize(680,480);Surface *root=Box(Canvas(),0);window.contentView=root;
        NSStackView *stack=NSStackView.new;stack.orientation=NSUserInterfaceLayoutOrientationVertical;stack.alignment=NSLayoutAttributeLeading;stack.spacing=20;stack.translatesAutoresizingMaskIntoConstraints=NO;[root addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:28],[stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-28],[stack.topAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.topAnchor constant:24],[stack.bottomAnchor constraintLessThanOrEqualToAnchor:root.safeAreaLayoutGuide.bottomAnchor constant:-24]]];
        [stack addArrangedSubview:Text(@"系统导航与操作控件",22,NSFontWeightSemibold,Ink())];
        NSTextField *hint=Text(@"请切换每个选项，尤其是中间项；系统外观和窗口激活状态会影响材质。",13,NSFontWeightRegular,Muted());hint.maximumNumberOfLines=2;hint.lineBreakMode=NSLineBreakByWordWrapping;[stack addArrangedSubview:hint];
        for(NSArray *titles in @[@[@"今日",@"本周"],@[@"课程内容",@"已加入任务",@"仓库信息",@"提交记录"]]){
            ThemeSegmentedControl *tabs=Segments(titles,self,@selector(changed:));tabs.selectedSegment=titles.count==4 ? 1:0;tabs.accessibilityLabel=@"导航控件样例";[stack addArrangedSubview:tabs];
        }
        self.selectionLabel=Text(@"课程导航当前选中：已加入任务",13,NSFontWeightRegular,Ink());[stack addArrangedSubview:self.selectionLabel];
        NSSlider *slider=[NSSlider sliderWithValue:0.55 minValue:0 maxValue:1 target:nil action:nil];slider.controlSize=NSControlSizeLarge;slider.accessibilityLabel=@"系统滑块样例";[stack addArrangedSubview:slider];[slider.widthAnchor constraintEqualToConstant:360].active=YES;
        NSSearchField *search=NSSearchField.new;search.placeholderString=@"系统搜索框样例";[stack addArrangedSubview:search];[search.widthAnchor constraintEqualToConstant:360].active=YES;
        NSStackView *actions=[NSStackView stackViewWithViews:@[Button(@"主要操作",self,@selector(action:),1),Button(@"次要操作",self,@selector(action:),0)]];actions.spacing=12;[stack addArrangedSubview:actions];
        [stack addArrangedSubview:Text(@"模拟数据预览，不保存任务、不访问课程或凭据。",12,NSFontWeightRegular,Muted())];[window center];
    }return self;
}
- (void)changed:(NSSegmentedControl *)sender{self.selectionLabel.stringValue=[@"当前选中：" stringByAppendingString:[sender labelForSegment:sender.selectedSegment]];}
- (void)action:(id)sender{self.selectionLabel.stringValue=@"按钮已响应（模拟操作）";}
@end
