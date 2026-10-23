#import <objc/runtime.h>
#import "SSCourseWindow.h"
#import <fcntl.h>
#import <unistd.h>
#import "SSGit.h"
#import "SSGitHub.h"
#import "SSLocalData.h"
#import "DDLCore.h"
#import "DDLUI.h"
#import "SSAssignments.h"
#import "SSRecognition.h"
#import "SSSecurity.h"
#import "AMUI-Swift.h"
#import "AMRenderer.h"
#import "AMActivityPresentation.h"

#import "SSSubmission.inc"

@interface SSCourseTable : NSTableView @end
@implementation SSCourseTable
- (void)keyDown:(NSEvent *)event { if ([event.charactersIgnoringModifiers isEqual:@"\r"] && self.selectedRow >= 0) { [NSApp sendAction:self.doubleAction to:self.target from:self]; return; } [super keyDown:event]; }
@end

#import "AMCourseWorkflow.inc"

static NSButton *SSButton(NSString *text, id target, SEL action, NSRect frame) { ActionButton *button=Button(text,target,action,0);button.frame=frame;return button; }
@interface SSCourseController ()
@property AMSubmissionHistoryController *submissionHistory;
@property NSString *submissionTaskID;
@property(nonatomic) SSGitHub *github;
@property(nonatomic) SSGit *git;
@property NSMutableDictionary<NSString *,AMCourseOperationContext *> *workflowContexts;
@property NSMutableDictionary<NSString *,AMCourseOperationContext *> *workflowFailures;
@property AMCourseOperationContext *workflowAwaitingLogin;
@property AMWorkflowNotice *workflowNotice;
@property AMCourseOperationContext *workflowNoticeContext;
@property NSMutableSet *dismissedWorkflowNotices;
@property NSMutableArray<NSMutableDictionary *> *courses;
@property NSMutableDictionary<NSString *, NSArray *> *candidates;
@property NSMutableDictionary<NSString *, NSArray *> *materials;
@property NSMutableDictionary *kindOverrides;
@property NSMutableDictionary *automaticDeferrals;
@property NSMutableDictionary *skillProgress;
@property NSMutableDictionary *skillBatches;
@property NSMutableDictionary *skillJobs;
@property NSTimer *skillTimer;
@property NSMutableArray *skillWatchers;
@property NSPopUpButton *typeFilter;
@property NSButton *typeButton;
@property NSArray<NSDictionary *> *availableForks;
@property dispatch_queue_t queue;
@property dispatch_queue_t externalQueue;
@property NSProgress *discoveryCancellation;
#ifdef DDL_TESTING
@property(copy) SSGit *(^workflowGitFactory)(void);
@property(copy) SSGitHub *(^workflowAPIFactory)(void);
#endif
@property SSGit *externalReader;
@property SSGitHub *externalAPI;
#ifdef DDL_TESTING
@property(copy) SSGit *(^externalReaderFactory)(NSDictionary *course);
#endif
@property AMCourseController *courseWorkspace;
@property NSPopUpButton *reviewFilter;
@property NSInteger presentedSection;
@property NSInteger presentedType;
@property NSInteger presentedReviewFilter;
@property NSSegmentedControl *sections;
@property NSStackView *nativeHeader;
@property NSStackView *operationStatus;
@property NSView *progressRow;
@property NSSearchField *search;
@property NSString *query;
@property NSString *selectedFork;
@property NSString *selectedCandidateID;
@property NSMutableDictionary *pageStates;
@property NSUInteger workGeneration;
@property NSButton *scanButton;
@property NSButton *syncButton;
@property NSButton *commitButton;
@property NSButton *moreButton;
@property NSButton *assistantButton;
@property NSButton *assistantImportButton;
@property NSButton *reviewButton;
@property NSButton *setupButton;
@property NSButton *recoveryButton;
@property AMSkillJobsController *skillJobsController;
@property BOOL showingSkillJobs;
@property NSMutableDictionary *deferredScans;
@property NSButton *cancelReadButton;
@property NSProgressIndicator *progress;
@property NSTextField *emptyLabel;
@property NSMutableDictionary *statuses;
@property NSString *operationFork;
@property NSString *operationKind;
@property NSString *operationPhase;
@property(nonatomic) NSString *operationID;
@property(nonatomic) NSString *statusFork;
@property BOOL connected;
@property BOOL preview;
@property BOOL guided;
@property AMSetupController *setupWorkspace;
@property NSWindow *setupWindow;
@property NSMutableArray<NSMutableDictionary *> *setupRecords;
@property NSInteger setupStep;
@property NSDictionary *loginChallenge;
@property NSArray *setupSelection;
@property BOOL firstCheckRunning;
@property NSMutableDictionary *errorDetails;
@property BOOL refreshing;
@property NSTableView *table;
@property NSTextView *detail;
@property NSTextField *accountLabel;
@property NSTextField *statusLabel;
@property NSTimer *timer;
@property BOOL busy;
@property BOOL discoveringExternal;
@property NSDate *lastExternalDiscovery;
@property NSMutableDictionary *externalOffsets;
@property NSMutableDictionary *completionReverifyTimes;
#ifdef DDL_TESTING
@property(copy) NSArray * (^recognitionScopeSelector)(PFMaterials *materials);
#endif
@property BOOL loginActive;
@property NSArray<NSButton *> *actionButtons;
@property NSDictionary *reports;
@property SSSubmissionController *submission;
@property NSWindow *checkScopeWindow;
@property AMCheckScopeController *checkScope;
@property NSArray *checkScopeRecords;
@property NSUInteger checkScopeGeneration;
@property NSString *checkScopeOperation;
@property NSUInteger checkPreviewGeneration;
@property BOOL allowingExitSubmission;
@property BOOL exitSubmissionInFlight;
@property AMReviewController *reviewWorkspace;
@property BOOL resolvingReview;
@property (readwrite) BOOL submissionFailedDuringExit;
@end

