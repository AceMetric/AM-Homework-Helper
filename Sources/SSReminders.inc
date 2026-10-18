// Notification removals are asynchronous. A batch is settled only after the
// notification service returns a clean pending AND delivered snapshot.
@interface AMReminderScheduler:NSObject
@property NSInteger generation;
@property NSInteger scheduled;
@property BOOL running;
@property BOOL cleanupVerified;
@property NSUInteger serial;
@property NSUInteger outstandingAdds;
@property NSTimeInterval timeout;
@property NSArray *latestTasks;
@property id center;
@property NSString *error;
@property NSString *notice;
@property(copy) void (^changed)(NSInteger,NSString *,NSString *);
- (void)schedule:(NSArray *)tasks;
- (void)startSchedule;
@end
@implementation AMReminderScheduler
- (void)publish {if(self.changed)self.changed(self.scheduled,self.error,self.notice);}
- (NSDictionary *)activeTask:(NSString *)identifier {
    for(NSDictionary *task in self.latestTasks)if([task[@"id"] isEqual:identifier] && ![task[@"completed"] boolValue] && ![task[@"archived"] boolValue] && ![task[@"deleted"] boolValue])return task;
    return nil;
}
- (NSString *)taskIDForRequest:(UNNotificationRequest *)request {
    id value=request.content.userInfo[@"taskID"];
    if([value isKindOfClass:NSString.class] && [value length])return value;
    if(request.content.threadIdentifier.length)return request.content.threadIdentifier;
    NSString *key=request.identifier;if(![key hasPrefix:@"ddl."] || [key isEqual:@"ddl.test"])return nil;
    NSRange offset=[key rangeOfString:@".offset." options:NSBackwardsSearch];
    return offset.location!=NSNotFound && offset.location>4 ? [key substringWithRange:NSMakeRange(4,offset.location-4)]:nil;
}
- (NSString *)revisionForTask:(NSDictionary *)task {
    NSArray *values=@[task[@"id"] ?: @"",task[@"due"] ?: NSDate.distantPast,task[@"title"] ?: @"",task[@"subject"] ?: @"",[DDLReminderOffsetsForTask(task) sortedArrayUsingSelector:@selector(compare:)],NSTimeZone.localTimeZone.name];
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:values format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    return AMPreflightHash(data);
}
- (BOOL)isRequestCurrent:(UNNotificationRequest *)request {
    if([request.identifier isEqual:@"ddl.test"])return YES;
    NSDictionary *task=[self activeTask:[self taskIDForRequest:request]];
    if(!task || ![request.content.userInfo[@"reminderRevision"] isEqual:[self revisionForTask:task]])return NO;
    for(NSNumber *offset in DDLReminderOffsetsForTask(task))if([request.identifier isEqual:[NSString stringWithFormat:@"ddl.%@.offset.%ld",task[@"id"],(long)offset.integerValue]])return YES;
    return NO;
}
- (BOOL)safeToExit {return self.cleanupVerified && !self.running && !self.outstandingAdds;}
- (void)removeInactiveNotifications {
    id center=self.center ?: UNUserNotificationCenter.currentNotificationCenter;
    // Use the latest task state when callbacks arrive, never an old capture.
    [center getPendingNotificationRequestsWithCompletionHandler:^(NSArray *pending){dispatch_async(dispatch_get_main_queue(),^{NSMutableArray *ids=NSMutableArray.array;for(UNNotificationRequest *r in pending)if(![r.identifier isEqual:@"ddl.test"] && ![self activeTask:[self taskIDForRequest:r]])[ids addObject:r.identifier];if(ids.count)[center removePendingNotificationRequestsWithIdentifiers:ids];});}];
    [center getDeliveredNotificationsWithCompletionHandler:^(NSArray *delivered){dispatch_async(dispatch_get_main_queue(),^{NSMutableArray *ids=NSMutableArray.array;for(UNNotification *n in delivered)if(![n.request.identifier isEqual:@"ddl.test"] && ![self activeTask:[self taskIDForRequest:n.request]])[ids addObject:n.request.identifier];if(ids.count)[center removeDeliveredNotificationsWithIdentifiers:ids];});}];
}
- (void)schedule:(NSArray *)tasks {
    NSArray *previous=self.latestTasks;self.latestTasks=[[NSArray alloc] initWithArray:tasks copyItems:YES];self.generation++;self.cleanupVerified=NO;
    NSMutableSet *remove=NSMutableSet.set;for(NSDictionary *task in [previous ?: @[] arrayByAddingObjectsFromArray:tasks])if(![self activeTask:task[@"id"]])for(NSNumber *offset in DDLReminderOffsetsForTask(task))[remove addObject:[NSString stringWithFormat:@"ddl.%@.offset.%ld",task[@"id"],(long)offset.integerValue]];
    id center=self.center ?: UNUserNotificationCenter.currentNotificationCenter;
    if(remove.count){[center removePendingNotificationRequestsWithIdentifiers:remove.allObjects];[center removeDeliveredNotificationsWithIdentifiers:remove.allObjects];}
    [self removeInactiveNotifications];if(!self.running)[self startSchedule];
}
- (void)finish:(NSUInteger)serial generation:(NSInteger)generation verified:(BOOL)verified error:(NSString *)error {
    if(serial!=self.serial || !self.running)return;
    self.running=NO;
    if(generation!=self.generation){[self startSchedule];return;}
    self.error=error;self.cleanupVerified=verified && !self.outstandingAdds;
    if(error)self.notice=@"提醒更新未确认，请在提醒设置中重试。";
    SSDiagnostic(@"reminder",error ? @"failed":@"success",0);[self publish];
}
- (void)verify:(NSUInteger)serial generation:(NSInteger)generation desired:(NSSet *)desired {
    if(serial!=self.serial || !self.running)return;
    if(generation!=self.generation){[self finish:serial generation:generation verified:NO error:nil];return;}
    id center=self.center ?: UNUserNotificationCenter.currentNotificationCenter;
    [center getPendingNotificationRequestsWithCompletionHandler:^(NSArray *pending){
        [center getDeliveredNotificationsWithCompletionHandler:^(NSArray *delivered){dispatch_async(dispatch_get_main_queue(),^{
            if(serial!=self.serial || !self.running)return;
            if(generation!=self.generation){[self finish:serial generation:generation verified:NO error:nil];return;}
            NSMutableArray *stale=NSMutableArray.array,*shown=NSMutableArray.array;NSInteger count=0;
            for(UNNotificationRequest *r in pending){if([r.identifier isEqual:@"ddl.test"])continue;if(![desired containsObject:r.identifier] || ![self isRequestCurrent:r])[stale addObject:r.identifier];else count++;}
            for(UNNotification *n in delivered)if(![self isRequestCurrent:n.request])[shown addObject:n.request.identifier];
            if(stale.count)[center removePendingNotificationRequestsWithIdentifiers:stale];
            if(shown.count)[center removeDeliveredNotificationsWithIdentifiers:shown];
            if(stale.count || shown.count || self.outstandingAdds){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self verify:serial generation:generation desired:desired];});return;}
            self.scheduled=count;[self finish:serial generation:generation verified:YES error:self.error];
        });}];
    }];
}
- (void)startSchedule {
    self.running=YES;self.cleanupVerified=NO;self.error=nil;self.notice=nil;
    NSUInteger serial=++self.serial;NSInteger generation=self.generation;
    // A stalled system service must not leave update/restart waiting forever.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)((self.timeout>0 ? self.timeout:8)*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[self finish:serial generation:generation verified:NO error:@"通知服务未确认更新。"];} );
    NSMutableArray *plans=NSMutableArray.array;NSDate *now=NSDate.date;
    for(NSDictionary *task in self.latestTasks)[plans addObjectsFromArray:DDLReminderPlan(task,now,Cal())];
    [plans sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"date"] compare:b[@"date"]];}];
    NSArray *queue=[plans subarrayWithRange:NSMakeRange(0,MIN((NSUInteger)60,plans.count))];
    id center=self.center ?: UNUserNotificationCenter.currentNotificationCenter;
    [center getPendingNotificationRequestsWithCompletionHandler:^(NSArray *pending){dispatch_async(dispatch_get_main_queue(),^{
        if(serial!=self.serial || !self.running)return;
        if(generation!=self.generation){[self finish:serial generation:generation verified:NO error:nil];return;}
        NSMutableDictionary *existing=NSMutableDictionary.dictionary;for(UNNotificationRequest *r in pending)existing[r.identifier]=r;
        NSMutableSet *desired=NSMutableSet.set;dispatch_group_t registrations=dispatch_group_create();
        for(NSDictionary *plan in queue){
            NSString *identifier=plan[@"id"];[desired addObject:identifier];NSDictionary *task=plan[@"task"];
            if([self isRequestCurrent:existing[identifier]])continue;
            UNMutableNotificationContent *content=UNMutableNotificationContent.new;content.title=task[@"subject"];content.body=[NSString stringWithFormat:@"%@：%@\n截止 %@",plan[@"message"],task[@"title"],DDLFormatDate(task[@"due"],@"M月d日 HH:mm")];content.sound=UNNotificationSound.defaultSound;content.threadIdentifier=task[@"id"];content.userInfo=@{@"taskID":task[@"id"],@"reminderRevision":[self revisionForTask:task]};
            NSDateComponents *parts=[Cal() components:(NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitSecond) fromDate:plan[@"date"]];parts.timeZone=NSTimeZone.localTimeZone;
            UNNotificationRequest *request=[UNNotificationRequest requestWithIdentifier:identifier content:content trigger:[UNCalendarNotificationTrigger triggerWithDateMatchingComponents:parts repeats:NO]];
            self.outstandingAdds++;dispatch_group_enter(registrations);__weak id registrationCenter=center;
            [center addNotificationRequest:request withCompletionHandler:^(NSError *error){dispatch_async(dispatch_get_main_queue(),^{
                self.outstandingAdds--;
                if(![self isRequestCurrent:request]){[registrationCenter removePendingNotificationRequestsWithIdentifiers:@[identifier]];[registrationCenter removeDeliveredNotificationsWithIdentifiers:@[identifier]];}
                if(serial!=self.serial){self.generation++;self.cleanupVerified=NO;}
                if(error && serial==self.serial && generation==self.generation)self.error=error.localizedDescription;
                dispatch_group_leave(registrations);
                // A late registration after the watchdog also needs reconciliation.
                if(!self.running && !self.outstandingAdds)[self startSchedule];
            });}];
        }
        NSMutableArray *stale=NSMutableArray.array;for(UNNotificationRequest *r in pending)if(![desired containsObject:r.identifier] && ![r.identifier isEqual:@"ddl.test"])[stale addObject:r.identifier];if(stale.count)[center removePendingNotificationRequestsWithIdentifiers:stale];
        dispatch_group_notify(registrations,dispatch_get_main_queue(),^{[self verify:serial generation:generation desired:desired.copy];});
    });}];
}
@end
