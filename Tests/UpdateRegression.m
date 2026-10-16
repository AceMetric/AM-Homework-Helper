#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
#import <Sparkle/Sparkle.h>
#include <stdio.h>
static NSUInteger assertions;
static void Check(BOOL value, NSString *description) { assertions++; if (!value) { fprintf(stderr, "FAIL: %s\n", description.UTF8String); exit(1); } }
static void Drain(void) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; }
// Exercise real NSURLSession callbacks without reaching a public feed or reading account credentials.
@interface SSUpdateController (FeedTests)
+ (NSDictionary *)checkProblemForResponse:(NSURLResponse *)response error:(NSError *)error;
- (NSURLSessionConfiguration *)feedSessionConfiguration;
- (void)cancelFeedCheck:(id)sender;
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler;
- (void)updater:(SPUUpdater *)updater didAbortWithError:(NSError *)error;
- (void)updater:(SPUUpdater *)updater didFinishUpdateCycleForUpdateCheck:(SPUUpdateCheck)updateCheck error:(NSError *)error;
@end
static NSInteger feedStatus = 200, feedError = 0;
static NSTimeInterval feedDelay = 0;
static NSURLRequest *lastFeedRequest;
@interface FeedProtocol : NSURLProtocol
@property BOOL stopped;
@end
@implementation FeedProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [request.URL.host isEqual:@"updates.example.invalid"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    lastFeedRequest = self.request; NSInteger status = feedStatus, error = feedError;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(feedDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.stopped) return;
        if (error) { [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:error userInfo:nil]]; return; }
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:@{}];
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed]; [self.client URLProtocolDidFinishLoading:self];
    });
}
- (void)stopLoading { self.stopped = YES; }
@end
@interface FeedController : SSUpdateController
@property NSUInteger forwarded;
@property NSUInteger shownProblems;
@property NSDictionary *problem;
@property NSURL *testURL;
@end
@implementation FeedController
- (NSURL *)updateFeedURL { return self.testURL; }
- (NSURLSessionConfiguration *)feedSessionConfiguration {
    NSURLSessionConfiguration *config = [super feedSessionConfiguration]; config.protocolClasses = @[FeedProtocol.class]; return config;
}
- (void)beginSparkleCheck { self.forwarded++; }
- (void)showCheckProblem:(NSDictionary *)problem { self.problem = problem; self.shownProblems++; }
@end
static void WaitForFeed(FeedController *controller) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:3];
    while ([[controller valueForKey:@"checking"] boolValue] && [limit timeIntervalSinceNow] > 0) Drain();
    Check(![[controller valueForKey:@"checking"] boolValue], @"feed check completes and unlocks controls");
}
static void FeedChecks(void) {
    FeedController *controller = [[FeedController alloc] initWithPreview:YES]; [controller setValue:@YES forKey:@"available"];
    controller.testURL = [NSURL URLWithString:@"https://updates.example.invalid/appcast.xml"];
    NSURLSessionConfiguration *config = [controller feedSessionConfiguration];
    Check(!config.URLCache && !config.HTTPCookieStorage && !config.HTTPShouldSetCookies && !config.URLCredentialStorage, @"update preflight has no cookies, credential store or persistent cache");
    feedStatus = 404; [controller checkForUpdates:nil]; [controller checkForUpdates:nil]; WaitForFeed(controller);
    Check(controller.forwarded == 0 && controller.shownProblems == 1 && [controller.problem[@"title"] isEqual:@"更新服务尚未上线"], @"404 reports unpublished source once without Sparkle's generic error");
    Check([lastFeedRequest.HTTPMethod isEqual:@"HEAD"] && ![lastFeedRequest valueForHTTPHeaderField:@"Authorization"], @"reachability check requests only public headers without credentials");
    Check([controller.problem[@"message"] containsString:@"不表示已经是最新版"], @"missing feed is never presented as up to date");
    Check(![controller valueForKey:@"checkWindow"], @"progress panel closes on completion");
    feedStatus = 503; [controller checkForUpdates:nil]; WaitForFeed(controller);
    Check(controller.forwarded == 0 && [controller.problem[@"title"] isEqual:@"更新服务暂时不可用"], @"server error is separate from unpublished source");
    NSDictionary *networkCases = @{@(NSURLErrorNotConnectedToInternet):@"网络连接不可用", @(NSURLErrorTimedOut):@"连接更新服务超时", @(NSURLErrorServerCertificateUntrusted):@"无法安全连接更新服务", @(NSURLErrorCancelled):@"更新检查已取消"};
    for (NSNumber *code in networkCases) {
        feedError = code.integerValue; [controller checkForUpdates:nil]; WaitForFeed(controller);
        Check(controller.forwarded == 0 && [controller.problem[@"title"] isEqual:networkCases[code]], @"network, timeout, TLS and transport cancellation have specific feedback and never bypass checks");
    }
    feedError = 0; feedStatus = 200; [controller checkForUpdates:nil]; WaitForFeed(controller);
    Check(controller.forwarded == 1, @"retry succeeds after source becomes live and forwards to Sparkle signature validation");
    feedStatus = 405; [controller checkForUpdates:nil]; WaitForFeed(controller);
    Check(controller.forwarded == 2, @"HEAD unsupported leaves verified GET handling to Sparkle");
    NSUInteger problems = controller.shownProblems; feedDelay = 0.3; [controller checkForUpdates:nil];
    Check([controller valueForKey:@"checkWindow"] != nil, @"manual checks display cancellable native progress even without the main window");
    [[controller valueForKey:@"checkWindow"] performClose:nil]; feedDelay = 0; feedStatus = 200; [controller checkForUpdates:nil]; WaitForFeed(controller);
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
    Check(controller.forwarded == 3 && controller.shownProblems == problems, @"cancelled request cannot alert or interfere with a newer retry");
    controller.testURL = [NSURL URLWithString:@"http://updates.example.invalid/appcast.xml"]; [controller checkForUpdates:nil];
    Check(controller.forwarded == 3 && [controller.problem[@"title"] isEqual:@"更新配置需要修复"], @"insecure configured feed is blocked before networking");
    __block BOOL rejected = NO;
    [controller URLSession:nil task:nil willPerformHTTPRedirection:nil newRequest:[NSURLRequest requestWithURL:controller.testURL] completionHandler:^(NSURLRequest *request) { rejected = request == nil; }];
    Check(rejected, @"redirect cannot downgrade to HTTP");
    __block NSString *notice;
    controller.statusChanged = ^(NSString *message) { notice = message; };
    [controller updater:nil didAbortWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUNoUpdateError userInfo:nil]];
    Check([notice isEqual:@"本次检查没有发现适用的新版本。"], @"no applicable update clears the checking phase without claiming latest version");
    [controller updater:nil didAbortWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationCanceledError userInfo:nil]];
    Check([notice containsString:@"已取消安装"], @"cancelled installation is distinct from a failed check");
    [controller updater:nil didFinishUpdateCycleForUpdateCheck:SPUUpdateCheckUpdates error:nil];
    Check([notice isEqual:@"更新检查已完成。"], @"dismissed or skipped update clears the checking phase");
}
@interface FailedSubmissionGit : SSGit @end
@implementation FailedSubmissionGit
- (NSArray *)changesForCourse:(NSDictionary *)course error:(NSError **)error { return @[@{@"path":@"answers.md", @"status":@"M"}]; }
- (BOOL)commitCourse:(NSDictionary *)course paths:(NSArray *)paths message:(NSString *)message login:(NSString *)login userID:(NSNumber *)userID token:(NSString *)token error:(NSError **)error {
    if (error) *error = [NSError errorWithDomain:@"synthetic" code:1 userInfo:@{NSLocalizedDescriptionKey:@"模拟：敏感内容检查阻止提交"}]; return NO;
}
@end
@interface SubmissionAPI : SSGitHub @end
@implementation SubmissionAPI
- (NSDictionary *)user:(NSError **)error { return @{@"login":@"student", @"id":@1}; }
- (NSString *)accessToken:(NSError **)error { return @"synthetic"; }
@end
static void ApplicationExitChecks(AppDelegate *app){
    SSUpdateController *original=app.updates;FeedController *update=[[FeedController alloc] initWithPreview:YES];[update setValue:@YES forKey:@"available"];update.testURL=[NSURL URLWithString:@"https://updates.example.invalid/appcast.xml"];feedStatus=200;feedError=0;feedDelay=0;[update checkForUpdates:nil];WaitForFeed(update);app.updates=update;
    [update setValue:@YES forKey:@"installing"];
    Check(!app.exitCoordinator.operationBusy(),@"the actual application exit gate excludes the live updater row, preventing Sparkle self-wait");
    __block NSUInteger replies=0;__block BOOL ready=NO;__block NSString *message=nil;__block BOOL offeredCancel=NO;
    IMP oldReply=class_getMethodImplementation(NSApplication.class,@selector(replyToApplicationShouldTerminate:));
    AMQuietReplace(NSApplication.class,@selector(replyToApplicationShouldTerminate:),imp_implementationWithBlock(^(id sender,BOOL value){replies++;ready=value;}));
    IMP oldModal=class_getMethodImplementation(NSAlert.class,@selector(runModal));
    AMQuietReplace(NSAlert.class,@selector(runModal),imp_implementationWithBlock(^NSModalResponse(NSAlert *alert){message=alert.informativeText;offeredCancel=alert.buttons.count>1 && alert.buttons[1].enabled;return ((NSModalResponse(*)(id,SEL))oldModal)(alert,@selector(runModal));}));
    Check([app applicationShouldTerminate:NSApp]==NSTerminateLater,@"real app delegate accepts install-and-restart while the update row is still running");Drain();
    Check(replies==1 && ready && !app.exitCoordinator.pending,@"real host exit completes without relying on Sparkle finishing first");app.courseWindow.operationsPaused=NO;
    __block BOOL cancelled=NO;__block NSString *readID=nil;readID=AMOperationBegin(@"检查课程材料",@"模拟课程",YES,^{cancelled=YES;AMOperationFinish(readID,@"cancelled",@"检查已取消");});AMOperationProgress(readID,@"核验第 2 个文件",2,5);
    [AMQuietDialogChoices addObject:@(NSAlertThirdButtonReturn)];
    Check([app applicationShouldTerminate:NSApp]==NSTerminateCancel && !cancelled && !app.exitCoordinator.pending,@"postponing update leaves the current background check intact");
    Check([message containsString:@"模拟课程"] && [message containsString:@"核验第 2 个文件"] && [message containsString:@"2／5"] && [message containsString:@"秒"] && offeredCancel,@"restart wait identifies the target, phase, count, elapsed time and safe cancellation choice");
    [update setValue:@YES forKey:@"installing"];[AMQuietDialogChoices addObject:@(NSAlertSecondButtonReturn)];
    Check([app applicationShouldTerminate:NSApp]==NSTerminateLater,@"cancel-and-continue still uses normal draft and persistence checks");Drain();
    Check(cancelled && replies==2 && ready,@"cancelling a safe background read releases the actual update exit gate");app.courseWindow.operationsPaused=NO;
    NSString *writeID=AMOperationBegin(@"保存课程文件",@"模拟写入",NO,nil);[AMQuietDialogChoices addObject:@(NSAlertFirstButtonReturn)];
    Check([app applicationShouldTerminate:NSApp]==NSTerminateLater,@"active writes remain protected while waiting for restart");Drain();
    Check(replies==2 && app.exitCoordinator.pending && !offeredCancel,@"non-interruptible writes are not offered a cancellation shortcut");
    AMOperationFinish(writeID,@"success",@"安全写入完成");Drain();
    Check(replies==3 && ready && !app.exitCoordinator.pending,@"restart resumes after the protected write finishes");app.courseWindow.operationsPaused=NO;
    [update updater:nil didAbortWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationCanceledError userInfo:nil]];
    app.updates=original;AMQuietReplace(NSApplication.class,@selector(replyToApplicationShouldTerminate:),oldReply);AMQuietReplace(NSAlert.class,@selector(runModal),oldModal);
}
int main(int argc, char **argv) { @autoreleasepool {
    [NSApplication sharedApplication];
    FeedChecks();
    NSString *location = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:location withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *appPath = [location stringByAppendingPathComponent:@"Synthetic.app"];
    Check([SSUpdateController canUpdateApplicationAtPath:appPath], @"writable application folder accepts updating");
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0555} ofItemAtPath:location error:nil];
    Check(![SSUpdateController canUpdateApplicationAtPath:appPath], @"read-only application location rejects updating");
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0755} ofItemAtPath:location error:nil];
    Check(![SSUpdateController canUpdateApplicationAtPath:[location stringByAppendingPathComponent:@"AppTranslocation/Synthetic.app"]], @"translocated app requests move to Applications");
    [NSFileManager.defaultManager removeItemAtPath:location error:nil];
    __block BOOL busy = YES, paused = NO, edited = YES, persistOK = YES, result = NO, called = NO;
    __block NSUInteger saves = 0, cancels = 0;
    SSExitCoordinator *gate = SSExitCoordinator.new;
    gate.operationBusy = ^BOOL { return busy; };
    gate.pauseOperations = ^(BOOL value) { paused = value; };
    gate.cancelLogin = ^{ cancels++; };
    gate.resolveEdits = ^BOOL(BOOL updating) { saves++; return edited; };
    gate.persist = ^BOOL { return persistOK; };
    [gate requestForUpdate:YES completion:^(BOOL value) { called = YES; result = value; }]; Drain();
    Check(paused && gate.pending && !called && saves == 0 && cancels == 1, @"busy Git operation delays termination without canceling it");
    [gate requestForUpdate:YES completion:^(BOOL value) { abort(); }];
    Check(cancels == 1, @"duplicate quit does not replace completion or repeat cancellation");
    busy = NO; [gate operationStateChanged];
    Check(called && result && paused && !gate.pending && saves == 1, @"completion terminates only after save and leaves gate closed");
    called = NO; edited = NO;
    [gate requestForUpdate:NO completion:^(BOOL value) { called = YES; result = value; }]; Drain();
    Check(called && !result && !paused && !gate.pending, @"invalid edits or postponed update unpause course work");
    called = NO; edited = YES; persistOK = NO;
    [gate requestForUpdate:YES completion:^(BOOL value) { called = YES; result = value; }]; Drain();
    Check(called && !result && !paused, @"storage failure prevents termination");
    persistOK = YES; called = NO; __block BOOL first = YES;
    gate.resolveEdits = ^BOOL(BOOL updating) { if (first) { busy = YES; first = NO; } return YES; };
    [gate requestForUpdate:YES completion:^(BOOL value) { called = YES; result = value; }]; Drain();
    Check(!called && paused && gate.pending, @"save-and-submit starts Git and is rechecked before termination");
    busy = NO; [gate operationStateChanged]; Check(called && result, @"submission completion resumes waiting exit");

    AppDelegate *app = AppDelegate.new; [app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
    ApplicationExitChecks(app);
    EditorController *editor = [[EditorController alloc] initWithTask:nil owner:app]; app.editor = editor;
    Check(!editor.hasUnsavedChanges, @"untouched task sheet is not dirty");
    editor.notesField.string = @"synthetic unsaved notes"; Check(editor.hasUnsavedChanges, @"notes edits detected even without a delegate event");
    editor.titleField.stringValue = @"测试任务"; editor.timePicker.stringValue = @"99:99";
    Check(![editor saveForExit] && app.editor == editor, @"invalid date leaves editor open and blocks exit");
    [editor updateDate:DDLParseDate(@"明天 21:00", NSDate.date, Cal())];
    NSUInteger before = app.tasks.count; Check([editor saveForExit] && !app.editor && app.tasks.count == before + 1, @"validated editor save completes before exit");
    SSCourseController *courses = app.courseWindow;
    courses.preview = NO; courses.operationsPaused = YES; __block BOOL ran = NO;
    [courses work:@"must not run" forCourse:@{@"fork":@"student/course"} operation:^id(NSError **error) { ran = YES; return @YES; } completion:^(id value, NSError *error) { abort(); }]; Drain();
    Check(!ran && !courses.operationBusy && !courses.setupButton.enabled, @"shutdown gate blocks course jobs and setup controls");
    courses.operationsPaused = NO; Check(courses.setupButton.enabled, @"canceling shutdown restores setup controls"); courses.preview = YES;
    SSSubmissionController *submission = [[SSSubmissionController alloc] initWithCourse:@{@"fork":@"student/course", @"branch":@"main"} changes:@[@{@"path":@"answers.md", @"status":@"M"}]];
    Check(!submission.hasUnsavedChanges, @"untouched submission is not dirty");
    submission.message.stringValue = @"未提交的说明"; Check(submission.hasUnsavedChanges, @"submission message is protected");
    [app.window beginSheet:submission.window completionHandler:nil];
    Check(![submission saveForExit] && submission.window.sheetParent, @"invalid submission remains open");
    submission.checks.firstObject.state = NSControlStateValueOn; __block BOOL submitted = NO;
    submission.submit = ^(NSArray *paths, NSString *message) { submitted = YES; };
    Check(![submission saveForExit] && !submitted && submission.window.sheetParent, @"exit returns to checks instead of implicitly submitting");[submission cancel:nil];
    courses.preview = NO; courses.git = FailedSubmissionGit.new; courses.github = SubmissionAPI.new;
    courses.courses = [@[[ @{@"fork":@"student/course", @"branch":@"main", @"path":@"/synthetic"} mutableCopy]] mutableCopy]; courses.selectedFork = @"student/course";
    [courses commit:nil]; while (courses.operationBusy) Drain();
    Check(courses.hasSubmissionSheet, @"failed-submission scenario opens real controller sheet");
    courses.submission.message.stringValue = @"保留我的说明"; courses.submission.checks.firstObject.state = NSControlStateValueOn;
    courses.operationsPaused = YES;
    Check(![courses saveSubmissionForExit] && !courses.operationBusy, @"exit never bypasses preflight or starts submission through paused gate");
    courses.operationsPaused=NO;
    courses.submission.performCheck=^NSDictionary *(NSArray *paths,NSArray *ids,NSString *extra,NSMutableDictionary *cache,BOOL(^cancelled)(void),NSError **error){return @{@"snapshot":@{},@"requirements":@"",@"report":@{@"version":@"fixture",@"issues":@[],@"coverage":@[],@"images":@[]}};};
    [courses.submission save:nil];while(courses.submission.checking)Drain();courses.submission.acknowledge.state=NSControlStateValueOn;[courses.submission save:nil];while(courses.submission.checking)Drain();
    while (courses.operationBusy) Drain();
    Check(!courses.submissionFailedDuringExit && courses.hasSubmissionSheet && [courses.submission.message.stringValue isEqual:@"保留我的说明"], @"explicit checked submission failure restores input");
    [AMQuietDialogChoices addObject:@(NSAlertFirstButtonReturn)];
    Check(![app resolveEditsForExit:YES] && !courses.submissionFailedDuringExit, @"failed submission returns to retained check form before update");
    [courses discardSubmission]; courses.preview = YES; courses.operationsPaused = NO;
    Check(!app.updates.available, @"UI preview never checks production feed");
    [app.ticker invalidate]; [app.searchTimer invalidate]; [app.window orderOut:nil]; [NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];
    printf("PASS: %lu update and exit assertions\n", (unsigned long)assertions);
} return 0; }
