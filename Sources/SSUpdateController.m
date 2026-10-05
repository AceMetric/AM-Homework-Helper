#import "SSUpdateController.h"
#import <Sparkle/Sparkle.h>
@interface SSUpdateController () <SPUUpdaterDelegate, NSMenuItemValidation>
@property SPUStandardUpdaterController *controller;
@property (readwrite) BOOL installing;
@property (readwrite) BOOL available;
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
- (BOOL)validateMenuItem:(NSMenuItem *)item { return self.available && self.controller.updater.canCheckForUpdates; }
+ (BOOL)canUpdateApplicationAtPath:(NSString *)path {
    return ![path containsString:@"/AppTranslocation/"] && [NSFileManager.defaultManager isWritableFileAtPath:path.stringByDeletingLastPathComponent];
}
- (void)checkForUpdates:(id)sender {
    if (!self.available) return;
    NSString *path = NSBundle.mainBundle.bundlePath;
    if (![SSUpdateController canUpdateApplicationAtPath:path]) {
        NSAlert *alert = NSAlert.new; alert.messageText = @"请先将应用移到“应用程序”";
        alert.informativeText = @"当前位置可能只读或由 macOS 临时隔离。退出应用，将 DDL-Manager 拖入“应用程序”后再检查更新。"; [alert addButtonWithTitle:@"知道了"]; [alert runModal]; return;
    }
    [self.controller checkForUpdates:sender];
}
- (void)showSettings:(id)sender {
    NSAlert *alert = NSAlert.new; alert.messageText = @"软件更新";
    alert.informativeText = self.available ? @"每天检查新版本。发现更新后展示说明，由你决定是否下载与安装；安装需要重新打开应用。" : @"界面预览不联网检查更新。";
    NSButton *check = [NSButton checkboxWithTitle:@"自动检查更新" target:nil action:NULL]; check.frame = NSMakeRect(0, 0, 320, 28); check.state = self.automaticallyChecks ? NSControlStateValueOn : NSControlStateValueOff; check.enabled = self.available;
    alert.accessoryView = check; [alert addButtonWithTitle:@"完成"]; [alert addButtonWithTitle:@"检查更新…"];
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
    if (self.statusChanged && error.code != SUNoUpdateError) self.statusChanged(@"更新未完成，可从“检查更新…”重试。当前任务和课程数据已保留。");
}
@end
