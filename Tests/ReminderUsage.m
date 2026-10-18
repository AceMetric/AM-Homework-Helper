#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
static void Wait(BOOL(^condition)(void)){NSDate *end=[NSDate dateWithTimeIntervalSinceNow:3];while(!condition() && end.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];Check(condition(),@"async reminder batch completes");}
@interface FakeNotice:NSObject
@property UNNotificationRequest *request;
@end
@implementation FakeNotice @end
@interface FakeCenter:NSObject
@property NSMutableDictionary *pending;
@property NSMutableArray *held;
@property NSMutableArray *delivered;
@property BOOL hold;
@property BOOL delayRemoval;
@property BOOL stall;
@property BOOL denied;
@property NSMutableSet *removedPending;
@property NSMutableSet *removedDelivered;
@end
@implementation FakeCenter
- (instancetype)init {if((self=[super init])){self.pending=NSMutableDictionary.dictionary;self.held=NSMutableArray.array;self.delivered=NSMutableArray.array;self.removedPending=NSMutableSet.set;self.removedDelivered=NSMutableSet.set;}return self;}
- (void)getPendingNotificationRequestsWithCompletionHandler:(void(^)(NSArray *))completion {if(!self.stall)completion(self.pending.allValues);}
- (void)addNotificationRequest:(UNNotificationRequest *)request withCompletionHandler:(void(^)(NSError *))completion {if(self.denied){completion([NSError errorWithDomain:@"SyntheticDenied" code:1 userInfo:nil]);return;}if(self.hold)[self.held addObject:@{@"request":request,@"completion":[completion copy]}];else{self.pending[request.identifier]=request;completion(nil);}}
- (void)removePendingNotificationRequestsWithIdentifiers:(NSArray *)identifiers {if(self.delayRemoval)[self.removedPending addObjectsFromArray:identifiers];else [self.pending removeObjectsForKeys:identifiers];}
- (void)getDeliveredNotificationsWithCompletionHandler:(void(^)(NSArray *))completion {if(!self.stall)completion(self.delivered.copy);}
- (void)removeDeliveredNotificationsWithIdentifiers:(NSArray *)identifiers {if(self.delayRemoval){[self.removedDelivered addObjectsFromArray:identifiers];return;}NSMutableArray *left=NSMutableArray.array;for(FakeNotice *notice in self.delivered)if(![identifiers containsObject:notice.request.identifier])[left addObject:notice];self.delivered=left;}
- (void)flushRemoval {self.delayRemoval=NO;[self removePendingNotificationRequestsWithIdentifiers:self.removedPending.allObjects];[self removeDeliveredNotificationsWithIdentifiers:self.removedDelivered.allObjects];[self.removedPending removeAllObjects];[self.removedDelivered removeAllObjects];}
- (void)releaseHeld {self.hold=NO;NSArray *held=self.held.copy;[self.held removeAllObjects];for(NSDictionary *row in held){UNNotificationRequest *request=row[@"request"];self.pending[request.identifier]=request;void(^completion)(NSError *)=row[@"completion"];completion(nil);}}
@end
@interface ReminderApp:AppDelegate @end
@implementation ReminderApp
- (void)render {}
- (void)refreshPermission {}
@end
int main(void){@autoreleasepool{
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];FakeCenter *center=FakeCenter.new;center.hold=YES;AMReminderScheduler *scheduler=AMReminderScheduler.new;scheduler.center=center;
    NSDictionary *task=@{@"id":@"reminder-fixture",@"title":@"Synthetic report",@"subject":@"Synthetic course",@"due":[NSDate dateWithTimeIntervalSinceNow:8*86400],@"completed":@NO,@"archived":@NO,@"reminderOffsets":@[@10080,@4320,@1440,@60,@0]};[scheduler schedule:@[task]];Wait(^BOOL{return center.held.count==5;});
    NSMutableDictionary *finished=task.mutableCopy;finished[@"completed"]=@YES;[scheduler schedule:@[finished]];Check(scheduler.running,@"finishing task does not start racing registration batch");[center releaseHeld];Wait(^BOOL{return !scheduler.running;});Check(!center.pending.count && scheduler.scheduled==0,@"late registration cannot restore completed task reminders");
    [scheduler schedule:@[task]];Wait(^BOOL{return !scheduler.running;});Check(center.pending.count==5,@"undo completion restores reminder plan");FakeNotice *notice=FakeNotice.new;notice.request=center.pending.allValues.firstObject;[center.delivered addObject:notice];finished=task.mutableCopy;finished[@"deleted"]=@YES;[scheduler schedule:@[finished]];Wait(^BOOL{return !scheduler.running && !center.delivered.count;});Check(!center.pending.count,@"deleted task clears pending and delivered notifications");
    [scheduler schedule:@[task]];Wait(^BOOL{return !scheduler.running;});
    UNNotificationRequest *activeRequest=center.pending.allValues.firstObject;FakeNotice *legacy=FakeNotice.new;UNMutableNotificationContent *legacyContent=UNMutableNotificationContent.new;legacy.request=[UNNotificationRequest requestWithIdentifier:activeRequest.identifier content:legacyContent trigger:nil];center.pending[legacy.request.identifier]=legacy.request;[center.delivered addObject:legacy];
    // A previous registration can still be in flight while completed reminders are already pending.
    center.hold=YES;NSMutableDictionary *changed=task.mutableCopy;changed[@"title"]=@"Changed synthetic title";[scheduler schedule:@[changed]];Wait(^BOOL{return center.held.count==5;});finished=[DDLTaskCompletion(changed,YES) mutableCopy];[scheduler schedule:@[finished]];
    Check(!center.pending.count,@"completion cancels already registered reminders before slow registration returns");
    Wait(^BOOL{return !center.delivered.count;});Check(center.held.count==5,@"completed delivered legacy notices clear while registration is still waiting");[center releaseHeld];Wait(^BOOL{return !scheduler.running;});Check(!center.pending.count,@"late registration cannot resurrect cancelled reminders");
    AMReminderScheduler *relaunched=AMReminderScheduler.new;relaunched.center=center;center.pending[legacy.request.identifier]=legacy.request;[center.delivered addObject:legacy];[relaunched schedule:@[finished]];Wait(^BOOL{return !relaunched.running && !center.delivered.count;});Check(!center.pending.count,@"launch prunes stale completed notifications without userInfo or prior snapshot");
    [scheduler schedule:@[task]];Wait(^BOOL{return !scheduler.running;});Check(center.pending.count==5,@"manual reopen restores future reminders after completion cleanup");
    AppDelegate *app=AppDelegate.new;app.tasks=[NSMutableArray arrayWithObject:finished];__block UNNotificationPresentationOptions options=123;[app userNotificationCenter:(id)center willPresentNotification:(id)notice withCompletionHandler:^(UNNotificationPresentationOptions value){options=value;}];Check(options==UNNotificationPresentationOptionNone,@"stale deleted notification suppressed at presentation");finished=task.mutableCopy;finished[@"completed"]=@YES;app.tasks=[NSMutableArray arrayWithObject:finished];[app userNotificationCenter:(id)center willPresentNotification:(id)notice withCompletionHandler:^(UNNotificationPresentationOptions value){options=value;}];Check(options==UNNotificationPresentationOptionNone,@"completed notification suppressed at presentation");[app userNotificationCenter:(id)center willPresentNotification:(id)legacy withCompletionHandler:^(UNNotificationPresentationOptions value){options=value;}];Check(options==UNNotificationPresentationOptionNone,@"legacy completed notification suppressed by its stable identifier");app.tasks=[NSMutableArray arrayWithObject:task.mutableCopy];[app userNotificationCenter:(id)center willPresentNotification:(id)notice withCompletionHandler:^(UNNotificationPresentationOptions value){options=value;}];Check(options!=UNNotificationPresentationOptionNone,@"active task notification remains visible");
    // A removal request is not an acknowledgement: keep exit/update waiting
    // until both service snapshots show that completed notices are gone.
    center.delayRemoval=YES;FakeNotice *shown=FakeNotice.new;shown.request=center.pending.allValues.firstObject;[center.delivered addObject:shown];[scheduler schedule:@[finished]];
    Wait(^BOOL{return center.removedPending.count>0 && center.removedDelivered.count>0;});
    Check(scheduler.running && !scheduler.safeToExit && center.pending.count>0,@"unacknowledged removal cannot report settled or permit exit");
    SSExitCoordinator *exitGate=SSExitCoordinator.new;__block NSInteger exitResult=0;exitGate.operationBusy=^BOOL{return scheduler.running;};exitGate.persist=^BOOL{return scheduler.safeToExit;};scheduler.changed=^(NSInteger count,NSString *error,NSString *message){[exitGate operationStateChanged];};
    [exitGate requestForUpdate:YES completion:^(BOOL ready){exitResult=ready ? 1:-1;}];
    Wait(^BOOL{return exitGate.pending;});Check(exitResult==0,@"update waits for reminder reconciliation");
    [center flushRemoval];Wait(^BOOL{return exitResult==1;});Check(!center.pending.count && !center.delivered.count && scheduler.safeToExit,@"exit proceeds only after pending and delivered cleanup is acknowledged");

    // Unknown and old-format requests must fail closed, including background
    // leftovers that have neither userInfo nor the modern stable identifier.
    UNNotificationRequest *unknown=[UNNotificationRequest requestWithIdentifier:@"old-format-orphan" content:UNMutableNotificationContent.new trigger:nil];FakeNotice *orphan=FakeNotice.new;orphan.request=unknown;center.pending[unknown.identifier]=unknown;[center.delivered addObject:orphan];
    UNNotificationRequest *test=[UNNotificationRequest requestWithIdentifier:@"ddl.test" content:UNMutableNotificationContent.new trigger:nil];center.pending[test.identifier]=test;
    [scheduler schedule:@[task]];Wait(^BOOL{return !scheduler.running;});Check(!center.pending[unknown.identifier] && !center.delivered.count && center.pending[test.identifier],@"startup removes orphan requests and preserves explicit test notification");
    app.tasks=[NSMutableArray arrayWithObject:task.mutableCopy];[app userNotificationCenter:(id)center willPresentNotification:(id)orphan withCompletionHandler:^(UNNotificationPresentationOptions value){options=value;}];Check(options==UNNotificationPresentationOptionNone,@"unidentifiable task reminder is suppressed");
    Check(![scheduler isRequestCurrent:legacy.request],@"legacy active request is replaced rather than trusted without revision");
    UNNotificationRequest *before=center.pending[notice.request.identifier];NSMutableDictionary *rescheduled=task.mutableCopy;rescheduled[@"due"]=[task[@"due"] dateByAddingTimeInterval:3600];[scheduler schedule:@[rescheduled]];Wait(^BOOL{return !scheduler.running;});Check(![scheduler isRequestCurrent:before],@"old due-date revision cannot be presented");Check([scheduler isRequestCurrent:center.pending[before.identifier]],@"new due-date revision replaces pending request");

    // A nonresponsive notification service cancels the exit attempt within a
    // bounded time; it never approves exit while registrations are outstanding.
    center.stall=YES;scheduler.timeout=0.1;[scheduler schedule:@[finished]];exitResult=0;[exitGate requestForUpdate:YES completion:^(BOOL ready){exitResult=ready ? 1:-1;}];Wait(^BOOL{return exitResult==-1;});Check(!scheduler.safeToExit && scheduler.error.length,@"service timeout cancels update visibly instead of waiting forever");
    center.stall=NO;[scheduler schedule:@[finished]];Wait(^BOOL{return !scheduler.running;});Check(scheduler.safeToExit && center.pending.count==1,@"retry clears completed requests after service recovers");
    center.hold=YES;[scheduler schedule:@[task]];Wait(^BOOL{return center.held.count==5;});Wait(^BOOL{return !scheduler.running;});Check(!scheduler.safeToExit && scheduler.outstandingAdds==5,@"timed out registration cannot allow exit");[scheduler schedule:@[finished]];[center releaseHeld];Wait(^BOOL{return !scheduler.running && scheduler.outstandingAdds==0;});Check(scheduler.safeToExit && center.pending.count==1,@"late timed-out callbacks reconcile completed task before permitting exit");
    // Exercise the real checkbox -> transactional save -> scheduler path,
    // using only the test runner's isolated store and fake notification center.
    Check(NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"].length>0,@"mutation regression requires isolated storage");
    center.hold=NO;scheduler.timeout=1;scheduler.changed=nil;
    ReminderApp *saving=ReminderApp.new;saving.tasks=NSMutableArray.array;saving.reminderScheduler=scheduler;
    Check([saving replaceTasks:@[task] action:@"Synthetic create" error:nil],@"real task mutation saves initial task");Wait(^BOOL{return !scheduler.running;});Check(center.pending.count==6,@"saved active task registers five real-plan reminders");
    NSButton *checkbox=NSButton.new;checkbox.identifier=task[@"id"];[saving toggleTask:checkbox];Wait(^BOOL{return !scheduler.running;});
    Check([saving.tasks.firstObject[@"completed"] boolValue] && [SSLoadTasks(NULL).firstObject[@"completed"] boolValue],@"checkbox completion reaches persistent task store");Check(center.pending.count==1 && scheduler.safeToExit,@"real completion clears all five offsets before exit");
    AMReminderScheduler *restart=AMReminderScheduler.new;restart.center=center;[restart schedule:SSLoadTasks(NULL)];Wait(^BOOL{return !restart.running;});Check(center.pending.count==1 && restart.safeToExit,@"restart does not requeue persisted completed task");
    [saving toggleTask:checkbox];Wait(^BOOL{return !scheduler.running;});Check(center.pending.count==6 && ![saving.tasks.firstObject[@"completed"] boolValue],@"real checkbox reopen restores reminders");
    center.denied=YES;[scheduler schedule:@[finished]];Wait(^BOOL{return !scheduler.running;});[scheduler schedule:@[task]];Wait(^BOOL{return !scheduler.running;});Check(scheduler.error.length && scheduler.safeToExit && center.pending.count==1,@"denied new registrations report failure but do not block exit after verified cleanup");
    printf("PASS: %lu reminder race, cleanup acknowledgement and exit assertions\n",(unsigned long)checks);
}return 0;}
