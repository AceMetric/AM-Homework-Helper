#import <Cocoa/Cocoa.h>
#import <UserNotifications/UserNotifications.h>
#ifndef REVISION
#define REVISION 1
#endif
static BOOL done;
static NSMutableDictionary *result;
static void Save(void) {result[@"revision"]=@(REVISION);[result writeToFile:[NSBundle.mainBundle objectForInfoDictionaryKey:@"ProbeResult"] atomically:YES];done=YES;}
int main(int argc,const char **argv){@autoreleasepool{
[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
result=NSMutableDictionary.dictionary;NSString *mode=argc>1 ? @(argv[1]):@"read";UNUserNotificationCenter *center=UNUserNotificationCenter.currentNotificationCenter;
void(^read)(void)=^{[center getPendingNotificationRequestsWithCompletionHandler:^(NSArray *requests){result[@"pending"]=[requests valueForKey:@"identifier"];[center getDeliveredNotificationsWithCompletionHandler:^(NSArray *delivered){result[@"delivered"]=@([delivered count]);Save();}];}];};
if([mode isEqual:@"seed"]){[center requestAuthorizationWithOptions:UNAuthorizationOptionProvisional completionHandler:^(BOOL granted,NSError *error){result[@"granted"]=@(granted);if(error)result[@"error"]=error.localizedDescription;if(!granted){Save();return;}UNMutableNotificationContent *c=UNMutableNotificationContent.new;c.title=@"Isolated reminder identity test";c.body=@"Synthetic fixture";[center addNotificationRequest:[UNNotificationRequest requestWithIdentifier:@"synthetic.future" content:c trigger:[UNTimeIntervalNotificationTrigger triggerWithTimeInterval:3600 repeats:NO]] withCompletionHandler:^(NSError *err){if(err)result[@"addError"]=err.localizedDescription;read();}];}];}
else if([mode isEqual:@"clear"]){[center removeAllPendingNotificationRequests];[center removeAllDeliveredNotifications];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),read);}
else read();
NSDate *end=[NSDate dateWithTimeIntervalSinceNow:12];while(!done && end.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];return done ? 0:2;
}}
