#import "SSLocalData.h"
#import <objc/runtime.h>
@interface AMOperationView ()
@property NSProgressIndicator *bar;
@property NSTextField *stage;
@property NSTextField *amount;
@property NSButton *cancelButton;
@property NSTimer *timer;
@property NSPopover *detailPopover;
@end
@implementation AMOperationView
- (instancetype)initWithFrame:(NSRect)frame{if((self=[super initWithFrame:frame])){
    self.stage=Text(@"",13,NSFontWeightMedium,Ink());self.stage.lineBreakMode=NSLineBreakByWordWrapping;self.stage.maximumNumberOfLines=2;self.stage.selectable=YES;
    self.amount=Text(@"",11,NSFontWeightRegular,Muted());self.bar=NSProgressIndicator.new;self.bar.style=NSProgressIndicatorStyleBar;self.bar.minValue=0;self.bar.maxValue=1;self.cancelButton=Button(@"取消",self,@selector(cancelOperation:),0);
    for(NSView *child in @[self.stage,self.amount,self.bar,self.cancelButton]){child.translatesAutoresizingMaskIntoConstraints=NO;[self addSubview:child];}
    [self.cancelButton setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.cancelButton setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.stage setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.stage setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [NSLayoutConstraint activateConstraints:@[[self.stage.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],[self.stage.topAnchor constraintEqualToAnchor:self.topAnchor],[self.stage.trailingAnchor constraintEqualToAnchor:self.cancelButton.leadingAnchor constant:-8],[self.cancelButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],[self.cancelButton.topAnchor constraintEqualToAnchor:self.topAnchor],[self.bar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],[self.bar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],[self.bar.topAnchor constraintEqualToAnchor:self.topAnchor constant:36],[self.bar.heightAnchor constraintEqualToConstant:8],[self.amount.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],[self.amount.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],[self.amount.topAnchor constraintEqualToAnchor:self.bar.bottomAnchor constant:4],[self.amount.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor]]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:AMOperationsChanged object:nil];__weak typeof(self) owner=self;self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){[owner refresh];}];
}return self;}
- (BOOL)isFlipped{return YES;}
- (void)setOperationID:(NSString *)operationID{_operationID=operationID.copy;[self refresh];}