@implementation SSCourseController
@synthesize git=_git,github=_github,operationID=_operationID,statusFork=_statusFork;
- (SSGit *)git{return AMCourseContext(self).git ?: _git;}
- (SSGitHub *)github{return AMCourseContext(self).api ?: _github;}
- (NSString *)operationID{return AMCourseContext(self).identifier ?: _operationID;}
- (NSString *)statusFork{return AMCourseContext(self).course[@"fork"] ?: _statusFork;}
@synthesize usesToolbar=_usesToolbar;
- (void)setUsesToolbar:(BOOL)usesToolbar {
    if(_usesToolbar==usesToolbar)return;_usesToolbar=usesToolbar;
    if(usesToolbar && self.nativeHeader){
        for(NSView *row in self.nativeHeader.arrangedSubviews.copy)if(row!=self.nativeHeader.arrangedSubviews.firstObject){[self.nativeHeader removeArrangedSubview:row];[row removeFromSuperview];}
        for(NSView *view in @[self.scanButton,self.syncButton,self.commitButton,self.assistantButton,self.moreButton,self.reviewFilter,self.typeFilter,self.search])[view removeFromSuperview];
        [self layoutContent];
    }
}
- (instancetype)initWithPreview:(BOOL)preview {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        self.preview = preview; self.github = SSGitHub.new; self.git = SSGit.new;
        self.git.scanCheckpoint=^BOOL(NSMutableDictionary *cache,NSError **error){return AMScanCacheSave(cache,error);};
        self.courses = NSMutableArray.array; self.candidates = NSMutableDictionary.dictionary; self.statuses = NSMutableDictionary.dictionary; self.query = @""; self.pageStates = NSMutableDictionary.dictionary;
        self.materials = NSMutableDictionary.dictionary;self.errorDetails=NSMutableDictionary.dictionary;
        NSDictionary *discoveries = preview ? nil : SSReadPlist(@"discoveries.plist");
        if ([discoveries[@"candidates"] isKindOfClass:NSDictionary.class]) [self.candidates addEntriesFromDictionary:discoveries[@"candidates"]];
        if ([discoveries[@"materials"] isKindOfClass:NSDictionary.class]) [self.materials addEntriesFromDictionary:discoveries[@"materials"]];
        self.skillProgress=[discoveries[@"skillProgress"] isKindOfClass:NSDictionary.class] ? [discoveries[@"skillProgress"] mutableCopy] : NSMutableDictionary.dictionary;
        self.skillBatches=[discoveries[@"skillBatches"] isKindOfClass:NSDictionary.class] ? [discoveries[@"skillBatches"] mutableCopy] : NSMutableDictionary.dictionary;
        self.skillJobs=[discoveries[@"skillJobs"] isKindOfClass:NSDictionary.class] ? [discoveries[@"skillJobs"] mutableCopy]:NSMutableDictionary.dictionary;
        self.skillWatchers=NSMutableArray.array;
        for(NSString *batch in self.skillJobs.allKeys){NSMutableDictionary *job=[self.skillJobs[batch] mutableCopy];if([job[@"state"] isEqual:@"核验中"])job[@"state"]=@"等待助手";self.skillJobs[batch]=job;}
        id overrides = preview ? nil : SSReadPlist(@"discovery-overrides.plist");
        self.kindOverrides = [overrides isKindOfClass:NSDictionary.class] ? [overrides mutableCopy] : NSMutableDictionary.dictionary;
        id deferred=preview ? nil : SSReadPlist(@"automatic-review.plist");self.automaticDeferrals=[deferred isKindOfClass:NSDictionary.class] ? [deferred mutableCopy] : NSMutableDictionary.dictionary;
        NSArray *saved = preview ? @[] : SSReadPlist(@"courses.plist");
        for (id item in [saved isKindOfClass:NSArray.class] ? saved : @[]) if ([item isKindOfClass:NSDictionary.class] && [item[@"fork"] isKindOfClass:NSString.class]) [self.courses addObject:[item mutableCopy]];
        self.connected = !preview && self.github.hasCredentials;
        __weak typeof(self) weakSelf = self;
        self.git.identityVerifier = ^NSDictionary *(NSDictionary *course, NSError **error) { return [weakSelf.github verifyCourse:course error:error]; };
        [self configureCredentialAccess];
        self.git.progress = ^(NSString *phase) { dispatch_async(dispatch_get_main_queue(), ^{ if (weakSelf.busy) [weakSelf status:phase]; }); };
        self.queue = dispatch_queue_create("ddl.course-work", DISPATCH_QUEUE_SERIAL);
        self.externalQueue=dispatch_queue_create("ddl.external-history",DISPATCH_QUEUE_SERIAL);
        NSError *decisionError=nil;if(!preview)AMReviewDecisions(&decisionError);[self buildUI];[self refreshCourses];if(decisionError)[self showError:decisionError];
    } return self;
}
- (void)configureCredentialAccess { __weak typeof(self) weakSelf=self;self.git.teacherCredentialProvider=[@[@"oauth",@"githubCLI"] containsObject:self.github.authType] ? ^NSString *(NSDictionary *course,NSError **error){if(![weakSelf.github readableTeacher:course error:error])return nil;return [weakSelf.github accessToken:error];} : nil; }
- (NSWindow *)window { return self.view.window; }
- (BOOL)operationBusy {return self.busy || self.workflowContexts.count>0;}
- (NSSegmentedControl *)navigationControl {return self.sections;}
- (BOOL)hasCheckWorkspace {return self.checkScopeWindow!=nil;}
- (NSArray *)submissionCourses {NSMutableArray *rows=NSMutableArray.array;for(NSDictionary *course in self.courses)if([course[@"fork"] length] && [course[@"branch"] length] && [course[@"upstream"] length])[rows addObject:@{@"fork":course[@"fork"],@"branch":course[@"branch"],@"upstream":course[@"upstream"]}];return rows;}
- (NSSet *)editingTaskIDs {NSMutableSet *ids=NSMutableSet.set;BOOL visible=!self.view.hidden && self.view.window!=nil;if(((visible && !self.reviewWorkspace.view.hidden) || self.reviewWorkspace.hasUnsavedChanges) && self.reviewWorkspace.editingTaskID)[ids addObject:self.reviewWorkspace.editingTaskID];if(((visible && !self.courseWorkspace.view.hidden) || self.courseWorkspace.hasUnsavedChanges) && self.courseWorkspace.editingTaskID)[ids addObject:self.courseWorkspace.editingTaskID];return ids;}
- (void)showSubmissionCompletion:(NSUInteger)count {[self status:[NSString stringWithFormat:@"已完成 %lu 项",(unsigned long)count]];}
- (BOOL)hasUnsavedReview { return self.reviewWorkspace.hasUnsavedChanges || self.courseWorkspace.hasUnsavedChanges; }
- (BOOL)resolveUnsavedReview { if(self.setupWindow.sheetParent){NSAlert *alert=NSAlert.new;alert.messageText=@"课程配置尚未关闭";alert.informativeText=@"已成功关联的课程已经保存；尚未关联的目录选择会被放弃。";[alert addButtonWithTitle:@"继续配置"];[alert addButtonWithTitle:@"放弃未关联选择并继续"];if([alert runModal]!=NSAlertSecondButtonReturn)return NO;[self closeCourseSetup];} self.resolvingReview=YES; self.reviewWorkspace.paused=NO; self.courseWorkspace.paused=NO; BOOL ok=[self.reviewWorkspace resolveUnsavedChanges] && [self.courseWorkspace resolveUnsavedChanges]; self.resolvingReview=NO; self.reviewWorkspace.paused=self.operationsPaused; self.courseWorkspace.paused=self.operationsPaused; return ok; }
- (BOOL)saveConfigurationDraftForExit {if(!self.setupWindow)return YES;[self.setupWorkspace requestCloseSavingDraft];return self.setupWindow==nil;}
- (void)discardReview { [self.reviewWorkspace discardChanges];[self.courseWorkspace discardChanges];[self closeCourseSetup]; }
- (BOOL)hasSubmissionSheet { return self.submission.window.sheetParent != nil || self.checkScopeWindow != nil; }
- (BOOL)hasUnsavedSubmission { return (self.checkScopeWindow && self.checkScope.hasUnsavedChanges) || (self.submission && (!self.submission.closed || self.submission.preserveClosedDraft) && !self.submission.submittedSuccessfully && self.submission.hasUnsavedChanges); }
- (void)setOperationsPaused:(BOOL)paused { _operationsPaused = paused;if(paused){[self.discoveryCancellation cancel];self.externalAPI.requestsCancelled=YES;[self.externalReader cancelCurrentOperation];} [self refreshPresentation]; }
- (void)cancelPendingLogin { [self cancelLogin:nil]; }
- (void)discardSubmission { [self closeCheckScope];[self.submission cancel:nil]; self.submission = nil; }
- (void)acknowledgeSubmissionFailure { self.submissionFailedDuringExit = NO; }
- (BOOL)persistForExit:(NSError **)error { return self.preview || SSWritePlist(@"courses.plist", self.courses, error); }
- (BOOL)saveSubmissionForExit {
    if(self.checkScopeWindow){[self.checkScope setProgress:@"请完成或取消文件范围选择，再退出。"];return NO;}
    if(self.submission.closed && !self.window.attachedSheet){[self.submission resumeAfterSubmissionFailure:nil];[self.window beginSheet:self.submission.window completionHandler:nil];}
    self.allowingExitSubmission = YES; self.exitSubmissionInFlight = YES;
    BOOL saved = [self.submission saveForExit]; self.allowingExitSubmission = NO;
    if (!saved) self.exitSubmissionInFlight = NO;
    return saved;
}
- (NSString *)accountSummary { if (self.loginActive) return @"取消 GitHub 登录"; if (self.busy && !self.connected) return @"正在连接 GitHub…"; return self.connected ? @"GitHub 已连接" : @"连接 GitHub"; }
- (void)buildUI {
    Surface *root = Box(Canvas(), 0); root.frame = NSMakeRect(0, 0, 960, 600); self.view = root;
    __weak typeof(self) weakSelf = self; root.onResize = ^{ [weakSelf layoutContent]; }; root.onAppearanceChange = ^{ AMRefreshViewAppearance(weakSelf.view); };
    self.accountLabel = Text(@"", 13, NSFontWeightRegular, Muted()); [root addSubview:self.accountLabel];
    self.scanButton = SSButton(@"检查新作业", self, @selector(scan:), NSZeroRect);((ActionButton *)self.scanButton).tone=1; [root addSubview:self.scanButton];
    self.syncButton = SSButton(@"同步课程文件", self, @selector(sync:), NSZeroRect); [root addSubview:self.syncButton];
    self.commitButton = SSButton(@"提交作业", self, @selector(commit:), NSZeroRect); [root addSubview:self.commitButton];
    self.moreButton = SSButton(@"更多", self, @selector(more:), NSZeroRect); [root addSubview:self.moreButton];
    self.assistantButton=SSButton(@"助手识别",self,@selector(exportSkillContext:),NSZeroRect);[root addSubview:self.assistantButton];
    self.assistantImportButton=SSButton(@"导入助手结果…",self,@selector(importSkillResults:),NSZeroRect);[root addSubview:self.assistantImportButton];
    self.sections = Segments(@[@"课程内容", @"已加入任务", @"仓库信息", @"提交记录"], self, @selector(sectionChanged:));
    self.typeFilter = [[PastelPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [self.typeFilter addItemsWithTitles:@[@"全部类型", @"作业", @"课上任务", @"考试", @"待确认类型"]]; self.typeFilter.target = self; self.typeFilter.action = @selector(sectionChanged:); [root addSubview:self.typeFilter];
    self.reviewFilter = [[PastelPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [self.reviewFilter addItemsWithTitles:@[@"全部待审核", @"新作业", @"更新建议", @"已删除"]]; self.reviewFilter.target = self; self.reviewFilter.action = @selector(sectionChanged:); [root addSubview:self.reviewFilter];
    self.search = [[NSSearchField alloc] initWithFrame:NSZeroRect]; self.search.placeholderString = @"搜索作业或来源文件"; self.search.delegate = self; self.search.sendsSearchStringImmediately = YES; [root addSubview:self.search];
    self.statusLabel = Text(@"", 12, NSFontWeightRegular, Muted()); [root addSubview:self.statusLabel];
    self.progress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect]; self.progress.style = NSProgressIndicatorStyleBar; self.progress.displayedWhenStopped = NO; [root addSubview:self.progress];
    self.setupButton = SSButton(@"添加课程", self, @selector(setup:), NSZeroRect); [root addSubview:self.setupButton];
    self.recoveryButton = SSButton(@"", self, @selector(recover:), NSZeroRect); [root addSubview:self.recoveryButton];
    self.emptyLabel = Text(@"", 14, NSFontWeightMedium, Muted()); self.emptyLabel.alignment = NSTextAlignmentCenter; [root addSubview:self.emptyLabel];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect]; scroll.hasVerticalScroller = YES; scroll.autohidesScrollers = YES; scroll.borderType = NSNoBorder;
    self.table = [[SSCourseTable alloc] initWithFrame:NSZeroRect]; self.table.delegate = self; self.table.dataSource = self; self.table.rowHeight = 44; self.table.columnAutoresizingStyle = NSTableViewNoColumnAutoresizing; self.table.intercellSpacing = NSMakeSize(8, 0); self.table.usesAlternatingRowBackgroundColors = NO; self.table.backgroundColor = Card();
    for (NSArray *spec in @[@[@"title", @"作业", @250], @[@"due", @"截止时间", @190], @[@"source", @"来源", @240], @[@"state", @"状态", @100]]) { NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:spec[0]]; column.title = spec[1]; column.width = [spec[2] doubleValue]; column.minWidth = 72; [self.table addTableColumn:column]; }
    self.table.target = self; self.table.action = @selector(candidateSelected:); self.table.doubleAction = @selector(review:); scroll.documentView = self.table; [root addSubview:scroll];
    NSScrollView *detailScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect]; detailScroll.hasVerticalScroller = YES; detailScroll.autohidesScrollers = YES; detailScroll.drawsBackground = NO;
    self.detail = [[PastelNotesView alloc] initWithFrame:NSZeroRect]; self.detail.editable = NO; self.detail.font = [NSFont systemFontOfSize:13]; self.detail.textColor = Ink(); self.detail.backgroundColor = Canvas(); self.detail.textContainerInset = NSMakeSize(8, 8); self.detail.autoresizingMask = NSViewWidthSizable; self.detail.textContainer.widthTracksTextView = YES; detailScroll.documentView = self.detail; [root addSubview:detailScroll];
    self.reviewButton = SSButton(@"审核作业…", self, @selector(review:), NSZeroRect); self.reviewButton.bezelColor=NSColor.controlAccentColor; [root addSubview:self.reviewButton];
    self.typeButton = SSButton(@"更改类型…", self, @selector(changeType:), NSZeroRect); [root addSubview:self.typeButton];
    self.actionButtons = @[self.scanButton, self.syncButton, self.commitButton, self.moreButton, self.setupButton];
    self.reviewWorkspace = [AMReviewController new];
    __weak typeof(self) owner = self;
    self.reviewWorkspace.sourceHandler=^NSDictionary *(NSString *identifier){
        NSDictionary *source=[owner reviewSourceWithID:identifier];if(!source)return nil;
        NSMutableDictionary *copy=[SSEnrichDiscovery(source) mutableCopy];
        for(NSDictionary *task in owner.tasksProvider ? owner.tasksProvider():@[])if([task[@"sourceID"] isEqual:identifier]){copy[@"existingTask"]=task;break;}
        return copy;
    };
    self.reviewWorkspace.saveHandler = ^NSString *(NSArray *items) {
        if ((owner.operationsPaused && !owner.resolvingReview)) return @"请等待当前操作结束后再保存。";
        if (!owner.saveReviewItems) return @"任务保存接口尚未就绪。";
        NSString *previous=owner.selectedCandidateID;NSUInteger nextIndex=0;NSArray *before=owner.visible;
        for(NSUInteger i=0;i<before.count;i++)if([before[i][@"id"] isEqual:previous]){nextIndex=i;break;}
        NSString *message = owner.saveReviewItems(items, NO);
        if (!message.length) {
            NSArray *remaining=owner.visible;BOOL retained=NO;for(NSDictionary *record in remaining)if([record[@"id"] isEqual:previous]){retained=YES;break;}
            if(!retained)owner.selectedCandidateID=remaining.count ? remaining[MIN(nextIndex,remaining.count-1)][@"id"]:nil;
            [owner refreshPresentation];
        }
        return message;
    };
    self.reviewWorkspace.decisionHandler=^NSString *(NSArray *records,BOOL deleted){
        if(owner.operationsPaused)return @"正在退出，请稍后重试。";
        if(deleted)for(NSDictionary *record in records){NSDictionary *live=[owner reviewSourceWithID:record[@"id"]];if(!live || ![live[@"blobSHA"] isEqual:record[@"blobSHA"]])return @"来源已变化，请刷新列表后再删除建议。";if([[owner stateForCandidate:live] isEqual:@"已导入"])return @"该作业已加入任务，请在任务页管理；这里仅删除待审核建议。";}
        NSError *error=nil;if(!AMReviewSetDeleted(records,deleted,&error))return error.localizedDescription ?: @"审核记录未保存，请重试。";
        [owner refreshPresentation];return @"";
    };
    [self addChildViewController:self.reviewWorkspace]; [root addSubview:self.reviewWorkspace.view];
    self.courseWorkspace=AMCourseController.new;
    self.courseWorkspace.saveHandler=self.reviewWorkspace.saveHandler;
    self.courseWorkspace.sourceHandler=self.reviewWorkspace.sourceHandler;
    self.courseWorkspace.decisionHandler=self.reviewWorkspace.decisionHandler;
    self.courseWorkspace.actionHandler=^(NSString *action,NSString *identifier){
        if([action isEqual:@"course-result"]){if([owner selectCourseID:identifier]){owner.sections.selectedSegment=0;[owner.typeFilter selectItemAtIndex:0];owner.query=@"";owner.search.stringValue=@"";[owner refreshPresentation];}return;}
        if([action isEqual:@"restore-notes"]){if(owner.restoreTaskNotes)owner.restoreTaskNotes(identifier);return;}
        if([action isEqual:@"edit-task"]){if(owner.editTask)owner.editTask(identifier);return;}
        if([action isEqual:@"select"]){dispatch_async(dispatch_get_main_queue(),^{
            for(NSDictionary *record in owner.visible)if([record[@"id"] isEqual:identifier]){owner.selectedCandidateID=identifier;[owner refreshPresentation];break;}
        });return;}
        if(owner.operationsPaused)return;
        NSArray *visible=owner.visible;
        for(NSUInteger index=0;index<visible.count;index++)if([visible[index][@"id"] isEqual:identifier]){
            owner.selectedCandidateID=identifier;[owner.table selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
            if([action isEqual:@"type"]){if(owner.hasUnsavedReview && ![owner resolveUnsavedReview])return;[owner changeType:nil];}else if([action isEqual:@"review"])[owner review:nil];break;
        }
    };
    [self addChildViewController:self.courseWorkspace];[root addSubview:self.courseWorkspace.view];
    self.submissionHistory=AMSubmissionHistoryController.new;[self addChildViewController:self.submissionHistory];[root addSubview:self.submissionHistory.view];self.submissionHistory.view.hidden=YES;
    __weak typeof(self) historyOwner=self;self.submissionHistory.actionHandler=^(NSString *action,NSString *identifier){[historyOwner submissionAction:action identifier:identifier];};
    self.skillJobsController=AMSkillJobsController.new;[self addChildViewController:self.skillJobsController];[root addSubview:self.skillJobsController.view];self.skillJobsController.view.hidden=YES;
    self.skillJobsController.actionHandler=^(NSString *action,NSString *batch){[owner skillJobAction:action batch:batch];};
    self.cancelReadButton=SSButton(@"",self,@selector(cancelReadOperation:),NSZeroRect);AMConfigureStopButton(self.cancelReadButton,@"停止");[root addSubview:self.cancelReadButton];self.cancelReadButton.hidden=YES;
    self.nativeHeader=NSStackView.new;self.nativeHeader.orientation=NSUserInterfaceLayoutOrientationVertical;self.nativeHeader.alignment=NSLayoutAttributeLeading;self.nativeHeader.spacing=8;self.nativeHeader.translatesAutoresizingMaskIntoConstraints=NO;[root addSubview:self.nativeHeader];
    NSArray *headerRows=self.usesToolbar ? @[@[self.accountLabel,self.setupButton]]:@[@[self.accountLabel,self.setupButton],@[self.scanButton,self.syncButton,self.commitButton,self.assistantButton,self.moreButton],@[self.reviewFilter,self.typeFilter,self.search]];
    for(NSArray *controls in headerRows){
        NSStackView *row=[NSStackView stackViewWithViews:controls];row.orientation=NSUserInterfaceLayoutOrientationHorizontal;row.spacing=8;row.alignment=NSLayoutAttributeCenterY;row.detachesHiddenViews=YES;[self.nativeHeader addArrangedSubview:row];row.translatesAutoresizingMaskIntoConstraints=NO;[row.widthAnchor constraintEqualToAnchor:self.nativeHeader.widthAnchor].active=YES;
    }
    [NSLayoutConstraint activateConstraints:@[[self.nativeHeader.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],[self.nativeHeader.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],[self.nativeHeader.topAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.topAnchor]]];
    [self.search.widthAnchor constraintGreaterThanOrEqualToConstant:160].active=YES;[self.search.widthAnchor constraintLessThanOrEqualToConstant:360].active=YES;[self.search setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];[self.accountLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.operationStatus=NSStackView.new;self.operationStatus.orientation=NSUserInterfaceLayoutOrientationVertical;self.operationStatus.alignment=NSLayoutAttributeLeading;self.operationStatus.spacing=8;self.operationStatus.detachesHiddenViews=YES;self.operationStatus.translatesAutoresizingMaskIntoConstraints=NO;[root addSubview:self.operationStatus];
    NSStackView *statusRow=[NSStackView stackViewWithViews:@[self.statusLabel,self.recoveryButton,self.cancelReadButton]];
    statusRow.orientation=NSUserInterfaceLayoutOrientationHorizontal;statusRow.alignment=NSLayoutAttributeCenterY;statusRow.distribution=NSStackViewDistributionFill;statusRow.detachesHiddenViews=YES;
    // Stack views space alignment rectangles. Reserve the native drawing
    // outsets as well so complete control frames remain separate on older OSes.
    NSEdgeInsets labelInsets=self.statusLabel.alignmentRectInsets,buttonInsets=self.cancelReadButton.alignmentRectInsets;
    NSEdgeInsets recoveryInsets=self.recoveryButton.alignmentRectInsets;
    CGFloat buttonLeft=MAX(0,MAX(buttonInsets.left,recoveryInsets.left)),buttonRight=MAX(0,MAX(buttonInsets.right,recoveryInsets.right));
    statusRow.spacing=8+MAX(0,MAX(labelInsets.right,buttonRight))+buttonLeft;
    statusRow.edgeInsets=NSEdgeInsetsMake(MAX(4,MAX(buttonInsets.top,recoveryInsets.top)),MAX(4,labelInsets.left),MAX(4,MAX(buttonInsets.bottom,recoveryInsets.bottom)),MAX(4,buttonRight));
    [self.operationStatus addArrangedSubview:statusRow];
    // Keep the indicator's full frame inside its own row: AppKit's alignment
    // insets differ between legacy progress bars and the current appearance.
    CGFloat progressHeight=MAX(6,self.progress.fittingSize.height);
    self.progressRow=[[NSView alloc] initWithFrame:NSMakeRect(0,0,1,progressHeight)];self.progress.frame=self.progressRow.bounds;self.progress.autoresizingMask=NSViewWidthSizable | NSViewHeightSizable;[self.progressRow addSubview:self.progress];[self.operationStatus addArrangedSubview:self.progressRow];
    self.statusLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;[self.statusLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];[self.statusLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    for(NSButton *button in @[self.recoveryButton,self.cancelReadButton]){[button setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];[button setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];}
    [NSLayoutConstraint activateConstraints:@[[self.operationStatus.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],[self.operationStatus.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],[self.operationStatus.topAnchor constraintEqualToAnchor:self.nativeHeader.bottomAnchor constant:8],[statusRow.widthAnchor constraintEqualToAnchor:self.operationStatus.widthAnchor],[self.progressRow.widthAnchor constraintEqualToAnchor:self.operationStatus.widthAnchor],[self.progressRow.heightAnchor constraintEqualToConstant:progressHeight]]];
    if(self.usesToolbar){for(NSView *view in @[self.scanButton,self.syncButton,self.commitButton,self.assistantButton,self.moreButton,self.reviewFilter,self.typeFilter,self.search])[view removeFromSuperview];}
    [self layoutContent];
}
- (NSArray<NSString *> *)toolbarActionIdentifiers {
    if(self.inbox)return @[];
    if(self.selectedFork && ![self course])return @[@"AMCourseMore"];
    return [self course] ? @[@"AMCourseScan",@"AMCourseSync",@"AMCourseSubmit",@"AMCourseMore"]:@[@"AMCourseScan",@"AMCourseMore"];
}
- (NSToolbarItem *)toolbarItemForIdentifier:(NSString *)identifier {
    (void)self.view;
    if([identifier isEqual:@"AMCourseSearch"]){NSSearchToolbarItem *item=[[NSSearchToolbarItem alloc] initWithItemIdentifier:identifier];item.label=@"搜索课程内容";item.visibilityPriority=NSToolbarItemVisibilityPriorityHigh;item.searchField=self.search;item.preferredWidthForSearchField=220;return item;}
    NSDictionary *controls=@{@"AMCourseScan":self.scanButton,@"AMCourseSync":self.syncButton,@"AMCourseSubmit":self.commitButton,@"AMCourseMore":self.moreButton,@"AMCourseFilter":self.typeFilter};
    NSControl *control=controls[identifier];if(!control)return nil;
    if([control isKindOfClass:NSPopUpButton.class])return PopupToolbarItem(identifier,@"材料类型",(id)control);
    NSToolbarItem *item=[[NSToolbarItem alloc] initWithItemIdentifier:identifier];[control sizeToFit];item.view=control;
    item.label=[control isKindOfClass:NSButton.class] ? [(NSButton *)control title]:@"材料类型";item.visibilityPriority=[identifier isEqual:@"AMCourseSync"] ? NSToolbarItemVisibilityPriorityLow:([identifier isEqual:@"AMCourseScan"] ? NSToolbarItemVisibilityPriorityHigh:NSToolbarItemVisibilityPriorityStandard);
    NSMenuItem *overflow=[[NSMenuItem alloc] initWithTitle:item.label action:control.action keyEquivalent:@""];overflow.target=control.target;item.menuFormRepresentation=overflow;return item;
}
- (void)layoutContent {
    CGFloat w = NSWidth(self.view.bounds), h = NSHeight(self.view.bounds);
    if(self.usesToolbar){if(self.inbox && !self.reviewFilter.superview){[self.nativeHeader addArrangedSubview:self.reviewFilter];}else if(!self.inbox && self.reviewFilter.superview==self.nativeHeader){[self.nativeHeader removeArrangedSubview:self.reviewFilter];[self.reviewFilter removeFromSuperview];}}
    self.sections.hidden=NO;self.typeFilter.hidden=self.inbox || self.sections.selectedSegment!=0;self.reviewFilter.hidden=!self.inbox;self.search.hidden=self.inbox;self.assistantButton.hidden=self.inbox;self.assistantImportButton.hidden=YES;self.assistantButton.enabled=self.assistantImportButton.enabled=!self.operationsPaused;BOOL modelConfigured=![SSRecognitionSettings()[@"mode"] isEqual:@"rules"];self.assistantButton.hidden=self.inbox || !modelConfigured;self.assistantButton.title=modelConfigured ? @"AI增强识别…":@"Skill识别…";self.assistantButton.action=modelConfigured ? @selector(enhanceRecognition:):@selector(exportSkillContext:);
    self.syncButton.hidden=self.inbox || ![self course];self.commitButton.hidden=self.syncButton.hidden;
    self.cancelReadButton.hidden=!self.busy;self.progress.hidden=!self.busy;self.progressRow.hidden=!self.busy;
    // The activity toolbar owns feedback; status changes never move the workspace.
    self.operationStatus.hidden=YES;
    [self.view layoutSubtreeIfNeeded];CGFloat workspaceTop=NSMaxY(self.nativeHeader.frame)+8;
    self.table.enclosingScrollView.frame = NSMakeRect(0, 184, w, MAX(112, h - 348));
    self.detail.enclosingScrollView.frame = NSMakeRect(0, h - 152, w, 104); self.reviewButton.frame = NSMakeRect(w - 152, h - 40, 152, 36);
    self.typeButton.frame = NSMakeRect(0, h - 40, 136, 36);
    self.emptyLabel.frame = NSMakeRect(16, 204, w - 32, 72);
    CGFloat reviewTop=workspaceTop;
    self.reviewWorkspace.view.frame = NSMakeRect(0, reviewTop, w, MAX(120,h - reviewTop));
    self.reviewWorkspace.view.hidden = !self.inbox;
    if (self.inbox) { self.table.enclosingScrollView.hidden = YES; self.detail.enclosingScrollView.hidden = YES; self.reviewButton.hidden = YES; self.typeButton.hidden = YES; self.emptyLabel.hidden = YES; self.search.hidden = YES; }
    else { self.detail.enclosingScrollView.hidden = NO; self.search.hidden = NO; }
    self.courseWorkspace.view.hidden=self.inbox;self.courseWorkspace.view.frame=NSMakeRect(0,workspaceTop,w,MAX(120,h-workspaceTop));
    if(!self.inbox){self.table.enclosingScrollView.hidden=YES;self.detail.enclosingScrollView.hidden=YES;self.reviewButton.hidden=YES;self.typeButton.hidden=YES;self.emptyLabel.hidden=YES;}
    self.submissionHistory.view.frame=NSMakeRect(0,workspaceTop,w,MAX(120,h-workspaceTop));self.submissionHistory.view.hidden=self.inbox || self.sections.selectedSegment!=3 || self.showingSkillJobs;
    if(!self.submissionHistory.view.hidden){self.courseWorkspace.view.hidden=YES;self.reviewWorkspace.view.hidden=YES;}
    self.skillJobsController.view.frame=NSMakeRect(0,workspaceTop,w,MAX(120,h-workspaceTop));self.skillJobsController.view.hidden=!self.showingSkillJobs;
    if(self.showingSkillJobs){self.courseWorkspace.view.hidden=YES;self.reviewWorkspace.view.hidden=YES;}
    CGFloat available = w - 132; self.table.tableColumns[3].width = 96;
    NSArray *weights = @[@0.34, @0.28, @0.38];
    for (NSUInteger i = 0; i < 3; i++) self.table.tableColumns[i].width = MAX(72, available * [weights[i] doubleValue]);
}
- (void)setInbox:(BOOL)inbox {
    if (_inbox == inbox) return;
    NSString *oldKey = _inbox ? @"inbox" : @"courses";
    self.pageStates[oldKey] = @{@"fork":self.selectedFork ?: @"", @"query":self.query ?: @"", @"selection":self.selectedCandidateID ?: @"", @"scroll":@(self.table.enclosingScrollView.contentView.bounds.origin.y), @"section":@(self.sections.selectedSegment), @"type":@(self.typeFilter.indexOfSelectedItem), @"review":@(self.reviewFilter.indexOfSelectedItem)};
    self.showingSkillJobs=NO;
    _inbox = inbox; NSDictionary *state = self.pageStates[inbox ? @"inbox" : @"courses"];
    self.selectedFork = [state[@"fork"] length] ? state[@"fork"] : nil; self.selectedCandidateID = state[@"selection"]; self.query = state[@"query"] ?: @""; self.search.stringValue = self.query;
    self.sections.selectedSegment = [state[@"section"] integerValue]; [self.typeFilter selectItemAtIndex:[state[@"type"] integerValue]]; [self.reviewFilter selectItemAtIndex:[state[@"review"] integerValue]];
    [self refreshCourses]; [self.table.enclosingScrollView.contentView scrollToPoint:NSMakePoint(0, [state[@"scroll"] doubleValue])];
}
- (void)startAutomaticChecks {
    [self discoverExternalSubmissions:NO];
    if (self.preview || self.timer) return;
    [self startSkillReception];
    NSDictionary *progress=SSReadPlist(@"onboarding.plist");
    if([progress[@"completed"] boolValue] && self.connected)[self scanAll:nil];
    else if(!progress && !self.courses.count && !(self.tasksProvider ? self.tasksProvider().count:0)){
        // Show the welcome sheet once for a fresh installation, never on an upgrade
        // or merely because a previous configuration was left unfinished.
        if(SSWritePlist(@"onboarding.plist",@{@"welcomeShown":@YES},NULL))dispatch_async(dispatch_get_main_queue(),^{[self setup:nil];});
    }
    self.timer = [NSTimer scheduledTimerWithTimeInterval:6 * 3600 target:self selector:@selector(scanAll:) userInfo:nil repeats:YES];
}
- (void)dealloc { [self.timer invalidate];[self.skillTimer invalidate];for(dispatch_source_t source in self.skillWatchers)dispatch_source_cancel(source); }
- (NSUInteger)pendingCount {
    NSUInteger count = 0; NSMutableSet *seen = NSMutableSet.set;
    for (NSDictionary *course in self.courses) for (NSDictionary *candidate in [self discoveriesForFork:course[@"fork"]]) if ([candidate[@"kind"] isEqual:@"assignment"] && ![seen containsObject:candidate[@"id"]] && ![candidate[@"reviewDeleted"] boolValue] && ![[self stateForCandidate:candidate] isEqual:@"已导入"]) { [seen addObject:candidate[@"id"]]; count++; }
    for(NSDictionary *record in self.localReviewProvider ? self.localReviewProvider():@[])if(!AMReviewIsDeleted(record))count++;return count;
}
- (void)accountSettings:(id)sender {
    if(self.operationsPaused)return;if(self.busy){if(self.loginActive)[self cancelLogin:nil];return;}
    if(!self.connected){[self setup:nil];return;}
    NSAlert *alert=NSAlert.new;alert.messageText=@"GitHub 已连接";alert.informativeText=[@[@"oauth",@"githubCLI"] containsObject:self.github.authType] ? @"私有课程通过 HTTPS 访问，无需 SSH。登录令牌只保存在本机。旧 GitHub App 安装需在 GitHub 单独撤销。" : @"正在使用旧 GitHub App 登录，可切换到内置 GitHub 官方登录。";
    [alert addButtonWithTitle:@"配置课程…"];[alert addButtonWithTitle:@"退出登录"];[alert addButtonWithTitle:@"高级登录设置…"];[alert addButtonWithTitle:@"重新登录"];[alert addButtonWithTitle:@"关闭"];
    NSModalResponse choice=[alert runModal];if(choice==NSAlertFirstButtonReturn)[self addFork:nil];else if(choice==NSAlertSecondButtonReturn)[self signOut:nil];else if(choice==NSAlertThirdButtonReturn)[self authenticationSettings:nil];else if(choice==NSAlertThirdButtonReturn+1)[self login:nil];
}
- (void)authenticationSettings:(id)sender {
    if(self.busy || self.operationsPaused || self.preview)return;
    NSAlert *alert=AMVerticalChoiceAlert(@"登录与兼容设置",@"推荐 GitHub 官方登录。旧方式可能受组织限制；切换保留任务与凭据。",@[@"GitHub 官方登录",@"旧 GitHub App 登录",@"撤销旧 App 安装…",@"旧 App 公开配置…",@"旧 App 安装授权…",@"旧 OAuth 登录"]);
    NSModalResponse choice=AMRunVerticalChoiceAlert(alert);if(choice==NSAlertThirdButtonReturn){[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://github.com/settings/installations"]];return;}
    if(choice==NSAlertThirdButtonReturn+1){[self setClientID:nil];return;}if(choice==NSAlertThirdButtonReturn+2){[self installApp:nil];return;}
    if(choice!=NSAlertFirstButtonReturn && choice!=NSAlertSecondButtonReturn && choice!=NSAlertThirdButtonReturn+3)return;NSError *error=nil;
    if(![self.github selectAuthentication:choice==NSAlertFirstButtonReturn ? @"githubCLI":(choice==NSAlertSecondButtonReturn ? @"githubApp":@"oauth") error:&error]){[self showError:error];return;}
    [self configureCredentialAccess];self.connected=self.github.hasCredentials;if(!self.connected)[self login:nil];else [self refreshPresentation];
}
- (void)setup:(id)sender {
    if(self.busy || self.operationsPaused)return;self.guided=YES;
    NSDictionary *saved=self.preview ? nil:SSReadPlist(@"onboarding.plist");self.setupSelection=[saved[@"completed"] boolValue] ? nil:saved[@"selected"];
    if(self.connected && ![saved[@"completed"] boolValue] && [saved[@"step"] integerValue]>=2 && [saved[@"records"] isKindOfClass:NSArray.class]){
        self.setupRecords=NSMutableArray.array;for(NSDictionary *row in saved[@"records"])[self.setupRecords addObject:row.mutableCopy];self.setupStep=MIN(3,[saved[@"step"] integerValue]);self.setupSelection=saved[@"selected"];
        [self presentCourseSetup];[self updateCourseSetup:@"继续上次配置。检查不会自动重复执行；可以重试未完成课程。"];return;
    }
    self.setupStep=self.connected ? 1:0;[self presentCourseSetup];if(self.connected)[self addFork:nil];
}
- (void)startUsing:(id)sender { [self setup:sender]; }
- (void)chooseLocalFolder {
    NSAlert *alert = NSAlert.new; alert.messageText = @"关联课程文件夹"; alert.informativeText = @"已下载课程仓库时选择已有文件夹；还未下载时选择保存位置。";
    [alert addButtonWithTitle:@"选择已有文件夹"]; [alert addButtonWithTitle:@"下载课程仓库"]; [alert addButtonWithTitle:@"稍后"];
    NSModalResponse answer = [alert runModal]; if (answer == NSAlertFirstButtonReturn) [self linkFolder:nil]; else if (answer == NSAlertSecondButtonReturn) [self cloneFork:nil];
}
- (void)newStandaloneCourse:(id)sender {
    NSAlert *alert=NSAlert.new;alert.messageText=@"新建课程";NSTextField *name=[NSTextField textFieldWithString:@""];name.frame=NSMakeRect(0,0,300,24);name.placeholderString=@"课程名称";alert.accessoryView=name;[alert addButtonWithTitle:@"创建"];[alert addButtonWithTitle:@"取消"];
    if([alert runModal]!=NSAlertFirstButtonReturn)return;NSString *title=[name.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!title.length)return;
    NSMutableArray *catalog=[AMCourseCatalog(self.courses) mutableCopy];NSDictionary *entry=AMNewCourse(title);[catalog addObject:entry];NSError *error=nil;if(!AMSaveCourseCatalog(catalog,&error)){[self showError:error];return;}[self selectCourseID:entry[@"id"]];[self refreshPresentation];
}
- (void)renameCatalogCourse:(id)sender {
    NSMutableArray *catalog=[AMCourseCatalog(self.courses) mutableCopy];NSUInteger index=[catalog indexOfObjectPassingTest:^BOOL(NSDictionary *row,NSUInteger i,BOOL *stop){return [row[@"id"] isEqual:self.selectedFork] || [row[@"fork"] isEqual:self.selectedFork];}];if(index==NSNotFound)return;
    NSAlert *alert=NSAlert.new;alert.messageText=@"重命名课程";NSTextField *name=[NSTextField textFieldWithString:catalog[index][@"name"]];name.frame=NSMakeRect(0,0,300,24);alert.accessoryView=name;[alert addButtonWithTitle:@"保存"];[alert addButtonWithTitle:@"取消"];if([alert runModal]!=NSAlertFirstButtonReturn)return;
    NSString *title=[name.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!title.length)return;NSMutableDictionary *entry=[catalog[index] mutableCopy];entry[@"name"]=title;catalog[index]=entry;NSError *error=nil;if(!AMSaveCourseCatalog(catalog,&error)){[self showError:error];return;}[self refreshPresentation];
}
- (void)linkCatalogCourse:(id)sender {
    if(!self.courses.count){[self addFork:sender];return;}NSMutableArray *catalog=[AMCourseCatalog(self.courses) mutableCopy];NSDictionary *local=nil;for(NSDictionary *row in catalog)if([row[@"id"] isEqual:self.selectedFork])local=row;if(!local)return;
    NSAlert *alert=NSAlert.new;alert.messageText=@"关联课程仓库";NSPopUpButton *picker=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0,0,340,28)];for(NSDictionary *course in self.courses)[picker addItemWithTitle:course[@"fork"]];alert.accessoryView=picker;[alert addButtonWithTitle:@"关联"];[alert addButtonWithTitle:@"取消"];if([alert runModal]!=NSAlertFirstButtonReturn)return;
    NSDictionary *repository=self.courses[picker.indexOfSelectedItem];NSMutableDictionary *entry=local.mutableCopy;NSMutableSet *aliases=[NSMutableSet setWithArray:entry[@"aliases"] ?: @[]];for(NSDictionary *row in catalog.copy)if([row[@"fork"] isEqual:repository[@"fork"]]){[aliases addObject:row[@"id"]];[aliases addObjectsFromArray:row[@"aliases"] ?: @[]];[catalog removeObject:row];}[catalog removeObject:local];[aliases removeObject:entry[@"id"]];entry[@"aliases"]=aliases.allObjects;entry[@"fork"]=repository[@"fork"];if(repository[@"upstream"])entry[@"upstream"]=repository[@"upstream"];[catalog addObject:entry];NSError *error=nil;if(!AMSaveCourseCatalog(catalog,&error)){[self showError:error];return;}[self selectCourseID:repository[@"fork"]];[self refreshPresentation];
}
- (NSMenu *)courseActionsMenu {
    NSMenu *menu=NSMenu.new;menu.autoenablesItems=NO;NSDictionary *course=[self course];
    void (^add)(NSMenu *,NSString *,SEL,BOOL)=^(NSMenu *target,NSString *title,SEL action,BOOL enabled){NSMenuItem *item=[target addItemWithTitle:title action:action keyEquivalent:@""];item.target=self;item.enabled=enabled && !self.operationsPaused;};
    add(menu,@"识别问题…",@selector(showRecognitionFailures:),[self recognitionFailures].count>0);
    add(menu,@"增强识别…",@selector(enhanceRecognition:),course && ![SSRecognitionSettings()[@"mode"] isEqual:@"rules"]);
    add(menu,@"交给助手识别…",@selector(exportSkillContext:),YES);
    add(menu,@"识别批次与进度…",@selector(showSkillJobs:),YES);
    add(menu,@"重新分析材料…",@selector(exportAllSkillContext:),YES);
    [menu addItem:NSMenuItem.separatorItem];
    add(menu,@"新建课程…",@selector(newStandaloneCourse:),YES);add(menu,@"添加仓库课程…",@selector(addFork:),YES);add(menu,@"重命名课程…",@selector(renameCatalogCourse:),course!=nil);add(menu,@"关联文件夹…",@selector(linkFolder:),course!=nil);add(menu,@"下载课程…",@selector(cloneFork:),course!=nil);add(menu,@"打开文件夹",@selector(openFolder:),[course[@"path"] length]>0);
    if([course[@"pendingMergeTip"] length])add(menu,@"处理冲突…",@selector(continueMerge:),YES);
    if([course[@"pushFailed"] boolValue])add(menu,@"重试推送",@selector(push:),YES);
    if([self.errorDetails[self.selectedFork ?: @"all"] length])add(menu,@"操作详情…",@selector(operationDetails:),YES);
    [menu addItem:NSMenuItem.separatorItem];
    add(menu,[course[@"enabled"] isEqual:@NO] ? @"启用自动检查":@"停用自动检查",@selector(toggleCourse:),course!=nil);
    NSMenuItem *advanced=[menu addItemWithTitle:@"更多设置" action:nil keyEquivalent:@""];NSMenu *options=NSMenu.new;options.autoenablesItems=NO;advanced.submenu=options;
    add(options,@"调整识别课程…",@selector(adjustSkillCourses:),YES);add(options,@"导入助手结果…",@selector(importSkillResults:),YES);add(options,@"本地模型重新识别…",@selector(recognizeLocal:),course!=nil);add(options,@"识别模板…",@selector(editCourseTemplate:),course!=nil);add(options,@"恢复课程访问…",@selector(restoreAccess:),course!=nil);add(options,@"登录与兼容设置…",@selector(authenticationSettings:),YES);
    add(menu,@"移除课程…",@selector(removeCourse:),course!=nil);
    return menu;
}
- (void)more:(id)sender {
    if(self.selectedFork && ![self course]){NSMenu *menu=NSMenu.new;for(NSArray *entry in @[@[@"新建课程…",@"newStandaloneCourse:"],@[@"重命名课程…",@"renameCatalogCourse:"],@[@"关联课程仓库…",@"linkCatalogCourse:"]]){NSMenuItem *item=[menu addItemWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:@""];item.target=self;}[menu popUpMenuPositioningItem:nil atLocation:NSZeroPoint inView:self.moreButton];return;}
    NSMenu *menu=[self courseActionsMenu];NSView *anchor=[sender isKindOfClass:NSView.class] ? sender:self.view;
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0,anchor==self.view ? 0:NSHeight(anchor.bounds)) inView:anchor];
}
- (void)editCourseTemplate:(id)sender {
    NSMutableDictionary *course=[self savedCourse:[self course]];if(!course || self.busy || self.operationsPaused)return;
    NSAlert *alert=NSAlert.new;alert.messageText=@"课程识别模板";alert.informativeText=@"可用 titlePattern、contentPattern、deadlinePattern 提取每行的第一个捕获组。留空对象 {} 使用默认 Markdown / 文本模板。模板新增的材料仍须审核；不覆盖已确认任务。";
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,480,160)];scroll.hasVerticalScroller=YES;NSTextView *input=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,460,160)];input.font=[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];input.string=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:course[@"recognitionTemplate"] ?: @{} options:NSJSONWritingPrettyPrinted error:NULL] encoding:NSUTF8StringEncoding];scroll.documentView=input;alert.accessoryView=scroll;[alert addButtonWithTitle:@"保存模板"];[alert addButtonWithTitle:@"取消"];
    if([alert runModal]!=NSAlertFirstButtonReturn)return;NSError *error=nil;id template=[NSJSONSerialization JSONObjectWithData:[input.string dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&error];if(!template || !SSValidateCourseTemplate(template,&error)){[self showError:error];return;}
    NSMutableDictionary *next=course.mutableCopy;next[@"recognitionTemplate"]=template;NSMutableArray *all=self.courses.mutableCopy;all[[all indexOfObject:course]]=next;
    if(!self.preview && !SSWritePlist(@"courses.plist",all,&error)){[self showError:error];return;}[course setDictionary:next];[self status:@"模板已保存，下次检查生效。"]; }
