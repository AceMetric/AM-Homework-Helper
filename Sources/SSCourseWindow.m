#import "SSCourseWindow.h"
#import "SSGit.h"
#import "SSGitHub.h"
#import "SSLocalData.h"
#import "DDLCore.h"

@interface SSCourseSurface : NSView @end
@implementation SSCourseSurface
- (void)drawRect:(NSRect)rect { [NSColor.windowBackgroundColor setFill]; NSRectFill(rect); }
@end

static NSTextField *SSLabel(NSString *text, NSRect frame, CGFloat size) {
    NSTextField *label = [NSTextField labelWithString:text]; label.frame = frame;
    label.font = [NSFont systemFontOfSize:size]; label.lineBreakMode = NSLineBreakByTruncatingTail; return label;
}
static NSButton *SSButton(NSString *text, id target, SEL action, NSRect frame) {
    NSButton *button = [NSButton buttonWithTitle:text target:target action:action]; button.frame = frame; return button;
}

@interface SSCourseWindow ()
@property SSGitHub *github;
@property SSGit *git;
@property NSMutableArray<NSMutableDictionary *> *courses;
@property NSMutableDictionary<NSString *, NSArray *> *candidates;
@property NSArray<NSDictionary *> *availableForks;
@property dispatch_queue_t queue;
@property NSPopUpButton *coursePicker;
@property NSTableView *table;
@property NSTextView *detail;
@property NSTextField *accountLabel;
@property NSTextField *statusLabel;
@property NSTimer *timer;
@property BOOL busy;
@property BOOL loginActive;
@property NSArray<NSButton *> *actionButtons;
@property NSDictionary *reports;
@end

