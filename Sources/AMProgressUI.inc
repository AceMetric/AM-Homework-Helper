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
void AMShowOperations(NSWindow *parent){static char key;NSWindow *previous=objc_getAssociatedObject(NSApp,&key);[previous orderOut:nil];NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,660,480) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];window.title=@"后台任务与进度";window.releasedWhenClosed=NO;NSScrollView *scroll=NSScrollView.new;scroll.hasVerticalScroller=YES;scroll.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;window.contentView=scroll;Surface *body=Box(Canvas(),0);NSArray *rows=AMOperations();body.frame=NSMakeRect(0,0,640,MAX(440,rows.count*88+24));for(NSUInteger i=0;i<rows.count;i++){AMOperationView *progress=[[AMOperationView alloc] initWithFrame:NSMakeRect(16,16+i*88,608,72)];progress.autoresizingMask=NSViewWidthSizable;progress.operationID=rows[i][@"id"];[body addSubview:progress];}scroll.documentView=body;[window center];[window makeKeyAndOrderFront:nil];objc_setAssociatedObject(NSApp,&key,window,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
void AMRefreshViewAppearance(NSView *root){
    if([root isKindOfClass:NSTextView.class]){NSTextView *text=(id)root;text.textColor=Ink();text.backgroundColor=Card();ThemeEditor(text);}
    else if([root isKindOfClass:NSTextField.class]){NSTextField *text=(id)root;if(text.editable)text.textColor=Ink();}
    if([root isKindOfClass:NSScrollView.class])[(NSScrollView *)root setBackgroundColor:Card()];root.needsDisplay=YES;for(NSView *child in root.subviews)AMRefreshViewAppearance(child);
}