#import "SSCourseSkill.inc"
#import "SSCourseLocal.inc"
#import "SSCourseSetup.inc"
- (void)repositoryDetails:(id)sender { self.sections.selectedSegment = 2; [self refreshPresentation]; }
- (void)operationDetails:(id)sender { NSAlert *alert=NSAlert.new;NSString *key=self.selectedFork ?: @"all";alert.messageText=[self course][@"fork"] ?: @"课程检查";alert.informativeText=self.errorDetails[key] ?: self.statuses[key] ?: @"尚无操作记录。";[alert addButtonWithTitle:@"关闭"];[alert addButtonWithTitle:@"复制详情"];[alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse choice){if(choice==NSAlertSecondButtonReturn){[NSPasteboard.generalPasteboard clearContents];[NSPasteboard.generalPasteboard setString:SSRedactedText(alert.informativeText) forType:NSPasteboardTypeString];}}]; }
- (void)restoreAccess:(id)sender {if(self.busy || self.operationsPaused)return;NSString *issue=self.reports[self.selectedFork ?: @"all"][@"issue"];if([issue isEqual:@"login"]){self.guided=YES;[self login:nil];}else if([issue isEqual:@"ssh"]){self.guided=YES;[self authenticationSettings:nil];}else if([issue isEqual:@"sso"]){NSString *owner=[[self course][@"upstream"] componentsSeparatedByString:@"/"].firstObject;[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://github.com/orgs/%@/sso",owner]]];}else if([issue isEqual:@"permission"] && [self.github.authType isEqual:@"githubCLI"]){NSAlert *alert=NSAlert.new;alert.messageText=@"当前账户无法读取课程";alert.informativeText=@"先在 GitHub 打开老师仓库，核对登录账户和已有课程权限；学校要求 SSO 时完成学校登录。无需申请批准本项目应用。";[alert addButtonWithTitle:@"打开老师仓库"];[alert addButtonWithTitle:@"重新登录"];[alert addButtonWithTitle:@"稍后"];NSInteger answer=[alert runModal];NSString *teacher=[self course][@"upstream"];if(answer==NSAlertFirstButtonReturn && SSCanonicalRepository([@"https://github.com/" stringByAppendingString:teacher ?: @""]))[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:[@"https://github.com/" stringByAppendingString:teacher]]];else if(answer==NSAlertSecondButtonReturn)[self login:nil];}else if([issue isEqual:@"approval"] || [issue isEqual:@"permission"])[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://github.com/settings/applications"]];else [self setup:nil];}
- (void)recover:(id)sender { if ([[self course][@"pendingMergeTip"] length]) [self continueMerge:nil]; else [self push:nil]; }
- (void)focusSearch { if(self.inbox)[self.reviewWorkspace focusSearch];else [self.view.window makeFirstResponder:self.search]; }
- (void)sectionChanged:(id)sender {
    if(self.hasUnsavedReview && ![self resolveUnsavedReview]){[self.sections setSelectedSegment:self.presentedSection];[self.typeFilter selectItemAtIndex:self.presentedType];[self.reviewFilter selectItemAtIndex:self.presentedReviewFilter];return;}
    [self refreshPresentation];
}
- (void)controlTextDidChange:(NSNotification *)notification { if (notification.object == self.search) { self.query = self.search.stringValue; [self refreshPresentation]; } }
- (void)saveCourses { if (self.preview) return; NSError *error = nil; if (!SSWritePlist(@"courses.plist", self.courses, &error)){AMCourseOperationContext *context=AMCourseContext(self);__weak typeof(self) owner=self;if(context)context.saveResult=^BOOL(NSError **issue){return SSWritePlist(@"courses.plist",owner.courses,issue);};[self showError:error];} }
- (NSMutableDictionary *)savedCourse:(NSDictionary *)course { for (NSMutableDictionary *saved in self.courses) if ([saved[@"fork"] isEqual:course[@"fork"]]) return saved; return nil; }
- (NSArray<NSString *> *)courseRepositoryNames {NSMutableArray *names=NSMutableArray.array;for(NSDictionary *course in self.courses)if(course[@"fork"])[names addObject:course[@"fork"]];return names.copy;}
- (NSDictionary *)course { for (NSDictionary *course in self.courses) if ([course[@"fork"] isEqual:self.selectedFork]) return course; return nil; }
- (NSArray *)discoveriesForFork:(NSString *)fork {
    NSMutableArray *result = NSMutableArray.array;
    for (NSDictionary *item in [(self.candidates[fork] ?: @[]) arrayByAddingObjectsFromArray:self.materials[fork] ?: @[]]) {
        NSMutableDictionary *copy = item.mutableCopy; NSString *kind = self.kindOverrides[item[@"id"]] ?: item[@"kind"] ?: @"assignment";
        if (![@[@"assignment", @"classroom", @"exam", @"unknown"] containsObject:kind]) kind = @"unknown";
        copy[@"reviewDeleted"]=@(AMReviewIsDeleted(copy));
        copy[@"automaticDeferred"]=@([self.automaticDeferrals[item[@"id"]] isEqual:item[@"blobSHA"]]);
        copy[@"kind"] = kind; if (self.kindOverrides[item[@"id"]]) copy[@"kindReason"] = @"你已手动确认类型";
        BOOL exact=NO, nearby=NO;
        for (NSDictionary *task in self.tasksProvider ? self.tasksProvider() : @[]) {
            if ([task[@"sourceID"] isEqual:copy[@"id"]]) exact=YES;
            if ([task[@"sourceRepository"] isEqual:copy[@"repository"]] && [task[@"sourcePath"] isEqual:copy[@"path"]]) nearby=YES;
        }
        if (!exact && nearby) {copy[@"identityUncertain"]=@YES;NSMutableArray *warnings=[copy[@"warnings"] mutableCopy] ?: NSMutableArray.array;[warnings addObject:@"同一文档已有任务，来源匹配不确定；请核对是否是新作业，避免重复加入。旧任务保留。"];copy[@"warnings"]=warnings;}

        [result addObject:copy];
    } return result;
}
- (BOOL)deferAutomaticImportOfTasks:(NSArray *)tasks error:(NSError **)error {
    NSMutableDictionary *next=self.automaticDeferrals.mutableCopy;
    for(NSDictionary *task in tasks)if([task[@"sourceID"] length] && [task[@"sourceBlobSHA"] length])next[task[@"sourceID"]]=task[@"sourceBlobSHA"];
    if(!self.preview && !SSWritePlist(@"automatic-review.plist",next,error))return NO;
    self.automaticDeferrals=next;return YES;
}
- (BOOL)setKind:(NSString *)kind forDiscovery:(NSDictionary *)record error:(NSError **)error {
    if (!record[@"id"] || ![@[@"assignment", @"classroom", @"exam", @"unknown"] containsObject:kind]) return NO;
    NSMutableDictionary *next = self.kindOverrides.mutableCopy; next[record[@"id"]] = kind;
    if (!self.preview && !SSWritePlist(@"discovery-overrides.plist", next, error)) return NO;
    self.kindOverrides = next; [self refreshPresentation]; return YES;
}
- (void)changeType:(id)sender {
    NSInteger row = self.table.selectedRow; if (self.operationsPaused || row < 0 || row >= (NSInteger)self.visible.count) return;
    NSDictionary *record = self.visible[row]; if ([record[@"confirmed"] boolValue]) return;
    NSAlert *alert = NSAlert.new; alert.messageText = @"确认课程内容类型"; alert.informativeText = @"只有作业进入待审核清单。考试与课上任务只在课程页标注；已确认的任务不会被自动删除。";
    NSPopUpButton *menu = [[PastelPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 280, 32) pullsDown:NO]; [menu addItemsWithTitles:@[@"作业", @"课上任务", @"考试", @"待确认类型"]];
    NSArray *kinds = @[@"assignment", @"classroom", @"exam", @"unknown"]; NSInteger selected = [kinds indexOfObject:record[@"kind"]]; [menu selectItemAtIndex:selected == NSNotFound ? 3 : selected]; alert.accessoryView = menu;
    [alert addButtonWithTitle:@"保存类型"]; [alert addButtonWithTitle:@"取消"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse answer) { if (answer == NSAlertFirstButtonReturn) { NSError *error = nil; if (![self setKind:kinds[menu.indexOfSelectedItem] forDiscovery:record error:&error]) [self showError:error]; } }];
}
- (NSArray *)visible {
    NSMutableArray *result = NSMutableArray.array; NSMutableSet *seen = NSMutableSet.set;
    NSDictionary *local=nil;if(!self.inbox && self.selectedFork && ![self course])for(NSDictionary *row in AMCourseCatalog(self.courses))if([row[@"id"] isEqual:self.selectedFork])local=row;
    if(local || (!self.inbox && self.sections.selectedSegment == 1)) {
        for (NSDictionary *task in self.tasksProvider ? self.tasksProvider() : @[]) if (![task[@"deleted"] boolValue] && AMTaskBelongsToCourse(task,local ?: [self course])) {
            NSMutableDictionary *copy = task.mutableCopy; copy[@"confirmed"] = @YES; copy[@"path"] = task[@"sourcePath"] ?: @""; copy[@"line"] = task[@"sourceLine"] ?: @0; [result addObject:copy];
        }
    } else {
        for (NSDictionary *course in self.courses) {
            if (self.selectedFork && ![course[@"fork"] isEqual:self.selectedFork]) continue;
            for (NSDictionary *candidate in [self discoveriesForFork:course[@"fork"]]) {
                if (self.inbox && ![candidate[@"kind"] isEqual:@"assignment"]) continue;
                NSArray *types = @[@"", @"assignment", @"classroom", @"exam", @"unknown"];
                if (!self.inbox && self.typeFilter.indexOfSelectedItem > 0 && ![candidate[@"kind"] isEqual:types[self.typeFilter.indexOfSelectedItem]]) continue;
                if([candidate[@"reviewDeleted"] boolValue])continue;
                NSString *state = [self stateForCandidate:candidate];
                // Reviewed assignments belong to tasks, never to a review/material queue.
                if ([state isEqual:@"已导入"]) continue;
                if (self.inbox && ((self.reviewFilter.indexOfSelectedItem == 1 && ![state isEqual:@"待审核"]) || (self.reviewFilter.indexOfSelectedItem == 2 && ![state isEqual:@"有更新"]))) continue;
                if (![seen containsObject:candidate[@"id"]]) { [seen addObject:candidate[@"id"]]; [result addObject:candidate]; }
            }
        }
    }
    if(self.inbox && self.localReviewProvider)for(NSDictionary *record in self.localReviewProvider())if(!AMReviewIsDeleted(record))[result addObject:record];
    if(self.inbox && self.reviewFilter.indexOfSelectedItem==3){[result removeAllObjects];for(NSDictionary *record in AMReviewDeletedRecords())if(!self.selectedFork || [record[@"repository"] isEqual:[self course][@"upstream"]])[result addObject:record];}
    NSString *query = [self.query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (query.length) [result filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) { NSString *text = [NSString stringWithFormat:@"%@ %@ %@", item[@"title"], item[@"path"], item[@"repository"] ?: item[@"subject"]]; return [text rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound; }]];
    return AMCourseDisplayTasks(result,AMCourseCatalog(self.courses));
}
- (NSArray<NSDictionary *> *)pendingReviewCandidates {
    return [[self visible] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
        return ![item[@"confirmed"] boolValue] && (!item[@"kind"] || [item[@"kind"] isEqual:@"assignment"]) && ![[self stateForCandidate:item] isEqual:@"已导入"];
    }]];
}
- (NSArray<NSDictionary *> *)allPendingReviewCandidates {
    NSMutableArray *records=NSMutableArray.array; NSMutableSet *seen=NSMutableSet.set;
    for (NSDictionary *course in self.courses) for (NSDictionary *record in [self discoveriesForFork:course[@"fork"]]) if ([record[@"kind"] isEqual:@"assignment"] && ![seen containsObject:record[@"id"]] && ![record[@"reviewDeleted"] boolValue] && ![[self stateForCandidate:record] isEqual:@"已导入"]) { [seen addObject:record[@"id"]]; [records addObject:record]; }
    if(self.localReviewProvider)for(NSDictionary *record in self.localReviewProvider())if(!AMReviewIsDeleted(record))[records addObject:record];
    return records;
}
- (NSDictionary *)reviewSourceWithID:(NSString *)identifier {
    for(NSDictionary *record in self.localReviewProvider ? self.localReviewProvider():@[])if([record[@"id"] isEqual:identifier])return AMReviewIsDeleted(record) ? nil:record;
    for(NSString *fork in self.deferredScans){NSDictionary *scan=self.deferredScans[fork];for(NSDictionary *row in [(scan[@"candidates"] ?: @[]) arrayByAddingObjectsFromArray:scan[@"materials"] ?: @[]])if([row[@"id"] isEqual:identifier]){NSMutableDictionary *record=row.mutableCopy;if(self.kindOverrides[identifier])record[@"kind"]=self.kindOverrides[identifier];return AMReviewIsDeleted(record) ? nil:record;}for(NSDictionary *row in self.candidates[fork])if([row[@"id"] isEqual:identifier])return nil;}
    // An imported source is still valid for editing. Pending status and active
    // page filters must never decide whether its source version is current.
    for (NSDictionary *course in self.courses) for (NSDictionary *record in [self discoveriesForFork:course[@"fork"]]) if ([record[@"id"] isEqual:identifier]) return AMReviewIsDeleted(record) ? nil:record;
    return nil;
}
- (void)refreshCourses {
    if(self.selectedFork && ![self savedCourse:@{@"fork":self.selectedFork}]){BOOL found=NO;for(NSDictionary *row in AMCourseCatalog(self.courses))if([row[@"id"] isEqual:self.selectedFork])found=YES;if(!found)self.selectedFork=nil;}
    [self refreshPresentation];
}
- (NSString *)selectedCourseID {return self.selectedFork;}
- (NSArray *)courseSnapshots {
    NSMutableArray *result=NSMutableArray.array;
    for(NSDictionary *course in self.courses){NSUInteger pending=0,updates=0;for(NSDictionary *record in [self discoveriesForFork:course[@"fork"]])if([record[@"kind"] isEqual:@"assignment"] && ![record[@"reviewDeleted"] boolValue] && ![[self stateForCandidate:record] isEqual:@"已导入"]){pending++;if([[self stateForCandidate:record] isEqual:@"有更新"])updates++;}
        NSString *symbol=[course[@"path"] length] ? @"book.closed":@"folder.badge.questionmark";
        if([course[@"pendingMergeTip"] length] || [course[@"pushFailed"] boolValue] || self.reports[course[@"fork"]][@"error"])symbol=@"exclamationmark.triangle";
        if(self.busy && [self.operationFork isEqual:course[@"fork"]])symbol=@"arrow.triangle.2.circlepath";
        [result addObject:@{@"id":course[@"fork"],@"name":[course[@"fork"] lastPathComponent],@"pending":@(pending),@"newCount":@(pending-updates),@"updateCount":@(updates),@"symbol":symbol,@"linked":@([course[@"path"] length]>0),@"status":(self.busy && [self.operationFork isEqual:course[@"fork"]]) ? @"检查中":(self.reports[course[@"fork"]] ? AMCourseCheckPresentation(self.reports[course[@"fork"]],pending)[@"summary"]:(self.statuses[course[@"fork"]] ?: ([course[@"path"] length] ? @"已关联":@"待关联目录")))}];
    }
    NSArray *catalog=AMCourseCatalog(self.courses);for(NSUInteger i=0;i<result.count;i++){NSMutableDictionary *row=[result[i] mutableCopy];for(NSDictionary *c in catalog)if([c[@"fork"] isEqual:row[@"id"]])row[@"name"]=c[@"name"];result[i]=row;}
    for(NSDictionary *c in catalog){BOOL represented=NO;for(NSDictionary *repository in self.courses)if([repository[@"fork"] isEqual:c[@"fork"]])represented=YES;if(!represented)[result addObject:@{@"id":c[@"id"],@"name":c[@"name"],@"pending":@0,@"symbol":@"book.closed",@"linked":@NO,@"status":@""}];}return result;
}
- (BOOL)selectCourseID:(NSString *)identifier {
    if(identifier && ![self savedCourse:@{@"fork":identifier}]){BOOL exists=NO;for(NSDictionary *row in AMCourseCatalog(self.courses))if([row[@"id"] isEqual:identifier])exists=YES;if(!exists)return NO;}
    if(self.showingSkillJobs){self.showingSkillJobs=NO;[self refreshPresentation];}
    if([self.selectedFork isEqual:identifier] || (!identifier && !self.selectedFork))return YES;
    if(self.hasUnsavedReview && ![self resolveUnsavedReview])return NO;
    NSString *oldKey=[@"course:" stringByAppendingString:self.selectedFork ?: @"all"];
    self.pageStates[oldKey]=@{@"positions":[self.courseWorkspace scrollPositions],@"query":self.query ?: @"",@"id":self.selectedCandidateID ?: @"",@"section":@(self.sections.selectedSegment),@"type":@(self.typeFilter.indexOfSelectedItem),@"scroll":@(self.table.enclosingScrollView.contentView.bounds.origin.y)};
    self.selectedFork=identifier;NSDictionary *state=self.pageStates[[@"course:" stringByAppendingString:identifier ?: @"all"]];self.query=state[@"query"] ?: @"";self.search.stringValue=self.query;self.selectedCandidateID=state[@"id"];self.sections.selectedSegment=[state[@"section"] integerValue];[self.typeFilter selectItemAtIndex:[state[@"type"] integerValue]];
    [self refreshPresentation];[self.courseWorkspace restoreScrollPositions:state[@"positions"] ?: @[]];[self.table.enclosingScrollView.contentView scrollToPoint:NSMakePoint(0,[state[@"scroll"] doubleValue])];return YES;
}
- (void)refreshPresentation {
    if (self.refreshing || !self.table) return; self.refreshing = YES;
    if(!self.hasUnsavedReview && self.deferredScans.count){for(NSString *fork in self.deferredScans){NSDictionary *scan=self.deferredScans[fork];self.candidates[fork]=[self retainingSkill:self.candidates[fork] current:scan[@"candidates"] documents:scan[@"documents"]];self.materials[fork]=[self retainingSkill:self.materials[fork] current:scan[@"materials"] ?: @[] documents:scan[@"documents"]];}[self.deferredScans removeAllObjects];if(!self.preview)SSWritePlist(@"discoveries.plist",self.discoveryEnvelope,NULL);}
    NSDictionary *course = [self course]; NSString *key = self.selectedFork ?: @"all";
    NSDictionary *localCourse=nil;if(!self.inbox && !course && self.selectedFork)for(NSDictionary *c in AMCourseCatalog(self.courses))if([c[@"id"] isEqual:self.selectedFork])localCourse=c;
    if(localCourse){self.sections.segmentCount=1;[self.sections setLabel:@"任务" forSegment:0];self.sections.selectedSegment=0;self.accountLabel.stringValue=localCourse[@"name"];self.setupButton.hidden=YES;self.scanButton.hidden=YES;self.syncButton.hidden=YES;self.commitButton.hidden=YES;self.typeFilter.hidden=YES;self.typeButton.hidden=YES;self.recoveryButton.hidden=YES;self.moreButton.enabled=!self.operationsPaused;NSMutableArray *records=NSMutableArray.array;for(NSDictionary *task in self.tasksProvider ? self.tasksProvider():@[])if(![task[@"deleted"] boolValue] && [AMCourseForTask(task,AMCourseCatalog(self.courses))[@"id"] isEqual:localCourse[@"id"]] && (!self.query.length || [task[@"title"] localizedCaseInsensitiveContainsString:self.query])){NSMutableDictionary *row=task.mutableCopy;row[@"confirmed"]=@YES;row[@"subject"]=localCourse[@"name"];[records addObject:row];}[records sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"due"] compare:b[@"due"]];}];[self.courseWorkspace showCourseSummaries:@[] visible:NO];[self.courseWorkspace updateRecords:records selected:self.selectedCandidateID ?: @"" information:@"" empty:@"暂无任务" paused:self.operationsPaused];[self layoutContent];self.refreshing=NO;if(self.stateChanged)self.stateChanged();return;}
    if(self.sections.segmentCount!=4){self.sections.segmentCount=4;NSArray *labels=@[@"课程内容",@"已加入任务",@"仓库信息",@"提交记录"];for(NSInteger i=0;i<4;i++)[self.sections setLabel:labels[i] forSegment:i];self.sections.selectedSegment=0;}self.scanButton.hidden=NO;

    if(self.workflowNoticeContext)self.workflowNotice.hidden=[self.dismissedWorkflowNotices containsObject:self.workflowNoticeContext.identifier] || (self.workflowNoticeContext.course && ![self.workflowNoticeContext.course[@"fork"] isEqual:key]);
    NSDate *last = course[@"lastScan"];
    NSString *context = course ? [NSString stringWithFormat:@"%@ · 上次成功检查：%@%@", course[@"upstream"], last ? DDLFormatDate(last, @"M月d日 HH:mm") : @"尚未检查", [course[@"enabled"] isEqual:@NO] ? @" · 自动检查已停用" : @""] : @"所有课程的发现结果集中在这里";
    self.accountLabel.stringValue = context;
    self.statusLabel.stringValue = self.statuses[key] ?: @"";
    if (self.busy) self.statusLabel.stringValue = [NSString stringWithFormat:@"%@：%@", self.operationFork ?: @"课程检查", self.statuses[self.operationFork ?: @"all"] ?: @"正在处理…"];
    self.statusLabel.toolTip = self.statusLabel.stringValue; self.accountLabel.toolTip = context;
    BOOL local = [course[@"path"] length] > 0;
    self.setupButton.title = !self.connected ? @"连接 GitHub" : (course && !local ? @"关联文件夹…" : @"添加课程…");
    self.setupButton.hidden = self.inbox || (self.connected && self.courses.count>0 && (!course || local));
    self.setupButton.enabled = !self.operationsPaused; self.moreButton.enabled = !self.operationsPaused;
    self.syncButton.hidden = self.inbox || !course; self.commitButton.hidden = self.inbox || !course;
    self.scanButton.title=course ? @"检查新作业":@"检查所有课程";self.scanButton.bezelColor=NSColor.controlAccentColor;
    self.syncButton.enabled = self.commitButton.enabled = !self.operationsPaused && local && self.connected;
    BOOL anyLocal = NO; for (NSDictionary *item in self.courses) if ([item[@"path"] length]) anyLocal = YES; self.scanButton.enabled = !self.operationsPaused && (local || (!course && anyLocal));
    self.recoveryButton.hidden = !course || (![course[@"pendingMergeTip"] length] && ![course[@"pushFailed"] boolValue]); self.recoveryButton.enabled = !self.operationsPaused;
    self.recoveryButton.title = [course[@"pendingMergeTip"] length] ? @"处理冲突…" : @"重试推送";


    NSArray *visible = [self visible];
    NSMutableArray *reviewRecords = NSMutableArray.array;
    for (NSDictionary *record in visible) {
        NSMutableDictionary *copy = [SSEnrichDiscovery(record) mutableCopy];copy[@"reviewStatus"]=[self stateForCandidate:record];
        for (NSDictionary *task in self.tasksProvider ? self.tasksProvider() : @[]) if ([task[@"sourceID"] isEqual:record[@"id"]]) { copy[@"existingTask"] = task; break; }
        [reviewRecords addObject:copy];
    }
    NSMutableArray *jobs=NSMutableArray.array;for(NSString *key in self.skillJobs){NSMutableDictionary *row=[self.skillJobs[key] mutableCopy];row[@"id"]=key;[jobs addObject:row];}if(self.localSkillJobsProvider)[jobs addObjectsFromArray:self.localSkillJobsProvider()];[jobs addObjectsFromArray:AMPreflightJobs()];[jobs sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [b[@"date"] compare:a[@"date"]];}];[self.skillJobsController updateRecords:jobs busy:self.operationsPaused];
    self.scanButton.toolTip=self.busy ? @"排队检查":(!local && !anyLocal ? @"尚未关联本地课程文件夹":@"检查新作业");
    self.syncButton.toolTip=self.connected && local ? @"同步课程文件":@"需要登录并关联本地课程文件夹。";self.commitButton.toolTip=self.connected && local ? @"提交作业":@"需要登录并关联本地课程文件夹。";
    self.reviewWorkspace.paused = self.operationsPaused;
    if (self.inbox) [self.reviewWorkspace updateRecords:reviewRecords];
    NSString *selectedID = self.selectedCandidateID; NSPoint scrollPosition = self.table.enclosingScrollView.contentView.bounds.origin;
    [self.table reloadData]; [self.table deselectAll:nil];
    if (selectedID) for (NSUInteger i = 0; i < visible.count; i++) if ([visible[i][@"id"] isEqual:selectedID]) { [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO]; break; }
    [self.table.enclosingScrollView.contentView scrollToPoint:scrollPosition];
    BOOL info = !self.inbox && self.sections.selectedSegment == 2;
    self.table.enclosingScrollView.hidden = info || !visible.count;
    self.emptyLabel.hidden = info || visible.count > 0;
    self.emptyLabel.stringValue = !self.courses.count ? @"尚未添加课程" : (course && !local ? @"这门课尚未关联本地文件夹" : (self.query.length ? @"没有匹配的作业" : (self.inbox ? @"暂无待审核作业" : @"暂无待审核作业")));
    self.emptyLabel.maximumNumberOfLines = 2; self.emptyLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.table.backgroundColor = Card(); self.detail.textColor = Ink(); ThemeEditor(self.detail);
    if (info) [self report:nil]; else [self candidateSelected:nil];
    self.reviewButton.hidden = info;
    self.table.tableColumns.firstObject.title = self.inbox ? @"作业" : @"课程内容";
    self.typeButton.hidden = info || (!self.inbox && self.sections.selectedSegment == 1);
    self.typeFilter.hidden = self.inbox || self.sections.selectedSegment != 0;
    NSMutableArray *content=NSMutableArray.array;
    for(NSDictionary *record in visible){
        NSMutableDictionary *copy=[SSEnrichDiscovery(record) mutableCopy];
        if([record[@"confirmed"] boolValue]){
            NSDictionary *source=[self reviewSourceWithID:record[@"sourceID"]];
            if(source && [source[@"kind"] isEqual:@"assignment"]){NSMutableDictionary *review=[SSEnrichDiscovery(source) mutableCopy];review[@"existingTask"]=record;review[@"reviewStatus"]=[self stateForCandidate:source];copy[@"reviewRecord"]=review;}
        }else{
            copy[@"reviewStatus"]=[self stateForCandidate:record];
            for(NSDictionary *task in self.tasksProvider ? self.tasksProvider() : @[])if([task[@"sourceID"] isEqual:record[@"id"]]){copy[@"existingTask"]=task;if([copy[@"reviewStatus"] isEqual:@"已导入"])copy[@"due"]=task[@"due"];break;}
        }
        [content addObject:copy];
    }
    NSString *information=info ? self.detail.string : @"";
    NSMutableArray *summaries=NSMutableArray.array;if(!course && !self.inbox){for(NSDictionary *snapshot in self.courseSnapshots){NSMutableDictionary *row=snapshot.mutableCopy;row[@"failed"]=AMCourseCheckPresentation(self.reports[snapshot[@"id"]] ?: @{},[snapshot[@"pending"] unsignedIntegerValue])[@"warning"];[summaries addObject:row];}[content removeAllObjects];information=@"";}[self.courseWorkspace showCourseSummaries:summaries visible:!course && !self.inbox];
    [self.courseWorkspace updateRecords:content selected:self.selectedCandidateID ?: @"" information:information empty:self.emptyLabel.stringValue paused:self.operationsPaused];
    self.presentedSection=self.sections.selectedSegment;self.presentedType=self.typeFilter.indexOfSelectedItem;self.presentedReviewFilter=self.reviewFilter.indexOfSelectedItem;
    if(!self.inbox && self.sections.selectedSegment==3 && !self.discoveringExternal)dispatch_async(dispatch_get_main_queue(),^{[self discoverExternalSubmissions:NO];});
    NSError *historyError=nil;NSArray *storedHistory=AMSubmissionRecords(&historyError);if(historyError && !self.inbox && self.sections.selectedSegment==3)self.statusLabel.stringValue=historyError.localizedDescription;
    NSMutableArray *history=NSMutableArray.array;for(NSDictionary *record in storedHistory ?: @[])if(![record[@"teacherHistoryExcluded"] boolValue] && (!course || [record[@"repository"] isEqual:course[@"fork"]])){NSMutableDictionary *row=record.mutableCopy;row[@"label"]=AMSubmissionStateLabel(record);[history insertObject:row atIndex:0];}[self.submissionHistory updateReading:self.discoveringExternal];[self.submissionHistory updateRecords:history busy:self.operationsPaused];
    [self layoutContent]; self.refreshing = NO;
    if (self.stateChanged) self.stateChanged();
}
- (void)cancelReadOperation:(id)sender {AMCourseOperationContext *context=self.workflowContexts[_operationID];if(context){AMOperationCancel(context.identifier);self.cancelReadButton.enabled=NO;[self status:@"正在停止…"];return;}if(self.busy){self.git.cancelledReads=YES;[self.git cancelCurrentOperation];self.github.requestsCancelled=YES;self.cancelReadButton.enabled=NO;[self status:@"正在停止…"];} }
- (NSDictionary *)checkPresentationForFork:(NSString *)fork {
    NSMutableSet *pending=NSMutableSet.set;for(NSDictionary *record in [self discoveriesForFork:fork])if([record[@"kind"] isEqual:@"assignment"] && ![record[@"reviewDeleted"] boolValue] && ![[self stateForCandidate:record] isEqual:@"已导入"] && record[@"id"])[pending addObject:record[@"id"]];
    return AMCourseCheckPresentation(self.reports[fork] ?: @{},pending.count);
}
- (void)updateCheckSummaryForCourse:(NSDictionary *)course {
    NSString *fork=course[@"fork"];if(!fork)return;NSDictionary *display=[self checkPresentationForFork:fork];self.statuses[fork]=display[@"summary"];self.errorDetails[fork]=display[@"details"];
}
- (void)status:(NSString *)message {
    AMCourseOperationContext *context=AMCourseContext(self);NSString *key=context.course[@"fork"] ?: self.statusFork ?: self.selectedFork ?: @"all";self.statuses[key]=message ?: @"";if(context)context.lastStatus=message;
    if(context || self.busy){self.operationPhase=message;AMOperationProgress(self.operationID,message,0,0);}
    if(message.length && !self.operationID.length){__weak typeof(self) owner=self;NSString *scope=[@"course:" stringByAppendingString:key];BOOL failed=[message hasPrefix:@"⚠"] || [message containsString:@"失败"] || [message containsString:@"无法"];
        AMPostUIMessage(scope,@"status",message,failed ? AMUIMessageError:AMUIMessageInformation,failed ? @"查看":nil,failed ? ^{if(![key isEqual:@"all"] && ![owner selectCourseID:key])return;[owner operationDetails:nil];}:nil);
    }
    [self refreshPresentation];
}
- (void)showError:(NSError *)error {if(!error)return;AMCourseOperationContext *context=AMCourseContext(self);if(context){context.failure=error;context.problem=AMWorkflowProblem(error,context.stage,context.git.lastWorkflowRecord);self.errorDetails[context.course[@"fork"] ?: @"all"]=context.problem[@"details"];return;}NSDictionary *problem=AMWorkflowProblem(error,@"",nil);self.errorDetails[self.selectedFork ?: @"all"]=problem[@"details"];[self status:[NSString stringWithFormat:@"%@ · %@",problem[@"title"],problem[@"effect"]]];}
#include "AMCourseRecovery.inc"