- (void)refresh{NSDictionary *row=nil;for(NSDictionary *candidate in AMOperations())if([candidate[@"id"] isEqual:self.operationID]){row=candidate;break;}if(!row){self.stage.stringValue=@"暂无后台操作";self.amount.stringValue=@"";self.bar.hidden=YES;self.cancelButton.hidden=YES;return;}
    BOOL running=[row[@"state"] isEqual:@"running"],queued=[row[@"state"] isEqual:@"queued"];self.stage.stringValue=[NSString stringWithFormat:@"%@%@",[row[@"target"] length] ? [row[@"target"] stringByAppendingString:@" · "]:@"",row[@"stage"]];self.stage.toolTip=self.stage.stringValue;self.stage.textColor=[row[@"state"] isEqual:@"failed"] ? NSColor.systemOrangeColor:Ink();NSInteger total=[row[@"total"] integerValue],done=[row[@"completed"] integerValue];self.bar.hidden=!running;self.bar.indeterminate=total<=0;if(total>0){[self.bar stopAnimation:nil];self.bar.doubleValue=MIN(1,(double)done/total);}else if(running)[self.bar startAnimation:nil];BOOL failed=[row[@"state"] isEqual:@"failed"];self.cancelButton.title=failed ? @"详情":(queued ? @"取消排队":@"终止当前步骤");self.cancelButton.action=failed ? @selector(showDetails:):@selector(cancelOperation:);self.cancelButton.hidden=(running || queued) ? ![row[@"cancellable"] boolValue]:!failed;NSTimeInterval seconds=-[row[@"started"] timeIntervalSinceNow];if(row[@"finished"])seconds=[row[@"finished"] timeIntervalSinceDate:row[@"started"]];self.amount.stringValue=[NSString stringWithFormat:queued ? @"%@等待 %.0f 秒":@"%@已用 %.0f 秒",total>0 ? [NSString stringWithFormat:@"%ld／%ld · ",(long)done,(long)total]:@"",MAX(0,seconds)];self.needsLayout=YES;
}
- (void)cancelOperation:(id)sender{AMOperationCancel(self.operationID);}
- (void)showDetails:(id)sender {
    NSString *message=self.stage.stringValue;NSViewController *controller=NSViewController.new;NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,480,280)];scroll.hasVerticalScroller=YES;scroll.autohidesScrollers=YES;
    NSTextView *text=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,480,280)];text.editable=NO;text.selectable=YES;text.font=[NSFont systemFontOfSize:13];text.textContainerInset=NSMakeSize(16,16);text.autoresizingMask=NSViewWidthSizable;text.textContainer.widthTracksTextView=YES;text.string=message;text.textColor=Ink();text.backgroundColor=NSColor.textBackgroundColor;scroll.documentView=text;controller.view=scroll;
    self.detailPopover=NSPopover.new;self.detailPopover.behavior=NSPopoverBehaviorTransient;self.detailPopover.contentViewController=controller;[self.detailPopover showRelativeToRect:self.cancelButton.bounds ofView:self.cancelButton preferredEdge:NSRectEdgeMaxY];
}
- (void)viewDidChangeEffectiveAppearance{[super viewDidChangeEffectiveAppearance];[self refresh];}
- (void)dealloc{[self.timer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
@end
@interface AMOperationsPanel:NSWindow
@property NSArray *identifiers;
@property NSScrollView *operationScroll;
@property NSTextField *summary;
@property NSButton *history;
@property BOOL showsHistory;
@end
@implementation AMOperationsPanel
- (instancetype)initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)mask backing:(NSBackingStoreType)backing defer:(BOOL)defer {
    if((self=[super initWithContentRect:rect styleMask:mask backing:backing defer:defer])) {
        self.title=@"后台任务";self.releasedWhenClosed=NO;self.contentMinSize=NSMakeSize(440,240);self.frameAutosaveName=@"AMOperationsWindow";
        Surface *root=Box(Canvas(),0);self.contentView=root;
        self.summary=Text(@"",13,NSFontWeightSemibold,Ink());Put(root,self.summary,20,16,NSWidth(root.bounds)-40,24);self.summary.autoresizingMask=NSViewWidthSizable;
        self.operationScroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,88,NSWidth(root.bounds),MAX(0,NSHeight(root.bounds)-88))];self.operationScroll.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;self.operationScroll.hasVerticalScroller=YES;self.operationScroll.autohidesScrollers=YES;self.operationScroll.drawsBackground=NO;[root addSubview:self.operationScroll];
        self.history=[NSButton buttonWithTitle:@"显示已完成记录" target:self action:@selector(toggleHistory:)];self.history.bezelStyle=NSBezelStyleRounded;Put(root,self.history,20,48,180,28);
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshRows) name:AMOperationsChanged object:nil];[self refreshRows];
    }return self;
}
- (void)refreshRows {
    NSArray *all=AMOperations();NSUInteger running=0,queued=0,failed=0,completed=0;for(NSDictionary *row in all){if([row[@"state"] isEqual:@"running"])running++;else if([row[@"state"] isEqual:@"queued"])queued++;else if([row[@"state"] isEqual:@"failed"])failed++;else completed++;}
    self.history.title=[NSString stringWithFormat:@"%@已完成记录（%lu）",self.showsHistory ? @"收起":@"显示",(unsigned long)completed];self.history.hidden=completed==0;
    NSMutableArray *rows=NSMutableArray.array;for(NSString *state in @[@"running",@"queued",@"failed"])for(NSDictionary *row in all)if([row[@"state"] isEqual:state])[rows addObject:row];if(self.showsHistory)for(NSDictionary *row in all)if(![@[@"running",@"queued",@"failed"] containsObject:row[@"state"]])[rows addObject:row];
    self.summary.stringValue=(running || queued) ? [NSString stringWithFormat:@"%lu 项进行中 · %lu 项排队 · %lu 项最近记录",(unsigned long)running,(unsigned long)queued,(unsigned long)(all.count-running-queued)]:[NSString stringWithFormat:@"暂无进行中的任务 · %lu 项最近记录%@",(unsigned long)all.count,failed ? [NSString stringWithFormat:@" · %lu 项未完成",(unsigned long)failed]:@""];
    NSMutableArray *identifiers=NSMutableArray.array;for(NSDictionary *row in rows)[identifiers addObject:[NSString stringWithFormat:@"%@/%@",row[@"id"],row[@"state"]]];if([identifiers isEqual:self.identifiers])return;self.identifiers=identifiers;
    NSScrollView *scroll=self.operationScroll;NSPoint position=scroll.contentView.bounds.origin;CGFloat width=MAX(400,scroll.contentSize.width);
    Surface *body=Box(nil,0);body.frame=NSMakeRect(0,0,width,MAX(120,rows.count*96+16));body.autoresizingMask=NSViewWidthSizable;
    for(NSUInteger i=0;i<rows.count;i++) {
        Surface *card=Box(nil,0);Put(body,card,16,8+i*96,width-32,88);card.autoresizingMask=NSViewWidthSizable;
        AMOperationView *progress=[[AMOperationView alloc] initWithFrame:NSMakeRect(12,10,width-56,68)];progress.autoresizingMask=NSViewWidthSizable;progress.operationID=rows[i][@"id"];[card addSubview:progress];[progress layoutSubtreeIfNeeded];
    }
    if(!rows.count)Put(body,Text(@"暂无进行中的操作",13,NSFontWeightRegular,Muted()),20,24,width-40,32);
    scroll.documentView=body;[scroll.contentView scrollToPoint:position];[scroll reflectScrolledClipView:scroll.contentView];
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
