#import "SSCourseWindow.h"
#import "SSGit.h"
#import "SSGitHub.h"
#import "SSLocalData.h"
#import "DDLCore.h"
#import "DDLUI.h"
#import "SSAssignments.h"

#import "SSSubmission.inc"

@interface SSCourseTable : NSTableView @end
@implementation SSCourseTable
- (void)keyDown:(NSEvent *)event { if ([event.charactersIgnoringModifiers isEqual:@"\r"] && self.selectedRow >= 0) { [NSApp sendAction:self.doubleAction to:self.target from:self]; return; } [super keyDown:event]; }
@end

static NSButton *SSButton(NSString *text, id target, SEL action, NSRect frame) { ActionButton *button = Button(text, target, action, 2); button.frame = frame; return button; }
@interface SSCourseController ()
@property SSGitHub *github;
@property SSGit *git;
@property NSMutableArray<NSMutableDictionary *> *courses;
@property NSMutableDictionary<NSString *, NSArray *> *candidates;
@property NSMutableDictionary<NSString *, NSArray *> *materials;
@property NSMutableDictionary *kindOverrides;
@property NSPopUpButton *typeFilter;
@property NSButton *typeButton;
@property NSArray<NSDictionary *> *availableForks;
@property dispatch_queue_t queue;
@property NSPopUpButton *coursePicker;
@property NSPopUpButton *reviewFilter;
@property NSSegmentedControl *sections;
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
@property NSButton *reviewButton;
@property NSButton *setupButton;
@property NSButton *recoveryButton;
@property NSProgressIndicator *progress;
@property NSTextField *emptyLabel;
@property NSMutableDictionary *statuses;
@property NSString *operationFork;
@property NSString *statusFork;
@property BOOL connected;
@property BOOL preview;
@property BOOL guided;
@property BOOL refreshing;
@property NSTableView *table;
@property NSTextView *detail;
@property NSTextField *accountLabel;
@property NSTextField *statusLabel;
@property NSTimer *timer;
@property BOOL busy;
@property BOOL loginActive;
@property NSArray<NSButton *> *actionButtons;
@property NSDictionary *reports;
@property SSSubmissionController *submission;
@property BOOL allowingExitSubmission;
@property BOOL exitSubmissionInFlight;
@property (readwrite) BOOL submissionFailedDuringExit;
@end