@implementation SSCourseWindow
- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1040, 700)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:window])) {
        window.title = @"DDL-Manager · GitHub 课程";
        window.minSize = NSMakeSize(1040, 700); window.releasedWhenClosed = NO;
        self.github = [SSGitHub new]; self.git = [SSGit new];
        NSArray *saved = SSReadPlist(@"courses.plist");
        self.courses = NSMutableArray.array;
        for (id item in [saved isKindOfClass:NSArray.class] ? saved : @[]) if ([item isKindOfClass:NSDictionary.class] && [item[@"fork"] isKindOfClass:NSString.class]) [self.courses addObject:[item mutableCopy]];
        __weak typeof(self) weakSelf = self;
        self.git.identityVerifier = ^NSDictionary *(NSDictionary *course, NSError **error) { return [weakSelf.github verifyCourse:course error:error]; };
        self.candidates = NSMutableDictionary.dictionary;
        self.queue = dispatch_queue_create("ss.homework.course-work", DISPATCH_QUEUE_SERIAL);
        [self buildUI]; [self refreshCourses];
    }
    return self;
}
- (void)buildUI {
    NSView *view = [[SSCourseSurface alloc] initWithFrame:NSMakeRect(0, 0, 1040, 700)];
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable; self.window.contentView = view;
    self.accountLabel = SSLabel(@"GitHub：未登录", NSMakeRect(20, 662, 420, 22), 13); [view addSubview:self.accountLabel];
    [view addSubview:SSButton(@"Client ID…", self, @selector(setClientID:), NSMakeRect(650, 660, 100, 28))];
    [view addSubview:SSButton(@"登录", self, @selector(login:), NSMakeRect(758, 660, 70, 28))];
    [view addSubview:SSButton(@"退出登录", self, @selector(signOut:), NSMakeRect(836, 660, 90, 28))];
    [view addSubview:SSButton(@"添加 fork", self, @selector(addFork:), NSMakeRect(934, 660, 86, 28))];
    self.coursePicker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 618, 360, 30) pullsDown:NO];
    self.coursePicker.target = self; self.coursePicker.action = @selector(courseChanged:); [view addSubview:self.coursePicker];
    [view addSubview:SSButton(@"关联已有克隆", self, @selector(linkFolder:), NSMakeRect(390, 618, 120, 30))];
    [view addSubview:SSButton(@"克隆", self, @selector(cloneFork:), NSMakeRect(518, 618, 70, 30))];
    [view addSubview:SSButton(@"移除课程", self, @selector(removeCourse:), NSMakeRect(596, 618, 90, 30))];
    [view addSubview:SSButton(@"启用 / 停用检查", self, @selector(toggleCourse:), NSMakeRect(694, 618, 135, 30))];
    [view addSubview:SSButton(@"安装授权…", self, @selector(installApp:), NSMakeRect(837, 618, 120, 30))];
    [view addSubview:SSButton(@"检查作业", self, @selector(scan:), NSMakeRect(20, 574, 110, 30))];
    [view addSubview:SSButton(@"拉取并更新我的 fork", self, @selector(sync:), NSMakeRect(138, 574, 168, 30))];
    [view addSubview:SSButton(@"继续冲突合并", self, @selector(continueMerge:), NSMakeRect(314, 574, 125, 30))];
    [view addSubview:SSButton(@"提交作业…", self, @selector(commit:), NSMakeRect(447, 574, 110, 30))];
    [view addSubview:SSButton(@"推送我的 fork", self, @selector(push:), NSMakeRect(565, 574, 120, 30))];
    [view addSubview:SSButton(@"打开文件夹", self, @selector(openFolder:), NSMakeRect(693, 574, 110, 30))];
    [view addSubview:SSButton(@"检查详情", self, @selector(report:), NSMakeRect(811, 574, 90, 30))];
    [view addSubview:SSButton(@"取消登录", self, @selector(cancelLogin:), NSMakeRect(909, 574, 110, 30))];
    self.statusLabel = SSLabel(@"请选择课程。", NSMakeRect(20, 536, 1000, 28), 12); [view addSubview:self.statusLabel];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 160, 1000, 370)];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable; scroll.hasVerticalScroller = YES;
    self.table = [[NSTableView alloc] initWithFrame:scroll.bounds]; self.table.delegate = self; self.table.dataSource = self;
    for (NSArray *spec in @[@[@"title", @"作业", @330], @[@"due", @"老师截止", @160], @[@"source", @"来源文件", @360], @[@"state", @"状态", @120]]) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:spec[0]];
        column.title = spec[1]; column.width = [spec[2] doubleValue]; [self.table addTableColumn:column];
    }
    self.table.headerView = [[NSTableHeaderView alloc] initWithFrame:NSMakeRect(0, 0, 1000, 24)];
    self.table.target = self; self.table.action = @selector(candidateSelected:);
    scroll.documentView = self.table; [view addSubview:scroll];
    NSScrollView *detailScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 48, 850, 98)];
    detailScroll.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin; detailScroll.hasVerticalScroller = YES;
    self.detail = [[NSTextView alloc] initWithFrame:detailScroll.bounds]; self.detail.editable = NO;
    self.detail.font = [NSFont systemFontOfSize:12]; detailScroll.documentView = self.detail; [view addSubview:detailScroll];
    NSButton *review = SSButton(@"审核并导入 / 更新", self, @selector(review:), NSMakeRect(880, 78, 140, 36));
    review.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin; [view addSubview:review];
    [view addSubview:SSLabel(@"仅扫描老师主分支；只会向自己的 fork 推送。令牌存于本机钥匙串。", NSMakeRect(20, 14, 900, 20), 11)];
    NSMutableArray *buttons = NSMutableArray.array;
    for (NSView *child in view.subviews) {
        if (NSMinY(child.frame) >= 536) child.autoresizingMask = NSViewMinYMargin;
        if ([child isKindOfClass:NSButton.class] && ![[(NSButton *)child title] isEqual:@"取消登录"]) [buttons addObject:child];
    }
    self.actionButtons = buttons;
}
- (void)show { [self showWindow:nil]; [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; }
- (void)startAutomaticChecks {
    [self scanAll:nil];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:6 * 3600 target:self selector:@selector(scanAll:) userInfo:nil repeats:YES];
}
- (void)saveCourses { NSError *error = nil; if (!SSWritePlist(@"courses.plist", self.courses, &error)) [self showError:error]; }
- (NSMutableDictionary *)savedCourse:(NSDictionary *)course { for (NSMutableDictionary *saved in self.courses) if ([saved[@"fork"] isEqual:course[@"fork"]]) return saved; return nil; }
- (NSDictionary *)course { NSInteger index = self.coursePicker.indexOfSelectedItem; return index >= 0 && index < (NSInteger)self.courses.count ? self.courses[index] : nil; }
- (NSArray *)visible { NSString *fork = [self course][@"fork"]; return fork ? (self.candidates[fork] ?: @[]) : @[]; }
- (void)refreshCourses {
    NSInteger old = self.coursePicker.indexOfSelectedItem;
    [self.coursePicker removeAllItems];
    for (NSDictionary *course in self.courses) [self.coursePicker addItemWithTitle:course[@"fork"] ?: @"课程"];
    if (self.courses.count) [self.coursePicker selectItemAtIndex:MIN(MAX(old, 0), (NSInteger)self.courses.count - 1)];
    NSDictionary *course = [self course];
    NSDate *last = course[@"lastScan"];
    self.statusLabel.stringValue = course ? [NSString stringWithFormat:@"%@ · 上次成功检查：%@", [course[@"enabled"] isEqual:@NO] ? [course[@"upstream"] stringByAppendingString:@" · 自动检查已停用"] : course[@"upstream"], last ? DDLFormatDate(last, @"M月d日 HH:mm") : @"尚未检查"] : @"请选择课程。";
    [self.table reloadData]; [self candidateSelected:nil];
}
- (void)status:(NSString *)message { self.statusLabel.stringValue = message ?: @""; }
- (void)showError:(NSError *)error { if (error) { [self status:error.localizedDescription]; self.detail.string = error.localizedDescription; } }
- (void)work:(NSString *)message operation:(id (^)(NSError **))operation completion:(void (^)(id, NSError *))completion {
    if (self.busy) { [self status:@"已有操作正在执行，请稍候。"] ; return; }
    self.busy = YES; [self status:message];
    for (NSButton *button in self.actionButtons) button.enabled = NO;
    self.coursePicker.enabled = NO;
    dispatch_async(self.queue, ^{
        NSError *error = nil; id value = operation(&error);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO; for (NSButton *button in self.actionButtons) button.enabled = YES; self.coursePicker.enabled = YES;
            completion(value, error);
        });
    });
}
- (void)setClientID:(id)sender {
    NSAlert *alert = [NSAlert new]; alert.messageText = @"GitHub App Client ID";
    alert.informativeText = @"填写开发者注册的 GitHub App 公开 Client ID 和安装链接。注册说明位于 docs/GITHUB_APP_SETUP.md。不要填写密钥或个人令牌。";
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 42, 440, 28)]; field.stringValue = self.github.clientID ?: @"";
    NSTextField *install = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 440, 28)]; install.stringValue = self.github.installationURL ?: @""; install.placeholderString = @"https://github.com/apps/应用名称/installations/new";
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
            [self status:@"GitHub 登录成功。请添加自己的课程 fork。"];
        }];
    }];
}
- (void)cancelLogin:(id)sender { if (self.loginActive) { [self.github cancelDeviceLogin]; [self status:@"正在取消登录…"]; } }
- (void)signOut:(id)sender { [self.github signOut]; self.accountLabel.stringValue = @"GitHub：未登录"; [self status:@"已退出登录；本地课程和 DDL 已保留。"] ; }
- (void)addFork:(id)sender {
    [self work:@"正在读取可访问的 fork…" operation:^id(NSError **error) { return [self.github accessibleForks:error]; } completion:^(NSArray *forks, NSError *error) {
        if (!forks) { [self showError:error]; return; }
        self.availableForks = forks;
        self.accountLabel.stringValue = [NSString stringWithFormat:@"GitHub：已登录 · 可选 %lu 个 fork", (unsigned long)forks.count];
        NSMutableArray *choices = [NSMutableArray array];
        for (NSDictionary *repo in forks) if (![self courseExists:repo[@"full_name"]]) [choices addObject:repo];
        if (!choices.count) { [self status:@"没有新的可选 fork。请在 GitHub App 安装页授权课程 fork。"] ; return; }
        NSPopUpButton *picker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 410, 28) pullsDown:NO];
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
            [self.coursePicker selectItemAtIndex:self.courses.count - 1];
            [self status:@"已添加课程。请关联本地克隆或选择克隆。"];
        }];
    }];
}
- (BOOL)courseExists:(NSString *)fork { for (NSDictionary *course in self.courses) if ([course[@"fork"] caseInsensitiveCompare:fork] == NSOrderedSame) return YES; return NO; }
- (void)courseChanged:(id)sender { [self refreshCourses]; }
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
    NSInteger index = self.coursePicker.indexOfSelectedItem; if (index < 0) return;
    NSAlert *alert = [NSAlert new]; alert.messageText = @"移除课程关联？"; alert.informativeText = @"不会删除本地仓库或已导入的 DDL。";
    [alert addButtonWithTitle:@"移除"]; [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    [self.courses removeObjectAtIndex:index]; [self saveCourses]; [self refreshCourses];
}
- (void)scan:(id)sender { [self scanCourses:@[[self course] ?: @{}]]; }
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
    [self work:@"正在扫描老师仓库…" operation:^id(NSError **error) {
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
        self.reports = result;
        for (NSMutableDictionary *course in self.courses) {
            NSDictionary *scan = result[course[@"fork"]]; if (!scan) continue;
            if (scan[@"error"]) { [messages addObject:[NSString stringWithFormat:@"%@: %@", course[@"fork"], scan[@"error"]]]; continue; }
            self.candidates[course[@"fork"]] = scan[@"candidates"];
            course[@"lastScan"] = scan[@"date"];
            if (scan[@"branch"]) course[@"upstreamBranch"] = scan[@"branch"];
            [messages addObject:[NSString stringWithFormat:@"%@：%lu 项建议，%lu 个文件跳过", course[@"fork"], [scan[@"candidates"] count], [scan[@"skipped"] count]]];
        }
        [self saveCourses]; [self refreshCourses];
        [self status:messages.count ? [messages componentsJoinedByString:@"；"] : @"尚未关联可扫描的仓库。"];
    }];
}
- (void)sync:(id)sender {
    NSDictionary *course = [self course]; if (!course) return;
    [self work:@"正在安全合并上游，并更新自己的 fork…" operation:^id(NSError **error) {
        NSString *token = [self.github accessToken:error]; if (!token) return nil;
        return [self.git syncCourse:course token:token error:error];
    } completion:^(NSDictionary *result, NSError *error) {
        if (result[@"conflicts"]) {
            NSMutableDictionary *saved = [self savedCourse:course]; saved[@"pendingMergeTip"] = result[@"mergeHead"]; saved[@"pendingConflicts"] = result[@"conflicts"]; [self saveCourses];
            [self showError:error]; [self conflictGuide:course];
        }
        else if (!result) [self showError:error];
        else { [self status:@"老师作业已合并到本地并推送到自己的 fork。"] ; [self scan:nil]; }
    }];
}
- (void)continueMerge:(id)sender { NSDictionary *course = [self course]; if (course) [self conflictGuide:course]; }
- (void)finishMerge:(NSDictionary *)course {
    [self work:@"正在完成合并并更新自己的 fork…" operation:^id(NSError **error) {
        NSString *token = [self.github accessToken:error]; if (!token) return @NO;
        return @([self.git continueMergeForCourse:course token:token error:error]);
    } completion:^(NSNumber *ok, NSError *error) { if (ok.boolValue) { NSMutableDictionary *saved = [self savedCourse:course]; [saved removeObjectForKey:@"pendingMergeTip"]; [saved removeObjectForKey:@"pendingConflicts"]; [self saveCourses]; [self status:@"冲突合并已完成，并已推送到自己的 fork。"] ; } else [self showError:error]; }];
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
    NSDictionary *course = [self course]; if (!course) return;
    [self work:@"正在检查待推送历史和 fork 身份…" operation:^id(NSError **error) {
        NSString *token = [self.github accessToken:error]; if (!token) return @NO;
        return @([self.git pushCourse:course token:token error:error]);
    } completion:^(NSNumber *ok, NSError *error) { if (ok.boolValue) [self status:@"本地提交已安全推送到自己的 fork。"] ; else [self showError:error]; }];
}
- (void)conflictGuide:(NSDictionary *)course {
    [self work:@"正在读取冲突状态…" operation:^id(NSError **error) { return [self.git conflicts:course error:error]; } completion:^(NSArray *files, NSError *error) {
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
            [self work:@"正在撤销此次合并…" operation:^id(NSError **innerError) { return @([self.git abortMerge:course error:innerError]); } completion:^(NSNumber *ok, NSError *innerError) {
                if (!ok.boolValue) { [self showError:innerError]; return; }
                NSMutableDictionary *saved = [self savedCourse:course]; [saved removeObjectForKey:@"pendingMergeTip"]; [saved removeObjectForKey:@"pendingConflicts"]; [self saveCourses]; [self status:@"已撤销此次上游合并。"];
            }]; return;
        }
        if (answer != NSAlertFirstButtonReturn) return;
        if (!files.count) { [self finishMerge:course]; return; }
        NSMutableArray *selected = NSMutableArray.array;
        for (NSUInteger i = 0; i < checks.count; i++) if (checks[i].state == NSControlStateValueOn) [selected addObject:files[i]];
        if (!selected.count) { [self status:@"请选择已经编辑并保存的冲突文件。"] ; return; }
        [self work:@"正在检查并标记冲突文件…" operation:^id(NSError **innerError) { return @([self.git stageResolvedFiles:course paths:selected error:innerError]); } completion:^(NSNumber *ok, NSError *innerError) { if (!ok.boolValue) [self showError:innerError]; else [self conflictGuide:course]; }];
    }];
}
- (void)commit:(id)sender {
    NSDictionary *course = [self course]; if (!course) return;
    [self work:@"正在读取本地修改…" operation:^id(NSError **error) { return [self.git changesForCourse:course error:error]; } completion:^(NSArray *changes, NSError *error) {
        if (!changes) { [self showError:error]; return; }
        if (!changes.count) { [self status:@"没有需要提交的改动。"] ; return; }
        NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 590, 350)];
        NSView *list = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 565, MAX(30, changes.count * 27))];
        NSMutableArray<NSButton *> *checks = NSMutableArray.array;
        for (NSDictionary *change in changes) {
            NSString *name = [NSString stringWithFormat:@"%@  %@%@", change[@"status"], change[@"path"], [change[@"sensitive"] boolValue] ? @" · 敏感文件" : @""];
            NSButton *check = [NSButton checkboxWithTitle:name target:nil action:NULL]; check.state = NSControlStateValueOff; check.enabled = ![change[@"sensitive"] boolValue];
            check.frame = NSMakeRect(0, NSHeight(list.frame) - (checks.count + 1) * 27, 560, 25);
            [checks addObject:check]; [list addSubview:check];
        }
        NSTextField *message = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 570, 28)]; message.placeholderString = @"提交说明，例如：完成第 3 周实验";
        [accessory addSubview:message];
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 45, 590, 300)]; scroll.hasVerticalScroller = YES; scroll.documentView = list; [accessory addSubview:scroll];
        NSAlert *alert = [NSAlert new]; alert.messageText = @"选择本次作业文件";
        alert.informativeText = @"逐项勾选需要提交的文件。推送前检查全部待推送历史；超过 5 MB 的文件与压缩包会被阻止。"; alert.accessoryView = accessory;
        [alert addButtonWithTitle:@"检查并提交到我的 fork"]; [alert addButtonWithTitle:@"取消"];
        if ([alert runModal] != NSAlertFirstButtonReturn) return;
        NSMutableArray *paths = NSMutableArray.array;
        for (NSUInteger i = 0; i < checks.count; i++) if (checks[i].state == NSControlStateValueOn) [paths addObject:changes[i][@"path"]];
        [self work:@"正在检查、提交并推送到自己的 fork…" operation:^id(NSError **innerError) {
            NSDictionary *user = [self.github user:innerError]; if (!user) return @NO;
            NSString *token = [self.github accessToken:innerError]; if (!token) return @NO;
            return @([self.git commitCourse:course paths:paths message:message.stringValue login:user[@"login"] userID:user[@"id"] token:token error:innerError]);
        } completion:^(NSNumber *ok, NSError *innerError) { if (ok.boolValue) [self status:@"所选文件已提交并推送到自己的 fork。"] ; else [self showError:innerError]; }];
    }];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.visible.count; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSDictionary *candidate = self.visible[row]; NSString *key = column.identifier;
    NSString *value = @"";
    if ([key isEqual:@"title"]) value = candidate[@"title"];
    else if ([key isEqual:@"due"]) value = candidate[@"deadlineText"] ? [candidate[@"deadlineText"] stringByAppendingString:@" · 待确认"] : (!candidate[@"due"] ? @"截止待定" : ([candidate[@"needsDate"] boolValue] ? @"日期待确认" : ([candidate[@"needsTime"] boolValue] ? [DDLFormatDate(candidate[@"due"], @"yyyy-MM-dd") stringByAppendingString:@" · 待补时间"] : DDLFormatDate(candidate[@"due"], @"yyyy-MM-dd HH:mm"))));
    else if ([key isEqual:@"source"]) value = [NSString stringWithFormat:@"%@:%@", candidate[@"path"], candidate[@"line"]];
    else if ([key isEqual:@"state"]) value = [self stateForCandidate:candidate];
    NSTextField *label = [NSTextField labelWithString:value ?: @""]; label.lineBreakMode = NSLineBreakByTruncatingMiddle; label.toolTip = value; return label;
}
- (NSString *)stateForCandidate:(NSDictionary *)candidate {
    for (NSDictionary *task in self.tasksProvider ? self.tasksProvider() : @[]) if ([task[@"sourceID"] isEqual:candidate[@"id"]])
        return [task[@"sourceBlobSHA"] isEqual:candidate[@"blobSHA"]] ? @"已导入" : @"有更新";
    return @"待审核";
}
- (void)candidateSelected:(id)sender {
    NSInteger row = self.table.selectedRow;
    NSDictionary *candidate = row >= 0 && row < (NSInteger)self.visible.count ? self.visible[row] : nil;
    self.detail.string = candidate ? [NSString stringWithFormat:@"%@ · %@:%@\n%@", candidate[@"repository"], candidate[@"path"], candidate[@"line"], candidate[@"snippet"]] : @"选择一项作业，查看老师原文与位置。";
}
- (void)review:(id)sender {
    NSInteger row = self.table.selectedRow; if (row < 0 || row >= (NSInteger)self.visible.count) return;
    NSMutableDictionary *candidate = [self.visible[row] mutableCopy];
    candidate[@"observedDue"] = candidate[@"due"];
    if ([candidate[@"needsTime"] boolValue] || [candidate[@"needsDate"] boolValue]) {
        NSAlert *alert = [NSAlert new]; alert.messageText = @"请确认老师的具体截止时间";
        alert.informativeText = candidate[@"deadlineText"] ? [NSString stringWithFormat:@"老师原文：%@\n相对日期取决于老师布置作业的时间，不能按今天推算。请确认完整日期和时间。", candidate[@"deadlineText"]] : @"文档缺少明确的年份、日期或时间。请依据老师原文或课程说明输入完整时间，不能默认当作 23:59。";
        NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 28)]; field.stringValue = candidate[@"due"] ? DDLFormatDate(candidate[@"due"], @"yyyy-MM-dd") : @""; field.placeholderString = @"2026-10-08 20:00"; alert.accessoryView = field;
        [alert addButtonWithTitle:@"确认"]; [alert addButtonWithTitle:@"取消"];
        if ([alert runModal] != NSAlertFirstButtonReturn) return;
        if ([field.stringValue rangeOfString:@"^20\\d{2}[-/]\\d{1,2}[-/]\\d{1,2}\\s+(?:[01]?\\d|2[0-3]):[0-5]\\d$" options:NSRegularExpressionSearch].location == NSNotFound) { [self status:@"请填写明确的时:分，例如 2026-10-01 20:00。"] ; return; }
        NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]; calendar.timeZone = [NSTimeZone timeZoneWithName:candidate[@"timeZone"] ?: NSTimeZone.localTimeZone.name] ?: NSTimeZone.localTimeZone;
        NSDate *due = DDLParseDate(field.stringValue, NSDate.date, calendar);
        if (!due) { [self status:@"截止时间格式无效。"] ; return; }
        candidate[@"due"] = due; candidate[@"needsTime"] = @NO; candidate[@"needsDate"] = @NO;
    }
    if (self.reviewCandidate) self.reviewCandidate(candidate);
}
@end