- (void)work:(NSString *)message operation:(id (^)(NSError **))operation completion:(void (^)(id, NSError *))completion {
    [self work:message forCourse:[self course] operation:operation completion:completion];
}
- (void)work:(NSString *)message forCourse:(NSDictionary *)course operation:(id (^)(NSError **))operation completion:(void (^)(id, NSError *))completion {
    [self work:message forCourse:course requestKey:@"" priority:100 operation:operation completion:completion];
}
- (void)work:(NSString *)message forCourse:(NSDictionary *)course requestKey:(NSString *)scope priority:(NSInteger)priority operation:(id (^)(NSError **))operation completion:(void (^)(id,NSError *))completion {
    [self work:message forCourse:course requestKey:scope priority:priority kind:AMCourseWorkGit operation:operation completion:completion];
}
- (BOOL)workflowSourceMatches:(AMCourseOperationContext *)context {
    if(context.api!=_github && ![context.authenticationIdentity isEqual:_github.authenticationIdentity])return NO;if(!context.course)return YES;NSDictionary *saved=[self savedCourse:context.course];if(!saved)return NO;
    for(NSString *field in @[@"path",@"branch",@"upstream",@"forkID",@"upstreamID",@"ownerID"])if(![(context.course[field] ?: NSNull.null) isEqual:saved[field] ?: NSNull.null])return NO;
    if(context.kind==AMCourseWorkModel && context.sourceCommit.length && ![context.sourceCommit isEqual:self.reports[context.course[@"fork"]][@"commit"]])return NO;return YES;
}
- (void)work:(NSString *)message forCourse:(NSDictionary *)course requestKey:(NSString *)scope priority:(NSInteger)priority kind:(AMCourseWorkKind)kind operation:(id (^)(NSError **))operation completion:(void (^)(id,NSError *))completion {
    if(self.preview){[self status:@"模拟预览不会操作真实账户或仓库"];return;}if(self.operationsPaused && !self.allowingExitSubmission)return;
    if(kind!=AMCourseWorkModel && priority>=100 && self.discoveringExternal){[self.discoveryCancellation cancel];[self.externalReader cancelCurrentOperation];}
    if(!self.workflowContexts)self.workflowContexts=NSMutableDictionary.dictionary;if(!self.workflowFailures)self.workflowFailures=NSMutableDictionary.dictionary;
    AMCourseOperationContext *context=AMCourseOperationContext.new;context.owner=self;context.course=course.copy;context.authType=_github.authType.copy;context.authenticationIdentity=_github.authenticationIdentity;context.kind=kind;context.enqueued=NSDate.date;context.stage=message;context.sourceCommit=self.reports[course[@"fork"] ?: @"all"][@"commit"];
    if((kind==AMCourseWorkLocal || kind==AMCourseWorkSubmission) && [self.submission.course[@"fork"] isEqual:course[@"fork"]] && [self.submission.course[@"branch"] isEqual:course[@"branch"]] && [self.submission.course[@"path"] isEqual:course[@"path"]])context.submissionDraft=self.submission;
    context.git=SSGit.new;context.api=SSGitHub.new;context.api.authType=_github.authType;context.api.clientID=_github.clientID;context.api.installationURL=_github.installationURL;
#ifdef DDL_TESTING
    if(self.workflowGitFactory)context.git=self.workflowGitFactory();else if(_git.class!=SSGit.class)context.git=_git;if(self.workflowAPIFactory)context.api=self.workflowAPIFactory();else if(_github.class!=SSGitHub.class)context.api=_github;
#endif
    if(!course && self.loginActive)context.api=_github;
    SSGitHub *api=context.api;context.git.identityVerifier=^NSDictionary *(NSDictionary *snapshot,NSError **error){return [api verifyCourse:snapshot error:error];};
    context.git.teacherCredentialProvider=[@[@"oauth",@"githubCLI"] containsObject:api.authType] ? ^NSString *(NSDictionary *snapshot,NSError **error){if(![api readableTeacher:snapshot error:error])return nil;return [api accessToken:error];}:nil;context.git.scanCheckpoint=^BOOL(NSMutableDictionary *cache,NSError **error){return AMScanCacheSave(cache,error);};
#ifdef DDL_TESTING
    if(!self.workflowGitFactory && _git.class!=SSGit.class){context.git.identityVerifier=_git.identityVerifier;context.git.teacherCredentialProvider=_git.teacherCredentialProvider;}
#endif
    __weak typeof(self) owner=self;__weak AMCourseOperationContext *weakContext=context;
    context.git.progress=^(NSString *phase){AMCourseOperationContext *current=weakContext;if(!current)return;current.stage=phase;AMOperationProgress(current.identifier,phase,0,0);};
    NSString *key=[NSString stringWithFormat:@"course|%@|%@|%@|%@",message,course ?: self.courses,scope,SSRecognitionSettings()];NSArray *resources=kind==AMCourseWorkModel ? @[[NSString stringWithFormat:@"model-course:%@",course[@"fork"] ?: @"all"]]:(self.loginActive && !course ? @[@"account-login"]:@[@"git-write"]);
    NSString *scheduled=AMScheduleCourseWorkflow(key,message,course[@"fork"] ?: @"所有课程",resources,priority,YES,^(NSString *identifier){
        context.identifier=identifier;dispatch_async(dispatch_get_main_queue(),^{
            if(![self workflowSourceMatches:context]){NSError *error=AMWorkflowError(@"source-changed",@"课程关联已变化，原请求未执行",nil);[self finishWorkflow:context value:nil error:error completion:completion retry:operation message:message scope:scope priority:priority];return;}
            self.workflowContexts[identifier]=context;self.cancelReadButton.enabled=YES;SSWorkflowDiagnostic(@"workflow-wait",@"success",@"",-context.enqueued.timeIntervalSinceNow);self.busy=YES;self.operationID=identifier;self.operationFork=course[@"fork"];self.workGeneration++;context.git.readsCancellable=YES;SSDiagnostic(@"operation",@"started",0);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{__block NSError *failure=nil;__block id value=nil;NSDate *started=NSDate.date;
                AMWithCourseContext(context,^{@try{if(context.cancelled)failure=AMWorkflowError(@"cancelled",@"已停止",nil);else value=operation(&failure);}@catch(NSException *exception){failure=AMWorkflowError(@"unknown",SSRedactedText(exception.reason),nil);}});
                if(!failure && (!value || ([value isKindOfClass:NSNumber.class] && ![value boolValue])))failure=AMWorkflowError(@"unknown",@"操作未返回有效结果",nil);
                if((context.cancelled || context.git.operationCancelled || context.git.cancelledReads || context.api.requestsCancelled) && ![context.git.lastWorkflowRecord[@"state"] isEqual:@"confirmed"] && (!failure || [AMWorkflowIssue(failure) isEqual:@"unknown"]))failure=AMWorkflowError(@"cancelled",@"已停止",failure);
                SSDiagnostic(@"operation",[AMWorkflowIssue(failure) isEqual:@"cancelled"] ? @"cancelled":(failure ? @"failed":@"success"),-started.timeIntervalSinceNow);
                dispatch_async(dispatch_get_main_queue(),^{[self finishWorkflow:context value:value error:failure completion:completion retry:operation message:message scope:scope priority:priority];});
            }});
        });
    },^(BOOL beforeStart){context.cancelled=YES;context.git.cancelledReads=YES;[context.git cancelCurrentOperation];context.api.requestsCancelled=YES;if(beforeStart)dispatch_async(dispatch_get_main_queue(),^{[owner finishWorkflow:context value:nil error:AMWorkflowError(@"cancelled",@"已取消排队，未执行操作",nil) completion:completion retry:operation message:message scope:scope priority:priority];});});
    context.identifier=scheduled;if(!self.workflowContexts[scheduled])self.workflowContexts[scheduled]=context;
}
- (void)finishWorkflow:(AMCourseOperationContext *)context value:(id)value error:(NSError *)error completion:(void (^)(id,NSError *))completion retry:(id (^)(NSError **))operation message:(NSString *)message scope:(NSString *)scope priority:(NSInteger)priority {
    if(!context.identifier.length || context.finished)return;context.finished=YES;AMOperationReleaseResources(context.identifier);
    if(!error && ![self workflowSourceMatches:context])error=AMWorkflowError(@"source-changed",@"来源已变化，旧结果未应用",nil);
    if(context.git.lastWorkflowRecord)context.record=context.git.lastWorkflowRecord;
    __block NSError *failure=error;AMWithCourseContext(context,^{@try{completion(failure && !([value isKindOfClass:NSDictionary.class] && ((value[@"conflicts"] && [AMWorkflowIssue(failure) isEqual:@"merge-conflict"]) || [AMWorkflowIssue(failure) isEqual:@"storage"])) ? nil:value,failure);}@catch(NSException *exception){failure=AMWorkflowError(@"unknown",SSRedactedText(exception.reason),failure);}});
    if(context.failure)failure=context.failure;
    if(!failure && [value isKindOfClass:NSDictionary.class]){NSDictionary *report=value;failure=SSRecognitionFailureError(report[@"modelFailures"]);
        if(!failure)for(NSString *key in report){id entry=report[key];if([entry isKindOfClass:NSDictionary.class] && entry[@"error"]){failure=AMWorkflowError(entry[@"issue"] ?: @"unknown",entry[@"detail"] ?: entry[@"error"],nil);break;}}}
    if([AMWorkflowIssue(failure) isEqual:@"storage"] && !context.record){NSDictionary *envelope=[self.discoveryEnvelope copy];BOOL (^priorSave)(NSError **)=context.saveResult;context.saveResult=^BOOL(NSError **issue){return (!priorSave || priorSave(issue)) && SSWritePlist(@"discoveries.plist",envelope,issue);};}
    if(!failure && [context.record[@"state"] isEqual:@"uncertain"])failure=AMWorkflowError(@"verification-pending",@"推送结果待核验",nil);
    if(failure){context.failure=failure;context.problem=AMWorkflowProblem(failure,context.stage,context.record);if([value isKindOfClass:NSDictionary.class] && !context.record && [@[@"recognition",@"storage"] containsObject:AMWorkflowIssue(failure)]){NSMutableDictionary *partial=context.problem.mutableCopy;partial[@"result"]=@"partial";partial[@"effect"]=@"可用结果已保留";context.problem=partial;}self.workflowFailures[context.identifier]=context;NSMutableSet *retained=NSMutableSet.set;for(NSDictionary *row in AMOperations())[retained addObject:row[@"id"]];for(NSString *key in self.workflowFailures.allKeys)if(![retained containsObject:key])[self.workflowFailures removeObjectForKey:key];[self showWorkflowProblem:context retry:operation message:message scope:scope priority:priority completion:completion];}
    else if(!context.customResult){NSString *summary=context.lastStatus ?: @"操作完成";NSDictionary *check=context.course ? [self checkPresentationForFork:context.course[@"fork"]]:nil;AMOperationSetResult(context.identifier,summary,self.errorDetails[context.course[@"fork"] ?: @"all"] ?: @"",[check[@"warning"] boolValue],nil,nil);}
    if(!failure && [context.record[@"state"] isEqual:@"local"]){__weak typeof(self) owner=self;AMOperationSetResult(context.identifier,@"本地提交尚未推送",[NSString stringWithFormat:@"%@ · %@\n%@",context.record[@"repository"],context.record[@"branch"],context.record[@"commit"] ?: @""],YES,@"重试推送",^{if([owner workflowRecoveryAllowed:context])[owner submissionAction:@"retry" identifier:context.record[@"id"]];});}
    NSString *state=failure ? ([AMWorkflowIssue(failure) isEqual:@"cancelled"] ? @"cancelled":@"failed"):@"success";AMOperationSetWorkflowResult(context.identifier,failure ? context.problem[@"result"]:([context.record[@"state"] isEqual:@"local"] ? @"needs-action":@"completed"),failure ? context.problem[@"issue"]:@"",context.stage);AMOperationFinish(context.identifier,state,failure ? [NSString stringWithFormat:@"%@ · %@",context.problem[@"title"],context.problem[@"effect"]]:(context.lastStatus ?: @"操作完成"));[self.workflowContexts removeObjectForKey:context.identifier];self.busy=self.workflowContexts.count>0;
    AMCourseOperationContext *active=self.workflowContexts.allValues.firstObject;_operationID=active.identifier;self.operationFork=active.course[@"fork"];_statusFork=nil;[self refreshPresentation];if(self.verifiedSubmissionsChanged)self.verifiedSubmissionsChanged();if(self.operationStateChanged)self.operationStateChanged();
}

