#import "SSUpdateController.h"
#import <Sparkle/Sparkle.h>
@interface SSUpdateController () <SPUUpdaterDelegate, NSMenuItemValidation, NSURLSessionTaskDelegate, NSWindowDelegate>
@property SPUStandardUpdaterController *controller;
@property (readwrite) BOOL installing;
@property (readwrite) BOOL available;
@property BOOL checking;
@property NSUInteger checkGeneration;
@property NSURLSession *feedSession;
@property NSURLSessionDataTask *feedTask;
@property NSPanel *checkWindow;
@end
@implementation SSUpdateController
- (instancetype)initWithPreview:(BOOL)preview {
    if ((self = [super init])) {
        self.available = !preview && [NSBundle.mainBundle.bundlePath.pathExtension isEqual:@"app"] && [NSBundle.mainBundle objectForInfoDictionaryKey:@"SUPublicEDKey"] != nil;
#ifdef DDL_TESTING
        // The integration harness owns its updater; two engines for one bundle interfere.
        if ([NSBundle.mainBundle objectForInfoDictionaryKey:@"DDLTestRoot"]) self.available = NO;
#endif
        if (self.available) self.controller = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:YES updaterDelegate:self userDriverDelegate:nil];
    } return self;
}
- (BOOL)automaticallyChecks { return self.controller.updater.automaticallyChecksForUpdates; }
- (BOOL)validateMenuItem:(NSMenuItem *)item { return self.available && !self.checking && self.controller.updater.canCheckForUpdates; }
+ (BOOL)canUpdateApplicationAtPath:(NSString *)path {
    return ![path containsString:@"/AppTranslocation/"] && [NSFileManager.defaultManager isWritableFileAtPath:path.stringByDeletingLastPathComponent];
}
- (void)checkForUpdates:(id)sender {
    if (!self.available || self.checking) return;
    if (self.controller && !self.controller.updater.canCheckForUpdates) { [self.controller checkForUpdates:sender]; return; }
    NSString *path = NSBundle.mainBundle.bundlePath;
    if (![SSUpdateController canUpdateApplicationAtPath:path]) {
        NSAlert *alert = NSAlert.new; alert.messageText = @"请先将应用移到“应用程序”";
        alert.informativeText = @"当前位置可能只读或由 macOS 临时隔离。退出应用，将 AM's Homework Helper 拖入“应用程序”后再检查更新。"; [alert addButtonWithTitle:@"知道了"]; [alert runModal]; return;
    }
    NSURL *url = [self updateFeedURL];
    if (![SSUpdateController secureFeedURL:url]) { [self showCheckProblem:@{@"title":@"更新配置需要修复", @"message":@"更新地址配置不正确，请安装维护者提供的新版应用。", @"retry":@NO}]; return; }
    self.checking = YES; NSUInteger generation = ++self.checkGeneration;
    [self showCheckProgress];
    if (self.statusChanged) self.statusChanged(@"正在检查软件更新…");
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:12];
    request.HTTPMethod = @"HEAD";
    self.feedSession = [NSURLSession sessionWithConfiguration:[self feedSessionConfiguration] delegate:self delegateQueue:nil];
    __weak typeof(self) weakSelf = self;
    self.feedTask = [self.feedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SSUpdateController *owner = weakSelf; if (!owner || !owner.checking || owner.checkGeneration != generation) return;
            [owner finishFeedCheck];
            NSDictionary *problem = [SSUpdateController checkProblemForResponse:response error:error];
            if (problem) {
                if (owner.statusChanged) owner.statusChanged(problem[@"message"]);
                [owner showCheckProblem:problem];
            } else {
                if (owner.statusChanged) owner.statusChanged(@"正在获取已签名的更新信息…");
                // Reachability is not authentication. Sparkle still downloads and verifies the signed feed and ZIP.
                [owner beginSparkleCheck];
            }
        });
    }];
    [self.feedTask resume];
}
- (NSURL *)updateFeedURL { return self.controller.updater.feedURL; }
+ (BOOL)secureFeedURL:(NSURL *)url { return [url.scheme.lowercaseString isEqual:@"https"] && url.host.length && !url.user.length && !url.password.length; }
- (NSURLSessionConfiguration *)feedSessionConfiguration {
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.URLCache = nil; config.HTTPCookieStorage = nil; config.HTTPShouldSetCookies = NO; config.URLCredentialStorage = nil;
    config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 15; return config;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    completionHandler([SSUpdateController secureFeedURL:request.URL] ? request : nil);
}
+ (NSDictionary *)checkProblemForResponse:(NSURLResponse *)response error:(NSError *)error {
    NSString *title = @"无法连接更新服务", *message = @"暂时无法获取更新信息，请稍后重试。本机任务和课程可继续使用。";
    if (error) {
        if ([error.domain isEqual:NSURLErrorDomain]) {
            if (error.code == NSURLErrorCancelled) { title = @"更新检查已取消"; message = @"检查没有完成，可稍后重试。"; }
            else if (error.code == NSURLErrorNotConnectedToInternet || error.code == NSURLErrorNetworkConnectionLost) { title = @"网络连接不可用"; message = @"请检查网络连接，然后重试更新。"; }
            else if (error.code == NSURLErrorTimedOut) { title = @"连接更新服务超时"; message = @"更新服务未及时响应，请稍后重试。"; }
            else if (error.code == NSURLErrorSecureConnectionFailed || (error.code <= NSURLErrorServerCertificateHasBadDate && error.code >= NSURLErrorClientCertificateRejected)) { title = @"无法安全连接更新服务"; message = @"无法验证更新服务的安全连接，已停止检查。请检查电脑日期和网络，勿绕过安全验证。"; }
        }
    } else if (![response isKindOfClass:NSHTTPURLResponse.class] || ![self secureFeedURL:response.URL]) {
        title = @"更新服务响应无效"; message = @"更新服务没有返回安全、有效的响应，已停止检查。请稍后重试。";
    } else {
        NSInteger code = ((NSHTTPURLResponse *)response).statusCode;
        // Servers without HEAD support are handed to Sparkle's normal, verified GET path.
        if ((code >= 200 && code < 300) || code == 405 || code == 501) return nil;
        if (code == 404 || code == 410) { title = @"更新服务尚未上线"; message = @"更新清单暂不可用，请等待维护者发布后再检查。当前版本可继续使用，这不表示已经是最新版。"; }
        else if (code == 429 || code >= 500) { title = @"更新服务暂时不可用"; message = @"更新服务繁忙或暂时故障，请稍后重试。"; }
        else if (code == 401 || code == 403) { title = @"更新服务访问受限"; message = @"软件更新应允许公开下载，无需 GitHub 登录。请稍后重试或联系维护者。"; }
    }
    return @{@"title":title, @"message":message, @"retry":@YES};
}
- (void)beginSparkleCheck { [self.controller checkForUpdates:nil]; }
- (void)showCheckProgress {
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 380, 140) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    panel.title = @"软件更新"; panel.releasedWhenClosed = NO; panel.delegate = self;
    NSProgressIndicator *spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(24, 90, 20, 20)]; spinner.style = NSProgressIndicatorStyleSpinning; [spinner startAnimation:nil]; [panel.contentView addSubview:spinner];
    NSTextField *label = [NSTextField labelWithString:@"正在连接更新服务…"]; label.frame = NSMakeRect(52, 88, 300, 24); [panel.contentView addSubview:label];
    NSTextField *detail = [NSTextField labelWithString:@"可继续使用任务和课程，也可取消检查。"]; detail.frame = NSMakeRect(24, 54, 332, 24); detail.textColor = NSColor.secondaryLabelColor; [panel.contentView addSubview:detail];
    NSButton *cancel = [NSButton buttonWithTitle:@"取消检查" target:self action:@selector(cancelFeedCheck:)]; cancel.bezelStyle = NSBezelStyleRounded; cancel.frame = NSMakeRect(254, 14, 102, 32); cancel.keyEquivalent = @"\033"; [panel.contentView addSubview:cancel];
    self.checkWindow = panel; [panel center]; [panel makeKeyAndOrderFront:nil];
}
- (void)finishFeedCheck {
    self.checking = NO; self.feedTask = nil; [self.feedSession finishTasksAndInvalidate]; self.feedSession = nil;
    self.checkWindow.delegate = nil; [self.checkWindow close]; self.checkWindow = nil;
}
- (void)cancelFeedCheck:(id)sender {
    if (!self.checking) return;
    ++self.checkGeneration; [self.feedTask cancel]; [self.feedSession invalidateAndCancel]; [self finishFeedCheck];
    if (self.statusChanged) self.statusChanged(@"已取消更新检查。");
}
- (BOOL)windowShouldClose:(NSWindow *)sender { [self cancelFeedCheck:nil]; return YES; }
- (void)showCheckProblem:(NSDictionary *)problem {
    NSAlert *alert = NSAlert.new; alert.messageText = problem[@"title"]; alert.informativeText = problem[@"message"];
    [alert addButtonWithTitle:@"知道了"]; if ([problem[@"retry"] boolValue]) [alert addButtonWithTitle:@"重试"];
    if ([alert runModal] == NSAlertSecondButtonReturn) [self checkForUpdates:nil];
}
- (void)showSettings:(id)sender {
    NSAlert *alert = NSAlert.new; alert.messageText = @"软件更新";
    alert.informativeText = self.available ? @"每天检查新版本。发现更新后展示说明，由你决定是否下载与安装；安装需要重新打开应用。" : @"界面预览不联网检查更新。";
    NSButton *check = [NSButton checkboxWithTitle:@"自动检查更新" target:nil action:NULL]; check.frame = NSMakeRect(0, 0, 320, 28); check.state = self.automaticallyChecks ? NSControlStateValueOn : NSControlStateValueOff; check.enabled = self.available;
    alert.accessoryView = check; [alert addButtonWithTitle:@"完成"]; [alert addButtonWithTitle:@"检查更新…"].enabled = self.available && !self.checking && self.controller.updater.canCheckForUpdates;
    NSModalResponse answer = [alert runModal];
    if (self.available) { self.controller.updater.automaticallyChecksForUpdates = check.state == NSControlStateValueOn; self.controller.updater.automaticallyDownloadsUpdates = NO; }
    if (answer == NSAlertSecondButtonReturn) [self checkForUpdates:sender];
}
- (void)updater:(SPUUpdater *)updater userDidMakeChoice:(SPUUserUpdateChoice)choice forUpdate:(SUAppcastItem *)item state:(SPUUserUpdateState *)state {
    self.installing = choice == SPUUserUpdateChoiceInstall && state.stage != SPUUserUpdateStageNotDownloaded;
}
- (void)updater:(SPUUpdater *)updater willInstallUpdate:(SUAppcastItem *)item { self.installing = YES; }
- (BOOL)updater:(SPUUpdater *)updater shouldPostponeRelaunchForUpdate:(SUAppcastItem *)item untilInvokingBlock:(void (^)(void))installHandler { self.installing = YES; return NO; }
- (void)terminationCancelled { self.installing = NO; }
- (void)updater:(SPUUpdater *)updater didAbortWithError:(NSError *)error {
    self.installing = NO;
    if (!self.statusChanged || self.checking) return;
    if ([error.domain isEqual:SUSparkleErrorDomain] && error.code == SUNoUpdateError) self.statusChanged(@"本次检查没有发现适用的新版本。");
    else if ([error.domain isEqual:SUSparkleErrorDomain] && error.code == SUInstallationCanceledError) self.statusChanged(@"已取消安装更新，当前版本可继续使用。");
    else self.statusChanged(@"更新未完成，可从“检查更新…”重试。当前任务和课程数据已保留。");
}
- (void)updater:(SPUUpdater *)updater didFinishUpdateCycleForUpdateCheck:(SPUUpdateCheck)updateCheck error:(NSError *)error {
    if (!error && !self.installing && !self.checking && self.statusChanged) self.statusChanged(@"更新检查已完成。");
}
@end
