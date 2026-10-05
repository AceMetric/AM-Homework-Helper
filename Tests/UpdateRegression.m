#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
#include <stdio.h>
static NSUInteger assertions;
static void Check(BOOL value, NSString *description) { assertions++; if (!value) { fprintf(stderr, "FAIL: %s\n", description.UTF8String); exit(1); } }
static void Drain(void) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; }
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
int main(int argc, char **argv) { @autoreleasepool {
    [NSApplication sharedApplication];
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
    Check([submission saveForExit] && submitted, @"explicit save validates selection and invokes submission");
    courses.preview = NO; courses.git = FailedSubmissionGit.new; courses.github = SubmissionAPI.new;
    courses.courses = [@[[ @{@"fork":@"student/course", @"branch":@"main", @"path":@"/synthetic"} mutableCopy]] mutableCopy]; courses.selectedFork = @"student/course";
    [courses commit:nil]; while (courses.operationBusy) Drain();
    Check(courses.hasSubmissionSheet, @"failed-submission scenario opens real controller sheet");
    courses.submission.message.stringValue = @"保留我的说明"; courses.submission.checks.firstObject.state = NSControlStateValueOn;
    courses.operationsPaused = YES;
    Check([courses saveSubmissionForExit] && courses.operationBusy, @"explicit exit save starts submission through paused gate");
    while (courses.operationBusy) Drain();
    Check(courses.submissionFailedDuringExit && courses.hasSubmissionSheet && [courses.submission.message.stringValue isEqual:@"保留我的说明"], @"Git validation failure restores input and prevents exit");
    Check(![app resolveEditsForExit:YES] && !courses.submissionFailedDuringExit, @"failed exit submission cancels without another save prompt");
    [courses discardSubmission]; courses.preview = YES; courses.operationsPaused = NO;
    Check(!app.updates.available, @"UI preview never checks production feed");
    [app.ticker invalidate]; [app.searchTimer invalidate]; [app.window orderOut:nil]; [NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];
    printf("PASS: %lu update and exit assertions\n", (unsigned long)assertions);
} return 0; }