@implementation SSCourseController
- (instancetype)initWithPreview:(BOOL)preview {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        self.preview = preview; self.github = SSGitHub.new; self.git = SSGit.new;
        self.courses = NSMutableArray.array; self.candidates = NSMutableDictionary.dictionary; self.statuses = NSMutableDictionary.dictionary; self.query = @""; self.pageStates = NSMutableDictionary.dictionary;
        self.materials = NSMutableDictionary.dictionary;
        id overrides = preview ? nil : SSReadPlist(@"discovery-overrides.plist");
        self.kindOverrides = [overrides isKindOfClass:NSDictionary.class] ? [overrides mutableCopy] : NSMutableDictionary.dictionary;
        NSArray *saved = preview ? @[] : SSReadPlist(@"courses.plist");
        for (id item in [saved isKindOfClass:NSArray.class] ? saved : @[]) if ([item isKindOfClass:NSDictionary.class] && [item[@"fork"] isKindOfClass:NSString.class]) [self.courses addObject:[item mutableCopy]];
        self.connected = !preview && SSReadSecret(@"github") != nil;
        __weak typeof(self) weakSelf = self;
        self.git.identityVerifier = ^NSDictionary *(NSDictionary *course, NSError **error) { return [weakSelf.github verifyCourse:course error:error]; };
        self.git.progress = ^(NSString *phase) { dispatch_async(dispatch_get_main_queue(), ^{ if (weakSelf.busy) [weakSelf status:phase]; }); };
        self.queue = dispatch_queue_create("ddl.course-work", DISPATCH_QUEUE_SERIAL);
        [self buildUI]; [self refreshCourses];
    } return self;
}
- (NSWindow *)window { return self.view.window; }
- (BOOL)operationBusy { return self.busy; }
- (BOOL)hasSubmissionSheet { return self.submission.window.sheetParent != nil; }
- (BOOL)hasUnsavedSubmission { return self.hasSubmissionSheet && self.submission.hasUnsavedChanges; }
- (void)setOperationsPaused:(BOOL)paused { _operationsPaused = paused; [self refreshPresentation]; }
- (void)cancelPendingLogin { [self cancelLogin:nil]; }
- (void)discardSubmission { [self.submission cancel:nil]; self.submission = nil; }
- (void)acknowledgeSubmissionFailure { self.submissionFailedDuringExit = NO; }
- (BOOL)persistForExit:(NSError **)error { return self.preview || SSWritePlist(@"courses.plist", self.courses, error); }
- (BOOL)saveSubmissionForExit {
    self.allowingExitSubmission = YES; self.exitSubmissionInFlight = YES;
    BOOL saved = [self.submission saveForExit]; self.allowingExitSubmission = NO;
    if (!saved) self.exitSubmissionInFlight = NO;
    return saved;
}
- (NSString *)accountSummary { if (self.loginActive) return @"取消 GitHub 登录"; if (self.busy && !self.connected) return @"正在连接 GitHub…"; return self.connected ? @"GitHub 已连接" : @"连接 GitHub"; }
- (void)buildUI {
    Surface *root = Box(Canvas(), 0); root.frame = NSMakeRect(0, 0, 960, 600); self.view = root;
    __weak typeof(self) weakSelf = self; root.onResize = ^{ [weakSelf layoutContent]; }; root.onAppearanceChange = ^{ [weakSelf refreshPresentation]; };
    self.accountLabel = Text(@"", 13, NSFontWeightRegular, Muted()); [root addSubview:self.accountLabel];
    self.coursePicker = [[PastelPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; self.coursePicker.target = self; self.coursePicker.action = @selector(courseChanged:); [root addSubview:self.coursePicker];
    self.scanButton = SSButton(@"检查作业", self, @selector(scan:), NSZeroRect); [root addSubview:self.scanButton];
    self.syncButton = SSButton(@"更新作业", self, @selector(sync:), NSZeroRect); [root addSubview:self.syncButton];
    self.commitButton = SSButton(@"提交作业", self, @selector(commit:), NSZeroRect); [root addSubview:self.commitButton];
    self.moreButton = SSButton(@"更多", self, @selector(more:), NSZeroRect); [root addSubview:self.moreButton];
    self.sections = Segments(@[@"课程内容", @"已加入任务", @"仓库信息"], self, @selector(sectionChanged:)); [root addSubview:self.sections];
    self.typeFilter = [[PastelPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [self.typeFilter addItemsWithTitles:@[@"全部类型", @"作业", @"课上任务", @"考试", @"待确认类型"]]; self.typeFilter.target = self; self.typeFilter.action = @selector(sectionChanged:); [root addSubview:self.typeFilter];
    self.reviewFilter = [[PastelPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [self.reviewFilter addItemsWithTitles:@[@"待审核", @"全部结果", @"已导入"]]; self.reviewFilter.target = self; self.reviewFilter.action = @selector(sectionChanged:); [root addSubview:self.reviewFilter];
    self.search = [[NSSearchField alloc] initWithFrame:NSZeroRect]; self.search.placeholderString = @"搜索作业或来源文件"; self.search.delegate = self; self.search.sendsSearchStringImmediately = YES; [root addSubview:self.search];
    self.statusLabel = Text(@"", 12, NSFontWeightRegular, Muted()); [root addSubview:self.statusLabel];
    self.progress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect]; self.progress.style = NSProgressIndicatorStyleSpinning; self.progress.displayedWhenStopped = NO; [root addSubview:self.progress];
    self.setupButton = SSButton(@"添加课程", self, @selector(setup:), NSZeroRect); [root addSubview:self.setupButton];
    self.recoveryButton = SSButton(@"", self, @selector(recover:), NSZeroRect); [root addSubview:self.recoveryButton];
    self.emptyLabel = Text(@"", 14, NSFontWeightMedium, Muted()); self.emptyLabel.alignment = NSTextAlignmentCenter; [root addSubview:self.emptyLabel];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect]; scroll.hasVerticalScroller = YES; scroll.autohidesScrollers = YES; scroll.borderType = NSNoBorder;
    self.table = [[SSCourseTable alloc] initWithFrame:NSZeroRect]; self.table.delegate = self; self.table.dataSource = self; self.table.rowHeight = 44; self.table.columnAutoresizingStyle = NSTableViewNoColumnAutoresizing; self.table.intercellSpacing = NSMakeSize(8, 0); self.table.usesAlternatingRowBackgroundColors = NO; self.table.backgroundColor = Card();
    for (NSArray *spec in @[@[@"title", @"作业", @250], @[@"due", @"截止时间", @190], @[@"source", @"来源", @240], @[@"state", @"状态", @100]]) { NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:spec[0]]; column.title = spec[1]; column.width = [spec[2] doubleValue]; column.minWidth = 72; [self.table addTableColumn:column]; }
    self.table.target = self; self.table.action = @selector(candidateSelected:); self.table.doubleAction = @selector(review:); scroll.documentView = self.table; [root addSubview:scroll];
    NSScrollView *detailScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect]; detailScroll.hasVerticalScroller = YES; detailScroll.autohidesScrollers = YES; detailScroll.drawsBackground = NO;
    self.detail = [[PastelNotesView alloc] initWithFrame:NSZeroRect]; self.detail.editable = NO; self.detail.font = [NSFont systemFontOfSize:13]; self.detail.textColor = Ink(); self.detail.backgroundColor = Canvas(); self.detail.textContainerInset = NSMakeSize(8, 8); self.detail.autoresizingMask = NSViewWidthSizable; self.detail.textContainer.widthTracksTextView = YES; detailScroll.documentView = self.detail; [root addSubview:detailScroll];
    self.reviewButton = SSButton(@"审核作业…", self, @selector(review:), NSZeroRect); ((ActionButton *)self.reviewButton).tone = 1; [root addSubview:self.reviewButton];
    self.typeButton = SSButton(@"更改类型…", self, @selector(changeType:), NSZeroRect); [root addSubview:self.typeButton];
    self.actionButtons = @[self.scanButton, self.syncButton, self.commitButton, self.moreButton, self.setupButton];
    [self layoutContent];
}
- (void)layoutContent {
    CGFloat w = NSWidth(self.view.bounds), h = NSHeight(self.view.bounds);
    self.accountLabel.frame = NSMakeRect(0, 0, w - 152, 28); self.setupButton.frame = NSMakeRect(w - 136, 0, 136, 36);
    self.coursePicker.frame = NSMakeRect(0, 48, MAX(180, w - (self.inbox ? 192 : 416)), 36);
    self.scanButton.frame = NSMakeRect(w - (self.inbox ? 184 : 408), 48, 104, 36); self.syncButton.frame = NSMakeRect(w - 296, 48, 104, 36); self.commitButton.frame = NSMakeRect(w - 184, 48, 104, 36); self.moreButton.frame = NSMakeRect(w - 72, 48, 72, 36);
    self.sections.frame = NSMakeRect(0, 100, 296, 32); self.sections.hidden = self.inbox;
    self.typeFilter.frame = NSMakeRect(312, 100, 120, 32); self.typeFilter.hidden = self.inbox;
    self.reviewFilter.frame = NSMakeRect(0, 100, 152, 32); self.reviewFilter.hidden = !self.inbox;
    self.search.frame = NSMakeRect(MAX(448, w - 272), 100, MAX(128, MIN(272, w - 448)), 32);
    if (self.inbox) self.search.frame = NSMakeRect(w - 272, 100, 272, 32);
    self.statusLabel.frame = NSMakeRect(24, 144, w - 180, 24); self.progress.frame = NSMakeRect(0, 148, 16, 16); self.recoveryButton.frame = NSMakeRect(w - 144, 140, 144, 32);
    self.table.enclosingScrollView.frame = NSMakeRect(0, 184, w, MAX(112, h - 348));
    self.detail.enclosingScrollView.frame = NSMakeRect(0, h - 152, w, 104); self.reviewButton.frame = NSMakeRect(w - 152, h - 40, 152, 36);
    self.typeButton.frame = NSMakeRect(0, h - 40, 136, 36);
    self.emptyLabel.frame = NSMakeRect(16, 204, w - 32, 72);
    CGFloat available = w - 132; self.table.tableColumns[3].width = 96;
    NSArray *weights = @[@0.34, @0.28, @0.38];
    for (NSUInteger i = 0; i < 3; i++) self.table.tableColumns[i].width = MAX(72, available * [weights[i] doubleValue]);
}
- (void)setInbox:(BOOL)inbox {
    if (_inbox == inbox) return;
    NSString *oldKey = _inbox ? @"inbox" : @"courses";
    self.pageStates[oldKey] = @{@"fork":self.selectedFork ?: @"", @"query":self.query ?: @"", @"selection":self.selectedCandidateID ?: @"", @"scroll":@(self.table.enclosingScrollView.contentView.bounds.origin.y), @"section":@(self.sections.selectedSegment), @"type":@(self.typeFilter.indexOfSelectedItem), @"review":@(self.reviewFilter.indexOfSelectedItem)};
    _inbox = inbox; NSDictionary *state = self.pageStates[inbox ? @"inbox" : @"courses"];
    self.selectedFork = [state[@"fork"] length] ? state[@"fork"] : nil; self.selectedCandidateID = state[@"selection"]; self.query = state[@"query"] ?: @""; self.search.stringValue = self.query;
    self.sections.selectedSegment = [state[@"section"] integerValue]; [self.typeFilter selectItemAtIndex:[state[@"type"] integerValue]]; [self.reviewFilter selectItemAtIndex:[state[@"review"] integerValue]];
    [self refreshCourses]; [self.table.enclosingScrollView.contentView scrollToPoint:NSMakePoint(0, [state[@"scroll"] doubleValue])];
}
- (void)startAutomaticChecks {
    if (self.preview || self.timer) return;
    [self scanAll:nil]; self.timer = [NSTimer scheduledTimerWithTimeInterval:6 * 3600 target:self selector:@selector(scanAll:) userInfo:nil repeats:YES];
}
- (void)dealloc { [self.timer invalidate]; }
- (NSUInteger)pendingCount {
    NSUInteger count = 0; NSMutableSet *seen = NSMutableSet.set;
    for (NSDictionary *course in self.courses) for (NSDictionary *candidate in [self discoveriesForFork:course[@"fork"]]) if ([candidate[@"kind"] isEqual:@"assignment"] && ![seen containsObject:candidate[@"id"]] && ![[self stateForCandidate:candidate] isEqual:@"已导入"]) { [seen addObject:candidate[@"id"]]; count++; }
    return count;
}
- (void)accountSettings:(id)sender {
    if (self.operationsPaused) return;
    if (self.busy) { if (self.loginActive) [self cancelLogin:nil]; return; }
    NSAlert *alert = NSAlert.new; alert.messageText = self.connected ? @"GitHub 账户已连接" : @"连接 GitHub";
    alert.informativeText = @"先授权自己的课程仓库，再通过设备码登录。登录信息只保存在本机钥匙串。";
    [alert addButtonWithTitle:self.connected ? @"退出登录" : @"登录 GitHub"]; [alert addButtonWithTitle:@"安装授权…"]; if (self.loginActive) [alert addButtonWithTitle:@"取消登录"]; [alert addButtonWithTitle:@"关闭"];
    NSModalResponse answer = [alert runModal]; if (answer == NSAlertFirstButtonReturn) { if (self.connected) [self signOut:nil]; else [self login:nil]; } else if (answer == NSAlertSecondButtonReturn) [self installApp:nil]; else if (self.loginActive && answer == NSAlertThirdButtonReturn) [self cancelLogin:nil];
}
- (void)setup:(id)sender {
    self.guided = YES;
    if (!self.connected) [self accountSettings:nil]; else if ([self course] && ![[self course][@"path"] length]) [self chooseLocalFolder]; else [self addFork:nil];
}
- (void)chooseLocalFolder {
    NSAlert *alert = NSAlert.new; alert.messageText = @"关联课程文件夹"; alert.informativeText = @"已下载课程仓库时选择已有文件夹；还未下载时选择保存位置。";
    [alert addButtonWithTitle:@"选择已有文件夹"]; [alert addButtonWithTitle:@"下载课程仓库"]; [alert addButtonWithTitle:@"稍后"];
    NSModalResponse answer = [alert runModal]; if (answer == NSAlertFirstButtonReturn) [self linkFolder:nil]; else if (answer == NSAlertSecondButtonReturn) [self cloneFork:nil];
}
- (void)more:(NSButton *)sender {
    NSMenu *menu = NSMenu.new; menu.autoenablesItems = NO; NSDictionary *course = [self course];
    for (NSArray *entry in @[@[@"添加课程…", NSStringFromSelector(@selector(addFork:))], @[@"关联文件夹…", NSStringFromSelector(@selector(linkFolder:))], @[@"下载课程仓库…", NSStringFromSelector(@selector(cloneFork:))], @[@"打开文件夹", NSStringFromSelector(@selector(openFolder:))], @[@"继续处理冲突…", NSStringFromSelector(@selector(continueMerge:))], @[@"重试推送", NSStringFromSelector(@selector(push:))], @[@"启用 / 停用自动检查", NSStringFromSelector(@selector(toggleCourse:))], @[@"仓库详情", NSStringFromSelector(@selector(repositoryDetails:))], @[@"操作详情…", NSStringFromSelector(@selector(operationDetails:))], @[@"移除课程…", NSStringFromSelector(@selector(removeCourse:))]]) {
        NSMenuItem *item = [menu addItemWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:@""]; item.target = self;
        if (item.action == @selector(continueMerge:)) item.enabled = [course[@"pendingMergeTip"] length] > 0;
        if (item.action == @selector(push:)) item.enabled = [course[@"pushFailed"] boolValue];
        if (item.action == @selector(toggleCourse:)) item.title = [course[@"enabled"] isEqual:@NO] ? @"启用自动检查" : @"停用自动检查";
    }
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight(sender.bounds)) inView:sender];
}
- (void)repositoryDetails:(id)sender { self.sections.selectedSegment = 2; [self refreshPresentation]; }
- (void)operationDetails:(id)sender { NSAlert *alert = NSAlert.new; alert.messageText = [self course][@"fork"] ?: @"课程检查"; alert.informativeText = self.statuses[self.selectedFork ?: @"all"] ?: @"尚无操作记录。"; [alert addButtonWithTitle:@"关闭"]; [alert beginSheetModalForWindow:self.window completionHandler:nil]; }
- (void)recover:(id)sender { if ([[self course][@"pendingMergeTip"] length]) [self continueMerge:nil]; else [self push:nil]; }
- (void)focusSearch { [self.view.window makeFirstResponder:self.search]; }
- (void)sectionChanged:(id)sender { [self refreshPresentation]; }
- (void)controlTextDidChange:(NSNotification *)notification { if (notification.object == self.search) { self.query = self.search.stringValue; [self refreshPresentation]; } }
- (void)saveCourses { if (self.preview) return; NSError *error = nil; if (!SSWritePlist(@"courses.plist", self.courses, &error)) [self showError:error]; }
- (NSMutableDictionary *)savedCourse:(NSDictionary *)course { for (NSMutableDictionary *saved in self.courses) if ([saved[@"fork"] isEqual:course[@"fork"]]) return saved; return nil; }
- (NSDictionary *)course { for (NSDictionary *course in self.courses) if ([course[@"fork"] isEqual:self.selectedFork]) return course; return nil; }
- (NSArray *)discoveriesForFork:(NSString *)fork {
    NSMutableArray *result = NSMutableArray.array;
    for (NSDictionary *item in [(self.candidates[fork] ?: @[]) arrayByAddingObjectsFromArray:self.materials[fork] ?: @[]]) {
        NSMutableDictionary *copy = item.mutableCopy; NSString *kind = self.kindOverrides[item[@"id"]] ?: item[@"kind"] ?: @"assignment";
        if (![@[@"assignment", @"classroom", @"exam", @"unknown"] containsObject:kind]) kind = @"unknown";
        copy[@"kind"] = kind; if (self.kindOverrides[item[@"id"]]) copy[@"kindReason"] = @"你已手动确认类型";
        [result addObject:copy];
    } return result;
}
- (BOOL)setKind:(NSString *)kind forDiscovery:(NSDictionary *)record error:(NSError **)error {
    if (!record[@"id"] || ![@[@"assignment", @"classroom", @"exam", @"unknown"] containsObject:kind]) return NO;
    NSMutableDictionary *next = self.kindOverrides.mutableCopy; next[record[@"id"]] = kind;
    if (!self.preview && !SSWritePlist(@"discovery-overrides.plist", next, error)) return NO;
    self.kindOverrides = next; [self refreshPresentation]; return YES;
}
- (void)changeType:(id)sender {
    NSInteger row = self.table.selectedRow; if (self.busy || self.operationsPaused || row < 0 || row >= (NSInteger)self.visible.count) return;
    NSDictionary *record = self.visible[row]; if ([record[@"confirmed"] boolValue]) return;
    NSAlert *alert = NSAlert.new; alert.messageText = @"确认课程内容类型"; alert.informativeText = @"只有作业进入待审核清单。考试与课上任务只在课程页标注；已确认的任务不会被自动删除。";
    NSPopUpButton *menu = [[PastelPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 280, 32) pullsDown:NO]; [menu addItemsWithTitles:@[@"作业", @"课上任务", @"考试", @"待确认类型"]];
    NSArray *kinds = @[@"assignment", @"classroom", @"exam", @"unknown"]; NSInteger selected = [kinds indexOfObject:record[@"kind"]]; [menu selectItemAtIndex:selected == NSNotFound ? 3 : selected]; alert.accessoryView = menu;
    [alert addButtonWithTitle:@"保存类型"]; [alert addButtonWithTitle:@"取消"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse answer) { if (answer == NSAlertFirstButtonReturn) { NSError *error = nil; if (![self setKind:kinds[menu.indexOfSelectedItem] forDiscovery:record error:&error]) [self showError:error]; } }];
}
- (NSArray *)visible {
    NSMutableArray *result = NSMutableArray.array; NSMutableSet *seen = NSMutableSet.set;
    if (!self.inbox && self.sections.selectedSegment == 1) {
        for (NSDictionary *task in self.tasksProvider ? self.tasksProvider() : @[]) if (![task[@"deleted"] boolValue] && [task[@"sourceRepository"] isEqual:[self course][@"upstream"]]) {
            NSMutableDictionary *copy = task.mutableCopy; copy[@"confirmed"] = @YES; copy[@"path"] = task[@"sourcePath"] ?: @""; copy[@"line"] = task[@"sourceLine"] ?: @0; [result addObject:copy];
        }
    } else {
        for (NSDictionary *course in self.courses) {
            if (self.selectedFork && ![course[@"fork"] isEqual:self.selectedFork]) continue;
            for (NSDictionary *candidate in [self discoveriesForFork:course[@"fork"]]) {
                if (self.inbox && ![candidate[@"kind"] isEqual:@"assignment"]) continue;
                NSArray *types = @[@"", @"assignment", @"classroom", @"exam", @"unknown"];
                if (!self.inbox && self.typeFilter.indexOfSelectedItem > 0 && ![candidate[@"kind"] isEqual:types[self.typeFilter.indexOfSelectedItem]]) continue;
                NSString *state = [self stateForCandidate:candidate];
                if (self.inbox && ((self.reviewFilter.indexOfSelectedItem == 0 && [state isEqual:@"已导入"]) || (self.reviewFilter.indexOfSelectedItem == 2 && ![state isEqual:@"已导入"]))) continue;
                if (![seen containsObject:candidate[@"id"]]) { [seen addObject:candidate[@"id"]]; [result addObject:candidate]; }
            }
        }
    }
    NSString *query = [self.query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (query.length) [result filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) { NSString *text = [NSString stringWithFormat:@"%@ %@ %@", item[@"title"], item[@"path"], item[@"repository"] ?: item[@"subject"]]; return [text rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound; }]];
    return result;
}
- (void)refreshCourses {
    [self.coursePicker removeAllItems]; if (self.inbox) [self.coursePicker addItemWithTitle:@"全部课程"];
    BOOL found = NO;
    for (NSDictionary *course in self.courses) {
        NSString *label = [NSString stringWithFormat:@"%@ · %@ · %@", [course[@"fork"] lastPathComponent], [course[@"path"] length] ? @"已关联" : @"待关联", course[@"lastScan"] ? DDLFormatDate(course[@"lastScan"], @"M/d HH:mm") : @"未检查"];
        [self.coursePicker addItemWithTitle:label]; self.coursePicker.lastItem.representedObject = course[@"fork"];
        if ([course[@"fork"] isEqual:self.selectedFork]) { [self.coursePicker selectItem:self.coursePicker.lastItem]; found = YES; }
    }
    if (!found) { self.selectedFork = self.inbox ? nil : [self.courses firstObject][@"fork"]; if (self.coursePicker.numberOfItems) [self.coursePicker selectItemAtIndex:0]; }
    [self refreshPresentation];
}
- (void)refreshPresentation {
    if (self.refreshing || !self.table) return; self.refreshing = YES;
    NSDictionary *course = [self course]; NSString *key = self.selectedFork ?: @"all";
    NSDate *last = course[@"lastScan"];
    NSString *context = course ? [NSString stringWithFormat:@"%@ · 上次检查：%@%@", course[@"upstream"], last ? DDLFormatDate(last, @"M月d日 HH:mm") : @"尚未检查", [course[@"enabled"] isEqual:@NO] ? @" · 自动检查已停用" : @""] : @"所有课程的发现结果集中在这里";
    self.accountLabel.stringValue = context;
    self.statusLabel.stringValue = self.statuses[key] ?: @"";
    if (self.busy) self.statusLabel.stringValue = [NSString stringWithFormat:@"%@：%@", self.operationFork ?: @"课程检查", self.statuses[self.operationFork ?: @"all"] ?: @"正在处理…"];
    self.statusLabel.toolTip = self.statusLabel.stringValue; self.accountLabel.toolTip = context;
    BOOL local = [course[@"path"] length] > 0;
    self.setupButton.title = !self.connected ? @"连接 GitHub" : (course && !local ? @"关联文件夹…" : @"添加课程…");
    self.setupButton.enabled = !self.busy && !self.operationsPaused; self.moreButton.enabled = !self.busy && !self.operationsPaused && course != nil;
    self.syncButton.hidden = self.inbox; self.commitButton.hidden = self.inbox;
    self.syncButton.enabled = self.commitButton.enabled = !self.busy && !self.operationsPaused && local && self.connected;
    BOOL anyLocal = NO; for (NSDictionary *item in self.courses) if ([item[@"path"] length]) anyLocal = YES; self.scanButton.enabled = !self.busy && !self.operationsPaused && (local || (self.inbox && !course && anyLocal));
    self.recoveryButton.hidden = !course || (![course[@"pendingMergeTip"] length] && ![course[@"pushFailed"] boolValue]); self.recoveryButton.enabled = !self.busy && !self.operationsPaused;
    self.recoveryButton.title = [course[@"pendingMergeTip"] length] ? @"处理冲突…" : @"重试推送";
    NSArray *visible = [self visible];
    NSString *selectedID = self.selectedCandidateID; NSPoint scrollPosition = self.table.enclosingScrollView.contentView.bounds.origin;
    [self.table reloadData]; [self.table deselectAll:nil];
    if (selectedID) for (NSUInteger i = 0; i < visible.count; i++) if ([visible[i][@"id"] isEqual:selectedID]) { [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO]; break; }
    [self.table.enclosingScrollView.contentView scrollToPoint:scrollPosition];
    BOOL info = !self.inbox && self.sections.selectedSegment == 2;
    self.table.enclosingScrollView.hidden = info || !visible.count;
    self.emptyLabel.hidden = info || visible.count > 0;
    self.emptyLabel.stringValue = !self.courses.count ? @"连接 GitHub，然后添加你的课程仓库" : (course && !local ? @"这门课尚未关联本地文件夹\n点击“关联文件夹…”继续" : (self.query.length ? @"没有匹配的作业，试试其他关键词" : (self.inbox ? @"暂无待审核作业，检查课程后会在这里显示" : @"暂无作业结果，点击“检查作业”刷新")));
    self.emptyLabel.maximumNumberOfLines = 2; self.emptyLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.table.backgroundColor = Card(); self.detail.textColor = Ink(); ThemeEditor(self.detail);
    if (info) [self report:nil]; else [self candidateSelected:nil];
    self.reviewButton.hidden = info;
    self.table.tableColumns.firstObject.title = self.inbox ? @"作业" : @"课程内容";
    self.typeButton.hidden = info || (!self.inbox && self.sections.selectedSegment == 1);
    self.typeFilter.hidden = self.inbox || self.sections.selectedSegment != 0;
    [self layoutContent]; self.refreshing = NO;
    if (self.stateChanged) self.stateChanged();
}
- (void)status:(NSString *)message { self.statuses[self.statusFork ?: self.selectedFork ?: @"all"] = message ?: @""; [self refreshPresentation]; }
- (void)showError:(NSError *)error { if (error) [self status:[@"⚠ " stringByAppendingString:error.localizedDescription]]; }
- (void)work:(NSString *)message operation:(id (^)(NSError **))operation completion:(void (^)(id, NSError *))completion {
    [self work:message forCourse:[self course] operation:operation completion:completion];
}
- (void)work:(NSString *)message forCourse:(NSDictionary *)course operation:(id (^)(NSError **))operation completion:(void (^)(id, NSError *))completion {
    if (self.preview) { [self status:@"模拟预览不会操作真实账户或仓库"]; return; }
    if (self.busy || (self.operationsPaused && !self.allowingExitSubmission)) return;
    self.busy = YES; self.workGeneration++; NSUInteger generation = self.workGeneration; NSString *target = course[@"fork"]; self.operationFork = target; self.statusFork = target; [self.progress startAnimation:nil]; [self status:message];
    dispatch_async(self.queue, ^{
        NSError *error = nil; id value = operation(&error);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO; [self.progress stopAnimation:nil]; self.statusFork = target;
            completion(value, error); if (self.workGeneration == generation) { self.statusFork = nil; self.operationFork = nil; } [self refreshPresentation];
            if (self.operationStateChanged) self.operationStateChanged();
        });
    });
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
    if (!SSWritePlist(@"settings.plist", @{@"clientID":identifier, @"installationURL":installationURL}, &error)) { [self showError:error]; return; }
    self.github.clientID = identifier; self.github.installationURL = installationURL; [self status:@"已保存公开应用信息。请先安装授权，再登录。"];
}
- (void)login:(id)sender {
    [self work:@"正在申请 GitHub 设备授权…" operation:^id(NSError **error) { return [self.github beginDeviceLogin:error]; } completion:^(NSDictionary *challenge, NSError *error) {
        if (self.operationsPaused) return;
        if (!challenge) { [self showError:error]; return; }
        NSAlert *alert = [NSAlert new]; alert.messageText = [@"请在 GitHub 输入代码 " stringByAppendingString:challenge[@"user_code"] ?: @""];
        alert.informativeText = @"浏览器中仅安装到你自己的课程 fork；应用不会要求老师安装。";
        [alert addButtonWithTitle:@"打开 GitHub 并等待授权"]; [alert addButtonWithTitle:@"取消"];
        if ([alert runModal] != NSAlertFirstButtonReturn) return;
        [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://github.com/login/device"]];
        self.loginActive = YES;
        [self work:@"等待 GitHub 授权…" operation:^id(NSError **innerError) { return @([self.github completeDeviceLogin:challenge error:innerError]); } completion:^(NSNumber *ok, NSError *innerError) {
            self.loginActive = NO;
            if (!ok.boolValue) { [self showError:innerError]; return; }
            self.connected = YES; [self refreshPresentation]; [self status:@"GitHub 已连接"]; if (self.guided && !self.operationsPaused) { if ([self course] && ![[self course][@"path"] length]) { self.guided = NO; [self chooseLocalFolder]; } else [self addFork:nil]; }
        }];
    }];
}
- (void)cancelLogin:(id)sender { if (self.loginActive) { [self.github cancelDeviceLogin]; [self status:@"正在取消登录…"]; } }
- (void)signOut:(id)sender { if (self.busy || self.preview || self.operationsPaused) return; [self.github signOut]; self.connected = NO; [self refreshPresentation]; [self status:@"已退出登录；本地课程和 DDL 已保留。"] ; }
- (void)addFork:(id)sender {
    [self work:@"正在读取可访问的 fork…" operation:^id(NSError **error) { return [self.github accessibleForks:error]; } completion:^(NSArray *forks, NSError *error) {
        if (self.operationsPaused) return;
        if (!forks) { [self showError:error]; return; }
        self.availableForks = forks;
        self.connected = YES;
        NSMutableArray *choices = [NSMutableArray array];
        for (NSDictionary *repo in forks) if (![self courseExists:repo[@"full_name"]]) [choices addObject:repo];
        if (!choices.count) { [self status:@"没有新的可选 fork。请在 GitHub App 安装页授权课程 fork。"] ; return; }
        NSPopUpButton *picker = [[PastelPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 410, 28) pullsDown:NO];
        for (NSDictionary *repo in choices) [picker addItemWithTitle:repo[@"full_name"]];
        NSAlert *alert = [NSAlert new]; alert.messageText = @"添加自己的课程 fork"; alert.accessoryView = picker;
        [alert addButtonWithTitle:@"添加"]; [alert addButtonWithTitle:@"取消"];
        if ([alert runModal] != NSAlertFirstButtonReturn) return;
        NSDictionary *choice = choices[picker.indexOfSelectedItem];
        [self work:@"正在核验老师上游…" operation:^id(NSError **innerError) { return [self.github repository:choice[@"full_name"] error:innerError]; } completion:^(NSDictionary *details, NSError *innerError) {
            NSDictionary *parent = details[@"parent"];
            if (![parent isKindOfClass:NSDictionary.class] || ![parent[@"full_name"] isKindOfClass:NSString.class]) { [self status:@"该仓库没有可验证的老师上游，不能添加。"] ; return; }
            if (!details[@"id"] || !parent[@"id"] || !details[@"owner"][@"id"]) { [self status:@"GitHub 未返回完整仓库身份，不能添加。"]; return; }
            NSMutableDictionary *course = [@{@"enabled":@YES, @"fork":details[@"full_name"], @"upstream":parent[@"full_name"], @"forkID":details[@"id"], @"upstreamID":parent[@"id"], @"ownerID":details[@"owner"][@"id"], @"timeZone":NSTimeZone.localTimeZone.name,
                @"branch":details[@"default_branch"] ?: @"main", @"upstreamBranch":parent[@"default_branch"] ?: @"main",
                @"upstreamURL":parent[@"clone_url"] ?: @""} mutableCopy];
            [self.courses addObject:course]; [self saveCourses]; [self refreshCourses];
            self.selectedFork = course[@"fork"]; [self refreshCourses];
            [self status:@"课程已添加，下一步关联本地文件夹"]; if (self.guided && !self.operationsPaused) { self.guided = NO; [self chooseLocalFolder]; }
        }];
    }];
}
- (BOOL)courseExists:(NSString *)fork { for (NSDictionary *course in self.courses) if ([course[@"fork"] caseInsensitiveCompare:fork] == NSOrderedSame) return YES; return NO; }
- (void)courseChanged:(id)sender {
    NSString *old = self.selectedFork ?: @"all"; self.pageStates[[@"selection:" stringByAppendingString:old]] = @{@"id":self.selectedCandidateID ?: @"", @"scroll":@(self.table.enclosingScrollView.contentView.bounds.origin.y)};
    self.selectedFork = self.coursePicker.selectedItem.representedObject; NSDictionary *state = self.pageStates[[@"selection:" stringByAppendingString:self.selectedFork ?: @"all"]]; self.selectedCandidateID = state[@"id"];
    [self refreshPresentation]; [self.table.enclosingScrollView.contentView scrollToPoint:NSMakePoint(0, [state[@"scroll"] doubleValue])];
}
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
    NSAlert *transport = [NSAlert new]; transport.messageText = @"使用哪种本机凭据读取老师上游？";
    transport.informativeText = @"私有上游需要这台 Mac 已配置的访问权限。公开上游可直接用 HTTPS。";
    [transport addButtonWithTitle:@"HTTPS · Git 钥匙串"]; [transport addButtonWithTitle:@"SSH · 本机密钥"]; [transport addButtonWithTitle:@"取消"];
    NSModalResponse response = [transport runModal]; if (response == NSAlertThirdButtonReturn) return;
    course[@"upstreamURL"] = response == NSAlertSecondButtonReturn ? [NSString stringWithFormat:@"git@github.com:%@.git", course[@"upstream"]] : [NSString stringWithFormat:@"https://github.com/%@.git", course[@"upstream"]];
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
- (void)scan:(id)sender { if (self.inbox && ![self course]) [self scanAll:nil]; else if ([self course]) [self scanCourses:@[[[self course] copy]]]; }
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
    NSMutableArray *enabled = NSMutableArray.array;
    for (NSDictionary *course in self.courses) if (!course[@"enabled"] || [course[@"enabled"] boolValue]) [enabled addObject:[course copy]];
    [self scanCourses:enabled];
}
- (void)scanCourses:(NSArray *)courses {
    if (!courses.count) return;
    courses = [[NSArray alloc] initWithArray:courses copyItems:YES];
    [self work:@"正在扫描老师仓库…" forCourse:courses.count == 1 ? courses.firstObject : nil operation:^id(NSError **error) {
        NSMutableDictionary *cache = [SSReadPlist(@"scan-cache.plist") isKindOfClass:NSDictionary.class] ? [SSReadPlist(@"scan-cache.plist") mutableCopy] : NSMutableDictionary.dictionary;
        NSMutableDictionary *result = NSMutableDictionary.dictionary;
        for (NSDictionary *course in courses) {
            if (![course[@"path"] length]) continue;
            NSError *scanError = nil;
            NSDictionary *scan = [self.git scanCourse:course cache:cache error:&scanError];
            result[course[@"fork"]] = scan ?: @{@"error":scanError.localizedDescription ?: @"扫描失败"};
        }
        SSWritePlist(@"scan-cache.plist", cache, NULL);
        return result;
    } completion:^(NSDictionary *result, NSError *error) {
        if (!result) { [self showError:error]; return; }
        NSMutableArray *messages = NSMutableArray.array;
        NSMutableDictionary *reports = [self.reports mutableCopy] ?: NSMutableDictionary.dictionary; [reports addEntriesFromDictionary:result]; self.reports = reports;
        for (NSMutableDictionary *course in self.courses) {
            NSDictionary *scan = result[course[@"fork"]]; if (!scan) continue;
            if (scan[@"error"]) { self.statuses[course[@"fork"]] = scan[@"error"]; [messages addObject:[NSString stringWithFormat:@"%@: %@", course[@"fork"], scan[@"error"]]]; continue; }
            self.candidates[course[@"fork"]] = scan[@"candidates"]; self.materials[course[@"fork"]] = scan[@"materials"] ?: @[];
            self.statuses[course[@"fork"]] = [NSString stringWithFormat:@"检查完成：%lu 项作业，%lu 组课程材料，%lu 个文件跳过", [scan[@"candidates"] count], [scan[@"materials"] count], [scan[@"skipped"] count]];
            course[@"lastScan"] = scan[@"date"];
            if (scan[@"branch"]) course[@"upstreamBranch"] = scan[@"branch"];
            [messages addObject:[NSString stringWithFormat:@"%@：%lu 项建议，%lu 个文件跳过", course[@"fork"], [scan[@"candidates"] count], [scan[@"skipped"] count]]];
        }
        [self saveCourses]; [self refreshCourses];
        if (courses.count > 1) self.statuses[@"all"] = messages.count ? [messages componentsJoinedByString:@"；"] : @"尚未关联可扫描的仓库。"; else if (!messages.count) [self status:@"请先关联本地课程文件夹，再检查作业。"];
    }];
}
- (void)sync:(id)sender {
    NSDictionary *course = [[self course] copy]; if (!course) return;
    [self work:@"正在安全合并上游，并更新自己的 fork…" forCourse:course operation:^id(NSError **error) {
        NSString *token = [self.github accessToken:error]; if (!token) return nil;
        return [self.git syncCourse:course token:token error:error];
    } completion:^(NSDictionary *result, NSError *error) {
        if (result[@"conflicts"]) {
            NSMutableDictionary *saved = [self savedCourse:course]; saved[@"pendingMergeTip"] = result[@"mergeHead"]; saved[@"pendingConflicts"] = result[@"conflicts"]; [self saveCourses];
            [self showError:error]; if (!self.operationsPaused && [self.selectedFork isEqual:course[@"fork"]] && !self.window.attachedSheet) [self conflictGuide:course];
        }
        else if (!result) { if ([error.userInfo[@"SSPendingPush"] boolValue]) { [self savedCourse:course][@"pushFailed"] = @YES; [self saveCourses]; } [self showError:error]; }
        else { [[self savedCourse:course] removeObjectForKey:@"pushFailed"]; [self saveCourses]; [self status:@"老师作业已更新到本地与个人仓库"]; [self scanCourses:@[course.copy]]; }
    }];
}
- (void)continueMerge:(id)sender { NSDictionary *course = [[self course] copy]; if (course) [self conflictGuide:course]; }
- (void)finishMerge:(NSDictionary *)course {
    [self work:@"正在完成合并并更新自己的 fork…" forCourse:course operation:^id(NSError **error) {
        NSString *token = [self.github accessToken:error]; if (!token) return @NO;
        return @([self.git continueMergeForCourse:course token:token error:error]);
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
        return @([self.git pushCourse:course token:token error:error]);
    } completion:^(NSNumber *ok, NSError *error) { if (ok.boolValue) { [[self savedCourse:course] removeObjectForKey:@"pushFailed"]; [self saveCourses]; [self status:@"本地提交已推送到自己的仓库"]; } else [self showError:error]; }];
}
- (void)conflictGuide:(NSDictionary *)course {
    [self work:@"正在读取冲突状态…" forCourse:course operation:^id(NSError **error) { return [self.git conflicts:course error:error]; } completion:^(NSArray *files, NSError *error) {
        if (self.operationsPaused) return;
        if (!files) { [self showError:error]; return; }
        if (![course[@"pendingMergeTip"] length]) { [self status:@"没有本应用记录的上游合并。请自行处理现有 Git 状态。"] ; return; }
        NSAlert *alert = NSAlert.new; alert.messageText = @"上游合并冲突引导";
        alert.informativeText = files.count ? @"在编辑器中打开文件，保留需要的内容并删除冲突标记。保存后勾选文件，点击“标记已解决”；全部解决后再完成合并。" : @"冲突文件已经标记解决。可以完成合并，然后检查并推送到自己的 fork。";
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
- (void)commit:(id)sender {
    NSDictionary *course = [[self course] copy]; if (!course) return;
    [self work:@"正在读取本地修改…" forCourse:course operation:^id(NSError **error) { return [self.git changesForCourse:course error:error]; } completion:^(NSArray *changes, NSError *error) {
        if (!changes) { [self showError:error]; return; }
        if (self.operationsPaused) return;
        if (!changes.count) { [self status:@"没有需要提交的改动。"] ; return; }
        if (self.window.attachedSheet) { [self status:@"请先关闭当前编辑弹窗，再打开“提交作业”。"]; return; }
        self.submission = [[SSSubmissionController alloc] initWithCourse:course changes:changes];
        __weak typeof(self) weakSelf = self;
        self.submission.readPreview = ^(NSString *file, void (^ready)(NSString *)) {
            dispatch_async(weakSelf.queue, ^{ NSError *previewError = nil; NSString *text = [weakSelf.git previewForCourse:course path:file error:&previewError]; dispatch_async(dispatch_get_main_queue(), ^{ ready(text ?: previewError.localizedDescription); }); });
        };
        self.submission.submit = ^(NSArray *paths, NSString *message) {
            SSCourseController *self = weakSelf; if (!self) return;
        [self work:@"正在检查、提交并推送到自己的 fork…" forCourse:course operation:^id(NSError **innerError) {
            NSDictionary *user = [self.github user:innerError]; if (!user) return @NO;
            NSString *token = [self.github accessToken:innerError]; if (!token) return @NO;
            return @([self.git commitCourse:course paths:paths message:message login:user[@"login"] userID:user[@"id"] token:token error:innerError]);
        } completion:^(NSNumber *ok, NSError *innerError) {
            if (self.exitSubmissionInFlight) { self.submissionFailedDuringExit = !ok.boolValue; self.exitSubmissionInFlight = NO; }
            if (ok.boolValue) { [[self savedCourse:course] removeObjectForKey:@"pushFailed"]; [self saveCourses]; [self status:@"所选文件已提交到自己的仓库"]; }
            else {
                if ([innerError.userInfo[@"SSPendingPush"] boolValue]) { [self savedCourse:course][@"pushFailed"] = @YES; [self saveCourses]; }
                else if (!self.window.attachedSheet) {
                    self.submission.validation.stringValue = innerError.localizedDescription ?: @"提交未完成，请检查后重试。";
                    self.submission.validation.textColor = NSColor.systemRedColor;
                    [self.window beginSheet:self.submission.window completionHandler:nil];
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
    for (NSDictionary *task in self.tasksProvider ? self.tasksProvider() : @[]) if ([task[@"sourceID"] isEqual:candidate[@"id"]])
        return [task[@"sourceBlobSHA"] isEqual:candidate[@"blobSHA"]] ? @"已导入" : @"有更新";
    return @"待审核";
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification { if (!self.refreshing) [self candidateSelected:nil]; }
- (void)candidateSelected:(id)sender {
    NSInteger row = self.table.selectedRow;
    NSDictionary *candidate = row >= 0 && row < (NSInteger)self.visible.count ? self.visible[row] : nil;
    BOOL assignment = !candidate[@"kind"] || [candidate[@"kind"] isEqual:@"assignment"];
    self.selectedCandidateID = candidate[@"id"]; self.reviewButton.enabled = candidate != nil && (assignment || [candidate[@"confirmed"] boolValue]); self.reviewButton.title = [candidate[@"confirmed"] boolValue] ? @"编辑任务…" : @"审核作业…";
    self.typeButton.enabled = candidate != nil && ![candidate[@"confirmed"] boolValue] && !self.busy && !self.operationsPaused;
    NSMutableString *preview = NSMutableString.string;
    if (candidate) {
        [preview appendFormat:@"%@ · %@ · %@\n%@\n", SSActivityKindLabel(candidate[@"kind"] ?: @"assignment"), candidate[@"repository"] ?: candidate[@"sourceRepository"], candidate[@"kindReason"] ?: @"", [candidate[@"warnings"] componentsJoinedByString:@"；"] ?: @""];
        NSArray *documents = candidate[@"documents"] ?: @[candidate];
        for (NSDictionary *document in documents) [preview appendFormat:@"%@:%@\n%@\n\n", document[@"path"], document[@"line"], document[@"snippet"] ?: document[@"notes"] ?: @""];
    }
    self.detail.string = candidate ? preview : @"选择课程内容，查看类型、老师原文与位置。";
}
- (void)review:(id)sender {
    NSInteger row = self.table.selectedRow; if (row < 0 || row >= (NSInteger)self.visible.count) return;
    NSDictionary *candidate = self.visible[row];
    if (candidate[@"kind"] && ![candidate[@"kind"] isEqual:@"assignment"] && ![candidate[@"confirmed"] boolValue]) return;
    if ([candidate[@"confirmed"] boolValue]) { if (self.editTask) self.editTask(candidate[@"id"]); }
    else if (self.reviewCandidate) self.reviewCandidate(candidate);
}
@end
