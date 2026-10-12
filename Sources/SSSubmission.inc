#import "AMPreflight.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "AMPreflightUI.inc"
#import "AMOnlineReviewUI.inc"
static NSDictionary *PFEffectiveReview(NSString *version){for(NSDictionary *job in [AMPreflightJobs() reverseObjectEnumerator])if([job[@"reportVersion"] isEqual:version] && job[@"result"] && ![job[@"cleaned"] boolValue])return job[@"result"];return nil;}
// Private sheet, shared controls. Only the captured course and selected paths leave this UI.
@interface SSSubmissionController : NSWindowController <NSTableViewDataSource,NSTableViewDelegate,NSTextViewDelegate>
@property NSArray *changes;
@property NSArray<NSButton *> *checks;
@property NSTextField *message;
@property NSArray<NSButton *> *taskChecks;
@property NSArray *taskIDs;
@property NSTextField *validation;
@property NSTextField *filesValidation;
@property NSTextField *checkValidation;
@property NSTextView *preview;
@property (copy) void (^readPreview)(NSString *, void (^)(NSString *));
@property (copy) void (^submit)(NSArray *, NSString *);
@property NSUInteger previewGeneration;
@property NSDictionary *course;
@property NSDictionary *snapshot;
@property NSDictionary *report;
@property NSDictionary *reviewSummary;
@property NSMutableDictionary *checkCache;
@property NSString *requirements;
@property NSTextView *supplement;
@property NSTextView *coverage;
@property NSTextView *findingDetail;
@property NSTableView *findingsTable;
@property PFImageView *findingImage;
@property NSButton *acknowledge;
@property NSButton *primary;
@property NSButton *filesPrimary;
@property NSButton *assistantButton;
@property NSButton *onlineButton;
@property AMOnlineReviewClient *onlineClient;
@property NSDictionary *onlineFocus;
#ifdef DDL_TESTING
@property(copy) AMOnlineReviewClient *(^onlineClientFactory)(void);
#endif
@property Surface *checkPage;
@property NSArray *findings;
@property NSArray *selectedPaths;
@property NSTimer *resultTimer;
@property BOOL checkOnly;
@property(copy) void (^backToScope)(void);
@property NSDictionary *reportFrames;
@property BOOL checking;
@property BOOL reportStale;
@property BOOL closed;
@property BOOL finalValidation;
@property NSString *assistantFingerprint;
@property(copy) NSDictionary *(^performCheck)(NSArray *,NSArray *,NSString *,NSMutableDictionary *,BOOL(^)(void),NSError **);
- (void)buildCheckPage;
- (void)checkNow:(id)sender;
- (void)layoutReport;
- (void)backToFiles:(id)sender;
- (void)refreshReport;
- (void)onlineReview:(id)sender;
- (void)onlineSettings:(id)sender;
- (void)reviewDoubt:(id)sender;
- (void)importAssistantResult:(id)sender;
- (void)pollReview:(id)sender;
- (BOOL)hasUnsavedChanges;
- (BOOL)saveForExit;
- (instancetype)initWithCourse:(NSDictionary *)course changes:(NSArray *)changes;
@end
@implementation SSSubmissionController
- (void)layoutReport {
    if(!self.reportFrames)return;CGFloat w=NSWidth(self.checkPage.bounds),h=NSHeight(self.checkPage.bounds),width=w-48;BOOL narrow=w<740;CGFloat bottom=h-188,body=MAX(120,bottom-264),left=floor((width-16)*.46);
    for(NSView *view in self.checkPage.subviews){NSRect f=[self.reportFrames[view.identifier] rectValue];
        if(f.origin.y>=536){f.origin.y+=h-676;if(f.origin.x==568)f.origin.x=w-192;else if(f.origin.x==464)f.origin.x=w-296;if(f.size.width==712)f.size.width=width;if([view isKindOfClass:NSButton.class] && [(NSButton *)view action]==@selector(showCoverage:))f.origin.x=w-160;if(view==self.acknowledge)f.size.width=MAX(200,width-312);if([view isKindOfClass:NSButton.class] && [(NSButton *)view action]==@selector(reviewDoubt:))f.origin.x=w-312;}
        else if(f.origin.y==488){f.origin.y=bottom;NSUInteger index=(NSUInteger)round((f.origin.x-24)/144);CGFloat cell=(width-32)/5;f.origin.x=24+index*(cell+8);f.size.width=cell;}
        else if(f.origin.y==20 && f.origin.x==600){f.origin.x=w-160;}
        else if(f.origin.y==20 && f.origin.x==24 && f.size.width==540){f.size.width=width-152;}
        else if(f.origin.y>=252 && f.origin.y<=384){
            if(f.origin.x==24){f=NSMakeRect(24,252,narrow ? width:left,narrow ? body*.40:body);}
            else if(f.origin.x==368){f.origin.x=narrow ? 24:40+left;f.size.width=narrow ? width:width-left-16;
                if(f.origin.y==252){f.origin.y=narrow ? 260+body*.40:252;f.size.height=narrow ? MAX(32,body*.30-8):MAX(64,body-100);}
                else {f.origin.y=narrow ? 260+body*.70:bottom-100;f.size.height=narrow ? MAX(24,body*.30-12):88;}
                if(view==self.findingDetail.enclosingScrollView && self.findingImage.hidden)f.size.height=narrow ? MAX(48,body*.60-8):body;
            }
        }else if(f.size.width==712)f.size.width=width;
        view.frame=f;
    }
    if(self.findingsTable){self.findingsTable.tableColumns.firstObject.width=MAX(160,NSWidth(self.findingsTable.enclosingScrollView.bounds)-24);}
}

