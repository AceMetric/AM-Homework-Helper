#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
static NSUInteger assertions;
static void Check(BOOL ok,NSString *message){assertions++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
@interface CompletionApp:AppDelegate
@property NSUInteger reminderUpdates;
@property NSUInteger remainingReminders;
@end
@implementation CompletionApp
- (void)refreshReminders {self.reminderUpdates++;self.remainingReminders=0;for(NSDictionary *task in self.tasks)self.remainingReminders+=DDLReminderPlan(task,NSDate.date,Cal()).count;}
@end
@interface CompletionCourse:SSCourseController
@property NSUInteger queuedVerifications;
@end
@implementation CompletionCourse
- (void)work:(NSString *)message forCourse:(NSDictionary *)course requestKey:(NSString *)scope priority:(NSInteger)priority operation:(id (^)(NSError **))operation completion:(void (^)(id,NSError *))completion {self.queuedVerifications++;}
@end
int main(void){@autoreleasepool{
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];CompletionApp *app=CompletionApp.new;NSApp.delegate=app;[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
    // Real persistence and App integration, synthetic controller and fake reminders only.
    app.preview=NO;app.recurrenceSeries=@[];NSDictionary *task=@{@"id":@"synthetic-completion",@"title":@"Synthetic answer",@"subject":@"Synthetic",@"notes":@"Before edit",@"courseRepository":@"student/course",@"sourceRepository":@"teacher/course",@"sourcePath":@"assignment-1/README.md",@"due":[NSDate dateWithTimeIntervalSinceNow:8*86400],@"completed":@NO};app.tasks=[DDLNormalizeTasks(@[task]) mutableCopy];
    app.courseWindow.courses=[@[[(@{@"fork":@"student/course",@"upstream":@"teacher/course",@"branch":@"main"}) mutableCopy]] mutableCopy];
    NSString *hash=[@"a" stringByPaddingToLength:40 withString:@"a" startingAtIndex:0];NSDictionary *record=@{@"id":NSUUID.UUID.UUIDString,@"repository":@"student/course",@"branch":@"main",@"commit":hash,@"remoteCommit":hash,@"kind":@"submission",@"state":@"confirmed",@"origin":@"app",@"message":@"Synthetic submission",@"date":NSDate.date,@"checkedAt":NSDate.date,@"files":@[@"assignment-1/assignment.md"],@"completionFiles":@[@"assignment-1/assignment.md"],@"taskIDs":@[@"synthetic-completion"],@"completionEligibility":@"new"};NSError *error=nil;
    Check(SSSaveScheduledTasks(@[],app.tasks,@[],@{},&error) && AMStoreSubmission(record,&error),@"persist isolated task and verified app submission");
    app.editor=[[EditorController alloc] initWithTask:app.tasks[0] owner:app];[app.window beginSheet:app.editor.window completionHandler:nil];[app applyVerifiedSubmissions];Check(![app.tasks[0][@"completed"] boolValue],@"active editor defers automatic completion");
    NSMutableDictionary *edited=[app.tasks[0] mutableCopy];edited[@"notes"]=@"Edited notes stay intact";Check([app commitTask:edited originalID:edited[@"id"]],@"editor can save while verified submission is pending");[app closeEditor];
    Check([app.tasks[0][@"completed"] boolValue] && [app.tasks[0][@"notes"] isEqual:@"Edited notes stay intact"],@"closing editor completes latest task without overwriting its edits");Check(app.reminderUpdates>0 && app.remainingReminders==0,@"automatic completion refreshes reminders through app path");
    Check(app.submissionCompletionUndoAvailable && app.taskUndo.canUndo && [app.notice isEqual:@"已完成 1 项"],@"completion exposes concise receipt and undo");BOOL undoVisible=NO;for(NSToolbarItem *item in app.window.toolbar.items)if([item.itemIdentifier isEqual:@"AMUndoSubmissionCompletion"])undoVisible=YES;Check(undoVisible,@"undo action is accessible from native toolbar");
    [app undo:nil];Check(![app.tasks[0][@"completed"] boolValue] && [app.tasks[0][@"notes"] isEqual:@"Edited notes stay intact"] && app.remainingReminders>0,@"undo restores pending state and reminders while preserving edited notes");[app applyVerifiedSubmissions];Check(![app.tasks[0][@"completed"] boolValue] && [AMSubmissionRecords(NULL)[0][@"completionDecisions"][@"synthetic-completion"][@"state"] isEqual:@"dismissed"],@"undo suppression persists through controller callbacks");
    NSMutableDictionary *stale=record.mutableCopy;stale[@"id"]=NSUUID.UUID.UUIDString;stale[@"checkedAt"]=[NSDate dateWithTimeIntervalSinceNow:-301];stale[@"completionStatus"]=@"deferred";Check(AMStoreSubmission(stale,&error),@"persist stale deferred evidence");CompletionCourse *queued=[[CompletionCourse alloc] initWithPreview:YES];queued.preview=NO;queued.connected=YES;queued.courses=app.courseWindow.courses;
    [queued reverifyDeferredSubmissionsExcept:[NSSet setWithObject:@"synthetic-completion"]];Check(queued.queuedVerifications==0,@"long editing does not reverify until editor closes");[queued reverifyDeferredSubmissionsExcept:NSSet.set];Check(queued.queuedVerifications==1,@"closing long editor queues fresh remote verification");[queued reverifyDeferredSubmissionsExcept:NSSet.set];Check(queued.queuedVerifications==1,@"failed or repeated callbacks cannot create an endless verification loop");[queued.timer invalidate];
    [app.ticker invalidate];[app.searchTimer invalidate];[app.window orderOut:nil];[NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];printf("PASS: %lu submission completion interaction assertions\n",(unsigned long)assertions);
}return 0;}
