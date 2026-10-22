#import "SSLocalData.h"
#import "AMActivityPresentation.h"
#import <objc/runtime.h>
static NSMutableSet *AMHiddenActivityOperations(void){static NSMutableSet *hidden;static dispatch_once_t once;dispatch_once(&once,^{hidden=NSMutableSet.set;});return hidden;}
static NSArray *AMPresentedOperations(void){NSMutableArray *visible=NSMutableArray.array;for(NSDictionary *row in AMOperations())if(!row[@"parent"])[visible addObject:row];return visible;}
@interface AMOperationView ()
@property NSProgressIndicator *bar;
@property NSTextField *stage;
@property NSTextField *amount;
@property NSButton *heading;
@property NSStackView *textStack;
@property NSButton *cancelButton;
@property NSTimer *timer;
@property NSPopover *detailPopover;
@property NSDictionary *presentation;
@property(copy) void (^recovery)(void);
@property NSString *recoveryTitle;
@end
@implementation AMOperationView
@synthesize hidesCancellation=_hidesCancellation,showsHeading=_showsHeading,allowsDismissal=_allowsDismissal;
- (void)setHidesCancellation:(BOOL)hidden{_hidesCancellation=hidden;[self refresh];}
- (void)setShowsHeading:(BOOL)value{_showsHeading=value;[self refresh];}
- (void)setAllowsDismissal:(BOOL)value{_allowsDismissal=value;[self refresh];}
- (instancetype)initWithFrame:(NSRect)frame{if((self=[super initWithFrame:frame])){
    self.stage=Text(@"",13,NSFontWeightRegular,Ink());self.stage.lineBreakMode=NSLineBreakByWordWrapping;self.stage.maximumNumberOfLines=2;self.stage.selectable=YES;
    self.heading=[NSButton buttonWithTitle:@"" target:self action:@selector(showDetails:)];self.heading.bordered=NO;self.heading.alignment=NSTextAlignmentLeft;self.heading.font=[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];self.heading.lineBreakMode=NSLineBreakByTruncatingMiddle;self.heading.accessibilityLabel=@"活动详情";
    self.amount=Text(@"",11,NSFontWeightRegular,Muted());self.bar=NSProgressIndicator.new;self.bar.style=NSProgressIndicatorStyleBar;self.bar.minValue=0;self.bar.maxValue=1;
    self.cancelButton=Button(@"",self,@selector(cancelOperation:),3);self.cancelButton.translatesAutoresizingMaskIntoConstraints=NO;[self addSubview:self.cancelButton];
    self.textStack=[NSStackView stackViewWithViews:@[self.heading,self.stage,self.bar,self.amount]];self.textStack.orientation=NSUserInterfaceLayoutOrientationVertical;self.textStack.alignment=NSLayoutAttributeLeading;self.textStack.spacing=4;self.textStack.detachesHiddenViews=YES;self.textStack.translatesAutoresizingMaskIntoConstraints=NO;[self addSubview:self.textStack];
    for(NSView *view in @[self.heading,self.stage,self.amount,self.bar]){[view setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];[view.widthAnchor constraintEqualToAnchor:self.textStack.widthAnchor].active=YES;}
    [NSLayoutConstraint activateConstraints:@[[self.cancelButton.widthAnchor constraintEqualToConstant:28],[self.cancelButton.heightAnchor constraintEqualToConstant:28],[self.cancelButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],[self.cancelButton.topAnchor constraintEqualToAnchor:self.topAnchor],[self.textStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],[self.textStack.topAnchor constraintEqualToAnchor:self.topAnchor],[self.textStack.trailingAnchor constraintEqualToAnchor:self.cancelButton.leadingAnchor constant:-8],[self.textStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor],[self.bar.heightAnchor constraintEqualToConstant:8]]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:AMOperationsChanged object:nil];__weak typeof(self) owner=self;self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){[owner refresh];}];
}return self;}
- (BOOL)isFlipped{return YES;}
- (void)setOperationID:(NSString *)operationID{_operationID=operationID.copy;[self refresh];}
- (CGFloat)heightForWidth:(CGFloat)width {
    CGFloat textWidth=MAX(1,width-36);self.stage.preferredMaxLayoutWidth=textWidth;
    CGFloat phase=ceil([self.stage.stringValue boundingRectWithSize:NSMakeSize(textWidth,CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading attributes:@{NSFontAttributeName:self.stage.font}].size.height);
    phase=MIN(phase,ceil(self.stage.font.ascender-self.stage.font.descender+4)*self.stage.maximumNumberOfLines);
    return MAX(28,(_showsHeading ? 22:0)+MAX(17,phase)+(self.bar.hidden ? 0:12)+(self.amount.hidden ? 0:18));
}
- (void)layout{self.stage.preferredMaxLayoutWidth=MAX(1,NSWidth(self.bounds)-36);[super layout];}
- (void)refresh{
    NSDictionary *row=nil;for(NSDictionary *candidate in AMOperations())if([candidate[@"id"] isEqual:self.operationID]){row=candidate;break;}
    if(!row){self.stage.stringValue=@"暂无后台操作";self.amount.hidden=YES;self.bar.hidden=YES;self.heading.hidden=YES;self.cancelButton.hidden=YES;return;}
    NSDictionary *display=AMActivityPresentation(row);self.presentation=display;self.recovery=row[@"recovery"];self.recoveryTitle=row[@"recoveryTitle"];BOOL running=[row[@"state"] isEqual:@"running"],queued=[row[@"state"] isEqual:@"queued"];
    self.heading.title=display[@"heading"];self.heading.hidden=!self.showsHeading;self.heading.toolTip=display[@"heading"];
    self.stage.maximumNumberOfLines=self.showsHeading ? 3:2;self.stage.stringValue=self.showsHeading ? display[@"phase"]:[NSString stringWithFormat:@"%@ · %@",display[@"heading"],display[@"phase"]];self.stage.toolTip=self.stage.stringValue;self.stage.textColor=([row[@"state"] isEqual:@"failed"] || [row[@"warning"] boolValue]) ? NSColor.systemOrangeColor:Ink();
    NSInteger total=[row[@"total"] integerValue],done=[row[@"completed"] integerValue];self.bar.hidden=!running;self.bar.indeterminate=total<=0;if(total>0){[self.bar stopAnimation:nil];self.bar.doubleValue=MIN(1,(double)done/total);}else if(running)[self.bar startAnimation:nil];else [self.bar stopAnimation:nil];
    BOOL active=[display[@"active"] boolValue];self.cancelButton.title=@"";self.cancelButton.image=[NSImage imageWithSystemSymbolName:active ? @"stop.circle":@"xmark" accessibilityDescription:nil];self.cancelButton.imagePosition=NSImageOnly;self.cancelButton.toolTip=display[@"action"];self.cancelButton.accessibilityLabel=display[@"action"];self.cancelButton.action=active ? @selector(cancelOperation:):@selector(dismissOperation:);self.cancelButton.hidden=self.hidesCancellation || (active ? ![display[@"action"] length]:!self.allowsDismissal);if(!self.showsHeading && !self.allowsDismissal && [row[@"state"] isEqual:@"failed"] && !self.hidesCancellation){self.cancelButton.hidden=NO;self.cancelButton.image=[NSImage imageWithSystemSymbolName:@"info.circle" accessibilityDescription:nil];self.cancelButton.toolTip=@"详情";self.cancelButton.accessibilityLabel=@"详情";self.cancelButton.action=@selector(showDetails:);}
    NSDate *start=row[@"started"] ?: NSDate.date;NSTimeInterval seconds=row[@"finished"] ? [row[@"finished"] timeIntervalSinceDate:start]:-[start timeIntervalSinceNow];self.amount.hidden=NO;self.amount.stringValue=[NSString stringWithFormat:queued ? @"%@等待 %.0f 秒":@"%@已用 %.0f 秒",total>0 ? [NSString stringWithFormat:@"%ld／%ld · ",(long)done,(long)total]:@"",MAX(0,seconds)];self.needsLayout=YES;
}
- (void)cancelOperation:(id)sender{AMOperationCancel(self.operationID);}
- (void)dismissOperation:(id)sender{for(NSDictionary *row in AMOperations())if([row[@"id"] isEqual:self.operationID] && ![@[@"running",@"queued"] containsObject:row[@"state"]]){[AMHiddenActivityOperations() addObject:self.operationID];[NSNotificationCenter.defaultCenter postNotificationName:AMOperationsChanged object:nil];break;}}
- (void)showDetails:(id)sender {
    NSViewController *controller=NSViewController.new;NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,420,240)];scroll.hasVerticalScroller=YES;scroll.autohidesScrollers=YES;
    NSTextView *text=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,420,240)];text.editable=NO;text.selectable=YES;text.font=[NSFont systemFontOfSize:13];text.textContainerInset=NSMakeSize(12,12);text.autoresizingMask=NSViewWidthSizable;text.textContainer.widthTracksTextView=YES;text.string=self.presentation[@"details"] ?: @"";text.textColor=Ink();text.backgroundColor=NSColor.textBackgroundColor;scroll.documentView=text;controller.view=scroll;
    if(self.recovery){NSView *root=[[NSView alloc] initWithFrame:NSMakeRect(0,0,420,280)];scroll.frame=NSMakeRect(0,40,420,240);[root addSubview:scroll];NSButton *button=[NSButton buttonWithTitle:self.recoveryTitle ?: @"查看" target:self action:@selector(recover:)];button.bezelStyle=NSBezelStyleRounded;button.frame=NSMakeRect(12,6,160,28);[root addSubview:button];controller.view=root;}
    self.detailPopover=NSPopover.new;self.detailPopover.behavior=NSPopoverBehaviorTransient;self.detailPopover.contentViewController=controller;NSView *anchor=self.heading.hidden ? self.stage:self.heading;[self.detailPopover showRelativeToRect:anchor.bounds ofView:anchor preferredEdge:NSRectEdgeMaxY];
}
- (void)recover:(id)sender{[self.detailPopover close];if(self.recovery)self.recovery();}
- (void)viewDidChangeEffectiveAppearance{[super viewDidChangeEffectiveAppearance];[self refresh];}
- (void)dealloc{[self.timer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
@end
@interface AMOperationsPanel:NSWindow
@property NSArray *identifiers;
@property NSScrollView *operationScroll;
@property NSTextField *summary;
@property NSButton *history;
@property BOOL showsHistory;
@property NSMutableDictionary<NSString *,AMOperationView *> *rowViews;
@end
@implementation AMOperationsPanel
- (instancetype)initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)mask backing:(NSBackingStoreType)backing defer:(BOOL)defer {
    if((self=[super initWithContentRect:rect styleMask:mask backing:backing defer:defer])) {
        self.title=@"后台任务";self.releasedWhenClosed=NO;self.contentMinSize=NSMakeSize(440,240);self.frameAutosaveName=@"AMOperationsWindow";
        Surface *root=Box(Canvas(),0);self.contentView=root;__weak typeof(self) owner=self;root.onResize=^{owner.identifiers=nil;[owner refreshRows];};
        self.summary=Text(@"",13,NSFontWeightSemibold,Ink());Put(root,self.summary,20,16,NSWidth(root.bounds)-40,24);self.summary.autoresizingMask=NSViewWidthSizable;
        self.operationScroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,88,NSWidth(root.bounds),MAX(0,NSHeight(root.bounds)-88))];self.operationScroll.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;self.operationScroll.hasVerticalScroller=YES;self.operationScroll.autohidesScrollers=YES;self.operationScroll.drawsBackground=NO;[root addSubview:self.operationScroll];
        self.history=[NSButton buttonWithTitle:@"显示已完成记录" target:self action:@selector(toggleHistory:)];self.history.bezelStyle=NSBezelStyleRounded;Put(root,self.history,20,48,180,28);
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshRows) name:AMOperationsChanged object:nil];[self refreshRows];
    }return self;
}
- (void)refreshRows {
    NSArray *all=AMPresentedOperations();NSUInteger running=0,queued=0,failed=0,completed=0;for(NSDictionary *row in all){if([row[@"state"] isEqual:@"running"])running++;else if([row[@"state"] isEqual:@"queued"])queued++;else if([row[@"state"] isEqual:@"failed"])failed++;else completed++;}
    self.history.title=[NSString stringWithFormat:@"%@历史记录（%lu）",self.showsHistory ? @"收起":@"显示",(unsigned long)(completed+failed)];self.history.hidden=(completed+failed)==0;
    NSMutableArray *rows=NSMutableArray.array;for(NSString *state in @[@"running",@"queued",@"failed"])for(NSDictionary *row in all)if([row[@"state"] isEqual:state] && ![AMHiddenActivityOperations() containsObject:row[@"id"]])[rows addObject:row];if(self.showsHistory)for(NSDictionary *row in all)if(![@[@"running",@"queued"] containsObject:row[@"state"]] && ![rows containsObject:row])[rows addObject:row];
    NSMutableArray *parts=NSMutableArray.array;if(running)[parts addObject:[NSString stringWithFormat:@"%lu 项进行中",(unsigned long)running]];if(queued)[parts addObject:[NSString stringWithFormat:@"%lu 项排队",(unsigned long)queued]];if(failed)[parts addObject:[NSString stringWithFormat:@"%lu 项未完成",(unsigned long)failed]];self.summary.stringValue=parts.count ? [parts componentsJoinedByString:@" · "]:@"暂无进行中的任务";
    NSMutableArray *identifiers=NSMutableArray.array;for(NSDictionary *row in rows)[identifiers addObject:[NSString stringWithFormat:@"%@/%@",row[@"id"],row[@"stage"]]];if([identifiers isEqual:self.identifiers])return;self.identifiers=identifiers;
    NSScrollView *scroll=self.operationScroll;NSPoint position=scroll.contentView.bounds.origin;CGFloat width=MAX(400,scroll.contentSize.width);
    Surface *body=(id)scroll.documentView;if(!body){body=Box(nil,0);body.autoresizingMask=NSViewWidthSizable;scroll.documentView=body;}if(!self.rowViews)self.rowViews=NSMutableDictionary.dictionary;
    NSMutableSet *wanted=NSMutableSet.set;for(NSDictionary *row in rows)[wanted addObject:row[@"id"]];for(NSString *key in self.rowViews.allKeys.copy)if(![wanted containsObject:key]){[self.rowViews[key] removeFromSuperview];[self.rowViews removeObjectForKey:key];}
    for(NSView *view in body.subviews.copy)if([view.identifier isEqual:@"operations-empty"])[view removeFromSuperview];
    CGFloat y=12;for(NSDictionary *row in rows){NSString *key=row[@"id"];AMOperationView *progress=self.rowViews[key];if(!progress){progress=AMOperationView.new;progress.showsHeading=YES;progress.allowsDismissal=YES;progress.operationID=key;self.rowViews[key]=progress;[body addSubview:progress];}[progress refresh];CGFloat height=[progress heightForWidth:width-40];progress.frame=NSMakeRect(20,y,width-40,height);y+=height+16;}
    body.frame=NSMakeRect(0,0,width,MAX(80,y));if(!rows.count){NSTextField *empty=Text(@"暂无进行中的操作",13,NSFontWeightRegular,Muted());empty.identifier=@"operations-empty";Put(body,empty,20,24,width-40,32);}
    [scroll.contentView scrollToPoint:NSMakePoint(position.x,MIN(position.y,MAX(0,NSHeight(body.frame)-scroll.contentSize.height)))];[scroll reflectScrolledClipView:scroll.contentView];
}
- (void)toggleHistory:(id)sender{self.showsHistory=!self.showsHistory;self.identifiers=nil;[self refreshRows];}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
@end
void AMShowOperations(NSWindow *parent){static char key;NSWindow *window=objc_getAssociatedObject(NSApp,&key);if(!window){window=[[AMOperationsPanel alloc] initWithContentRect:NSMakeRect(0,0,600,340) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];[window center];objc_setAssociatedObject(NSApp,&key,window,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}[window makeKeyAndOrderFront:nil];}
void AMRefreshViewAppearance(NSView *root){
    if([root isKindOfClass:NSTextView.class]){NSTextView *text=(id)root;text.textColor=Ink();text.backgroundColor=Card();ThemeEditor(text);}
    else if([root isKindOfClass:NSTextField.class]){NSTextField *text=(id)root;if(text.editable)text.textColor=Ink();}
    if([root isKindOfClass:NSScrollView.class])[(NSScrollView *)root setBackgroundColor:Card()];root.needsDisplay=YES;for(NSView *child in root.subviews)AMRefreshViewAppearance(child);
}
