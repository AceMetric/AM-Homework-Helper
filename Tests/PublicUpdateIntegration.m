// Real public-source install into a disposable host. The UI driver has a separate identity;
// the downloaded production app is opened only in its non-saving preview mode.
#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>

static NSString *Root(void) { return [NSBundle.mainBundle objectForInfoDictionaryKey:@"DDLPublicTestRoot"]; }
static NSBundle *Host(void) { return [NSBundle bundleWithPath:[Root() stringByAppendingPathComponent:@"host/AM's Homework Helper.app"]]; }
static void Record(NSString *name, NSDictionary *value) { [value writeToFile:[Root() stringByAppendingPathComponent:name] atomically:YES]; }
static NSString *InstalledVersion(void) { return [NSDictionary dictionaryWithContentsOfFile:[Host().bundlePath stringByAppendingPathComponent:@"Contents/Info.plist"]][@"CFBundleVersion"]; }

@interface PublicDriver : NSObject <SPUUserDriver, NSApplicationDelegate>
@property SPUUpdater *updater;
@end
@implementation PublicDriver
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    if ([[NSBundle.mainBundle objectForInfoDictionaryKey:@"DDLPublicTestMode"] isEqual:@"upgrade"] && [InstalledVersion() isEqual:@"4"]) {
        NSWorkspaceOpenConfiguration *config = NSWorkspaceOpenConfiguration.configuration;
        config.arguments = @[@"--preview"]; config.createsNewApplicationInstance = YES;
        [NSWorkspace.sharedWorkspace openApplicationAtURL:Host().bundleURL configuration:config completionHandler:^(NSRunningApplication *app, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!app) { Record(@"error.plist", @{@"stage":@"reopen", @"code":@(error.code)}); [NSApp terminate:nil]; return; }
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    Record(@"result.plist", @{@"version":InstalledVersion(), @"reopened":@(!app.terminated), @"previewOnly":@YES});
                    [app terminate]; [NSApp terminate:nil];
                });
            });
        }]; return;
    }
    self.updater = [[SPUUpdater alloc] initWithHostBundle:Host() applicationBundle:NSBundle.mainBundle userDriver:self delegate:nil];
    NSError *error = nil;
    if (![self.updater startUpdater:&error]) { Record(@"error.plist", @{@"stage":@"start", @"code":@(error.code)}); [NSApp terminate:nil]; return; }
    [self.updater checkForUpdates];
}
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply { reply([[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:NO sendSystemProfile:NO]); }
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancellation {}
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply { Record(@"found.plist", @{@"version":item.versionString}); reply(SPUUserUpdateChoiceInstall); }
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)data { Record(@"notes.plist", @{@"received":@YES}); }
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error { Record(@"error.plist", @{@"stage":@"notes", @"code":@(error.code)}); }
- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))ack { Record(@"result.plist", @{@"version":InstalledVersion(), @"noUpdate":@YES}); ack(); [NSApp terminate:nil]; }
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))ack { Record(@"error.plist", @{@"stage":@"update", @"code":@(error.code), @"description":error.localizedDescription}); ack(); [NSApp terminate:nil]; }
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancellation { Record(@"download.plist", @{@"started":@YES}); }
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)length {}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length {}
- (void)showDownloadDidStartExtractingUpdate {}
- (void)showExtractionReceivedProgress:(double)progress {}
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply { Record(@"ready.plist", @{@"ready":@YES}); reply(SPUUserUpdateChoiceInstall); }
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)terminated retryTerminatingApplication:(void (^)(void))retry {}
- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))ack { ack(); }
- (void)dismissUpdateInstallation {}
@end

int main(int argc, const char **argv) { @autoreleasepool {
    if (argc == 4) {
        NSString *command = @(argv[1]), *domain = @(argv[2]), *path = @(argv[3]);
        NSArray *keys = @[@"SUEnableAutomaticChecks", @"SUHasLaunchedBefore", @"SULastCheckTime", @"SUAutomaticallyUpdate", @"SUSkippedVersion", @"SUSendProfileInfo", @"SULastProfileSubmitDate", @"SUUpdateCheckInterval", @"SUFeedURL", @"SUSkippedSubreleaseVersion", @"SUUpdateGroupIdentifier"];
        if ([command isEqual:@"--save-preferences"]) {
            NSDictionary *values = CFBridgingRelease(CFPreferencesCopyMultiple((__bridge CFArrayRef)keys, (__bridge CFStringRef)domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
            return [values ?: @{} writeToFile:path atomically:YES] ? 0 : 1;
        }
        if ([command isEqual:@"--restore-preferences"]) {
            NSDictionary *values = [NSDictionary dictionaryWithContentsOfFile:path]; if (!values) return 1;
            for (NSString *key in keys) CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)values[key], (__bridge CFStringRef)domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            return CFPreferencesSynchronize((__bridge CFStringRef)domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) ? 0 : 1;
        }
        return 2;
    }
    [NSApplication sharedApplication]; PublicDriver *driver = PublicDriver.new; NSApp.delegate = driver; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory]; [NSApp run];
} }
