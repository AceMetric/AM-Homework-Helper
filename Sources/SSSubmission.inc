// Stable workflow labels are shared by file selection and report presentation.
static NSTextField *AMSubmissionStepLabel(NSInteger step,BOOL checkOnly){
    NSArray *names=checkOnly ? @[@"选择文件",@"检查"]:@[@"选择文件",@"检查",@"提交"];
    NSMutableAttributedString *line=NSMutableAttributedString.new;
    for(NSUInteger i=0;i<names.count;i++){if(i)[line appendAttributedString:[[NSAttributedString alloc] initWithString:@"   ›   " attributes:@{NSForegroundColorAttributeName:Muted()}]];[line appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%lu %@",(unsigned long)i+1,names[i]] attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:12 weight:(NSInteger)i==step ? NSFontWeightSemibold:NSFontWeightRegular],NSForegroundColorAttributeName:(NSInteger)i==step ? Ink():Muted()}]];}
    NSTextField *label=Text(@"",12,NSFontWeightRegular,Muted());label.attributedStringValue=line;label.accessibilityLabel=[NSString stringWithFormat:@"步骤 %ld：%@",(long)step+1,names[MIN((NSUInteger)step,names.count-1)]];return label;
}
#import "AMPreflight.h"
#import "AMRenderer.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "AMPreflightUI.inc"
#import "AMOnlineReviewUI.inc"
static NSDictionary *PFEffectiveReviewJob(NSString *version){for(NSDictionary *job in [AMPreflightJobs() reverseObjectEnumerator])if([job[@"reportVersion"] isEqual:version] && job[@"result"] && ![job[@"cleaned"] boolValue])return job;return nil;}
static NSDictionary *PFEffectiveReview(NSString *version){NSDictionary *result=PFEffectiveReviewJob(version)[@"result"],*job=AMPreflightJobForReport(version);if(job[@"failure"]){NSMutableDictionary *copy=[result mutableCopy] ?: NSMutableDictionary.dictionary;copy[@"failure"]=job[@"failure"];copy[@"partial"]=@YES;return copy;}return result;}
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
@property NSScrollView *fileListScroll;
@property NSScrollView *taskListScroll;
@property NSTextField *fileHeading;
@property NSTextField *previewHeading;
@property NSButton *fileCancel;
@property NSButton *expandPreviewButton;
@property NSButton *previewStopButton;
@property(copy) void (^previewCancellation)(void);
@property Surface *filesPage;
@property NSSplitView *fileSplit;
@property BOOL layingOutFiles;
@property NSView *taskSection;
@property NSLayoutConstraint *taskSectionHeight;
@property NSWindow *expandedPreview;
@property NSTextView *expandedText;
@property NSString *previewPath;
@property (copy) void (^readPreview)(NSString *, void (^)(NSString *));
@property (copy) void (^submit)(NSArray *, NSString *);
@property NSUInteger previewGeneration;
@property NSDictionary *course;
@property NSDictionary *snapshot;
@property NSDictionary *report;
@property NSDictionary *reviewSummary;
@property NSMutableDictionary *checkCache;
@property NSString *requirements;
@property NSDictionary *reviewMaterialsSnapshot;
@property NSArray *reviewMaterialImages;
@property NSDictionary *reviewFailure;
@property NSString *pendingSupplement;
@property NSTextView *supplement;
@property NSTextView *coverage;
@property NSTextField *coverageLabel;
@property AMDocumentView *findingDetail;
@property NSWindow *markdownReportWindow;
@property NSTextField *reviewModelLabel;
@property NSTableView *findingsTable;
@property PFImageView *findingImage;
@property NSButton *acknowledge;
@property NSButton *primary;
@property NSButton *filesPrimary;
@property NSButton *assistantButton;
@property NSButton *onlineButton;
@property AMOperationView *operationView;
@property NSString *operationID;
@property AMOnlineReviewClient *onlineClient;
@property NSMutableDictionary<NSString *,AMOnlineReviewClient *> *onlineRequests;
@property BOOL queueOnlineRequest;
@property NSDictionary *onlineFocus;
@property NSDictionary *confirmedOnlineSnapshot;
@property NSArray *confirmedOnlineImages;
@property NSDictionary *confirmedOnlineSettings;
@property NSString *confirmedOnlineVersion;
@property NSString *confirmedOnlineRequirements;
@property NSPopUpButton *reportMenu;
#ifdef DDL_TESTING
@property(copy) AMOnlineReviewClient *(^onlineClientFactory)(void);
#endif
@property Surface *checkPage;
@property NSArray *findings;
@property NSArray *selectedPaths;
@property NSTimer *resultTimer;
@property BOOL checkOnly;
@property NSArray *draftBaseline;
@property(copy) void (^backToScope)(void);
@property(copy) void (^finished)(void);
@property(copy) void (^refreshFiles)(void);
@property BOOL submittedSuccessfully;
@property BOOL preserveClosedDraft;
@property AMDocumentView *documentPreview;
@property NSSplitView *reportSplit;
@property NSStackView *reportHeader;
@property NSStackView *reportFooter;
@property NSLayoutConstraint *supplementHeight;
@property BOOL layingOutReport;
@property(nonatomic) BOOL checking;
@property BOOL localChecking;
@property BOOL reportStale;
@property BOOL closed;
@property BOOL finalValidation;
@property NSString *assistantFingerprint;
@property(copy) NSDictionary *(^performCheck)(NSArray *,NSArray *,NSString *,NSMutableDictionary *,BOOL(^)(void),NSError **);
- (void)buildCheckPage;
- (void)checkNow:(id)sender;
- (void)layoutReport;
- (void)layoutFiles;
- (void)expandPreview:(id)sender;
- (void)updateExpandedPreview;
- (void)bindReviewMaterials;
- (void)toggleSupplement:(id)sender;
- (void)backToFiles:(id)sender;
- (void)refreshReport;
- (void)onlineReview:(id)sender;
- (void)reviewOptions:(id)sender;
- (void)showReportStatus:(id)sender;
- (void)onlineSettings:(id)sender;
- (void)reviewDoubt:(id)sender;
- (void)importAssistantResult:(id)sender;
- (void)pollReview:(id)sender;
- (BOOL)hasUnsavedChanges;
- (BOOL)saveForExit;
- (void)resumeAfterSubmissionFailure:(NSError *)error;
- (instancetype)initWithCourse:(NSDictionary *)course changes:(NSArray *)changes;
@end
@implementation SSSubmissionController
@synthesize checking=_checking;
- (void)setChecking:(BOOL)checking {_checking=checking;self.operationView.hidden=!checking;self.validation.hidden=checking;}
- (void)submissionSplitResized:(NSNotification *)notification {[self layoutFiles];}
- (void)layoutFiles {
    if(self.layingOutFiles)return;
    if(self.checkPage && !self.checkPage.hidden){self.checkPage.frame=self.window.contentView.bounds;return;}
    self.layingOutFiles=YES;[self.window.contentView layoutSubtreeIfNeeded];
    NSView *document=self.fileListScroll.documentView;CGFloat width=self.fileListScroll.contentSize.width;NSRect frame=document.frame;frame.size.width=width;document.frame=frame;
    for(NSView *row in document.subviews){NSRect rect=row.frame;if([row isKindOfClass:NSButton.class] && ((NSButton *)row).action==@selector(showPreview:)){rect.origin.x=width-68;rect.size.width=60;}else rect.size.width=MAX(80,width-([row isKindOfClass:NSButton.class] ? 16:84));row.frame=rect;}
    if(self.taskListScroll){NSRect rect=self.taskListScroll.documentView.frame;rect.size.width=self.taskListScroll.contentSize.width;self.taskListScroll.documentView.frame=rect;}
    self.layingOutFiles=NO;
}
- (void)reportSplitResized:(NSNotification *)notification {[self layoutReport];}
- (void)layoutReport {
    if(!self.reportSplit || self.layingOutReport)return;self.layingOutReport=YES;
    self.supplementHeight.constant=self.supplement.enclosingScrollView.hidden ? 0:58;
    [self.window.contentView layoutSubtreeIfNeeded];self.findingsTable.tableColumns.firstObject.width=MAX(160,self.findingsTable.enclosingScrollView.contentSize.width-16);
    self.layingOutReport=NO;
}

- (instancetype)initWithCourse:(NSDictionary *)course changes:(NSArray *)changes {
    DDLFormPanel *panel = [[DDLFormPanel alloc] initWithContentRect:NSMakeRect(0, 0, 960, 720) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:panel])) {
        __weak typeof(self) weakSelf = self; panel.onConfirm = ^{ [weakSelf save:nil]; }; panel.onCancel = ^{ [weakSelf cancel:nil]; };
        panel.contentMinSize=NSMakeSize(760,580);self.course=course;self.checkCache=NSMutableDictionary.dictionary; self.changes = changes; panel.title = @"提交作业"; panel.releasedWhenClosed = NO;
        Surface *root=Box(Canvas(),0);root.frame=panel.contentView.bounds;panel.contentView=root;
        Surface *page=Box(nil,0);self.filesPage=page;page.translatesAutoresizingMaskIntoConstraints=NO;[root addSubview:page];
        [NSLayoutConstraint activateConstraints:@[[page.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],[page.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],[page.topAnchor constraintEqualToAnchor:root.topAnchor],[page.bottomAnchor constraintEqualToAnchor:root.bottomAnchor]]];
        NSTextField *title=Text(@"提交作业",23,NSFontWeightSemibold,Ink());NSTextField *steps=AMSubmissionStepLabel(0,NO);
        NSTextField *target=Text([NSString stringWithFormat:@"目标：%@ · %@",course[@"fork"],course[@"branch"]],13,NSFontWeightMedium,Ink());target.toolTip=target.stringValue;
        self.taskSection=Box(nil,0);self.taskSectionHeight=[self.taskSection.heightAnchor constraintEqualToConstant:0];self.taskSection.hidden=YES;
        self.fileSplit=NSSplitView.new;self.fileSplit.vertical=YES;self.fileSplit.dividerStyle=NSSplitViewDividerStyleThin;self.fileSplit.autosaveName=@"AMSubmissionFilesSplit";
        Surface *files=Box(nil,0),*detail=Box(nil,0);[self.fileSplit addArrangedSubview:files];[self.fileSplit addArrangedSubview:detail];
        self.fileHeading=Text(@"本次提交的文件",13,NSFontWeightSemibold,Ink());self.previewHeading=Text(@"变更预览",13,NSFontWeightSemibold,Ink());self.expandPreviewButton=Button(@"展开预览…",self,@selector(expandPreview:),0);self.previewStopButton=Button(@"",self,@selector(stopPreview:),0);AMConfigureStopButton(self.previewStopButton,@"停止读取");self.previewStopButton.hidden=YES;
        Surface *list=Box(Card(),0);list.frame=NSMakeRect(0,0,320,MAX(160,changes.count*64));NSMutableArray *checks=NSMutableArray.array;
        for(NSUInteger i=0;i<changes.count;i++){
            NSDictionary *change=changes[i];NSButton *check=[NSButton checkboxWithTitle:change[@"path"] target:self action:@selector(selectionChanged:)];check.tag=i;check.toolTip=change[@"path"];check.state=NSControlStateValueOff;check.enabled=![change[@"sensitive"] boolValue];check.font=[NSFont systemFontOfSize:13];Put(list,check,8,i*64+4,304,28);[checks addObject:check];
            NSButton *view=Button(@"查看",self,@selector(showPreview:),3);view.tag=i;Put(list,view,252,i*64+32,60,28);
            NSString *state=[change[@"sensitive"] boolValue] ? @"敏感文件，已排除":[NSString stringWithFormat:@"变更状态 %@",change[@"status"]];Put(list,Text(state,11,NSFontWeightRegular,Muted()),8,i*64+32,236,24);
        }self.checks=checks;
        self.fileListScroll=NSScrollView.new;self.fileListScroll.hasVerticalScroller=YES;self.fileListScroll.autohidesScrollers=YES;self.fileListScroll.drawsBackground=NO;self.fileListScroll.documentView=list;
        NSScrollView *previewScroll=NSScrollView.new;previewScroll.hasVerticalScroller=YES;previewScroll.hasHorizontalScroller=YES;previewScroll.autohidesScrollers=YES;
        self.preview=[[PastelNotesView alloc] initWithFrame:NSMakeRect(0,0,500,300)];self.preview.editable=NO;self.preview.selectable=YES;self.preview.richText=NO;self.preview.font=[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];self.preview.textColor=Ink();self.preview.backgroundColor=Card();self.preview.textContainerInset=NSMakeSize(12,12);self.preview.autoresizingMask=NSViewWidthSizable;self.preview.textContainer.widthTracksTextView=YES;self.preview.string=@"未选择预览文件";previewScroll.documentView=self.preview;
        for(NSView *child in @[self.fileHeading,self.fileListScroll]){child.translatesAutoresizingMaskIntoConstraints=NO;[files addSubview:child];}
        for(NSView *child in @[self.previewHeading,self.previewStopButton,self.expandPreviewButton,previewScroll]){child.translatesAutoresizingMaskIntoConstraints=NO;[detail addSubview:child];}
        [NSLayoutConstraint activateConstraints:@[[files.widthAnchor constraintGreaterThanOrEqualToConstant:240],[detail.widthAnchor constraintGreaterThanOrEqualToConstant:280],[self.fileHeading.topAnchor constraintEqualToAnchor:files.topAnchor],[self.fileHeading.leadingAnchor constraintEqualToAnchor:files.leadingAnchor],[self.fileListScroll.leadingAnchor constraintEqualToAnchor:files.leadingAnchor],[self.fileListScroll.trailingAnchor constraintEqualToAnchor:files.trailingAnchor constant:-8],[self.fileListScroll.topAnchor constraintEqualToAnchor:self.fileHeading.bottomAnchor constant:12],[self.fileListScroll.bottomAnchor constraintEqualToAnchor:files.bottomAnchor],[self.previewHeading.centerYAnchor constraintEqualToAnchor:self.expandPreviewButton.centerYAnchor],[self.previewHeading.leadingAnchor constraintEqualToAnchor:detail.leadingAnchor constant:8],[self.previewHeading.trailingAnchor constraintLessThanOrEqualToAnchor:self.previewStopButton.leadingAnchor constant:-8],[self.previewStopButton.trailingAnchor constraintEqualToAnchor:self.expandPreviewButton.leadingAnchor constant:-8],[self.previewStopButton.centerYAnchor constraintEqualToAnchor:self.expandPreviewButton.centerYAnchor],[self.expandPreviewButton.trailingAnchor constraintEqualToAnchor:detail.trailingAnchor],[self.expandPreviewButton.topAnchor constraintEqualToAnchor:detail.topAnchor],[previewScroll.leadingAnchor constraintEqualToAnchor:detail.leadingAnchor constant:8],[previewScroll.trailingAnchor constraintEqualToAnchor:detail.trailingAnchor],[previewScroll.topAnchor constraintEqualToAnchor:self.expandPreviewButton.bottomAnchor constant:8],[previewScroll.bottomAnchor constraintEqualToAnchor:detail.bottomAnchor]]];
        self.message=[[PastelTextField alloc] initWithFrame:NSZeroRect];self.message.placeholderString=@"提交说明";self.message.accessibilityLabel=@"提交说明";
        self.validation=Text(@"尚未选择文件",12,NSFontWeightRegular,Muted());self.filesValidation=self.validation;
        self.fileCancel=Button(@"取消",self,@selector(cancel:),0);self.fileCancel.keyEquivalent=@"\033";self.fileCancel.keyEquivalentModifierMask=0;
        self.filesPrimary=Button(@"检查",self,@selector(save:),1);self.primary=self.filesPrimary;self.filesPrimary.keyEquivalent=@"\r";self.filesPrimary.keyEquivalentModifierMask=0;
        for(NSView *child in @[title,steps,target,self.taskSection,self.fileSplit,self.message,self.validation,self.fileCancel,self.filesPrimary]){child.translatesAutoresizingMaskIntoConstraints=NO;[page addSubview:child];}
        [NSLayoutConstraint activateConstraints:@[[title.leadingAnchor constraintEqualToAnchor:page.leadingAnchor constant:24],[title.topAnchor constraintEqualToAnchor:page.safeAreaLayoutGuide.topAnchor constant:20],[title.trailingAnchor constraintLessThanOrEqualToAnchor:page.trailingAnchor constant:-24],[target.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[target.trailingAnchor constraintEqualToAnchor:page.trailingAnchor constant:-24],[steps.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[steps.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],[steps.trailingAnchor constraintLessThanOrEqualToAnchor:page.trailingAnchor constant:-24],[target.topAnchor constraintEqualToAnchor:steps.bottomAnchor constant:8],[self.taskSection.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[self.taskSection.trailingAnchor constraintEqualToAnchor:target.trailingAnchor],[self.taskSection.topAnchor constraintEqualToAnchor:target.bottomAnchor constant:12],self.taskSectionHeight,[self.fileSplit.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[self.fileSplit.trailingAnchor constraintEqualToAnchor:target.trailingAnchor],[self.fileSplit.topAnchor constraintEqualToAnchor:self.taskSection.bottomAnchor constant:12],[self.fileSplit.bottomAnchor constraintEqualToAnchor:self.message.topAnchor constant:-16],[self.fileSplit.heightAnchor constraintGreaterThanOrEqualToConstant:160],[self.message.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[self.message.trailingAnchor constraintEqualToAnchor:target.trailingAnchor],[self.message.heightAnchor constraintEqualToConstant:28],[self.validation.topAnchor constraintEqualToAnchor:self.message.bottomAnchor constant:12],[self.validation.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[self.validation.trailingAnchor constraintEqualToAnchor:target.trailingAnchor],[self.validation.bottomAnchor constraintEqualToAnchor:self.filesPrimary.topAnchor constant:-12],[self.filesPrimary.trailingAnchor constraintEqualToAnchor:target.trailingAnchor],[self.filesPrimary.bottomAnchor constraintEqualToAnchor:page.safeAreaLayoutGuide.bottomAnchor constant:-20],[self.fileCancel.trailingAnchor constraintEqualToAnchor:self.filesPrimary.leadingAnchor constant:-12],[self.fileCancel.centerYAnchor constraintEqualToAnchor:self.filesPrimary.centerYAnchor]]];
        panel.initialFirstResponder=self.message;panel.defaultButtonCell=self.filesPrimary.cell;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(submissionSplitResized:) name:NSSplitViewDidResizeSubviewsNotification object:self.fileSplit];root.onResize=^{[weakSelf layoutFiles];};[self layoutFiles];[self.fileSplit setPosition:NSWidth(self.fileSplit.bounds)*.38 ofDividerAtIndex:0];self.draftBaseline=[self draftValues];

    } return self;
}
- (void)configureTasks:(NSArray *)tasks selected:(NSArray *)selected {
    if(self.taskChecks)return;
    self.window.contentMinSize=NSMakeSize(760,676);self.taskSection.hidden=NO;self.taskSectionHeight.constant=88;
    NSTextField *heading=Text(@"关联作业（可选）",13,NSFontWeightSemibold,Ink());
    NSStackView *stack=NSStackView.new;stack.orientation=NSUserInterfaceLayoutOrientationVertical;stack.alignment=NSLayoutAttributeLeading;stack.spacing=4;
    NSMutableArray *checks=NSMutableArray.array;
    for(NSDictionary *task in tasks){NSButton *check=[NSButton checkboxWithTitle:task[@"title"] target:nil action:nil];check.identifier=task[@"id"];check.toolTip=task[@"title"];check.state=[selected containsObject:task[@"id"]] ? NSControlStateValueOn:NSControlStateValueOff;[stack addArrangedSubview:check];[checks addObject:check];}
    stack.frame=NSMakeRect(0,0,650,MAX(28,checks.count*24));NSScrollView *scroll=NSScrollView.new;scroll.hasVerticalScroller=YES;scroll.autohidesScrollers=YES;scroll.drawsBackground=NO;scroll.documentView=stack;self.taskChecks=checks;self.taskListScroll=scroll;
    for(NSView *child in @[heading,scroll]){child.translatesAutoresizingMaskIntoConstraints=NO;[self.taskSection addSubview:child];}
    [NSLayoutConstraint activateConstraints:@[[heading.leadingAnchor constraintEqualToAnchor:self.taskSection.leadingAnchor],[heading.topAnchor constraintEqualToAnchor:self.taskSection.topAnchor],[heading.trailingAnchor constraintEqualToAnchor:self.taskSection.trailingAnchor],[scroll.leadingAnchor constraintEqualToAnchor:self.taskSection.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.taskSection.trailingAnchor],[scroll.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:8],[scroll.bottomAnchor constraintEqualToAnchor:self.taskSection.bottomAnchor]]];[self layoutFiles];self.draftBaseline=[self draftValues];
}
- (NSArray *)draftValues {
    NSMutableArray *tasks=NSMutableArray.array;for(NSButton *check in self.taskChecks)if(check.state==NSControlStateValueOn)[tasks addObject:check.identifier ?: @""];
    return @[[self chosenPaths] ?: @[],[tasks sortedArrayUsingSelector:@selector(compare:)],self.message.stringValue ?: @"",self.supplement.string ?: self.pendingSupplement ?: @""];
}
- (BOOL)hasUnsavedChanges {return ![self.draftBaseline isEqual:[self draftValues]];}
- (void)resumeAfterSubmissionFailure:(NSError *)error {
    self.closed=NO;self.preserveClosedDraft=NO;self.checking=NO;self.localChecking=NO;self.primary.enabled=YES;self.filesPrimary.enabled=YES;
    self.validation=(self.checkPage && !self.checkPage.hidden) ? self.checkValidation:self.filesValidation;
    self.validation.stringValue=error.localizedDescription ?: @"提交未完成，请核验后重试。";self.validation.textColor=NSColor.systemRedColor;
    if([error.userInfo[@"SSPreflightStale"] boolValue]){self.reportStale=YES;self.acknowledge.state=NSControlStateValueOff;self.primary.enabled=NO;self.onlineButton.enabled=NO;}
    __weak typeof(self) owner=self;[self.resultTimer invalidate];self.resultTimer=[NSTimer scheduledTimerWithTimeInterval:3 repeats:YES block:^(NSTimer *timer){[owner pollReview:nil];}];
}
- (void)refreshFileList:(id)sender{if(self.refreshFiles)self.refreshFiles();}

- (BOOL)saveForExit { self.validation.stringValue=self.checkOnly ? @"请完成检查或关闭此窗口，再退出。":@"请先完成检查，并明确点击提交；可选择稍后退出。";return NO; }
- (void)selectionChanged:(NSButton *)sender { NSUInteger count = 0; for (NSButton *check in self.checks) if (check.state == NSControlStateValueOn) count++; self.validation.stringValue = [NSString stringWithFormat:@"已选择 %lu 个文件", (unsigned long)count]; self.validation.textColor = Muted(); if (sender) [self showPreview:sender]; }
- (void)showPreview:(NSButton *)sender {
    if(self.previewCancellation)self.previewCancellation();self.previewStopButton.hidden=NO;
    NSUInteger generation = ++self.previewGeneration;self.previewPath=self.changes[sender.tag][@"path"];self.previewHeading.toolTip=self.previewPath; self.preview.string = @"正在读取变更…";[self updateExpandedPreview];
    __weak typeof(self) weakSelf = self;
    if (self.readPreview) self.readPreview(self.previewPath, ^(NSString *text) { if (weakSelf && generation == weakSelf.previewGeneration){weakSelf.previewStopButton.hidden=YES;weakSelf.preview.string = text ?: @"无法读取预览。";[weakSelf.preview scrollRangeToVisible:NSMakeRange(0,0)];[weakSelf updateExpandedPreview];} });
}
- (void)stopPreview:(id)sender {if(self.previewCancellation)self.previewCancellation();self.previewGeneration++;self.previewStopButton.hidden=YES;self.preview.string=@"读取已终止。";[self updateExpandedPreview];}
- (void)expandPreview:(id)sender {
    if(!self.expandedPreview){NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1000,720) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];window.releasedWhenClosed=NO;window.contentMinSize=NSMakeSize(680,440);NSScrollView *scroll=NSScrollView.new;scroll.hasVerticalScroller=YES;scroll.hasHorizontalScroller=YES;scroll.autohidesScrollers=YES;self.expandedText=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,1000,720)];self.expandedText.editable=NO;self.expandedText.selectable=YES;self.expandedText.richText=NO;self.expandedText.font=[NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];self.expandedText.textContainerInset=NSMakeSize(20,20);self.expandedText.horizontallyResizable=YES;self.expandedText.verticallyResizable=YES;self.expandedText.maxSize=NSMakeSize(CGFLOAT_MAX,CGFLOAT_MAX);self.expandedText.textContainer.widthTracksTextView=NO;self.expandedText.textContainer.containerSize=NSMakeSize(CGFLOAT_MAX,CGFLOAT_MAX);scroll.documentView=self.expandedText;window.contentView=scroll;[window center];self.expandedPreview=window;}
    [self updateExpandedPreview];[self.expandedPreview makeKeyAndOrderFront:nil];
}
- (void)updateExpandedPreview {
    if(!self.expandedPreview)return;self.expandedPreview.title=self.previewPath.length ? [@"变更预览 · " stringByAppendingString:self.previewPath]:@"变更预览";self.expandedText.string=self.preview.string;self.expandedText.textColor=Ink();self.expandedText.backgroundColor=Card();[self.expandedText.layoutManager ensureLayoutForTextContainer:self.expandedText.textContainer];NSSize used=[self.expandedText.layoutManager usedRectForTextContainer:self.expandedText.textContainer].size;NSSize viewport=[(NSScrollView *)self.expandedPreview.contentView contentSize];[self.expandedText setFrameSize:NSMakeSize(MAX(viewport.width,used.width+40),MAX(viewport.height,used.height+40))];[self.expandedText scrollRangeToVisible:NSMakeRange(0,0)];
}
- (void)cancel:(id)sender {self.preserveClosedDraft=NO;if(self.previewCancellation)self.previewCancellation();[self.expandedPreview orderOut:nil];if(self.checking && !self.onlineClient)for(NSDictionary *operation in AMOperations())if([operation[@"id"] isEqual:self.operationID] && [operation[@"cancellable"] boolValue])AMOperationFinish(self.operationID,@"cancelled",@"检查已取消"); for(AMOnlineReviewClient *client in self.onlineRequests.allValues){AMOperationCancel(client.operationID);[client cancelImmediately];}[self.onlineClient cancelImmediately];self.closed=YES;self.previewGeneration++;[self.resultTimer invalidate];self.resultTimer=nil; [self.window.sheetParent endSheet:self.window]; [self.window orderOut:nil];if(self.finished){void(^done)(void)=self.finished;self.finished=nil;done();} }
- (void)textDidChange:(NSNotification *)notification {if(notification.object==self.supplement){NSMutableDictionary *materials=self.reviewMaterialsSnapshot.mutableCopy;[materials removeObjectForKey:@"reviewRequirements"];self.reviewMaterialsSnapshot=materials;self.confirmedOnlineSnapshot=nil;self.reviewFailure=nil;self.supplement.enclosingScrollView.hidden=NO;[self layoutReport];self.onlineButton.enabled=NO;self.report=nil;self.assistantButton.enabled=NO;self.acknowledge.state=NSControlStateValueOff;self.validation.stringValue=@"题目已修改，请重新检查。";}}
- (NSArray *)chosenPaths {NSMutableArray *paths=NSMutableArray.array;for(NSUInteger i=0;i<self.checks.count;i++)if(self.checks[i].enabled && self.checks[i].state==NSControlStateValueOn)[paths addObject:self.changes[i][@"path"]];return paths;}
- (NSArray *)chosenTasks {NSMutableArray *ids=NSMutableArray.array;for(NSButton *check in self.taskChecks)if(check.state==NSControlStateValueOn)[ids addObject:check.identifier];return ids;}
- (void)save:(id)sender {
    if((self.checking && (!self.onlineClient || self.localChecking)) || self.closed)return;
    if(![self.window makeFirstResponder:nil]){self.validation.stringValue=@"请先完成当前输入，再开始检查。";self.validation.textColor=NSColor.systemRedColor;return;}
    if(!self.checkPage || self.checkPage.hidden){self.selectedPaths=[self chosenPaths];self.taskIDs=[self chosenTasks];if(!self.selectedPaths.count || (!self.checkOnly && ![self.message.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length)){self.validation.stringValue=self.checkOnly ? @"请先选择需要检查的文件。":@"请选择文件并填写提交说明。";self.validation.textColor=NSColor.systemRedColor;return;}[self buildCheckPage];[self checkNow:nil];return;}
    if(self.checkOnly){[self cancel:nil];return;}
    if(!self.report){self.validation.stringValue=@"检查未完成，请重新检查或返回。";return;}
    if(self.acknowledge.state!=NSControlStateValueOn){self.validation.stringValue=@"请核对问题与未检查项，并确认继续。";self.validation.textColor=NSColor.systemRedColor;return;}
    self.finalValidation=YES;[self checkNow:nil];
}
- (void)buildCheckPage {
    for(NSView *view in self.window.contentView.subviews)if(view!=self.checkPage)view.hidden=YES;
    if(self.checkPage){self.checkPage.hidden=NO;self.validation=self.checkValidation;self.window.defaultButtonCell=self.primary.cell;return;}
    if(!self.checkOnly)self.window.contentMinSize=NSMakeSize(760,620);
    Surface *page=Box(Canvas(),0);page.frame=self.window.contentView.bounds;page.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;[self.window.contentView addSubview:page];self.checkPage=page;
    NSStackView *header=NSStackView.new;header.orientation=NSUserInterfaceLayoutOrientationVertical;header.alignment=NSLayoutAttributeLeading;header.spacing=8;self.reportHeader=header;
    NSTextField *title=Text(@"检查报告",20,NSFontWeightSemibold,Ink());NSButton *settings=Button(@"在线设置…",self,@selector(onlineSettings:),0);NSStackView *titleRow=[NSStackView stackViewWithViews:@[title,settings]];titleRow.spacing=16;[title setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];[header addArrangedSubview:titleRow];[header addArrangedSubview:AMSubmissionStepLabel(1,self.checkOnly)];

    self.reviewModelLabel=Text(@"",12,NSFontWeightRegular,Muted());self.reviewModelLabel.maximumNumberOfLines=1;[header addArrangedSubview:self.reviewModelLabel];[self.reviewModelLabel.widthAnchor constraintEqualToAnchor:header.widthAnchor].active=YES;
    self.coverage=PFText(page,NSMakeRect(0,0,400,60),NO);self.coverage.enclosingScrollView.hidden=YES;self.coverageLabel=Text(@"",12,NSFontWeightRegular,Muted());[header addArrangedSubview:self.coverageLabel];[self.coverageLabel.widthAnchor constraintEqualToAnchor:header.widthAnchor].active=YES;
    NSButton *requirements=Button(@"检查材料…",self,@selector(toggleSupplement:),0);[header addArrangedSubview:requirements];
    self.supplement=PFText(page,NSMakeRect(0,0,400,58),YES);self.supplement.string=self.pendingSupplement ?: @"";self.supplement.delegate=self;self.supplement.accessibilityLabel=@"补充题目与要求";NSScrollView *supplementScroll=self.supplement.enclosingScrollView;[header addArrangedSubview:supplementScroll];supplementScroll.hidden=!self.supplement.string.length;self.supplementHeight=[supplementScroll.heightAnchor constraintEqualToConstant:0];self.supplementHeight.active=YES;
    self.reportSplit=NSSplitView.new;self.reportSplit.vertical=YES;self.reportSplit.dividerStyle=NSSplitViewDividerStyleThin;self.reportSplit.autosaveName=@"AMCheckReportSplit";
    NSScrollView *list=NSScrollView.new;list.hasVerticalScroller=YES;list.autohidesScrollers=YES;self.findingsTable=NSTableView.new;self.findingsTable.style=NSTableViewStyleInset;NSTableColumn *column=[[NSTableColumn alloc] initWithIdentifier:@"finding"];column.width=280;[self.findingsTable addTableColumn:column];self.findingsTable.headerView=nil;self.findingsTable.rowHeight=56;self.findingsTable.dataSource=self;self.findingsTable.delegate=self;self.findingsTable.accessibilityLabel=@"检查问题";list.documentView=self.findingsTable;[self.reportSplit addArrangedSubview:list];
    NSView *details=NSView.new;[self.reportSplit addArrangedSubview:details];
    self.documentPreview=[[AMDocumentView alloc] initWithFrame:NSMakeRect(0,0,400,400)];self.documentPreview.translatesAutoresizingMaskIntoConstraints=NO;[details addSubview:self.documentPreview];
    self.findingDetail=self.documentPreview; // Existing report actions share the one reader.
    self.findingImage=PFImageView.new;self.findingImage.hidden=YES;
    [NSLayoutConstraint activateConstraints:@[[list.widthAnchor constraintGreaterThanOrEqualToConstant:200],[details.widthAnchor constraintGreaterThanOrEqualToConstant:280],[self.documentPreview.leadingAnchor constraintEqualToAnchor:details.leadingAnchor],[self.documentPreview.trailingAnchor constraintEqualToAnchor:details.trailingAnchor],[self.documentPreview.topAnchor constraintEqualToAnchor:details.topAnchor],[self.documentPreview.bottomAnchor constraintEqualToAnchor:details.bottomAnchor]]];
    NSStackView *footer=NSStackView.new;footer.orientation=NSUserInterfaceLayoutOrientationVertical;footer.alignment=NSLayoutAttributeLeading;footer.spacing=10;self.reportFooter=footer;
    self.onlineButton=Button(@"在线复核…",self,@selector(onlineReview:),1);self.assistantButton=Button(@"Skill 复核…",self,@selector(assistantReview:),0);self.assistantButton.hidden=YES;
    NSButton *recheck=Button(@"重新检查",self,@selector(checkNow:),0);recheck.enabled=self.performCheck!=nil;
    self.reportMenu=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];self.reportMenu.bezelStyle=NSBezelStyleRounded;self.reportMenu.font=[NSFont systemFontOfSize:13];[self.reportMenu addItemWithTitle:@"更多"];self.reportMenu.accessibilityLabel=@"更多";
    NSArray *options=@[@[@"在线设置…",NSStringFromSelector(@selector(onlineSettings:))],@[@"Skill 复核…",NSStringFromSelector(@selector(assistantReview:))],@[@"导入助手结果…",NSStringFromSelector(@selector(importAssistantResult:))],@[@"复核选中疑点",NSStringFromSelector(@selector(reviewDoubt:))],@[@"完整报告",NSStringFromSelector(@selector(showMarkdownReport:))],@[@"检查范围",NSStringFromSelector(@selector(showCoverage:))],@[@"显示选中文件…",NSStringFromSelector(@selector(openFinding:))],@[@"发送范围…",NSStringFromSelector(@selector(reviewOptions:))],@[@"状态…",NSStringFromSelector(@selector(showReportStatus:))]];
    for(NSArray *option in options){NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:option[0] action:NSSelectorFromString(option[1]) keyEquivalent:@""];item.target=self;[self.reportMenu.menu addItem:item];}
    NSStackView *actions=[NSStackView stackViewWithViews:@[self.onlineButton,recheck,self.reportMenu]];actions.spacing=12;[footer addArrangedSubview:actions];
    self.acknowledge=[NSButton checkboxWithTitle:@"已核对报告" target:nil action:nil];self.acknowledge.hidden=self.checkOnly;[footer addArrangedSubview:self.acknowledge];
    self.validation=Text(@"正在读取拟提交版本…",12,NSFontWeightRegular,Muted());self.checkValidation=self.validation;self.validation.selectable=YES;self.validation.maximumNumberOfLines=0;self.validation.lineBreakMode=NSLineBreakByWordWrapping;[footer addArrangedSubview:self.validation];[self.validation.widthAnchor constraintEqualToAnchor:footer.widthAnchor].active=YES;
    self.operationView=AMOperationView.new;self.operationView.hidden=YES;[footer addArrangedSubview:self.operationView];[self.operationView.heightAnchor constraintEqualToConstant:64].active=YES;
    NSButton *back=Button(self.checkOnly ? @"调整范围":@"返回文件",self,@selector(backToFiles:),0);back.enabled=self.changes.count>0;NSButton *cancel=Button(@"取消",self,@selector(cancel:),0);cancel.keyEquivalent=@"\033";cancel.keyEquivalentModifierMask=0;
    self.primary=Button(self.checkOnly ? @"完成":@"提交",self,@selector(save:),1);self.primary.keyEquivalent=@"\r";self.primary.keyEquivalentModifierMask=0;self.window.defaultButtonCell=self.primary.cell;
    NSButton *refresh=Button(@"刷新文件列表",self,@selector(refreshFileList:),0);refresh.hidden=self.checkOnly || !self.refreshFiles;
    NSView *space=NSView.new;[space.widthAnchor constraintGreaterThanOrEqualToConstant:8].active=YES;NSStackView *bottom=[NSStackView stackViewWithViews:@[back,refresh,space,cancel,self.primary]];bottom.spacing=12;[footer addArrangedSubview:bottom];
    for(NSView *child in @[header,self.reportSplit,footer]){child.translatesAutoresizingMaskIntoConstraints=NO;[page addSubview:child];}
    for(NSView *child in @[titleRow,self.coverageLabel,supplementScroll]){child.translatesAutoresizingMaskIntoConstraints=NO;[child.widthAnchor constraintEqualToAnchor:header.widthAnchor].active=YES;}
    for(NSView *child in @[self.operationView,bottom]){child.translatesAutoresizingMaskIntoConstraints=NO;[child.widthAnchor constraintEqualToAnchor:footer.widthAnchor].active=YES;}
    [NSLayoutConstraint activateConstraints:@[[header.leadingAnchor constraintEqualToAnchor:page.leadingAnchor constant:24],[header.trailingAnchor constraintEqualToAnchor:page.trailingAnchor constant:-24],[header.topAnchor constraintEqualToAnchor:page.safeAreaLayoutGuide.topAnchor constant:20],[self.reportSplit.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],[self.reportSplit.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],[self.reportSplit.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:12],[self.reportSplit.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-12],[self.reportSplit.heightAnchor constraintGreaterThanOrEqualToConstant:120],[footer.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],[footer.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],[footer.bottomAnchor constraintEqualToAnchor:page.safeAreaLayoutGuide.bottomAnchor constant:-20]]];
    __weak typeof(self) layoutOwner=self;page.onResize=^{[layoutOwner layoutReport];};[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reportSplitResized:) name:NSSplitViewDidResizeSubviewsNotification object:self.reportSplit];[self layoutReport];[self.reportSplit setPosition:NSWidth(self.reportSplit.bounds)*.32 ofDividerAtIndex:0];
    __weak typeof(self) owner=self;self.resultTimer=[NSTimer scheduledTimerWithTimeInterval:3 repeats:YES block:^(NSTimer *timer){[owner pollReview:nil];}];
}
- (void)bindReviewMaterials {if(!self.report || !self.reviewMaterialsSnapshot)return;self.requirements=self.reviewMaterialsSnapshot[@"reviewRequirements"] ?: self.requirements;NSMutableDictionary *versions=NSMutableDictionary.dictionary;for(NSString *path in self.reviewMaterialsSnapshot[@"files"])versions[path]=self.reviewMaterialsSnapshot[@"files"][path][@"version"] ?: @"";NSDictionary *identity=@{@"base":self.report[@"reviewBaseVersion"] ?: self.report[@"version"],@"files":versions,@"roles":self.reviewMaterialsSnapshot[@"reviewRoles"] ?: @{},@"links":self.reviewMaterialsSnapshot[@"questionLinks"] ?: @{},@"paths":self.reviewMaterialsSnapshot[@"paths"] ?: @[],@"excluded":self.reviewMaterialsSnapshot[@"materialExcluded"] ?: @[],@"requirements":self.requirements ?: @""};NSMutableDictionary *report=self.report.mutableCopy;report[@"reviewBaseVersion"]=identity[@"base"];report[@"version"]=AMPreflightHash([NSJSONSerialization dataWithJSONObject:identity options:NSJSONWritingSortedKeys error:NULL]);self.report=report;}
- (void)toggleSupplement:(id)sender{if(self.checking || !self.snapshot)return;PFMaterials *materials=[[PFMaterials alloc] initWithSnapshot:self.reviewMaterialsSnapshot ?: self.snapshot report:self.report requirements:self.requirements];materials.materialRoot=[NSURL fileURLWithPath:self.course[@"path"]];for(NSView *v in materials.window.contentView.subviews)if([v.identifier isEqual:@"material-prepare"])[(NSButton *)v setTitle:@"保存材料"];[materials.window center];NSModalResponse response=[NSApp runModalForWindow:materials.window];[materials.window orderOut:nil];if(response!=NSModalResponseOK)return;self.reviewMaterialsSnapshot=[materials selectedSnapshot];self.reviewMaterialImages=[materials selectedImages];self.requirements=materials.requirements;[self bindReviewMaterials];self.confirmedOnlineSnapshot=nil;self.reviewFailure=nil;self.acknowledge.state=NSControlStateValueOff;self.validation.stringValue=@"检查材料已保存 · 提交文件不变";}
- (void)backToFiles:(id)sender {if(self.checking && (!self.onlineClient || self.localChecking))return;if(self.onlineClient)self.previewGeneration++;if(self.checkOnly && self.backToScope){self.backToScope();return;}self.window.contentMinSize=NSMakeSize(760,self.taskChecks ? 676:580);self.checkPage.hidden=YES;for(NSView *view in self.window.contentView.subviews)if(view!=self.checkPage)view.hidden=NO;self.validation=self.filesValidation;self.report=nil;self.snapshot=nil;self.finalValidation=NO;self.window.defaultButtonCell=self.filesPrimary.cell;[self layoutFiles];}
- (void)checkNow:(id)sender {
    if((self.checking && (!self.onlineClient || self.localChecking)) || self.closed)return;
    if(!self.performCheck){self.validation.hidden=NO;self.validation.stringValue=@"检查尚未准备好，请返回文件列表后重试。";self.validation.textColor=NSColor.systemRedColor;return;}
    __block NSString *localID=nil;localID=AMOperationBegin(@"本机文件检查",self.course[@"fork"] ?: @"当前文件",YES,^{self.previewGeneration++;self.localChecking=NO;self.checking=self.onlineClient!=nil;self.primary.enabled=YES;self.validation.stringValue=@"检查已取消，可重新检查。";AMOperationFinish(localID,@"cancelled",@"检查已取消");});self.operationID=localID;self.operationView.operationID=self.operationID;self.operationView.hidesCancellation=NO;self.localChecking=YES;self.checking=YES;self.primary.enabled=NO;self.assistantButton.enabled=NO;self.onlineButton.enabled=NO;self.validation.textColor=Muted();self.validation.stringValue=self.finalValidation ? @"正在核对提交版本…":@"读取文件 → 检查结构、附件与未完成项…";
    NSUInteger generation=++self.previewGeneration;BOOL final=self.finalValidation;self.finalValidation=NO;NSString *extra=self.supplement.string.copy;NSArray *paths=self.selectedPaths.copy,*ids=self.taskIDs.copy;NSDictionary *previous=self.report;NSMutableDictionary *runCache=self.checkCache.mutableCopy;__weak typeof(self) owner=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;NSDictionary *bundle=owner.performCheck(paths,ids,extra,runCache,^BOOL{return !owner || owner.previewGeneration!=generation;},&error);
        dispatch_async(dispatch_get_main_queue(),^{SSSubmissionController *self=owner;if(!self || self.previewGeneration!=generation)return;self.checkCache=runCache;self.localChecking=NO;self.checking=self.onlineClient!=nil;self.primary.enabled=YES;self.assistantButton.enabled=YES;self.onlineButton.enabled=YES;AMOperationFinish(localID,bundle ? @"success":@"failed",bundle ? @"本机已检查范围完成；答案正确性尚未核对":(error.localizedDescription ?: @"检查未完成"));
            if(self.onlineClient){self.operationID=self.onlineClient.operationID;self.operationView.operationID=self.operationID;self.operationView.hidesCancellation=YES;}
            if(!bundle || [bundle[@"report"][@"cancelled"] boolValue]){self.report=nil;self.assistantButton.enabled=NO;self.onlineButton.enabled=NO;self.validation.stringValue=error.localizedDescription ?: @"检查未完成，文件和输入已保留，可重试。";self.validation.textColor=NSColor.systemRedColor;return;}
            if(![extra isEqual:self.supplement.string]){self.report=nil;self.validation.stringValue=@"检查期间题目被修改，请重新检查。";return;}
            BOOL same=[previous[@"version"] isEqual:bundle[@"report"][@"version"]];self.reportStale=NO;if(![self.snapshot[@"version"] isEqual:bundle[@"snapshot"][@"version"]]){self.reviewMaterialsSnapshot=nil;self.reviewMaterialImages=nil;self.confirmedOnlineSnapshot=nil;self.reviewFailure=nil;}self.snapshot=bundle[@"snapshot"];self.requirements=bundle[@"requirements"];self.report=bundle[@"report"];[self bindReviewMaterials];
            if(final && same && [extra isEqual:self.supplement.string]){NSDictionary *result=PFEffectiveReview(self.report[@"version"]);BOOL assistant=result!=nil;self.reviewSummary=@{@"date":NSDate.date,@"count":@([self.findings filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *issue,NSDictionary *bindings){return ![issue[@"provider"] isEqual:@"coverage"];}]].count),@"acknowledged":@YES,@"coverage":assistant ? ([result[@"partial"] boolValue] ? @"partial":@"assistant"):@"local"};NSString *message=[self.message.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];[self cancel:nil];self.preserveClosedDraft=YES;if(self.submit)self.submit(paths,message);return;}
            self.acknowledge.state=NSControlStateValueOff;self.assistantFingerprint=nil;[self refreshReport];self.validation.stringValue=final ? @"文件或题目已变化，已重新检查，请核对新报告后再提交。":(self.checkOnly ? @"检查完成":@"检查完成");self.validation.textColor=final ? NSColor.systemOrangeColor:Muted();
        });
    });
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table {return self.findings.count;}
- (NSView *)tableView:(NSTableView *)table viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {NSDictionary *issue=self.findings[row];NSString *location=[issue[@"path"] length] ? ([issue[@"line"] integerValue]>0 ? [NSString stringWithFormat:@"%@:%@",issue[@"path"],issue[@"line"]]:issue[@"path"]):@"检查范围";NSString *symbol=[issue[@"severity"] isEqual:@"error"] ? @"⚠":([issue[@"severity"] isEqual:@"warning"] ? @"△":@"ⓘ");NSTextField *label=Text([NSString stringWithFormat:@"%@ %@\n%@",symbol,issue[@"message"],location],12,NSFontWeightRegular,Ink());label.maximumNumberOfLines=2;label.toolTip=label.stringValue;return label;}
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row=self.findingsTable.selectedRow;
    if(row<0 || row>=(NSInteger)self.findings.count){self.documentPreview.markdown=AMPreflightReportMarkdown(self.report,self.snapshot,PFEffectiveReview(self.report[@"version"]));return;}
    NSDictionary *issue=self.findings[row];NSString *path=issue[@"path"];NSDictionary *file=self.snapshot[@"files"][path];
    if([file[@"problem"] isKindOfClass:NSString.class] && [file[@"problem"] length]){self.documentPreview.markdown=[NSString stringWithFormat:@"## 无法预览\n\n%@",file[@"problem"]];return;}
    if(!file){self.documentPreview.markdown=AMPreflightFindingMarkdown(issue,self.snapshot);[self layoutReport];return;}
    if([issue[@"provider"] isEqual:@"assistant"] && ![issue[@"version"] isEqual:file[@"version"]]){self.documentPreview.markdown=@"材料已变化，请重新检查。";return;}
    [self.documentPreview loadSnapshot:self.snapshot path:path];NSMutableArray *annotations=NSMutableArray.array;
    for(NSDictionary *finding in self.findings){if(![finding[@"path"] isEqual:path] || ([finding[@"provider"] isEqual:@"assistant"] && ![finding[@"version"] isEqual:file[@"version"]]))continue;
        NSMutableDictionary *note=[@{@"id":finding[@"id"] ?: @"",@"line":finding[@"line"] ?: @1,@"markdown":AMPreflightFindingMarkdown(finding,self.snapshot)} mutableCopy];if(finding[@"region"])note[@"region"]=finding[@"region"];[annotations addObject:note];
    }
    [self.documentPreview setAnnotations:annotations selected:issue[@"id"] ?: @""];[self layoutReport];
}
- (void)refreshReport {
    NSDictionary *effective=PFEffectiveReview(self.report[@"version"]),*scope=AMPreflightReviewScope(effective),*effectiveJob=PFEffectiveReviewJob(self.report[@"version"]);
    NSMutableArray *issues=[self.report[@"issues"] mutableCopy] ?: NSMutableArray.array;[issues addObjectsFromArray:effective[@"issues"] ?: @[]];
    NSString *selected=self.findingsTable.selectedRow>=0 && self.findingsTable.selectedRow<(NSInteger)self.findings.count ? self.findings[self.findingsTable.selectedRow][@"id"]:nil;
    NSMutableDictionary *groups=NSMutableDictionary.dictionary;
    for(NSString *reason in scope[@"unverified"]){NSString *path=@"";for(NSString *candidate in self.snapshot[@"files"])if([reason hasPrefix:[candidate stringByAppendingString:@"："]] || [reason hasPrefix:[candidate stringByAppendingString:@":"]]){path=candidate;break;}
        NSString *key=path.length ? path:reason;if(!groups[key])groups[key]=[@{@"path":path,@"reasons":NSMutableOrderedSet.orderedSet} mutableCopy];[groups[key][@"reasons"] addObject:reason];
    }
    for(NSString *key in [[groups allKeys] sortedArrayUsingSelector:@selector(compare:)]){NSDictionary *group=groups[key];NSMutableString *reason=NSMutableString.string;for(NSString *item in [group[@"reasons"] array])[reason appendFormat:@"- %@\n",item];
        [issues addObject:@{@"id":[@"coverage:" stringByAppendingString:key],@"path":group[@"path"],@"severity":@"info",@"category":@"unreadable",@"provider":@"coverage",@"message":@"检查未覆盖",@"reason":reason,@"suggestion":@"补充材料后重新复核。"}];
    }
    NSMutableSet *seen=NSMutableSet.set;NSMutableArray *unique=NSMutableArray.array;
    for(NSDictionary *issue in issues){NSMutableDictionary *identity=issue.mutableCopy;[identity removeObjectForKey:@"id"];NSString *key=AMPreflightHash([NSJSONSerialization dataWithJSONObject:identity options:NSJSONWritingSortedKeys error:NULL]);if(![seen containsObject:key]){[seen addObject:key];[unique addObject:issue];}}
    [unique sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){NSArray *order=@[@"error",@"warning",@"info"];NSUInteger x=[order indexOfObject:a[@"severity"]],y=[order indexOfObject:b[@"severity"]];return x<y ? NSOrderedAscending:(x>y ? NSOrderedDescending:[(a[@"path"] ?: @"") localizedStandardCompare:b[@"path"] ?: @""]);}];self.findings=unique;
    NSMutableSet *checked=NSMutableSet.set,*unverified=NSMutableSet.set;NSUInteger rendered=0,mathPending=0;
    for(NSDictionary *row in self.report[@"coverage"]){if([row[@"kind"] isEqual:@"math"]){if([row[@"status"] hasPrefix:@"已渲染"])rendered++;else mathPending++;}else if([row[@"path"] length]){if([row[@"status"] hasPrefix:@"已检查"])[checked addObject:row[@"path"]];else [unverified addObject:row[@"path"]];}}
    NSMutableString *status=[NSMutableString stringWithFormat:@"本机：%lu 个文件已检查 · %lu 个未覆盖\n",(unsigned long)checked.count,(unsigned long)unverified.count];
    if(effective)[status appendFormat:@"%@：%lu 个文件已检查 · %lu 项未覆盖 · %lu 项未选择发送\n",[effectiveJob[@"provider"] isEqual:@"Gemini"] ? @"Gemini":@"助手",(unsigned long)[effective[@"checked"] count],(unsigned long)groups.count,(unsigned long)[scope[@"excluded"] count]];else [status appendString:self.onlineClient ? @"在线：检查中\n":@"在线：尚未复核\n"];
    [status appendFormat:@"公式渲染：%lu 个文档完成 · %lu 个未覆盖",(unsigned long)rendered,(unsigned long)mathPending];
    self.coverage.toolTip=nil;self.coverage.string=status;
    self.coverageLabel.stringValue=[NSString stringWithFormat:@"%lu 个文件 · %lu 项建议%@",(unsigned long)checked.count,(unsigned long)unique.count,(unverified.count+groups.count) ? [NSString stringWithFormat:@" · %lu 项未覆盖",(unsigned long)(unverified.count+groups.count)]:@""];
    if(effective[@"failure"])self.coverageLabel.stringValue=@"在线复核未完成 · 已有结果保留";else if(!effective || self.onlineClient)self.coverageLabel.stringValue=[NSString stringWithFormat:@"%lu 个文件 · %@",(unsigned long)checked.count,self.onlineClient ? @"正在复核":@"在线尚未复核"];
    self.coverageLabel.toolTip=status;
    self.reviewModelLabel.hidden=self.checkOnly || ![self.course[@"fork"] length];self.reviewModelLabel.stringValue=[NSString stringWithFormat:@"%@ · %@",self.course[@"fork"] ?: @"",self.course[@"branch"] ?: @""];
    [self.findingsTable reloadData];if(unique.count){NSUInteger index=[unique indexOfObjectPassingTest:^BOOL(NSDictionary *row,NSUInteger i,BOOL *stop){return [row[@"id"] isEqual:selected];}];NSUInteger target=index==NSNotFound ? 0:index;if(self.findingsTable.selectedRow==(NSInteger)target)[self tableViewSelectionDidChange:[NSNotification notificationWithName:NSTableViewSelectionDidChangeNotification object:self.findingsTable]];else [self.findingsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:target] byExtendingSelection:NO];}else{self.documentPreview.markdown=AMPreflightReportMarkdown(self.report,self.snapshot,effective);[self layoutReport];}
}
- (void)pollReview:(id)sender {
    if(self.checkOnly && self.snapshot && !self.checking){for(NSString *path in self.snapshot[@"files"]){NSString *stamp=self.snapshot[@"files"][path][@"stamp"];if(stamp && ![stamp isEqual:AMPreflightFileStamp([NSURL fileURLWithPath:self.course[@"path"]],path)]){self.reportStale=YES;self.assistantButton.enabled=NO;self.onlineButton.enabled=NO;self.validation.stringValue=@"文件已变化，当前报告仅供参考；请重新检查后再交给助手。";self.validation.textColor=NSColor.systemOrangeColor;self.acknowledge.state=NSControlStateValueOff;return;}}}

    if(self.checking || self.closed || !self.report)return;__weak typeof(self) owner=self;NSString *version=self.report[@"version"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{AMPreflightPoll();NSDictionary *job=AMPreflightJobForReport(version);NSString *fingerprint=job[@"fingerprint"];dispatch_async(dispatch_get_main_queue(),^{if(owner && [owner.report[@"version"] isEqual:version] && fingerprint && ![owner.assistantFingerprint isEqual:fingerprint]){owner.assistantFingerprint=fingerprint;owner.acknowledge.state=NSControlStateValueOff;[owner refreshReport];owner.validation.stringValue=@"复核结果已接回";}});});
}
- (void)openFinding:(id)sender {NSInteger row=self.findingsTable.selectedRow;if(row<0 || row>=(NSInteger)self.findings.count)return;NSString *path=self.findings[row][@"path"],*root=[self.course[@"path"] stringByResolvingSymlinksInPath],*full=[root stringByAppendingPathComponent:path];if([full hasPrefix:[root stringByAppendingString:@"/"]] && [full isEqual:full.stringByResolvingSymlinksInPath] && !SSSensitivePath(path))[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:full]]];}
- (void)showMarkdownReport:(id)sender {
    [self.findingsTable deselectAll:nil];self.documentPreview.markdown=AMPreflightReportMarkdown(self.report,self.snapshot,PFEffectiveReview(self.report[@"version"]));[self layoutReport];
}
- (void)showCoverage:(id)sender {[self showMarkdownReport:sender];}
- (void)importAssistantResult:(id)sender {
    if(self.checking || self.closed || !self.report)return;
    NSDictionary *job=AMPreflightJobForReport(self.report[@"version"]);if(!job || [job[@"cleaned"] boolValue]){self.validation.stringValue=@"请先交给助手复核，准备本次材料包后再导入。";return;}
    NSOpenPanel *panel=NSOpenPanel.openPanel;panel.title=@"导入助手返回的 results.local.json";panel.canChooseDirectories=NO;panel.allowsMultipleSelection=NO;panel.allowedContentTypes=@[[UTType typeWithFilenameExtension:@"json"]];
    if([panel runModal]!=NSModalResponseOK)return;NSString *operation=AMOperationBegin(@"导入复核结果",@"Skill",NO,nil);self.operationID=operation;self.operationView.operationID=operation;self.checking=YES;self.primary.enabled=NO;self.assistantButton.enabled=NO;self.validation.stringValue=@"正在核验助手结果、批次与原文证据…";NSUInteger generation=++self.previewGeneration;__weak typeof(self) owner=self;NSURL *url=panel.URL;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;BOOL ok=AMPreflightImportResult(url,job[@"id"],&error);AMOperationFinish(operation,ok ? @"success":@"failed",ok ? @"结果已导入，请核对建议":error.localizedDescription ?: @"结果导入失败");dispatch_async(dispatch_get_main_queue(),^{if(!owner || owner.previewGeneration!=generation)return;owner.checking=NO;owner.primary.enabled=YES;owner.assistantButton.enabled=!owner.reportStale;[owner refreshReport];owner.acknowledge.state=NSControlStateValueOff;owner.validation.stringValue=ok ? @"复核结果已导入":(error.localizedDescription ?: @"结果未导入，可重试。");owner.validation.textColor=ok ? Muted():NSColor.systemRedColor;});});
}
- (void)onlineSettings:(id)sender {if(self.checking && !self.onlineClient)return;AMShowOnlineReviewSettings(self.window);[self refreshReport];}
- (void)reviewDoubt:(id)sender {
    NSInteger row=self.findingsTable.selectedRow;if((self.checking && !self.onlineClient) || row<0 || row>=(NSInteger)self.findings.count){self.validation.stringValue=@"请先选中需要重新核对的疑点。";return;}
    if([self.findings[row][@"provider"] isEqual:@"coverage"] && ![self.findings[row][@"path"] length]){self.validation.stringValue=@"这是尚未验证的内容。请先补充可核对的材料，再进行在线复核。";return;}
    self.onlineFocus=self.findings[row];self.queueOnlineRequest=YES;[self onlineReview:sender];self.queueOnlineRequest=NO;self.onlineFocus=nil;
}
- (void)onlineReview:(id)sender {
    if(!self.performCheck){self.validation.stringValue=@"历史报告仅供查看，请从任务详情重新检查当前文件。";return;}
    if(self.onlineClient && !self.queueOnlineRequest){AMOperationCancel(self.onlineClient.operationID);[self.onlineClient cancelImmediately];self.onlineButton.enabled=NO;self.validation.stringValue=@"正在终止复核；上传副本稍后清理，已发出的请求可能计费。";return;}
    [self pollReview:nil];if(self.reportStale || (self.checking && !self.onlineClient) || self.closed || !self.report)return;
    if(![AMOnlineReviewSettings()[@"enabled"] boolValue]){AMShowOnlineReviewSettings(self.window);if(![AMOnlineReviewSettings()[@"enabled"] boolValue])return;}
    NSDictionary *settings=AMOnlineReviewSettings();BOOL reuse=self.confirmedOnlineSnapshot && [self.confirmedOnlineSettings[@"model"] ?: @"" isEqual:settings[@"model"] ?: @""] && [self.confirmedOnlineVersion isEqual:self.report[@"version"]] && [self.confirmedOnlineRequirements isEqual:self.requirements] && [self.confirmedOnlineSettings[@"enabled"] isEqual:settings[@"enabled"]];
    if(!reuse){PFMaterials *materials=[[PFMaterials alloc] initWithSnapshot:self.reviewMaterialsSnapshot ?: self.snapshot report:self.report requirements:self.requirements];materials.materialRoot=[NSURL fileURLWithPath:self.course[@"path"]];materials.window.title=@"预览发送给 Gemini 的材料";materials.destination.hidden=YES;
        for(NSView *view in materials.window.contentView.subviews){if([view.identifier isEqual:@"handoff-hint"] && [view isKindOfClass:NSTextField.class])[(NSTextField *)view setStringValue:@"只发送所选材料给 Gemini；免费服务可能使用材料改进产品。不会执行代码或提交。"];
            if([view.identifier isEqual:@"material-prepare"] && [view isKindOfClass:NSButton.class])[(NSButton *)view setTitle:@"开始在线复核"];}
        [materials.window center];NSModalResponse response=[NSApp runModalForWindow:materials.window];[materials.window orderOut:nil];if(response!=NSModalResponseOK)return;[self pollReview:nil];if(self.reportStale)return;
        self.requirements=materials.requirements;self.reviewMaterialsSnapshot=[materials selectedSnapshot];self.reviewMaterialImages=[materials selectedImages];[self bindReviewMaterials];self.confirmedOnlineImages=[materials selectedImages];self.confirmedOnlineSnapshot=[materials selectedSnapshot];self.confirmedOnlineVersion=self.report[@"version"];self.confirmedOnlineRequirements=self.requirements;self.confirmedOnlineSettings=settings;
    }
    NSArray *images=self.confirmedOnlineImages;NSDictionary *snapshot=self.confirmedOnlineSnapshot,*report=self.report,*focus=self.onlineFocus;NSString *requirements=self.requirements,*courseID=self.course[@"fork"] ?: @"";
    NSDictionary *requestIdentity=@{@"version":report[@"version"],@"paths":snapshot[@"paths"] ?: @[],@"images":[images valueForKey:@"path"] ?: @[],@"roles":snapshot[@"reviewRoles"] ?: @{},@"links":snapshot[@"questionLinks"] ?: @{},@"requirements":requirements ?: @"",@"focus":focus ?: @{},@"model":AMOnlineReviewCurrentModel()};NSString *requestKey=[@"review|" stringByAppendingString:AMPreflightHash([NSJSONSerialization dataWithJSONObject:requestIdentity options:NSJSONWritingSortedKeys error:NULL])];
    AMOnlineReviewClient *existing=self.onlineRequests[requestKey];if(existing){self.operationID=existing.operationID;self.operationView.operationID=self.operationID;self.validation.stringValue=@"相同范围已在处理中，可从后台任务查看进度。";return;}
    self.checking=YES;self.primary.enabled=YES;self.assistantButton.enabled=YES;self.supplement.editable=YES;AMConfigureStopButton(self.onlineButton,@"停止复核");self.operationView.hidesCancellation=YES;self.validation.stringValue=@"准备所选材料，检查隐私与图片…";self.validation.textColor=Muted();AMOnlineReviewClient *client=AMOnlineReviewClient.new;
#ifdef DDL_TESTING
    if(self.onlineClientFactory)client=self.onlineClientFactory();
#endif
    client.model=client.model ?: AMOnlineReviewCurrentModel();client.requestLimit=[snapshot[@"requestLimit"] unsignedIntegerValue];self.reviewFailure=nil;self.onlineClient=client;NSString *extraAtStart=self.supplement.string.copy;NSDate *started=NSDate.date;NSUInteger generation=++self.previewGeneration;__weak typeof(self) owner=self;
    if(!self.onlineRequests)self.onlineRequests=NSMutableDictionary.dictionary;self.onlineRequests[requestKey]=client;
    self.operationID=AMOperationEnqueue(requestKey,@"在线复核",client.model ?: AMOnlineReviewCurrentModel(),@[@"model-service"],100,^(NSString *identifier){client.operationID=identifier;NSError *error=nil;NSURL *folder=AMPreflightFolder(NSUUID.UUID.UUIDString);NSDictionary *context=AMPreflightExport(report,snapshot,requirements,images,folder,&error);NSDictionary *answer=nil;
        if(!client.cancelled && context && AMOnlineReviewRegisterWithModel(context,report,courseID,client.model,&error))answer=[client reviewContext:context folder:folder focus:focus progress:^(NSString *stage){dispatch_async(dispatch_get_main_queue(),^{if(owner && owner.previewGeneration==generation && !client.cancelled)owner.validation.stringValue=[stage stringByAppendingFormat:@" · 已用 %.0f 秒",-started.timeIntervalSinceNow];});} error:&error];
        NSError *materialError=nil;if(!AMReviewMaterialsCurrent(snapshot,&materialError)){answer=nil;error=materialError;}if(client.cancelled){answer=nil;error=[NSError errorWithDomain:@"AMOnlineReview" code:NSUserCancelledError userInfo:@{NSLocalizedDescriptionKey:@"在线复核已终止，保留本机报告。"}];}if(answer){AMPreflightPoll();NSDictionary *saved=AMPreflightJobForReport(report[@"version"]);if(![saved[@"id"] isEqual:context[@"batchID"]] || !saved[@"result"]){answer=nil;error=[NSError errorWithDomain:@"AMOnlineReview" code:1 userInfo:@{NSLocalizedDescriptionKey:@"结果写入失败，保留本机报告，请重试。"}];}}if(!answer && context)AMOnlineReviewRecordFailure(context[@"batchID"],error);AMOperationFinish(client.operationID,answer ? ([answer[@"partial"] boolValue] ? @"failed":@"success"):(client.cancelled ? @"cancelled":@"failed"),answer ? ([answer[@"partial"] boolValue] ? @"复核部分完成，可查看未覆盖范围":@"复核完成"):(error.localizedDescription ?: @"在线复核未完成"));
        dispatch_async(dispatch_get_main_queue(),^{if(!owner || ![owner detachOnlineClient:client generation:generation])return;if(![extraAtStart isEqual:owner.supplement.string] || ![report[@"version"] isEqual:owner.report[@"version"]]){owner.validation.stringValue=@"原范围的复核已结束，当前填写保留；重新本机检查后可复核新范围。";return;}owner.primary.enabled=YES;owner.supplement.editable=YES;owner.onlineButton.enabled=YES;owner.assistantButton.enabled=YES;owner.acknowledge.state=NSControlStateValueOff;owner.assistantFingerprint=AMPreflightJobForReport(owner.report[@"version"])[@"fingerprint"];[owner refreshReport];[owner pollReview:nil];if(owner.reportStale)return;
            owner.validation.stringValue=answer ? ([answer[@"cached"] boolValue] ? @"已复用报告":([answer[@"partial"] boolValue] ? @"复核完成，部分材料未覆盖":@"复核完成")):(error.localizedDescription ?: @"复核已取消，保留本机报告。");
            owner.validation.textColor=answer ? Muted():NSColor.systemOrangeColor;
            if(answer && [answer[@"completedUnits"] unsignedIntegerValue]<[answer[@"totalUnits"] unsignedIntegerValue]){owner.onlineButton.title=@"继续检查";owner.validation.stringValue=[NSString stringWithFormat:@"检查未完成 · 已完成 %@/%@ 部分",answer[@"completedUnits"],answer[@"totalUnits"]];}
            if(!answer){owner.reviewFailure=@{@"reason":error.localizedDescription ?: @"复核已取消",@"code":@(error.code)};owner.validation.stringValue=error.code==1001 ? @"输出达到上限":(client.cancelled ? @"复核已停止":@"在线复核未完成");owner.validation.toolTip=nil;owner.onlineButton.title=@"继续检查";owner.findingDetail.markdown=AMPreflightReportMarkdown(owner.report,owner.snapshot,PFEffectiveReview(owner.report[@"version"]));}

        });
    },^(BOOL beforeStart){[client cancelImmediately];if(beforeStart)dispatch_async(dispatch_get_main_queue(),^{if(![owner detachOnlineClient:client generation:generation])return;owner.validation.stringValue=@"已取消排队，未发送材料。";});});client.operationID=self.operationID;self.operationView.operationID=self.operationID;
}
- (BOOL)detachOnlineClient:(AMOnlineReviewClient *)client generation:(NSUInteger)generation {
    for(NSString *key in self.onlineRequests.allKeys)if(self.onlineRequests[key]==client)[self.onlineRequests removeObjectForKey:key];
    if(self.onlineClient!=client)return NO;self.onlineClient=self.onlineRequests.allValues.lastObject;self.checking=self.localChecking || self.onlineRequests.count>0;if(self.onlineClient)AMConfigureStopButton(self.onlineButton,@"停止复核");else{self.onlineButton.title=@"在线复核…";self.onlineButton.image=nil;self.onlineButton.imagePosition=NSNoImage;self.onlineButton.bordered=YES;self.onlineButton.toolTip=nil;self.onlineButton.accessibilityLabel=@"在线复核";}self.operationView.hidesCancellation=self.onlineClient!=nil;self.onlineButton.enabled=self.onlineClient || (self.report && !self.reportStale);
    if(!self.localChecking){self.primary.enabled=YES;self.supplement.editable=YES;self.assistantButton.enabled=self.report!=nil && !self.reportStale;}
    if(self.onlineClient){self.operationID=self.onlineClient.operationID;self.operationView.operationID=self.operationID;self.operationView.hidesCancellation=YES;}
    return !self.closed && self.previewGeneration==generation && !self.onlineClient;
}
- (void)reviewOptions:(id)sender {self.confirmedOnlineSnapshot=nil;self.queueOnlineRequest=YES;[self onlineReview:sender];self.queueOnlineRequest=NO;}
- (void)showReportStatus:(id)sender {NSAlert *alert=NSAlert.new;alert.messageText=@"当前检查状态";alert.informativeText=self.validation.stringValue ?: @"尚未开始检查。";[alert addButtonWithTitle:@"好"];[alert runModal];}
- (void)assistantReview:(id)sender {
    [self pollReview:nil];if(self.reportStale || self.checking || self.closed || !self.report)return;
    PFMaterials *materials=[[PFMaterials alloc] initWithSnapshot:self.reviewMaterialsSnapshot ?: self.snapshot report:self.report requirements:self.requirements];materials.materialRoot=[NSURL fileURLWithPath:self.course[@"path"]];[materials.window center];NSModalResponse response=[NSApp runModalForWindow:materials.window];[materials.window orderOut:nil];if(response!=NSModalResponseOK)return;
    // The user may have edited the original files while reviewing the preview.
    [self pollReview:nil];if(self.reportStale)return;
    self.requirements=materials.requirements;self.reviewMaterialsSnapshot=[materials selectedSnapshot];[self bindReviewMaterials];NSArray *images=[materials selectedImages];NSDictionary *snapshot=[materials selectedSnapshot],*report=self.report;NSString *requirements=self.requirements;BOOL attachment=materials.destination.indexOfSelectedItem==0;
    NSString *operation=AMOperationBegin(@"准备Skill复核材料",@"Skill",NO,nil);self.operationID=operation;self.operationView.operationID=operation;self.checking=YES;self.primary.enabled=NO;self.assistantButton.enabled=NO;self.validation.stringValue=@"正在检查敏感信息并准备所选材料…";NSUInteger generation=++self.previewGeneration;__weak typeof(self) owner=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;NSURL *folder=AMPreflightFolder(NSUUID.UUID.UUIDString);NSDictionary *context=AMPreflightExport(report,snapshot,requirements,images,folder,&error);BOOL ok=context && AMPreflightRegister(context,report,owner.course[@"fork"] ?: @"",&error);NSURL *archive=ok && attachment ? AMPreflightAttachmentArchive(context[@"batchID"],&error):nil;if(attachment && !archive)ok=NO;AMOperationFinish(operation,ok ? @"success":@"failed",ok ? @"Skill材料已准备好":error.localizedDescription ?: @"材料准备失败");
        dispatch_async(dispatch_get_main_queue(),^{if(!owner || owner.previewGeneration!=generation)return;owner.checking=NO;owner.primary.enabled=YES;owner.assistantButton.enabled=YES;if(!ok){owner.validation.stringValue=error.localizedDescription ?: @"材料未准备好，可重试。";return;}
            NSAlert *ready=NSAlert.new;ready.messageText=attachment ? @"材料包已准备好":@"材料已准备好：本机助手";ready.informativeText=attachment ? @"材料包：AM-Helper-review.zip":@"仅交给已获准访问所选本机材料的助手。";
            [ready addButtonWithTitle:attachment ? @"显示附件包并复制指令":@"复制本机指令"];[ready addButtonWithTitle:@"稍后"];if([ready runModal]==NSAlertFirstButtonReturn){if(attachment){[NSPasteboard.generalPasteboard clearContents];[NSPasteboard.generalPasteboard setString:AMPreflightAttachmentPrompt() forType:NSPasteboardTypeString];[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[archive]];}else AMPreflightJobAction(@"copy",context[@"batchID"]);}
            owner.validation.stringValue=attachment ? @"材料包已准备好":@"等待本机助手复核结果";[owner refreshReport];
        });
    });
}
@end
