#import "SSLocalData.h"
#import <objc/runtime.h>
@interface AMOperationView ()
@property NSProgressIndicator *bar;
@property NSTextField *stage;
@property NSTextField *amount;
@property NSButton *cancelButton;
@property NSTimer *timer;
@end
@implementation AMOperationView
- (instancetype)initWithFrame:(NSRect)frame{if((self=[super initWithFrame:frame])){
    self.stage=Text(@"",13,NSFontWeightMedium,Ink());self.stage.lineBreakMode=NSLineBreakByWordWrapping;self.stage.maximumNumberOfLines=2;self.stage.selectable=YES;[self addSubview:self.stage];
    self.amount=Text(@"",11,NSFontWeightRegular,Muted());[self addSubview:self.amount];self.bar=NSProgressIndicator.new;self.bar.style=NSProgressIndicatorStyleBar;self.bar.minValue=0;self.bar.maxValue=1;[self addSubview:self.bar];self.cancelButton=Button(@"取消",self,@selector(cancelOperation:),0);[self addSubview:self.cancelButton];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:AMOperationsChanged object:nil];__weak typeof(self) owner=self;self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){[owner refresh];}];
}return self;}
- (BOOL)isFlipped{return YES;}
- (void)setOperationID:(NSString *)operationID{_operationID=operationID.copy;[self refresh];}
- (void)layout{[super layout];CGFloat width=NSWidth(self.bounds);self.stage.frame=NSMakeRect(0,0,MAX(100,width-72),32);self.cancelButton.frame=NSMakeRect(width-64,0,64,28);self.bar.frame=NSMakeRect(0,36,width,8);self.amount.frame=NSMakeRect(0,48,width,18);}
- (void)refresh{NSDictionary *row=nil;for(NSDictionary *candidate in AMOperations())if([candidate[@"id"] isEqual:self.operationID]){row=candidate;break;}if(!row){self.stage.stringValue=@"暂无后台操作";self.amount.stringValue=@"";self.bar.hidden=YES;self.cancelButton.hidden=YES;return;}
    BOOL running=[row[@"state"] isEqual:@"running"];self.stage.stringValue=[NSString stringWithFormat:@"%@%@",[row[@"target"] length] ? [row[@"target"] stringByAppendingString:@" · "]:@"",row[@"stage"]];self.stage.textColor=[row[@"state"] isEqual:@"failed"] ? NSColor.systemOrangeColor:Ink();NSInteger total=[row[@"total"] integerValue],done=[row[@"completed"] integerValue];self.bar.hidden=!running;self.bar.indeterminate=total<=0;if(total>0){[self.bar stopAnimation:nil];self.bar.doubleValue=MIN(1,(double)done/total);}else if(running)[self.bar startAnimation:nil];self.cancelButton.hidden=!running || ![row[@"cancellable"] boolValue];NSTimeInterval seconds=-[row[@"started"] timeIntervalSinceNow];if(row[@"finished"])seconds=[row[@"finished"] timeIntervalSinceDate:row[@"started"]];self.amount.stringValue=[NSString stringWithFormat:@"%@已用 %.0f 秒",total>0 ? [NSString stringWithFormat:@"%ld／%ld · ",(long)done,(long)total]:@"",MAX(0,seconds)];self.needsLayout=YES;
}
- (void)cancelOperation:(id)sender{AMOperationCancel(self.operationID);}
- (void)viewDidChangeEffectiveAppearance{[super viewDidChangeEffectiveAppearance];[self refresh];}
- (void)dealloc{[self.timer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
@end
@interface AMOperationsPanel:NSWindow
@property NSArray *identifiers;
@end
@implementation AMOperationsPanel
- (instancetype)initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)mask backing:(NSBackingStoreType)backing defer:(BOOL)defer{if((self=[super initWithContentRect:rect styleMask:mask backing:backing defer:defer])){self.title=@"后台任务与进度";self.releasedWhenClosed=NO;NSScrollView *scroll=NSScrollView.new;scroll.hasVerticalScroller=YES;self.contentView=scroll;[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshRows) name:AMOperationsChanged object:nil];[self refreshRows];}return self;}
- (void)refreshRows{NSArray *rows=AMOperations();NSArray *identifiers=[rows valueForKey:@"id"];if([identifiers isEqual:self.identifiers])return;self.identifiers=identifiers;NSScrollView *scroll=(id)self.contentView;NSPoint position=scroll.contentView.bounds.origin;CGFloat width=MAX(300,scroll.contentSize.width);Surface *body=Box(Canvas(),0);body.frame=NSMakeRect(0,0,width,MAX(440,rows.count*88+24));body.autoresizingMask=NSViewWidthSizable;for(NSUInteger i=0;i<rows.count;i++){AMOperationView *progress=[[AMOperationView alloc] initWithFrame:NSMakeRect(16,16+i*88,width-32,72)];progress.autoresizingMask=NSViewWidthSizable;progress.operationID=rows[i][@"id"];[body addSubview:progress];}if(!rows.count)Put(body,Text(@"暂无后台操作。开始检查后可在这里查看进度。",13,NSFontWeightRegular,Muted()),16,16,width-32,32);scroll.documentView=body;[scroll.contentView scrollToPoint:position];}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
@end
void AMShowOperations(NSWindow *parent){static char key;NSWindow *window=objc_getAssociatedObject(NSApp,&key);if(!window){window=[[AMOperationsPanel alloc] initWithContentRect:NSMakeRect(0,0,660,480) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];[window center];objc_setAssociatedObject(NSApp,&key,window,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}[window makeKeyAndOrderFront:nil];}
void AMRefreshViewAppearance(NSView *root){
    if([root isKindOfClass:NSTextView.class]){NSTextView *text=(id)root;text.textColor=Ink();text.backgroundColor=Card();ThemeEditor(text);}
    else if([root isKindOfClass:NSTextField.class]){NSTextField *text=(id)root;if(text.editable)text.textColor=Ink();}
    if([root isKindOfClass:NSScrollView.class])[(NSScrollView *)root setBackgroundColor:Card()];root.needsDisplay=YES;for(NSView *child in root.subviews)AMRefreshViewAppearance(child);
}

@interface AMToolbarProgressView:NSView
@property NSButton *button;
@property NSProgressIndicator *bar;
@end
@implementation AMToolbarProgressView
- (instancetype)initWithFrame:(NSRect)frame{if((self=[super initWithFrame:frame])){self.button=[NSButton buttonWithTitle:@"后台任务" target:nil action:nil];self.button.bordered=NO;self.button.alignment=NSTextAlignmentRight;self.button.lineBreakMode=NSLineBreakByTruncatingMiddle;self.button.font=[NSFont systemFontOfSize:12];self.button.frame=NSMakeRect(0,8,250,24);[self addSubview:self.button];self.bar=NSProgressIndicator.new;self.bar.style=NSProgressIndicatorStyleBar;self.bar.frame=NSMakeRect(0,2,250,4);self.bar.maxValue=1;[self addSubview:self.bar];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:AMOperationsChanged object:nil];[self refresh];}return self;}
- (NSSize)intrinsicContentSize{return NSMakeSize(250,36);}
- (void)refresh{NSDictionary *active=nil;NSUInteger count=0;for(NSDictionary *row in AMOperations())if([row[@"state"] isEqual:@"running"]){if(!active)active=row;count++;}self.bar.hidden=!active;self.button.title=active ? [NSString stringWithFormat:@"%@ · %@",active[@"target"],active[@"stage"]]:@"后台任务";self.button.toolTip=active ? [NSString stringWithFormat:@"%lu 项后台操作 · %@",(unsigned long)count,self.button.title]:@"查看后台操作与进度";self.button.accessibilityLabel=self.button.toolTip;NSInteger total=[active[@"total"] integerValue];self.bar.indeterminate=total<=0;if(active && total<=0)[self.bar startAnimation:nil];else {[self.bar stopAnimation:nil];self.bar.doubleValue=total>0 ? [active[@"completed"] doubleValue]/total:0;}}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
@end
NSView *AMToolbarProgress(id target,SEL action){AMToolbarProgressView *view=[[AMToolbarProgressView alloc] initWithFrame:NSMakeRect(0,0,250,36)];view.button.target=target;view.button.action=action;return view;}