- (instancetype)initWithCourse:(NSDictionary *)course changes:(NSArray *)changes {
    DDLFormPanel *panel = [[DDLFormPanel alloc] initWithContentRect:NSMakeRect(0, 0, 760, 580) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:panel])) {
        __weak typeof(self) weakSelf = self; panel.onConfirm = ^{ [weakSelf save:nil]; }; panel.onCancel = ^{ [weakSelf cancel:nil]; };
        panel.minSize=NSMakeSize(620,600);self.course=course;self.checkCache=NSMutableDictionary.dictionary; self.changes = changes; panel.title = @"提交作业"; panel.releasedWhenClosed = NO;
        Surface *root = Box(Canvas(), 0); root.frame = NSMakeRect(0, 0, 760, 580); panel.contentView = root;
        Put(root, Text(@"提交作业", 23, NSFontWeightSemibold, Ink()), 24, 24, 712, 32);
        NSTextField *target = Text([NSString stringWithFormat:@"目标：%@ · %@", course[@"fork"], course[@"branch"]], 13, NSFontWeightMedium, Accent()); target.toolTip = target.stringValue; Put(root, target, 24, 64, 712, 24);
        Put(root, Text(@"逐项勾选文件；下方可关联作业。推送前检查全部待推送提交。", 13, NSFontWeightRegular, Muted()), 24, 96, 712, 24);
        Put(root, Text(@"本次提交的文件", 13, NSFontWeightSemibold, Ink()), 24, 136, 304, 24);
        Put(root, Text(@"变更预览", 13, NSFontWeightSemibold, Ink()), 344, 136, 392, 24);
        Surface *list = Box(Card(), 8); list.frame = NSMakeRect(0, 0, 288, MAX(272, changes.count * 64)); NSMutableArray *checks = NSMutableArray.array;
        for (NSUInteger i = 0; i < changes.count; i++) {
            NSDictionary *change = changes[i]; NSButton *check = [NSButton checkboxWithTitle:change[@"path"] target:self action:@selector(selectionChanged:)]; check.tag = i; check.toolTip = change[@"path"]; check.state = NSControlStateValueOff; check.enabled = ![change[@"sensitive"] boolValue]; check.font = [NSFont systemFontOfSize:13]; Put(list, check, 8, i * 64 + 4, 272, 28); [checks addObject:check];
            ActionButton *view = Button(@"查看", self, @selector(showPreview:), 3); view.tag = i; Put(list, view, 220, i * 64 + 32, 60, 28);
            NSString *state = [change[@"sensitive"] boolValue] ? @"⚠ 敏感文件，已排除" : [NSString stringWithFormat:@"变更状态 %@", change[@"status"]]; Put(list, Text(state, 11, NSFontWeightRegular, Muted()), 8, i * 64 + 32, 204, 24);
        } self.checks = checks;
        NSScrollView *fileScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(24, 168, 304, 272)]; fileScroll.hasVerticalScroller = YES; fileScroll.autohidesScrollers = YES; fileScroll.drawsBackground = NO; fileScroll.documentView = list; [root addSubview:fileScroll];
        NSScrollView *previewScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(344, 168, 392, 272)]; previewScroll.hasVerticalScroller = YES; previewScroll.autohidesScrollers = YES;
        self.preview = [[PastelNotesView alloc] initWithFrame:NSMakeRect(0, 0, 372, 272)]; self.preview.editable = NO; self.preview.richText = NO; self.preview.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]; self.preview.textColor = Ink(); self.preview.backgroundColor = Card(); self.preview.textContainerInset = NSMakeSize(8, 8); self.preview.autoresizingMask = NSViewWidthSizable; self.preview.textContainer.widthTracksTextView = YES; self.preview.string = @"点击文件旁的“查看”检查变更。"; previewScroll.documentView = self.preview; [root addSubview:previewScroll];
        self.message = [[PastelTextField alloc] initWithFrame:NSZeroRect]; self.message.placeholderString = @"提交说明，例如：完成第四次物理作业"; self.message.accessibilityLabel = @"提交说明"; Put(root, self.message, 24, 456, 712, 36);
        self.validation = Text(@"尚未选择文件", 12, NSFontWeightRegular, Muted()); Put(root, self.validation, 24, 512, 400, 40);self.filesValidation=self.validation;
        ActionButton *cancel = Button(@"取消", self, @selector(cancel:), 2); cancel.keyEquivalent = @"\033"; cancel.keyEquivalentModifierMask = 0; Put(root, cancel, 464, 520, 88, 36);
        ActionButton *save = Button(@"下一步：检查", self, @selector(save:), 1); save.keyEquivalent = @"\r"; save.keyEquivalentModifierMask = 0; Put(root, save, 568, 520, 168, 36); self.primary=save;self.filesPrimary=save;panel.initialFirstResponder = self.message; panel.defaultButtonCell = save.cell;
    } return self;
}
- (void)configureTasks:(NSArray *)tasks selected:(NSArray *)selected {
    if(self.taskChecks)return;
    NSView *root=self.window.contentView;self.window.minSize=NSMakeSize(760,676);[self.window setContentSize:NSMakeSize(760,676)];root.frame=NSMakeRect(0,0,760,676);
    for(NSView *view in root.subviews)if(view.frame.origin.y>=136){NSRect frame=view.frame;frame.origin.y+=96;view.frame=frame;}
    Put(root,Text(@"关联作业（可选，不会自动选择文件）",13,NSFontWeightSemibold,Ink()),24,128,712,24);
    NSStackView *stack=NSStackView.new;stack.orientation=NSUserInterfaceLayoutOrientationVertical;stack.alignment=NSLayoutAttributeLeading;stack.spacing=4;
    NSMutableArray *checks=NSMutableArray.array;
    for(NSDictionary *task in tasks){NSButton *check=[NSButton checkboxWithTitle:task[@"title"] target:nil action:nil];check.identifier=task[@"id"];check.toolTip=task[@"title"];check.state=[selected containsObject:task[@"id"]] ? NSControlStateValueOn:NSControlStateValueOff;[stack addArrangedSubview:check];[checks addObject:check];}
    stack.frame=NSMakeRect(0,0,650,MAX(28,checks.count*24));NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(24,156,712,60)];scroll.hasVerticalScroller=YES;scroll.documentView=stack;[self.window.contentView addSubview:scroll];self.taskChecks=checks;
}
- (BOOL)hasUnsavedChanges {
    [self.window makeFirstResponder:nil];
    if (self.onlineClient || self.supplement.string.length || self.message.stringValue.length) return YES;
    for (NSButton *check in self.taskChecks) if(check.state==NSControlStateValueOn)return YES;
    for (NSButton *check in self.checks) if (check.state == NSControlStateValueOn) return YES;
    return NO;
}
- (BOOL)saveForExit { self.validation.stringValue=self.checkOnly ? @"请完成检查或关闭此窗口，再退出。":@"请先完成检查，并明确点击提交；可选择稍后退出。";return NO; }
- (void)selectionChanged:(NSButton *)sender { NSUInteger count = 0; for (NSButton *check in self.checks) if (check.state == NSControlStateValueOn) count++; self.validation.stringValue = [NSString stringWithFormat:@"已选择 %lu 个文件", (unsigned long)count]; self.validation.textColor = Muted(); if (sender) [self showPreview:sender]; }
- (void)showPreview:(NSButton *)sender {
    NSUInteger generation = ++self.previewGeneration; self.preview.string = @"正在读取变更…";
    __weak typeof(self) weakSelf = self;
    if (self.readPreview) self.readPreview(self.changes[sender.tag][@"path"], ^(NSString *text) { if (weakSelf && generation == weakSelf.previewGeneration) weakSelf.preview.string = text ?: @"无法读取预览。"; });
}
- (void)cancel:(id)sender { self.onlineClient.cancelled=YES;self.closed=YES;self.previewGeneration++;[self.resultTimer invalidate];self.resultTimer=nil; [self.window.sheetParent endSheet:self.window]; [self.window orderOut:nil]; }
- (void)textDidChange:(NSNotification *)notification {if(notification.object==self.supplement){self.onlineButton.enabled=NO;self.report=nil;self.assistantButton.enabled=NO;self.acknowledge.state=NSControlStateValueOff;self.validation.stringValue=@"题目已修改，请重新检查。";}}
- (NSArray *)chosenPaths {NSMutableArray *paths=NSMutableArray.array;for(NSUInteger i=0;i<self.checks.count;i++)if(self.checks[i].enabled && self.checks[i].state==NSControlStateValueOn)[paths addObject:self.changes[i][@"path"]];return paths;}
- (NSArray *)chosenTasks {NSMutableArray *ids=NSMutableArray.array;for(NSButton *check in self.taskChecks)if(check.state==NSControlStateValueOn)[ids addObject:check.identifier];return ids;}
- (void)save:(id)sender {
    if(self.checking || self.closed)return;
    if(!self.checkPage || self.checkPage.hidden){self.selectedPaths=[self chosenPaths];self.taskIDs=[self chosenTasks];if(!self.selectedPaths.count || (!self.checkOnly && ![self.message.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length)){self.validation.stringValue=self.checkOnly ? @"请先选择需要检查的文件。":@"请选择文件并填写提交说明。";self.validation.textColor=NSColor.systemRedColor;return;}[self buildCheckPage];[self checkNow:nil];return;}
    if(self.checkOnly){[self cancel:nil];return;}
    if(!self.report){self.validation.stringValue=@"检查未完成，请重新检查或返回。";return;}
    if(self.acknowledge.state!=NSControlStateValueOn){self.validation.stringValue=@"请核对问题与未检查项，并确认继续。";self.validation.textColor=NSColor.systemRedColor;return;}
    self.finalValidation=YES;[self checkNow:nil];
}
- (void)buildCheckPage {
    if(self.checkPage){self.checkPage.hidden=NO;self.validation=self.checkValidation;self.window.defaultButtonCell=self.primary.cell;return;}
    self.window.minSize=NSMakeSize(620,600);[self.window setContentSize:NSMakeSize(760,676)];Surface *page=Box(Canvas(),0);page.frame=NSMakeRect(0,0,760,676);[self.window.contentView addSubview:page];self.checkPage=page;
    Put(page,Text(self.checkOnly ? @"检查作业文件 · 检查报告":@"提交作业 · 检查报告",20,NSFontWeightSemibold,Ink()),24,20,540,32);
    Put(page,Button(@"在线设置…",self,@selector(onlineSettings:),0),600,20,136,28);
    Put(page,Text(self.checkOnly ? @"当前本机文件 · 本机检查和助手复核分别显示覆盖范围。":@"拟提交版本 · 质量建议可确认，凭据与推送安全检查始终强制执行。",12,NSFontWeightRegular,Muted()),24,58,712,24);
    self.coverage=PFText(page,NSMakeRect(24,92,712,56),NO);
    Put(page,Text(@"补充题目／评分要求（可选；修改后请重新检查）",12,NSFontWeightMedium,Ink()),24,154,712,22);
    self.supplement=PFText(page,NSMakeRect(24,180,712,58),YES);self.supplement.delegate=self;self.supplement.accessibilityLabel=@"补充题目与要求";
    NSScrollView *list=[[NSScrollView alloc] initWithFrame:NSMakeRect(24,252,328,224)];list.hasVerticalScroller=YES;self.findingsTable=NSTableView.new;NSTableColumn *column=[[NSTableColumn alloc] initWithIdentifier:@"finding"];column.width=306;[self.findingsTable addTableColumn:column];self.findingsTable.headerView=nil;self.findingsTable.rowHeight=48;self.findingsTable.dataSource=self;self.findingsTable.delegate=self;self.findingsTable.accessibilityLabel=@"检查问题";list.documentView=self.findingsTable;[page addSubview:list];
    self.findingDetail=PFText(page,NSMakeRect(368,252,368,128),NO);self.findingImage=[[PFImageView alloc] initWithFrame:NSMakeRect(368,384,368,92)];self.findingImage.hidden=YES;[page addSubview:self.findingImage];
    self.onlineButton=Button(@"在线复核…",self,@selector(onlineReview:),1);Put(page,self.onlineButton,24,488,136,32);
    self.assistantButton=Button(@"Skill 复核…",self,@selector(assistantReview:),0);Put(page,self.assistantButton,168,488,136,32);
    NSButton *recheck=Button(@"重新检查",self,@selector(checkNow:),0);recheck.enabled=self.performCheck!=nil;Put(page,recheck,312,488,136,32);
    Put(page,Button(@"导入结果…",self,@selector(importAssistantResult:),0),456,488,136,32);
    Put(page,Button(@"显示文件…",self,@selector(openFinding:),0),600,488,136,32);
    Put(page,Button(@"复核这个疑点",self,@selector(reviewDoubt:),0),448,536,140,28);
    self.acknowledge=[NSButton checkboxWithTitle:@"已核对问题与未检查项，继续提交" target:nil action:nil];self.acknowledge.font=[NSFont systemFontOfSize:12];self.acknowledge.hidden=self.checkOnly;Put(page,self.acknowledge,24,536,564,24);NSButton *coverageButton=Button(@"查看覆盖范围…",self,@selector(showCoverage:),0);Put(page,coverageButton,600,536,136,28);
    self.validation=Text(@"正在读取拟提交版本…",12,NSFontWeightRegular,Muted());Put(page,self.validation,24,568,712,40);self.checkValidation=self.validation;
    NSButton *back=Button(self.checkOnly ? @"调整范围":@"返回文件",self,@selector(backToFiles:),0);back.enabled=self.changes.count>0;Put(page,back,24,624,104,32);NSButton *cancel=Button(@"取消",self,@selector(cancel:),2);cancel.keyEquivalent=@"\033";cancel.keyEquivalentModifierMask=0;Put(page,cancel,464,624,88,32);
    self.primary=Button(self.checkOnly ? @"完成":@"提交到个人仓库",self,@selector(save:),1);Put(page,self.primary,568,624,168,32);self.primary.keyEquivalent=@"\r";self.primary.keyEquivalentModifierMask=0;self.window.defaultButtonCell=self.primary.cell;
    NSMutableDictionary *frames=NSMutableDictionary.dictionary;NSUInteger slot=0;for(NSView *view in page.subviews){view.identifier=[NSString stringWithFormat:@"report-slot-%lu",(unsigned long)slot++];frames[view.identifier]=[NSValue valueWithRect:view.frame];}self.reportFrames=frames;
    page.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;__weak typeof(self) layoutOwner=self;page.onResize=^{[layoutOwner layoutReport];};[self layoutReport];
    __weak typeof(self) owner=self;self.resultTimer=[NSTimer scheduledTimerWithTimeInterval:3 repeats:YES block:^(NSTimer *timer){[owner pollReview:nil];}];
}
- (void)backToFiles:(id)sender {if(self.checking)return;if(self.checkOnly && self.backToScope){self.backToScope();return;}self.window.minSize=NSMakeSize(760,676);[self.window setContentSize:NSMakeSize(760,676)];self.checkPage.hidden=YES;self.validation=self.filesValidation;self.report=nil;self.snapshot=nil;self.finalValidation=NO;self.window.defaultButtonCell=self.filesPrimary.cell;}
- (void)checkNow:(id)sender {
    if(self.checking || self.closed || !self.performCheck)return;
    self.checking=YES;self.primary.enabled=NO;self.assistantButton.enabled=NO;self.onlineButton.enabled=NO;self.validation.textColor=Muted();self.validation.stringValue=self.finalValidation ? @"正在核对提交版本…":@"读取文件 → 检查结构、附件与未完成项…";
    NSUInteger generation=++self.previewGeneration;BOOL final=self.finalValidation;self.finalValidation=NO;NSString *extra=self.supplement.string.copy;NSArray *paths=self.selectedPaths.copy,*ids=self.taskIDs.copy;NSDictionary *previous=self.report;__weak typeof(self) owner=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;NSDictionary *bundle=owner.performCheck(paths,ids,extra,owner.checkCache,^BOOL{return !owner || owner.previewGeneration!=generation;},&error);
        dispatch_async(dispatch_get_main_queue(),^{SSSubmissionController *self=owner;if(!self || self.previewGeneration!=generation)return;self.checking=NO;self.primary.enabled=YES;self.assistantButton.enabled=YES;self.onlineButton.enabled=YES;
            if(!bundle || [bundle[@"report"][@"cancelled"] boolValue]){self.report=nil;self.assistantButton.enabled=NO;self.onlineButton.enabled=NO;self.validation.stringValue=error.localizedDescription ?: @"检查未完成，文件和输入已保留，可重试。";self.validation.textColor=NSColor.systemRedColor;return;}
            if(![extra isEqual:self.supplement.string]){self.report=nil;self.validation.stringValue=@"检查期间题目被修改，请重新检查。";return;}
            BOOL same=[previous[@"version"] isEqual:bundle[@"report"][@"version"]];self.reportStale=NO;self.snapshot=bundle[@"snapshot"];self.requirements=bundle[@"requirements"];self.report=bundle[@"report"];
            if(final && same && [extra isEqual:self.supplement.string]){NSDictionary *result=PFEffectiveReview(self.report[@"version"]);BOOL assistant=result!=nil;self.reviewSummary=@{@"date":NSDate.date,@"count":@(self.findings.count),@"acknowledged":@YES,@"coverage":assistant ? ([result[@"partial"] boolValue] ? @"partial":@"assistant"):@"local"};NSString *message=[self.message.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];[self cancel:nil];if(self.submit)self.submit(paths,message);return;}
            self.acknowledge.state=NSControlStateValueOff;self.assistantFingerprint=nil;[self refreshReport];self.validation.stringValue=final ? @"文件或题目已变化，已重新检查，请核对新报告后再提交。":(self.checkOnly ? @"本机检查完成；可查看问题或交给助手复核，不代表答案正确。":@"检查完成；质量建议可确认后继续，不代表答案一定正确。");self.validation.textColor=final ? NSColor.systemOrangeColor:Muted();
        });
    });
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table {return self.findings.count;}
- (NSView *)tableView:(NSTableView *)table viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {NSDictionary *issue=self.findings[row];NSString *location=[issue[@"path"] length] ? [NSString stringWithFormat:@"%@:%@",issue[@"path"],issue[@"line"] ?: @1]:@"检查范围";NSString *symbol=[issue[@"severity"] isEqual:@"error"] ? @"⚠":([issue[@"severity"] isEqual:@"warning"] ? @"△":@"ⓘ");NSTextField *label=Text([NSString stringWithFormat:@"%@ %@\n%@",symbol,issue[@"message"],location],12,NSFontWeightRegular,Ink());label.maximumNumberOfLines=2;label.toolTip=label.stringValue;return label;}
- (void)tableViewSelectionDidChange:(NSNotification *)notification {NSInteger row=self.findingsTable.selectedRow;self.findingImage.image=nil;self.findingImage.region=nil;if(row<0 || row>=(NSInteger)self.findings.count){self.findingDetail.string=@"选择问题查看位置、依据与建议。";return;}NSDictionary *issue=self.findings[row];self.findingDetail.string=[NSString stringWithFormat:@"%@:%@ · %@\n%@\n\n依据：%@\n建议：%@",issue[@"path"],issue[@"line"] ?: @1,[issue[@"provider"] isEqual:@"assistant"] ? @"助手建议":@"本机检查",issue[@"message"],issue[@"reason"] ?: issue[@"evidence"] ?: @"",issue[@"suggestion"] ?: @""];NSDictionary *file=self.snapshot[@"files"][issue[@"path"]];if([file[@"text"] isKindOfClass:NSString.class]){NSArray *lines=[file[@"text"] componentsSeparatedByString:@"\n"];NSInteger line=[issue[@"line"] integerValue]-1;NSMutableString *context=NSMutableString.string;for(NSInteger i=MAX(0,line-2);i<MIN((NSInteger)lines.count,line+3);i++)[context appendFormat:@"%ld  %@\n",(long)i+1,lines[i]];self.findingDetail.string=[self.findingDetail.string stringByAppendingFormat:@"\n\n附近原文：\n%@",context];NSRange evidence=[self.findingDetail.string rangeOfString:issue[@"evidence"] ?: @"" options:NSBackwardsSearch];if(evidence.location!=NSNotFound && evidence.length)self.findingDetail.selectedRange=evidence;}if([file[@"image"] boolValue]){self.findingImage.image=[[NSImage alloc] initWithData:file[@"data"]];self.findingImage.region=issue[@"region"];}self.findingDetail.selectedRange=NSMakeRange(0,0);[self.findingDetail scrollRangeToVisible:NSMakeRange(0,0)];self.findingImage.hidden=self.findingImage.image==nil;self.findingImage.needsDisplay=YES;[self layoutReport];}
- (void)refreshReport {
    NSDictionary *job=AMPreflightJobForReport(self.report[@"version"]);NSMutableArray *issues=[self.report[@"issues"] mutableCopy] ?: NSMutableArray.array;NSDictionary *effective=PFEffectiveReview(self.report[@"version"]);if(effective)[issues addObjectsFromArray:effective[@"issues"]];NSString *selected=self.findingsTable.selectedRow>=0 && self.findingsTable.selectedRow<(NSInteger)self.findings.count ? self.findings[self.findingsTable.selectedRow][@"id"]:nil;self.findings=issues;
    NSUInteger checked=0,unverified=0;for(NSDictionary *row in self.report[@"coverage"]){if([row[@"status"] hasPrefix:@"已检查"])checked++;else if([row[@"path"] length])unverified++;}
    NSMutableString *status=[NSMutableString stringWithFormat:@"本机：%lu 个文件已检查，%lu 个未检查 · %lu 条建议\n%@",(unsigned long)checked,(unsigned long)unverified,(unsigned long)[self.report[@"issues"] count],job ? [@"助手：" stringByAppendingString:job[@"message"] ?: @""]:@"助手：未检查。可准备附件交给助手，再导入结果。"];
    if([effective[@"unverified"] count])[status appendFormat:@" · %lu 项未完成",(unsigned long)[effective[@"unverified"] count]];if(effective && !job[@"result"])[status appendString:@"（保留同一材料版本的上次报告）"];
    if([job[@"provider"] isEqual:@"Gemini"] && effective)[status appendFormat:@" · 已核对 %lu 个所选文件",(unsigned long)[effective[@"checked"] count]];
    self.coverage.toolTip=[self.report[@"coverage"] description];
    self.coverage.string=status;[self.findingsTable reloadData];if(issues.count){NSUInteger index=[issues indexOfObjectPassingTest:^BOOL(NSDictionary *row,NSUInteger i,BOOL *stop){return [row[@"id"] isEqual:selected];}];[self.findingsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:index==NSNotFound ? 0:index] byExtendingSelection:NO];}else self.findingDetail.string=@"本机已检查范围未发现问题；语义、手写推导与答案正确性尚需核对。";
}
- (void)pollReview:(id)sender {
    if(self.checkOnly && self.snapshot && !self.checking){for(NSString *path in self.snapshot[@"files"]){NSString *stamp=self.snapshot[@"files"][path][@"stamp"];if(stamp && ![stamp isEqual:AMPreflightFileStamp([NSURL fileURLWithPath:self.course[@"path"]],path)]){self.reportStale=YES;self.assistantButton.enabled=NO;self.onlineButton.enabled=NO;self.validation.stringValue=@"文件已变化，当前报告仅供参考；请重新检查后再交给助手。";self.validation.textColor=NSColor.systemOrangeColor;self.acknowledge.state=NSControlStateValueOff;return;}}}

    if(self.checking || self.closed || !self.report)return;__weak typeof(self) owner=self;NSString *version=self.report[@"version"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{AMPreflightPoll();NSDictionary *job=AMPreflightJobForReport(version);NSString *fingerprint=job[@"fingerprint"];dispatch_async(dispatch_get_main_queue(),^{if(owner && [owner.report[@"version"] isEqual:version] && fingerprint && ![owner.assistantFingerprint isEqual:fingerprint]){owner.assistantFingerprint=fingerprint;owner.acknowledge.state=NSControlStateValueOff;[owner refreshReport];owner.validation.stringValue=@"助手结果已接回，请核对建议；不会自动提交。";}});});
}
- (void)openFinding:(id)sender {NSInteger row=self.findingsTable.selectedRow;if(row<0 || row>=(NSInteger)self.findings.count)return;NSString *path=self.findings[row][@"path"],*root=[self.course[@"path"] stringByResolvingSymlinksInPath],*full=[root stringByAppendingPathComponent:path];if([full hasPrefix:[root stringByAppendingString:@"/"]] && [full isEqual:full.stringByResolvingSymlinksInPath] && !SSSensitivePath(path))[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:full]]];}
- (void)showCoverage:(id)sender {
    NSAlert *alert=NSAlert.new;alert.messageText=@"检查覆盖范围";alert.informativeText=@"已检查不代表答案正确；未完成项请补充材料或交给助手复核。";[alert addButtonWithTitle:@"好"];
    Surface *view=Box(Canvas(),0);view.frame=NSMakeRect(0,0,580,320);NSTextView *text=PFText(view,view.bounds,NO);NSMutableString *status=NSMutableString.string;for(NSDictionary *row in self.report[@"coverage"])[status appendFormat:@"%@\n%@\n\n",[row[@"path"] length] ? row[@"path"]:@"本机检查边界",row[@"status"]];NSDictionary *result=PFEffectiveReview(self.report[@"version"]);if(result){[status appendString:@"助手未完成项\n"];[status appendString:[result[@"unverified"] count] ? [result[@"unverified"] componentsJoinedByString:@"\n"]:@"无（仅代表本次报告覆盖范围）"];}text.string=status;alert.accessoryView=view;[alert runModal];
}
- (void)importAssistantResult:(id)sender {
    if(self.checking || self.closed || !self.report)return;
    NSDictionary *job=AMPreflightJobForReport(self.report[@"version"]);if(!job || [job[@"cleaned"] boolValue]){self.validation.stringValue=@"请先交给助手复核，准备本次材料包后再导入。";return;}
    NSOpenPanel *panel=NSOpenPanel.openPanel;panel.title=@"导入助手返回的 results.local.json";panel.canChooseDirectories=NO;panel.allowsMultipleSelection=NO;panel.allowedContentTypes=@[[UTType typeWithFilenameExtension:@"json"]];
    if([panel runModal]!=NSModalResponseOK)return;self.checking=YES;self.primary.enabled=NO;self.assistantButton.enabled=NO;self.validation.stringValue=@"正在核验助手结果、批次与原文证据…";NSUInteger generation=++self.previewGeneration;__weak typeof(self) owner=self;NSURL *url=panel.URL;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;BOOL ok=AMPreflightImportResult(url,job[@"id"],&error);dispatch_async(dispatch_get_main_queue(),^{if(!owner || owner.previewGeneration!=generation)return;owner.checking=NO;owner.primary.enabled=YES;owner.assistantButton.enabled=!owner.reportStale;[owner refreshReport];owner.acknowledge.state=NSControlStateValueOff;owner.validation.stringValue=ok ? @"助手结果已导入，请核对建议；不会自动提交。":(error.localizedDescription ?: @"结果未导入，可重试。");owner.validation.textColor=ok ? Muted():NSColor.systemRedColor;});});
}
- (void)onlineSettings:(id)sender {if(self.checking)return;AMShowOnlineReviewSettings(self.window);}
- (void)reviewDoubt:(id)sender {
    NSInteger row=self.findingsTable.selectedRow;if(self.checking || row<0 || row>=(NSInteger)self.findings.count){self.validation.stringValue=@"请先选中需要重新核对的疑点。";return;}
    self.onlineFocus=self.findings[row];[self onlineReview:sender];self.onlineFocus=nil;
}
- (void)onlineReview:(id)sender {
    if(!self.performCheck){self.validation.stringValue=@"历史报告仅供查看，请从任务详情重新检查当前文件。";return;}
    if(self.onlineClient){self.onlineClient.cancelled=YES;self.onlineButton.enabled=NO;self.validation.stringValue=@"正在取消并清理上传副本；已发出的请求可能消耗额度…";return;}
    [self pollReview:nil];if(self.reportStale || self.checking || self.closed || !self.report)return;
    if(![AMOnlineReviewSettings()[@"enabled"] boolValue]){AMShowOnlineReviewSettings(self.window);if(![AMOnlineReviewSettings()[@"enabled"] boolValue])return;}
    PFMaterials *materials=[[PFMaterials alloc] initWithSnapshot:self.snapshot report:self.report requirements:self.requirements];materials.window.title=@"预览发送给 Gemini 的材料";materials.destination.hidden=YES;
    for(NSView *view in materials.window.contentView.subviews){if([view.identifier isEqual:@"handoff-hint"] && [view isKindOfClass:NSTextField.class])[(NSTextField *)view setStringValue:@"只发送所选材料给 Gemini；免费服务可能使用材料改进产品。不会执行代码或提交。"];
        if([view.identifier isEqual:@"material-prepare"] && [view isKindOfClass:NSButton.class])[(NSButton *)view setTitle:@"开始在线复核"];}
    [materials.window center];NSModalResponse response=[NSApp runModalForWindow:materials.window];[materials.window orderOut:nil];if(response!=NSModalResponseOK)return;[self pollReview:nil];if(self.reportStale)return;
    NSArray *images=[materials selectedImages];NSDictionary *snapshot=[materials selectedSnapshot],*report=self.report,*focus=self.onlineFocus;NSString *requirements=self.requirements,*courseID=self.course[@"fork"] ?: @"";
    self.checking=YES;self.primary.enabled=NO;self.assistantButton.enabled=NO;self.supplement.editable=NO;self.onlineButton.title=@"取消在线复核";self.validation.stringValue=@"准备所选材料，检查隐私与图片…";self.validation.textColor=Muted();AMOnlineReviewClient *client=AMOnlineReviewClient.new;
#ifdef DDL_TESTING
    if(self.onlineClientFactory)client=self.onlineClientFactory();
#endif
    self.onlineClient=client;NSDate *started=NSDate.date;NSUInteger generation=++self.previewGeneration;__weak typeof(self) owner=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;NSURL *folder=AMPreflightFolder(NSUUID.UUID.UUIDString);NSDictionary *context=AMPreflightExport(report,snapshot,requirements,images,folder,&error);NSDictionary *answer=nil;
        if(!client.cancelled && context && AMOnlineReviewRegister(context,report,courseID,&error))answer=[client reviewContext:context folder:folder focus:focus progress:^(NSString *stage){dispatch_async(dispatch_get_main_queue(),^{if(owner && owner.previewGeneration==generation && !client.cancelled)owner.validation.stringValue=[stage stringByAppendingFormat:@" · 已用 %.0f 秒",-started.timeIntervalSinceNow];});} error:&error];
        if(answer){AMPreflightPoll();NSDictionary *saved=AMPreflightJobForReport(report[@"version"]);if(![saved[@"id"] isEqual:context[@"batchID"]] || !saved[@"result"]){answer=nil;error=[NSError errorWithDomain:@"AMOnlineReview" code:1 userInfo:@{NSLocalizedDescriptionKey:@"结果写入失败，保留本机报告，请重试。"}];}}if(!answer && context)AMOnlineReviewFailed(context[@"batchID"]);NSUInteger pending=AMOnlineReviewPendingUploads();
        dispatch_async(dispatch_get_main_queue(),^{if(!owner || owner.previewGeneration!=generation)return;owner.onlineClient=nil;owner.checking=NO;owner.primary.enabled=YES;owner.supplement.editable=YES;owner.onlineButton.title=@"在线复核…";owner.onlineButton.enabled=YES;owner.assistantButton.enabled=YES;owner.acknowledge.state=NSControlStateValueOff;owner.assistantFingerprint=AMPreflightJobForReport(owner.report[@"version"])[@"fingerprint"];[owner refreshReport];[owner pollReview:nil];if(owner.reportStale)return;
            owner.validation.stringValue=answer ? ([answer[@"cached"] boolValue] ? @"已复用相同材料的报告，请核对建议。":([answer[@"partial"] boolValue] ? @"在线复核返回部分结果，请查看未检查项；不会自动提交。":@"在线复核已完成，请核对建议；不会自动提交。")):(error.localizedDescription ?: @"复核已取消，保留本机报告。");
            if(answer)owner.validation.stringValue=[owner.validation.stringValue stringByAppendingFormat:@" 耗时 %.1f 秒。",-started.timeIntervalSinceNow];
            if(pending)owner.validation.stringValue=[owner.validation.stringValue stringByAppendingFormat:@" %lu 个上传副本保留供重试或待清理，可到在线设置处理。",(unsigned long)pending];owner.validation.textColor=answer ? Muted():NSColor.systemOrangeColor;
        });
    });
}
- (void)assistantReview:(id)sender {
    [self pollReview:nil];if(self.reportStale || self.checking || self.closed || !self.report)return;
    PFMaterials *materials=[[PFMaterials alloc] initWithSnapshot:self.snapshot report:self.report requirements:self.requirements];[materials.window center];NSModalResponse response=[NSApp runModalForWindow:materials.window];[materials.window orderOut:nil];if(response!=NSModalResponseOK)return;
    // The user may have edited the original files while reviewing the preview.
    [self pollReview:nil];if(self.reportStale)return;
    NSArray *images=[materials selectedImages];NSDictionary *snapshot=[materials selectedSnapshot],*report=self.report;NSString *requirements=self.requirements;BOOL attachment=materials.destination.indexOfSelectedItem==0;
    self.checking=YES;self.primary.enabled=NO;self.assistantButton.enabled=NO;self.validation.stringValue=@"正在检查敏感信息并准备所选材料…";NSUInteger generation=++self.previewGeneration;__weak typeof(self) owner=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;NSURL *folder=AMPreflightFolder(NSUUID.UUID.UUIDString);NSDictionary *context=AMPreflightExport(report,snapshot,requirements,images,folder,&error);BOOL ok=context && AMPreflightRegister(context,report,owner.course[@"fork"] ?: @"",&error);NSURL *archive=ok && attachment ? AMPreflightAttachmentArchive(context[@"batchID"],&error):nil;if(attachment && !archive)ok=NO;
        dispatch_async(dispatch_get_main_queue(),^{if(!owner || owner.previewGeneration!=generation)return;owner.checking=NO;owner.primary.enabled=YES;owner.assistantButton.enabled=YES;if(!ok){owner.validation.stringValue=error.localizedDescription ?: @"材料未准备好，可重试。";return;}
            NSAlert *ready=NSAlert.new;ready.messageText=attachment ? @"上传附件，再导入助手结果":@"材料已准备好：本机助手";ready.informativeText=attachment ? @"把 AM-Helper-review.zip 上传到助手；若不支持 ZIP，请解压后上传其中的文件。助手返回 results.local.json 后，下载并在本报告点‘导入助手结果…’。网页聊天无法读取 Mac 本机路径。":@"仅把指令交给获准读取本机文件的助手。结果写回本机批次目录后自动接回；普通网页聊天请使用附件方式。";
            [ready addButtonWithTitle:attachment ? @"显示附件包并复制指令":@"复制本机指令"];[ready addButtonWithTitle:@"稍后"];if([ready runModal]==NSAlertFirstButtonReturn){if(attachment){[NSPasteboard.generalPasteboard clearContents];[NSPasteboard.generalPasteboard setString:AMPreflightAttachmentPrompt() forType:NSPasteboardTypeString];[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[archive]];}else AMPreflightJobAction(@"copy",context[@"batchID"]);}
            owner.validation.stringValue=attachment ? @"材料包已准备好；上传给助手后，下载 JSON 并点‘导入助手结果…’。":@"等待本机助手写回复核结果；不会自动发送材料。";[owner refreshReport];
        });
    });
}
@end
