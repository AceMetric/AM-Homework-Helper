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
@end
@implementation FakeCenter
- (instancetype)init {if((self=[super init])){self.pending=NSMutableDictionary.dictionary;self.held=NSMutableArray.array;self.delivered=NSMutableArray.array;}return self;}
- (void)getPendingNotificationRequestsWithCompletionHandler:(void(^)(NSArray *))completion {completion(self.pending.allValues);}
- (void)addNotificationRequest:(UNNotificationRequest *)request withCompletionHandler:(void(^)(NSError *))completion {if(self.hold)[self.held addObject:@{@"request":request,@"completion":[completion copy]}];else{self.pending[request.identifier]=request;completion(nil);}}
- (void)removePendingNotificationRequestsWithIdentifiers:(NSArray *)identifiers {[self.pending removeObjectsForKeys:identifiers];}
- (void)getDeliveredNotificationsWithCompletionHandler:(void(^)(NSArray *))completion {completion(self.delivered.copy);}
- (void)removeDeliveredNotificationsWithIdentifiers:(NSArray *)identifiers {NSMutableArray *left=NSMutableArray.array;for(FakeNotice *notice in self.delivered)if(![identifiers containsObject:notice.request.identifier])[left addObject:notice];self.delivered=left;}
- (void)releaseHeld {self.hold=NO;NSArray *held=self.held.copy;[self.held removeAllObjects];for(NSDictionary *row in held){UNNotificationRequest *request=row[@"request"];self.pending[request.identifier]=request;void(^completion)(NSError *)=row[@"completion"];completion(nil);}}
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
    AppDelegate *app=AppDelegate.new;app.tasks=[NSMutableArray arrayWithObject:finished];__block UNNotificationPresentationOptions options=123;[app userNotificationCenter:(id)center willPresentNotification:(id)notice withCompletionHandler:^(UNNotificationPresentationOptions value){options=value;}];Check(options==UNNotificationPresentationOptionNone,@"stale deleted notification suppressed at presentation");finished=task.mutableCopy;finished[@"completed"]=@YES;app.tasks=[NSMutableArray arrayWithObject:finished];[app userNotificationCenter:(id)center willPresentNotification:(id)notice withCompletionHandler:^(UNNotificationPresentationOptions value){options=value;}];Check(options==UNNotificationPresentationOptionNone,@"completed notification suppressed at presentation");[app userNotificationCenter:(id)center willPresentNotification:(id)legacy withCompletionHandler:^(UNNotificationPresentationOptions value){options=value;}];Check(options==UNNotificationPresentationOptionNone,@"legacy completed notification suppressed by its stable identifier");app.tasks=[NSMutableArray arrayWithObject:task.mutableCopy];[app userNotificationCenter:(id)center willPresentNotification:(id)notice withCompletionHandler:^(UNNotificationPresentationOptions value){options=value;}];Check(options!=UNNotificationPresentationOptionNone,@"active task notification remains visible");printf("PASS: %lu reminder race and stale-presentation assertions\n",(unsigned long)checks);
}return 0;}
