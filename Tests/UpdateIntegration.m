// This full application harness is compiled with DDL_TESTING and an isolated bundle/data/keychain identity.
// It drives Sparkle's real downloader/installer without clicking the production UI or accessing user data.
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
#import <Sparkle/Sparkle.h>

static NSString *TestRoot(void) { return [NSBundle.mainBundle objectForInfoDictionaryKey:@"DDLTestRoot"]; }
static void Record(NSString *name, NSDictionary *value) { [value writeToFile:[TestRoot() stringByAppendingPathComponent:name] atomically:YES]; }
static BOOL TestKeychain(NSString *command) {NSTask *task=NSTask.new;task.executableURL=[NSURL fileURLWithPath:[TestRoot() stringByAppendingPathComponent:@"FixtureKeychain"]];task.arguments=@[command,[NSBundle.mainBundle objectForInfoDictionaryKey:@"DDLTestKeychainService"]];if(![task launchAndReturnError:NULL])return NO;[task waitUntilExit];return task.terminationStatus==0;}
static NSArray *ErrorCodes(NSError *error) {
    NSMutableArray *codes = [NSMutableArray arrayWithObject:@(error.code)];
    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if (underlying) [codes addObjectsFromArray:ErrorCodes(underlying)];
    return codes;
}
@interface TestDriver : NSObject <SPUUserDriver>
@property (weak) AppDelegate *app;
@end
@implementation TestDriver
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply { reply([[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:NO sendSystemProfile:NO]); }
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancellation {}
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply { Record(@"found.plist", @{@"version":item.versionString}); reply(SPUUserUpdateChoiceInstall); }
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)data { Record(@"notes.plist", @{@"received":@YES}); }
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error { Record(@"notes-error.plist", @{@"error":error.localizedDescription}); }
- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))ack { Record(@"no-update.plist", @{@"code":@(error.code)}); ack(); [NSApp terminate:nil]; }
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))ack { Record(@"error.plist", @{@"code":@(error.code), @"codes":ErrorCodes(error), @"error":error.localizedDescription}); ack(); [NSApp terminate:nil]; }
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancellation { Record(@"download.plist", @{@"started":@YES}); }
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)length {}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length {}
- (void)showDownloadDidStartExtractingUpdate { Record(@"extract.plist", @{@"started":@YES}); }
- (void)showExtractionReceivedProgress:(double)progress { if (progress > 0) Record(@"extraction-progress.plist", @{@"progress":@(progress)}); }
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply {
    Record(@"ready.plist", @{@"ready":@YES});
    [self.app.updates setValue:@YES forKey:@"installing"];
    // Hold a real asynchronous controller operation across the quit request.
    self.app.courseWindow.busy = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        Record(@"waited.plist", @{@"paused":@(self.app.courseWindow.operationsPaused), @"pending":@(self.app.exitCoordinator.pending)});
        self.app.courseWindow.busy = NO;
        [self.app.exitCoordinator operationStateChanged];
    });
    reply(SPUUserUpdateChoiceInstall);
}
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)terminated retryTerminatingApplication:(void (^)(void))retry {}
- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))ack { ack(); }
- (void)dismissUpdateInstallation {}
@end

@interface TestApplication : AppDelegate
@property TestDriver *driver;
@property SPUUpdater *testUpdater;
@end
@implementation TestApplication
- (BOOL)resolveEditsForExit:(BOOL)updating {BOOL result=[super resolveEditsForExit:updating];Record(@"exit-ready.plist",@{@"ready":@(result),@"reviewDirty":@(self.courseWindow.hasUnsavedReview),@"submission":@(self.courseWindow.hasSubmissionSheet),@"editor":@(self.editor!=nil),@"sheet":@(self.window.attachedSheet!=nil)});return result;}
- (void)applicationWillTerminate:(NSNotification *)note {Record(@"terminated.plist",@{@"version":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"]});}
- (void)refreshPermission { self.authorization = UNAuthorizationStatusDenied; }
- (void)refreshReminders {}
- (void)requestPermission {}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [super applicationDidFinishLaunching:notification];
    self.window.title = @"AM's Homework Helper · 升级测试（模拟数据）";
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    if ([version isEqual:@"2"]) {
        if (!TestKeychain(@"write")) { Record(@"error.plist", @{@"error":@"test keychain write failed"}); [NSApp terminate:nil]; return; }
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"DDLTestPreference"];
        self.driver = TestDriver.new; self.driver.app = self;
        self.testUpdater = [[SPUUpdater alloc] initWithHostBundle:NSBundle.mainBundle applicationBundle:NSBundle.mainBundle userDriver:self.driver delegate:nil];
        NSError *error = nil;
        if (![self.testUpdater startUpdater:&error]) { Record(@"error.plist", @{@"error":error.localizedDescription}); [NSApp terminate:nil]; return; }
        [self.testUpdater checkForUpdates];
    } else {
        BOOL keychainPreserved=TestKeychain(@"read");
        Record(@"relaunched.plist", @{@"version":version, @"tasks":@(self.tasks.count), @"task":self.tasks.firstObject ?: @{}, @"keychainPreserved":@(keychainPreserved), @"preferencePreserved":@([NSUserDefaults.standardUserDefaults boolForKey:@"DDLTestPreference"]), @"courses":SSReadPlist(@"courses.plist") ?: @[]});
        TestKeychain(@"delete");
        [NSApp terminate:nil];
    }
}
@end
int main(int argc, char **argv) { @autoreleasepool { [NSApplication sharedApplication]; TestApplication *app = TestApplication.new; NSApp.delegate = app; [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular]; [NSApp run]; } return 0; }