- (void)setClientID:(id)sender {
    if (self.busy || self.preview || self.operationsPaused) return;
    NSAlert *alert = [NSAlert new]; alert.messageText = @"GitHub App Client ID";
    alert.informativeText = @"填写开发者注册的 GitHub App 公开 Client ID 和安装链接。注册说明位于 docs/GITHUB_APP_SETUP.md。不要填写密钥或个人令牌。";
    NSTextField *field = [[PastelTextField alloc] initWithFrame:NSMakeRect(0, 42, 440, 28)]; field.stringValue = self.github.clientID ?: @"";
    NSTextField *install = [[PastelTextField alloc] initWithFrame:NSMakeRect(0, 0, 440, 28)]; install.stringValue = self.github.installationURL ?: @""; install.placeholderString = @"https://github.com/apps/应用名称/installations/new";
    NSView *settings = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 440, 70)]; [settings addSubview:field]; [settings addSubview:install];
    alert.accessoryView = settings; [alert addButtonWithTitle:@"保存"]; [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSString *identifier = [field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([identifier rangeOfString:@"^Iv[A-Za-z0-9.]{10,80}$" options:NSRegularExpressionSearch].location == NSNotFound) { [self status:@"Client ID 格式无效"]; return; }
    NSString *installationURL = [install.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (installationURL.length && [installationURL rangeOfString:@"^https://github\\.com/apps/[a-z0-9-]+/installations/new$" options:NSRegularExpressionSearch].location == NSNotFound) { [self status:@"安装页面链接格式无效。"]; return; }
    NSError *error = nil;
    NSMutableDictionary *next=[SSReadPlist(@"settings.plist") mutableCopy] ?: NSMutableDictionary.dictionary;next[@"clientID"]=identifier;next[@"installationURL"]=installationURL;next[@"authType"]=@"githubApp";next[@"authSelectionVersion"]=@2;
    if (!SSWritePlist(@"settings.plist", next, &error)) { [self showError:error]; return; }
    self.github.authType=@"githubApp";self.github.clientID = identifier; self.github.installationURL = installationURL;[self configureCredentialAccess];self.connected=self.github.hasCredentials; [self status:@"已保存公开应用信息。请先安装授权，再登录。"];
}
- (void)login:(id)sender {
    if(self.operationsPaused)return;
    self.setupStep=0;self.loginChallenge=nil;_github.requestsCancelled=NO;[self presentCourseSetup];self.loginActive=YES;
    [self work:@"正在连接内置 GitHub 官方登录工具…" forCourse:nil operation:^id(NSError **error) { return [self.github beginDeviceLogin:error]; } completion:^(NSDictionary *challenge, NSError *error) {
        if (!challenge) {self.loginActive=NO;[self updateCourseSetup:error.localizedDescription ?: @"连接暂缓，可以稍后重试。"];return;}
        if(self.operationsPaused || !self.setupWindow)[self.github cancelDeviceLogin];
        self.loginChallenge=challenge;[self updateCourseSetup:@"请复制验证码并打开 GitHub。完成网页授权后自动继续。"];
        [self work:@"等待浏览器登录并核验账户…" forCourse:nil operation:^id(NSError **innerError) { return @([self.github completeDeviceLogin:challenge error:innerError]); } completion:^(NSNumber *ok, NSError *innerError) {
            self.loginActive=NO;self.loginChallenge=nil;
            if(!ok.boolValue){[self updateCourseSetup:innerError.localizedDescription ?: @"登录未完成，请重试。"];return;}
            self.connected=YES;[self configureCredentialAccess];[self refreshPresentation];
            if(self.workflowAwaitingLogin){AMCourseOperationContext *pending=self.workflowAwaitingLogin;self.workflowAwaitingLogin=nil;pending.authenticationIdentity=_github.authenticationIdentity;pending.authType=_github.authType;AMOperationSetResult(pending.identifier,@"登录已恢复",@"继续前会重新核验账户、课程和文件版本",NO,@"继续",pending.recovery);AMPostUIMessage(@"course-workflow",pending.identifier,@"登录已恢复",AMUIMessageInformation,@"继续",pending.recovery);[self updateCourseSetup:@"登录已恢复，可关闭此窗口后继续原操作"];}
            else if(!self.operationsPaused && self.setupWindow)[self addFork:nil];
        }];[self updateCourseSetup:@"等待你在 GitHub 完成登录…"];
    }];[self updateCourseSetup:@"正在获取验证码…"];
}
- (void)cancelLogin:(id)sender { if (self.loginActive) { [self.github cancelDeviceLogin]; [self status:@"正在取消登录…"]; } }
- (void)signOut:(id)sender { if (self.busy || self.preview || self.operationsPaused) return; [self.github signOut]; self.connected = NO; [self refreshPresentation]; [self status:@"已退出登录；本地课程和 DDL 已保留。"] ; }
- (void)addFork:(id)sender {
    if(!self.connected){[self setup:nil];return;}
    if(!self.setupWindow)[self presentCourseSetup];NSWindow *requestedWindow=self.setupWindow;
    [self work:@"正在读取个人课程 fork…" forCourse:nil operation:^id(NSError **error){return [self.github accessibleForks:error];} completion:^(NSArray *forks,NSError *error){
        if(!forks){[self updateCourseSetup:error.localizedDescription];return;}self.availableForks=forks;self.setupStep=1;self.setupRecords=NSMutableArray.array;
        for(NSDictionary *repo in forks){NSMutableDictionary *row=[@{@"fork":repo[@"full_name"],@"existing":@([self courseExists:repo[@"full_name"]])} mutableCopy];[self.setupRecords addObject:row];}
        NSMutableArray *selected=NSMutableArray.array;for(NSDictionary *row in self.setupRecords)if(self.setupSelection ? [self.setupSelection containsObject:row[@"fork"]]:[row[@"existing"] boolValue])[selected addObject:row[@"fork"]];self.setupSelection=selected;if(self.setupWindow!=requestedWindow){[self updateCourseSetup:@"课程已读取，可从开始使用继续配置。"] ;return;}[self.setupWorkspace updateContext:@{@"selected":selected}];[self updateCourseSetup:@"已添加课程默认选中；选择需要管理的其他个人 fork。"];
    }];
}
- (BOOL)courseExists:(NSString *)fork { for (NSDictionary *course in self.courses) if ([course[@"fork"] caseInsensitiveCompare:fork] == NSOrderedSame) return YES; return NO; }
- (void)linkFolder:(id)sender {
    NSDictionary *current = [self course]; if (!current) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel]; panel.canChooseDirectories = YES; panel.canChooseFiles = NO; panel.allowsMultipleSelection = NO;
    if ([panel runModal] != NSModalResponseOK) return;
    NSMutableDictionary *course = [current mutableCopy]; course[@"path"] = panel.URL.path;
    [self work:@"正在检查仓库和私有上游读取权限…" operation:^id(NSError **error) { return @([self.git linkCourse:course error:error]); } completion:^(NSNumber *ok, NSError *error) {
        if (!ok.boolValue) { [self showError:error]; return; }
        NSMutableDictionary *saved = [self savedCourse:current]; [saved setDictionary:course]; [self saveCourses]; [self refreshCourses];
        [self status:@"本地仓库已关联，上游读取权限正常。"];
    }];
}
- (void)cloneFork:(id)sender {
    NSDictionary *current = [self course]; if (!current) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel]; panel.canChooseDirectories = YES; panel.canChooseFiles = NO; panel.message = @"选择存放课程仓库的父文件夹";
    if ([panel runModal] != NSModalResponseOK) return;
    NSString *destination = [panel.URL.path stringByAppendingPathComponent:[current[@"fork"] lastPathComponent]];
    NSMutableDictionary *course = [current mutableCopy]; course[@"path"] = destination;
    if([self.github.authType isEqual:@"oauth"])course[@"upstreamURL"]=[NSString stringWithFormat:@"https://github.com/%@.git",course[@"upstream"]];
    else {NSAlert *transport = [NSAlert new]; transport.messageText = @"使用哪种本机凭据读取老师上游？";
    transport.informativeText = @"私有上游需要这台 Mac 已配置的访问权限。公开上游可直接用 HTTPS。";
    [transport addButtonWithTitle:@"HTTPS · Git 钥匙串"]; [transport addButtonWithTitle:@"SSH · 本机密钥"]; [transport addButtonWithTitle:@"取消"];
    NSModalResponse response = [transport runModal]; if (response == NSAlertThirdButtonReturn) return;
    course[@"upstreamURL"] = response == NSAlertSecondButtonReturn ? [NSString stringWithFormat:@"git@github.com:%@.git", course[@"upstream"]] : [NSString stringWithFormat:@"https://github.com/%@.git", course[@"upstream"]];}
    [self work:@"正在克隆自己的 fork 并验证老师上游…" operation:^id(NSError **error) {
        NSString *token = [self.github accessToken:error]; if (!token) return nil;
        if (![self.git cloneFork:course into:destination token:token error:error]) return @{@"cloned":@NO};
        return @{@"cloned":@YES, @"linked":@([self.git linkCourse:course error:error])};
    } completion:^(NSDictionary *result, NSError *error) {
        if ([result[@"cloned"] boolValue]) { [[self savedCourse:current] setDictionary:course]; [self saveCourses]; [self refreshCourses]; }
        if (![result[@"linked"] boolValue]) { [self showError:error]; return; }
        [self status:@"克隆成功，上游读取权限正常。"];
    }];
}
- (void)removeCourse:(id)sender {
    NSUInteger index = [self.courses indexOfObject:[self savedCourse:[self course]]]; if (index == NSNotFound) return;
    NSAlert *alert = [NSAlert new]; alert.messageText = @"移除课程关联？"; alert.informativeText = @"不会删除本地仓库或已导入的 DDL。";
    [alert addButtonWithTitle:@"移除"]; [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    [self.courses removeObjectAtIndex:index]; [self saveCourses]; [self refreshCourses];
}
- (void)scan:(id)sender { if (![self course]) [self scanAll:nil]; else if ([self course]) [self scanCourses:@[[[self course] copy]]]; }
- (void)toggleCourse:(id)sender {
    NSMutableDictionary *course = [self savedCourse:[self course]]; if (!course) return;
    course[@"enabled"] = @(course[@"enabled"] ? ![course[@"enabled"] boolValue] : NO); [self saveCourses]; [self refreshCourses];
}
- (void)installApp:(id)sender {
    NSURL *url = [NSURL URLWithString:self.github.installationURL];
    if ([url.scheme isEqual:@"https"] && [url.host isEqual:@"github.com"] && [url.path hasPrefix:@"/apps/"]) [NSWorkspace.sharedWorkspace openURL:url];
    else [self status:@"尚未配置安装页面。开发者请按仓库 docs/GITHUB_APP_SETUP.md 注册后填写公开安装链接。"];
}
- (void)scanAll:(id)sender {
    if(!self.connected || self.setupWindow.sheetParent)return;
    NSMutableArray *enabled = NSMutableArray.array;
    for (NSDictionary *course in self.courses) if (!course[@"enabled"] || [course[@"enabled"] boolValue]) [enabled addObject:[course copy]];
    [self scanCourses:enabled];
}
- (void)scanCourses:(NSArray *)courses {
    if (!courses.count) return;
    courses = [[NSArray alloc] initWithArray:courses copyItems:YES];
    NSDictionary *recognitionSettings = self.preview ? @{@"mode":@"rules",@"automaticImport":@NO} : SSRecognitionSettings();
    [self work:@"正在扫描老师仓库…" forCourse:courses.count == 1 ? courses.firstObject : nil operation:^id(NSError **error) {
        self.git.recognitionSettings = @{@"mode":@"rules"};
        NSMutableDictionary *cache = AMScanCacheLoad(error);if(!cache)return nil;
        NSMutableDictionary *result = NSMutableDictionary.dictionary;
        for (NSDictionary *course in courses) {
            if(self.git.cancelledReads)break;
            if (![course[@"path"] length]){result[course[@"fork"]]=@{@"error":@"尚未关联目录",@"issue":@"directory"};continue;}
            AMCourseOperationContext *scanContext=AMCourseContext(self);dispatch_async(dispatch_get_main_queue(),^{AMWithCourseContext(scanContext,^{self.operationFork=course[@"fork"];self.statusFork=course[@"fork"];[self status:@"获取老师内容并进行规则识别…"];if(self.firstCheckRunning){for(NSMutableDictionary *row in self.setupRecords)if([row[@"fork"] isEqual:course[@"fork"]])row[@"status"]=@"正在获取老师内容并识别…";[self updateCourseSetup:@"正在逐门检查；可收起引导，后台继续。"];}});});
            NSError *scanError = nil;
            NSDictionary *scan = [self.git scanCourse:course cache:cache error:&scanError];
            if(scan){NSDictionary *rules=scan;dispatch_async(dispatch_get_main_queue(),^{if(scanContext.cancelled || ![self workflowSourceMatches:scanContext])return;AMWithCourseContext(scanContext,^{if(self.hasUnsavedReview || self.git.cancelledReads)return;self.candidates[course[@"fork"]]=[self retainingSkill:self.candidates[course[@"fork"]] current:rules[@"candidates"] documents:rules[@"documents"]];self.materials[course[@"fork"]]=[self retainingSkill:self.materials[course[@"fork"]] current:rules[@"materials"] documents:rules[@"documents"]];[self status:[SSCourseRecognitionSettings(recognitionSettings,course)[@"mode"] isEqual:@"rules"] ? @"规则结果已显示，正在整理结果…":@"规则结果已显示，正在补充模型分析…"];});});
                NSMutableDictionary *cachedSettings=recognitionSettings.mutableCopy;cachedSettings[@"cacheOnly"]=@YES;scan=[self.git enhanceScan:scan course:course settings:cachedSettings paths:nil cache:cache];}
            result[course[@"fork"]] = scan ?: @{@"error":scanError.localizedDescription ?: @"扫描失败",@"detail":scanError.userInfo[@"SSDetail"] ?: scanError.localizedDescription ?: @"",@"issue":scanError.userInfo[@"SSIssue"] ?: @"git"};
        }
        return [self retainWorkflowResult:result cache:cache error:error];
    } completion:^(NSDictionary *result, NSError *error) {
        if (!result) { [self finishSetupScan:nil error:error courses:courses];[self showError:error]; return; }
        NSMutableArray *messages = NSMutableArray.array;
        NSMutableDictionary *reports = [self.reports mutableCopy] ?: NSMutableDictionary.dictionary;for(NSDictionary *input in courses){NSDictionary *current=[self savedCourse:input];BOOL same=current!=nil;for(NSString *field in @[@"path",@"branch",@"upstream",@"forkID",@"upstreamID",@"ownerID"])if(![(input[field] ?: NSNull.null) isEqual:current[field] ?: NSNull.null])same=NO;if(same && result[input[@"fork"]])reports[input[@"fork"]]=result[input[@"fork"]];}self.reports=reports;
        for (NSMutableDictionary *course in self.courses) {
            NSDictionary *scan = result[course[@"fork"]]; if (!scan) continue;BOOL same=NO;for(NSDictionary *input in courses)if([input[@"fork"] isEqual:course[@"fork"]]){same=YES;for(NSString *field in @[@"path",@"branch",@"upstream",@"forkID",@"upstreamID",@"ownerID"])if(![(input[field] ?: NSNull.null) isEqual:course[field] ?: NSNull.null])same=NO;}if(!same)continue;
            if (scan[@"error"]) { self.errorDetails[course[@"fork"]]=scan[@"detail"] ?: scan[@"error"];self.statuses[course[@"fork"]] = @"检查失败"; [messages addObject:[NSString stringWithFormat:@"%@: %@", course[@"fork"], scan[@"error"]]]; continue; }
            if(self.hasUnsavedReview){if(!self.deferredScans)self.deferredScans=NSMutableDictionary.dictionary;self.deferredScans[course[@"fork"]]=scan;}else {self.candidates[course[@"fork"]] = [self retainingSkill:self.candidates[course[@"fork"]] current:scan[@"candidates"] documents:scan[@"documents"]]; self.materials[course[@"fork"]] = [self retainingSkill:self.materials[course[@"fork"]] current:scan[@"materials"] ?: @[] documents:scan[@"documents"]];}
            [self updateCheckSummaryForCourse:course];
            if([recognitionSettings[@"mode"] isEqual:@"local"] && scan[@"modelCompleted"]){SSWritePlist(@"recognition-last-result.plist",@{@"course":course[@"fork"],@"date":NSDate.date,@"model":recognitionSettings[@"model"] ?: @"",@"success":scan[@"modelCompleted"]},NULL);}
            course[@"lastScan"] = scan[@"date"];if(scan[@"commit"])course[@"teacherCommit"]=scan[@"commit"];
            if (scan[@"branch"]) course[@"upstreamBranch"] = scan[@"branch"];
            [messages addObject:[NSString stringWithFormat:@"%@：%@",[course[@"fork"] lastPathComponent],self.statuses[course[@"fork"]]]];
        }
        if (!self.preview && !SSWritePlist(@"discoveries.plist", [self discoveryEnvelope], &error)) [self showError:error];
        if ([recognitionSettings[@"automaticImport"] boolValue] && self.saveReviewItems && !self.hasUnsavedReview && !self.operationsPaused) {
            NSMutableArray *items = NSMutableArray.array;
            for (NSDictionary *course in courses) for (NSDictionary *record in [self discoveriesForFork:course[@"fork"]]) if (!AMReviewIsDeleted(record) && SSCanAutomaticallyImport(record,self.tasksProvider ? self.tasksProvider() : @[],NSDate.date)) [items addObject:@{@"record":record,@"draft":@{}}];
            if (items.count) {NSUInteger before=self.tasksProvider ? self.tasksProvider().count : 0;NSString *message=self.saveReviewItems(items,YES); if (message.length) [messages addObject:message]; else {NSString *notice=[NSString stringWithFormat:@"已加入 %lu 项作业",(unsigned long)MAX((NSInteger)0,(NSInteger)(self.tasksProvider ? self.tasksProvider().count : 0)-(NSInteger)before)];[messages addObject:notice];for(NSDictionary *course in courses)[self updateCheckSummaryForCourse:course];} }
        }
        [self saveCourses]; [self refreshCourses];
        [self finishSetupScan:result error:error courses:courses];[self postRecognitionSummary];
        for(NSDictionary *course in courses)if(!result[course[@"fork"]][@"error"])[self enqueueAutomaticEnhancement:result[course[@"fork"]] course:course settings:recognitionSettings];
        if (courses.count > 1) {NSUInteger failed=0;for(NSDictionary *course in courses)if(result[course[@"fork"]][@"error"])failed++;self.statuses[@"all"]=failed ? [NSString stringWithFormat:@"%lu 门课程检查未完成",(unsigned long)failed]:[NSString stringWithFormat:@"已检查 %lu 门课程",(unsigned long)courses.count];self.errorDetails[@"all"]=[messages componentsJoinedByString:@"\n"]; } else if (!messages.count) [self status:@"请先关联本地课程文件夹，再检查作业。"];
    }];
}
- (void)sync:(id)sender {
    NSDictionary *course = [[self course] copy]; if (!course) return;
    [self work:@"正在安全合并上游，并更新自己的 fork…" forCourse:course operation:^id(NSError **error) {
        NSString *token = [self.github accessToken:error]; if (!token) return nil;
        NSDictionary *record=[self.git performRecordedCourse:course kind:@"sync" taskIDs:@[] paths:@[] message:@"同步课程文件" token:token login:@"" userID:@0 error:error];
        if([record[@"state"] isEqual:@"confirmed"])return @{@"success":@YES};if(record[@"conflicts"])return @{@"conflicts":record[@"conflicts"],@"mergeHead":record[@"mergeHead"]};return nil;
    } completion:^(NSDictionary *result, NSError *error) {
        if (result[@"conflicts"]) {
            NSMutableDictionary *saved = [self savedCourse:course]; saved[@"pendingMergeTip"] = result[@"mergeHead"]; saved[@"pendingConflicts"] = result[@"conflicts"]; [self saveCourses];
            [self showError:error]; if (!self.operationsPaused && [self.selectedFork isEqual:course[@"fork"]] && !self.window.attachedSheet) [self conflictGuide:course];
        }
        else if (!result) { if ([error.userInfo[@"SSPendingPush"] boolValue]) { [self savedCourse:course][@"pushFailed"] = @YES; [self saveCourses]; } [self showError:error]; }
        else { [[self savedCourse:course] removeObjectForKey:@"pushFailed"]; [self saveCourses]; [self status:@"课程文件已同步到本地与个人仓库，正在检查新作业"]; [self scanCourses:@[course.copy]]; }
    }];
}
- (void)continueMerge:(id)sender { NSDictionary *course = [[self course] copy]; if (course) [self conflictGuide:course]; }
- (void)finishMerge:(NSDictionary *)course {
    [self work:@"正在完成合并并更新自己的 fork…" forCourse:course operation:^id(NSError **error) {
        NSString *token = [self.github accessToken:error]; if (!token) return @NO;
        NSDictionary *record=[self.git performRecordedCourse:course kind:@"merge" taskIDs:@[] paths:@[] message:@"完成课程合并" token:token login:@"" userID:@0 error:error];return @([record[@"state"] isEqual:@"confirmed"]);
    } completion:^(NSNumber *ok, NSError *error) { if (ok.boolValue || [error.userInfo[@"SSPendingPush"] boolValue]) { NSMutableDictionary *saved = [self savedCourse:course]; [saved removeObjectForKey:@"pendingMergeTip"]; [saved removeObjectForKey:@"pendingConflicts"]; [self saveCourses]; if (ok.boolValue) [self status:@"冲突合并已完成，并已推送到自己的 fork。"]; else { saved[@"pushFailed"] = @YES; [self saveCourses]; [self showError:error]; } } else [self showError:error]; }];
}
- (void)openFolder:(id)sender { NSString *path = [self course][@"path"]; if (path.length) [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:path]]; }
- (void)report:(id)sender {
    NSDictionary *course = [self course], *report = course ? self.reports[course[@"fork"]] : nil;
    NSMutableArray *parts = NSMutableArray.array;
    if (course) [parts addObject:[NSString stringWithFormat:@"老师：%@ / %@\n个人 fork：%@ / %@\n本地：%@\n时区：%@", course[@"upstream"], course[@"upstreamBranch"], course[@"fork"], course[@"branch"], course[@"path"] ?: @"未关联", course[@"timeZone"] ?: NSTimeZone.localTimeZone.name]];
    if (report[@"error"]) [parts addObject:report[@"error"]];
    if ([report[@"skipped"] count]) [parts addObject:[@"跳过的文件：\n" stringByAppendingString:[report[@"skipped"] componentsJoinedByString:@"\n"]]];
    self.detail.string = parts.count ? [parts componentsJoinedByString:@"\n\n"] : @"还没有检查结果。";
}
- (void)push:(id)sender {
    NSDictionary *course = [[self course] copy]; if (!course) return;
    [self work:@"正在检查待推送历史和 fork 身份…" forCourse:course operation:^id(NSError **error) {
        NSString *token = [self.github accessToken:error]; if (!token) return @NO;
        NSArray *records=AMSubmissionRecords(error);if(!records)return @NO;
        for(NSDictionary *record in records.reverseObjectEnumerator)if([record[@"repository"] isEqual:course[@"fork"]] && [record[@"branch"] isEqual:course[@"branch"]] && [record[@"commit"] length] && ![record[@"state"] isEqual:@"confirmed"]){
            NSDictionary *verified=[self.git verifySubmission:record course:course token:token retry:YES error:error];return @([verified[@"state"] isEqual:@"confirmed"]);
        }
        // Legacy versions did not persist a commit identity; retain their explicitly requested retry.
        return @([self.git pushCourse:course token:token error:error]);
    } completion:^(NSNumber *ok, NSError *error) { if (ok.boolValue) { [[self savedCourse:course] removeObjectForKey:@"pushFailed"]; [self saveCourses]; [self status:@"本地提交已核验并推送到自己的仓库"]; } else [self showError:error]; }];
}
- (void)conflictGuide:(NSDictionary *)course {
    NSDictionary *saved=[self savedCourse:course].copy;for(NSString *field in @[@"path",@"branch",@"upstream",@"forkID",@"upstreamID",@"ownerID"])if(![(saved[field] ?: NSNull.null) isEqual:course[field] ?: NSNull.null]){[self status:@"课程关联已变化，请重新检查冲突"];return;}course=saved ?: course;
    [self work:@"正在读取冲突状态…" forCourse:course operation:^id(NSError **error) { return [self.git conflicts:course error:error]; } completion:^(NSArray *files, NSError *error) {
        if (self.operationsPaused) return;
        if (!files) { [self showError:error]; return; }
        if (![course[@"pendingMergeTip"] length]) { [self status:@"没有本应用记录的上游合并。请自行处理现有 Git 状态。"] ; return; }
        NSAlert *alert = NSAlert.new; alert.messageText = @"上游合并冲突引导";
        alert.informativeText = files.count ? @"仍有未解决的冲突文件。" : @"所有冲突已解决，可以完成合并。";
        NSView *list = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 550, MAX(30, files.count * 26))];
        NSMutableArray<NSButton *> *checks = NSMutableArray.array;
        for (NSUInteger i = 0; i < files.count; i++) {
            NSButton *check = [NSButton checkboxWithTitle:files[i] target:nil action:NULL]; check.frame = NSMakeRect(0, NSHeight(list.frame) - (i + 1) * 26, 545, 24); [list addSubview:check]; [checks addObject:check];
        }
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 570, MIN(260, NSHeight(list.frame)))]; scroll.hasVerticalScroller = YES; scroll.documentView = list; alert.accessoryView = scroll;
        [alert addButtonWithTitle:files.count ? @"标记已解决" : @"完成合并并推送"]; [alert addButtonWithTitle:@"打开仓库文件夹"]; [alert addButtonWithTitle:@"撤销本次合并"]; [alert addButtonWithTitle:@"关闭"];
        NSModalResponse answer = [alert runModal];
        if (answer == NSAlertSecondButtonReturn) { [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:course[@"path"]]]; return; }
        if (answer == NSAlertThirdButtonReturn) {
            NSAlert *confirm = NSAlert.new; confirm.messageText = @"撤销此次上游合并？"; confirm.informativeText = @"本次冲突解决中的编辑可能被撤销。Git 会回到合并前的状态。";
            [confirm addButtonWithTitle:@"撤销合并"]; [confirm addButtonWithTitle:@"保留"];
            if ([confirm runModal] != NSAlertFirstButtonReturn) return;
            [self work:@"正在撤销此次合并…" forCourse:course operation:^id(NSError **innerError) { return @([self.git abortMerge:course error:innerError]); } completion:^(NSNumber *ok, NSError *innerError) {
                if (!ok.boolValue) { [self showError:innerError]; return; }
                NSMutableDictionary *saved = [self savedCourse:course]; [saved removeObjectForKey:@"pendingMergeTip"]; [saved removeObjectForKey:@"pendingConflicts"]; [self saveCourses]; [self status:@"已撤销此次上游合并。"];
            }]; return;
        }
        if (answer != NSAlertFirstButtonReturn) return;
        if (!files.count) { [self finishMerge:course]; return; }
        NSMutableArray *selected = NSMutableArray.array;
        for (NSUInteger i = 0; i < checks.count; i++) if (checks[i].state == NSControlStateValueOn) [selected addObject:files[i]];
        if (!selected.count) { [self status:@"请选择已经编辑并保存的冲突文件。"] ; return; }
        [self work:@"正在检查并标记冲突文件…" forCourse:course operation:^id(NSError **innerError) { return @([self.git stageResolvedFiles:course paths:selected error:innerError]); } completion:^(NSNumber *ok, NSError *innerError) { if (!ok.boolValue) [self showError:innerError]; else [self conflictGuide:course]; }];
    }];
}
#include "AMSubmissionUI.inc"
#include "AMExternalSubmissions.inc"
#include "AMCourseEnhancement.inc"
- (void)configurePreflight:(SSSubmissionController *)sheet course:(NSDictionary *)course tasks:(NSArray *)tasks {
    course=course.copy;
    __weak typeof(self) owner=self;
    // Reads share only the Git write barrier; model work cannot block browsing.
    dispatch_queue_t readQueue=dispatch_queue_create("ddl.preflight-read",DISPATCH_QUEUE_SERIAL);
    __weak SSSubmissionController *weakSheet=sheet;
    sheet.performCheck=^NSDictionary *(NSArray *paths,NSArray *ids,NSString *extra,NSMutableDictionary *cache,BOOL(^cancelled)(void),NSError **error){
        SSCourseController *self=owner;if(!self || cancelled())return nil;
        return AMPerformResourceOperation(NSUUID.UUID.UUIDString,@"检查文件",course[@"fork"] ?: @"本机项目",@[@"git-write"],100,cancelled,^id(NSError **problem){
        __block NSDictionary *snapshot=nil;__block NSString *requirements=nil;__block NSError *failure=nil;
        dispatch_sync(readQueue,^{if(cancelled())return;SSGit *reader=SSGit.new;reader.readsCancellable=YES;dispatch_source_t cancellation=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_global_queue(QOS_CLASS_UTILITY,0));dispatch_source_set_timer(cancellation,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),100*NSEC_PER_MSEC,10*NSEC_PER_MSEC);dispatch_source_set_event_handler(cancellation,^{if(cancelled())reader.cancelledReads=YES;});dispatch_resume(cancellation);NSMutableArray *selected=NSMutableArray.array;for(NSDictionary *task in tasks)if([ids containsObject:task[@"id"]])[selected addObject:task];snapshot=[reader preflightSnapshotForCourse:course paths:paths error:&failure];requirements=[reader preflightRequirementsForCourse:course tasks:selected];dispatch_source_cancel(cancellation);});
        if(!snapshot || cancelled()){if(problem)*problem=failure;return nil;}
        if(extra.length)requirements=[NSString stringWithFormat:@"%@\n\n用户补充题目：\n%@",requirements ?: @"",extra];
        NSDictionary *report=AMPreflightCheckWithProgress(snapshot,requirements ?: @"",cache,cancelled,^(NSUInteger done,NSUInteger total){AMOperationProgress(weakSheet.operationID,@"检查文件结构、公式和附件",done,total);});return @{@"snapshot":snapshot,@"requirements":requirements ?: @"",@"report":report};
        },error);
    };
}
- (NSString *)taskCheckBlockReason {
    if(self.operationsPaused)return @"正在准备退出或安装更新。取消退出或稍后更新后，即可检查作业。";
    if(self.window.attachedSheet)return [NSString stringWithFormat:@"“%@”窗口尚未关闭。请先完成或取消该窗口，再检查作业。",self.window.attachedSheet.title.length ? self.window.attachedSheet.title:@"当前编辑"];

    return nil;
}
- (void)showTaskCheckProblem:(NSString *)message {
    if(!self.busy)[self status:message];
    NSAlert *alert=NSAlert.new;alert.messageText=@"暂时无法检查作业";alert.informativeText=message;
    [alert addButtonWithTitle:@"好"];[alert runModal];
}
#include "SSFolderCheck.inc"
- (void)commit:(id)sender {
    if(self.checkScopeWindow){[self showCheckWorkspace];[self status:@"请先完成或取消当前文件检查，再打开提交界面。"];return;}
    NSDictionary *course = [[self course] copy]; if (!course) return;
    SSSubmissionController *previous=self.submission.closed && self.submission.preserveClosedDraft && !self.submission.checkOnly && !self.submission.submittedSuccessfully && [self.submission.course[@"fork"] isEqual:course[@"fork"]] ? self.submission:nil;
    [self openSubmissionForCourse:course preserving:previous];
}
- (void)openSubmissionForCourse:(NSDictionary *)course preserving:(SSSubmissionController *)previous {
    if(previous)for(NSString *field in @[@"fork",@"branch",@"path"])if(![(previous.course[field] ?: NSNull.null) isEqual:course[field] ?: NSNull.null]){previous=nil;break;}
    if(self.submission && !self.submission.closed && self.submission!=previous && self.window.attachedSheet){[self status:@"请先完成或关闭当前提交窗口，输入已保留"];return;}
    if(previous){[previous cancel:nil];previous.preserveClosedDraft=YES;}
    [self work:@"正在读取本地修改…" forCourse:course requestKey:@"local-files" priority:100 kind:AMCourseWorkLocal operation:^id(NSError **error) { return [self.git changesForCourse:course error:error]; } completion:^(NSArray *changes, NSError *error) {
        if (!changes) { [self showError:error]; return; }
        if (self.operationsPaused) return;
        if (!changes.count && !previous) { [self showNoChanges:course];return; }
        if (self.window.attachedSheet) { [self status:@"请先关闭当前编辑弹窗，再打开“提交作业”。"]; return; }
        if(previous && self.submission!=previous)return;
        self.submission = [[SSSubmissionController alloc] initWithCourse:course changes:changes];
        NSMutableArray *related=NSMutableArray.array;for(NSDictionary *task in self.tasksProvider ? self.tasksProvider():@[])if(![task[@"deleted"] boolValue] && AMTaskBelongsToCourse(task,course))[related addObject:task];
        [self configurePreflight:self.submission course:course tasks:related];
        [self.submission configureTasks:related selected:previous ? [previous chosenTasks]:(self.submissionTaskID ? @[self.submissionTaskID]:@[])];self.submissionTaskID=nil;
        if(previous){self.submission.checkCache=previous.checkCache.mutableCopy;self.submission.report=previous.report;self.submission.snapshot=previous.snapshot;self.submission.reviewSummary=previous.reviewSummary;self.submission.requirements=previous.requirements;self.submission.message.stringValue=previous.message.stringValue;self.submission.pendingSupplement=previous.supplement.string ?: previous.pendingSupplement;NSSet *chosen=[NSSet setWithArray:[previous chosenPaths]];for(NSButton *check in self.submission.checks)check.state=check.enabled && [chosen containsObject:changes[check.tag][@"path"]] ? NSControlStateValueOn:NSControlStateValueOff;self.submission.filesValidation.stringValue=changes.count ? @"文件列表已刷新。":@"没有待提交修改，请核验提交记录。";}
        __weak typeof(self) weakSelf = self;__weak SSSubmissionController *originalSheet=self.submission;
        self.submission.refreshFiles=^{SSCourseController *owner=weakSelf;SSSubmissionController *sheet=originalSheet;if(owner && sheet && owner.submission==sheet)[owner openSubmissionForCourse:course preserving:sheet];};
        self.submission.readPreview = ^(NSString *file, void (^ready)(NSString *)) {
            SSSubmissionController *sheet=originalSheet;if(!sheet)return;NSUInteger generation=sheet.previewGeneration;SSGit *reader=SSGit.new;reader.readsCancellable=YES;
            NSString *operation=AMOperationBegin(@"读取变更预览",file,YES,^{[reader cancelCurrentOperation];});sheet.previewCancellation=^{AMOperationCancel(operation);};
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *problem=nil;
                NSString *text=AMPerformResourceOperation(NSUUID.UUID.UUIDString,@"读取预览",file,@[@"git-write"],100,^BOOL{return reader.operationCancelled || !originalSheet || originalSheet.closed || originalSheet.previewGeneration!=generation;},^id(NSError **issue){return [reader previewForCourse:course path:file error:issue];},&problem);
                AMOperationFinish(operation,reader.operationCancelled ? @"cancelled":(problem ? @"failed":@"success"),problem.localizedDescription ?: @"预览读取完成");
                dispatch_async(dispatch_get_main_queue(),^{ready(text ?: problem.localizedDescription);});
            });
        };
        self.submission.submit = ^(NSArray *paths, NSString *message) {
            SSCourseController *self = weakSelf;SSSubmissionController *submitted=originalSheet;if (!self || !submitted) return;
        __block NSDictionary *operationRecord=nil;NSArray *taskIDs=submitted.taskIDs.copy;NSDictionary *snapshot=submitted.snapshot.copy,*review=submitted.reviewSummary.copy;
        [self work:@"正在检查、提交并推送到自己的 fork…" forCourse:course requestKey:[NSString stringWithFormat:@"%@|%@|%@|%@",paths,message,snapshot[@"version"],taskIDs] priority:100 kind:AMCourseWorkSubmission operation:^id(NSError **innerError) {
            if(self.git.progress)self.git.progress(@"核验 GitHub 登录…");
            NSDictionary *user = [self.github user:innerError]; if (!user) return @NO;
            NSString *token = [self.github accessToken:innerError]; if (!token) return @NO;
            self.git.expectedSubmissionSnapshot=snapshot;self.git.submissionReviewSummary=review;
            NSDictionary *result=[self.git performRecordedCourse:course kind:@"submission" taskIDs:taskIDs paths:paths message:message token:token login:user[@"login"] userID:user[@"id"] error:innerError];
            operationRecord=result;return @([result[@"state"] isEqual:@"confirmed"]);
        } completion:^(NSNumber *ok, NSError *innerError) {
            if (self.exitSubmissionInFlight) { self.submissionFailedDuringExit = !ok.boolValue; self.exitSubmissionInFlight = NO; }
            if (!innerError && (ok.boolValue || [operationRecord[@"state"] isEqual:@"confirmed"])) { submitted.submittedSuccessfully=YES;[[self savedCourse:course] removeObjectForKey:@"pushFailed"]; [self saveCourses]; [self status:@"所选文件已提交到自己的仓库"]; }
            else {
                if([operationRecord[@"commit"] length] || ([operationRecord[@"before"] length] && [operationRecord[@"state"] isEqual:@"uncertain"])){[self savedCourse:course][@"pushFailed"]=@YES;[self saveCourses];if(innerError)[self showError:innerError];[self status:[operationRecord[@"commit"] length] ? @"本地提交已保留，请到“提交记录”核验或重试。":@"提交结果尚未确认，请到“提交记录”核验后再试。"];return;}
                if ([innerError.userInfo[@"SSPendingPush"] boolValue]) { [self savedCourse:course][@"pushFailed"] = @YES; [self saveCourses]; }
                else if (!self.window.attachedSheet && self.submission==submitted && innerError.code!=NSUserCancelledError) {
                    [submitted resumeAfterSubmissionFailure:innerError];
                    [self.window beginSheet:submitted.window completionHandler:nil];
                }
                [self showError:innerError];
            }
        }];
        };
        [self.window beginSheet:self.submission.window completionHandler:nil];
    }];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.visible.count; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSDictionary *candidate = self.visible[row]; NSString *key = column.identifier;
    NSString *value = @"";
    if ([key isEqual:@"title"]) value = candidate[@"title"];
    else if ([key isEqual:@"due"]) value = candidate[@"deadlineText"] ? [candidate[@"deadlineText"] stringByAppendingString:@" · 待确认"] : (candidate[@"dateOnly"] && [candidate[@"needsTime"] boolValue] ? [candidate[@"dateOnly"] stringByAppendingString:@" · 待补时间"] : (!candidate[@"due"] ? @"未说明时间" : ([candidate[@"needsDate"] boolValue] ? @"日期待确认" : DDLFormatDate(candidate[@"due"], @"yyyy-MM-dd HH:mm"))));
    else if ([key isEqual:@"source"]) value = [NSString stringWithFormat:@"%@:%@", candidate[@"path"], candidate[@"line"]];
    else if ([key isEqual:@"state"]) { NSString *state = [self stateForCandidate:candidate]; value = [candidate[@"confirmed"] boolValue] ? ([candidate[@"completed"] boolValue] ? @"✓ 已完成" : @"○ 待完成") : [NSString stringWithFormat:@"%@ %@", [state isEqual:@"已导入"] ? @"✓" : ([state isEqual:@"有更新"] ? @"↻" : @"○"), state]; }
    NSTextField *label = Text(value ?: @"", 13, NSFontWeightRegular, Ink()); label.lineBreakMode = NSLineBreakByTruncatingMiddle; label.toolTip = value; return label;
}
- (NSString *)stateForCandidate:(NSDictionary *)candidate {
    if (candidate[@"kind"] && ![candidate[@"kind"] isEqual:@"assignment"]) return SSActivityKindLabel(candidate[@"kind"]);
    for (NSDictionary *task in self.tasksProvider ? self.tasksProvider() : @[]) if ([task[@"sourceID"] isEqual:candidate[@"id"]]){
        if(![task[@"sourceBlobSHA"] isEqual:candidate[@"blobSHA"]])return @"有更新";
        if(task[@"sourceContextVersion"] && ![task[@"sourceContextVersion"] isEqual:SSRecordSourceVersion(candidate)])return @"有更新";
        if((candidate[@"suggestedSubtasks"] || candidate[@"additionalSubtaskSuggestions"]) && ![(task[@"sourceSubtaskVersion"] ?: @"") isEqual:SSSubtaskProposalVersion(candidate)])return @"有更新";return @"已导入";
    }
    return @"待审核";
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification { if (!self.refreshing) [self candidateSelected:nil]; }
- (void)candidateSelected:(id)sender {
    NSInteger row = self.table.selectedRow;
    NSDictionary *candidate = row >= 0 && row < (NSInteger)self.visible.count ? self.visible[row] : nil;
    BOOL assignment = !candidate[@"kind"] || [candidate[@"kind"] isEqual:@"assignment"];
    if(candidate)self.selectedCandidateID = candidate[@"id"]; BOOL canStart = self.inbox && !candidate && self.pendingReviewCandidates.count > 0;
    self.reviewButton.enabled = canStart || (candidate != nil && (assignment || [candidate[@"confirmed"] boolValue])); self.reviewButton.title = canStart ? @"开始审核…" : ([candidate[@"confirmed"] boolValue] ? @"编辑任务…" : @"审核作业…");
    self.reviewButton.toolTip = @"审核作业（Return 保存并下一项）";
    self.typeButton.enabled = candidate != nil && ![candidate[@"confirmed"] boolValue] && !self.operationsPaused;
    NSMutableString *preview = NSMutableString.string;
    if (candidate) {
        [preview appendFormat:@"%@ · %@ · %@\n%@\n", SSActivityKindLabel(candidate[@"kind"] ?: @"assignment"), candidate[@"repository"] ?: candidate[@"sourceRepository"], candidate[@"kindReason"] ?: @"", [candidate[@"warnings"] componentsJoinedByString:@"；"] ?: @""];
        NSArray *documents = candidate[@"documents"] ?: @[candidate];
        for (NSDictionary *document in documents) [preview appendFormat:@"%@:%@\n%@\n\n", document[@"path"], document[@"line"], document[@"snippet"] ?: document[@"notes"] ?: @""];
    }
    self.detail.string = candidate ? preview : @"选择课程内容，查看类型、老师原文与位置。";
}
- (void)review:(id)sender {
    if(self.operationsPaused)return;
    NSDictionary *candidate=nil;
    for(NSDictionary *record in self.visible)if([record[@"id"] isEqual:self.selectedCandidateID]){candidate=record;break;}
    if(!candidate && self.inbox)candidate=self.pendingReviewCandidates.firstObject;
    if(!candidate || (candidate[@"kind"] && ![candidate[@"kind"] isEqual:@"assignment"] && ![candidate[@"confirmed"] boolValue]))return;
    // Both entry points select the inline form, never an AppKit review sheet.
    BOOL selected=self.inbox ? [self.reviewWorkspace selectRecordWithID:candidate[@"id"]] : [self.courseWorkspace selectRecordWithID:candidate[@"id"]];
    if(!selected)[self status:@"请先处理当前未保存修改，再选择作业。"];
}

@end
