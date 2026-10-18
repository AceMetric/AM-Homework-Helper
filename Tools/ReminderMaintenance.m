// Loaded only into an unmodified, pinned historical copy of this application's
// host. Exit in this constructor: its old UI, task store and network never run.
#import <Cocoa/Cocoa.h>
#import <UserNotifications/UserNotifications.h>
#import <unistd.h>
#ifndef AM_REMINDER_HOST_PREFIX
#define AM_REMINDER_HOST_PREFIX @"io.github.acemetric.sshomeworkmanager"
#endif
__attribute__((constructor)) static void AMMaintainHistoricalReminders(void) {@autoreleasepool {
    NSArray *args=NSProcessInfo.processInfo.arguments;
    if(args.count!=3 || ![args[1] isEqual:@"--am-reminder-maintenance"] || ![NSProcessInfo.processInfo.environment[@"AM_REMINDER_MAINTENANCE"] isEqual:@"1"] || ![NSBundle.mainBundle.bundleIdentifier isEqual:AM_REMINDER_HOST_PREFIX])_exit(91);
    UNUserNotificationCenter *center=UNUserNotificationCenter.currentNotificationCenter;__weak id weakCenter=center;
    __block BOOL read=NO;__block NSUInteger before=0,shown=0,left=NSNotFound;
    NSDate *end=[NSDate dateWithTimeIntervalSinceNow:5];
    [center getPendingNotificationRequestsWithCompletionHandler:^(NSArray *pending){NSUInteger pendingCount=pending.count;[weakCenter getDeliveredNotificationsWithCompletionHandler:^(NSArray *delivered){dispatch_async(dispatch_get_main_queue(),^{before=pendingCount;shown=delivered.count;read=YES;});}];}];
    while(!read && end.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    [center removeAllPendingNotificationRequests];[center removeAllDeliveredNotifications];
    while(read && end.timeIntervalSinceNow>0){
        __block BOOL checked=NO;
        [center getPendingNotificationRequestsWithCompletionHandler:^(NSArray *pending){NSUInteger pendingCount=pending.count;[weakCenter getDeliveredNotificationsWithCompletionHandler:^(NSArray *delivered){dispatch_async(dispatch_get_main_queue(),^{left=pendingCount+delivered.count;checked=YES;});}];}];
        while(!checked && end.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        if(checked && !left)break;
        [center removeAllPendingNotificationRequests];[center removeAllDeliveredNotifications];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
    }
    BOOL done=read && left==0;
    [@{@"pendingBefore":@(before),@"deliveredBefore":@(shown),@"remaining":@(left),@"confirmed":@(done)} writeToFile:args[2] atomically:YES];_exit(done ? 0:93);
}}
