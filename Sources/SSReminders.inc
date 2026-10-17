@interface AMReminderScheduler:NSObject
@property NSInteger generation;
@property NSInteger scheduled;
@property BOOL running;
@property NSArray *latestTasks;
@property id center;
- (void)startSchedule;
- (void)finishSchedule:(NSInteger)generation;
@property NSString *error;
@property NSString *notice;
@property(copy) void (^changed)(NSInteger,NSString *,NSString *);
- (void)schedule:(NSArray *)tasks;
@end
@implementation AMReminderScheduler
- (void)publish {if(self.changed)self.changed(self.scheduled,self.error,self.notice);}
- (BOOL)isTaskActive:(NSString *)identifier {
    for(NSDictionary *task in self.latestTasks)if([task[@"id"] isEqual:identifier])return ![task[@"completed"] boolValue] && ![task[@"archived"] boolValue] && ![task[@"deleted"] boolValue];return NO;
}
- (NSString *)taskIDForRequest:(UNNotificationRequest *)request {
    NSString *taskID=request.content.userInfo[@"taskID"] ?: request.content.threadIdentifier;if(taskID.length)return taskID;
    NSString *key=request.identifier;if(![key hasPrefix:@"ddl."] || [key isEqual:@"ddl.test"])return nil;NSRange offset=[key rangeOfString:@".offset." options:NSBackwardsSearch];return offset.location!=NSNotFound && offset.location>4 ? [key substringWithRange:NSMakeRange(4,offset.location-4)]:nil;
}
- (void)removeInactiveNotifications {
    id center=self.center ?: UNUserNotificationCenter.currentNotificationCenter;
    [center getPendingNotificationRequestsWithCompletionHandler:^(NSArray *pending){dispatch_async(dispatch_get_main_queue(),^{NSMutableArray *ids=NSMutableArray.array;for(UNNotificationRequest *r in pending){NSString *taskID=[self taskIDForRequest:r];if(taskID.length && ![self isTaskActive:taskID])[ids addObject:r.identifier];}if(ids.count)[center removePendingNotificationRequestsWithIdentifiers:ids];});}];
    [center getDeliveredNotificationsWithCompletionHandler:^(NSArray *delivered){dispatch_async(dispatch_get_main_queue(),^{NSMutableArray *ids=NSMutableArray.array;for(UNNotification *n in delivered){NSString *taskID=[self taskIDForRequest:n.request];if(taskID.length && ![self isTaskActive:taskID])[ids addObject:n.request.identifier];}if(ids.count)[center removeDeliveredNotificationsWithIdentifiers:ids];});}];
}
- (void)schedule:(NSArray *)tasks {
    NSArray *previous=self.latestTasks;self.latestTasks=[[NSArray alloc] initWithArray:tasks copyItems:YES];self.generation++;
    NSMutableSet *remove=NSMutableSet.set;for(NSDictionary *task in [previous ?: @[] arrayByAddingObjectsFromArray:tasks])if(![self isTaskActive:task[@"id"]])for(NSNumber *offset in DDLReminderOffsetsForTask(task))[remove addObject:[NSString stringWithFormat:@"ddl.%@.offset.%ld",task[@"id"],(long)offset.integerValue]];
    id center=self.center ?: UNUserNotificationCenter.currentNotificationCenter;if(remove.count)[center removePendingNotificationRequestsWithIdentifiers:remove.allObjects];
    [self removeInactiveNotifications];
    if(!self.running)[self startSchedule];
}
- (void)finishSchedule:(NSInteger)generation {
    self.running=NO;
    if(generation!=self.generation)[self startSchedule];
}
- (void)startSchedule {
    self.running=YES;NSArray *tasks=self.latestTasks;
    self.error = nil;self.notice=nil;
    NSInteger generation = self.generation;
    NSDate *now = NSDate.date; NSMutableArray *plans = [NSMutableArray array];
    for (NSDictionary *task in tasks) [plans addObjectsFromArray:DDLReminderPlan(task, now, Cal())];
    [plans sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"date"] compare:b[@"date"]]; }];
    // Keep the nearest reminders queued. Refill while running, on wake, and on launch.
    NSArray *queue = [plans subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)60, plans.count))];
    UNUserNotificationCenter *center = self.center ?: UNUserNotificationCenter.currentNotificationCenter;
    [center getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> *pending) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.generation) {[self finishSchedule:generation];return;}
            NSMutableDictionary *existing = [NSMutableDictionary dictionary]; for (UNNotificationRequest *r in pending) existing[r.identifier] = r;
            NSMutableSet *desired = [NSMutableSet set];
            dispatch_group_t scheduled = dispatch_group_create();
            for (NSDictionary *plan in queue) {
                NSString *identifier = plan[@"id"]; [desired addObject:identifier]; NSDictionary *task = plan[@"task"];
                NSString *body = [NSString stringWithFormat:@"%@：%@\n截止 %@", plan[@"message"], task[@"title"], DDLFormatDate(task[@"due"], @"M月d日 HH:mm")];
                UNNotificationRequest *old = existing[identifier]; NSDate *oldDate = [old.trigger isKindOfClass:UNCalendarNotificationTrigger.class] ? [(UNCalendarNotificationTrigger *)old.trigger nextTriggerDate] : nil;
                if (oldDate && fabs([oldDate timeIntervalSinceDate:plan[@"date"]]) < 1 && [old.content.body isEqual:body] && [old.content.title isEqual:task[@"subject"]]) continue;
                UNMutableNotificationContent *content = [UNMutableNotificationContent new]; content.title = task[@"subject"]; content.body = body; content.sound = UNNotificationSound.defaultSound; content.threadIdentifier = task[@"id"]; content.userInfo = @{@"taskID":task[@"id"]};
                NSDateComponents *parts = [Cal() components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond) fromDate:plan[@"date"]]; parts.timeZone = NSTimeZone.localTimeZone;
                UNCalendarNotificationTrigger *trigger = [UNCalendarNotificationTrigger triggerWithDateMatchingComponents:parts repeats:NO];
                UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger];
                dispatch_group_enter(scheduled);
                __weak UNUserNotificationCenter *registrationCenter=center;
                [center addNotificationRequest:request withCompletionHandler:^(NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if(generation!=self.generation || ![self isTaskActive:task[@"id"]]){[registrationCenter removePendingNotificationRequestsWithIdentifiers:@[identifier]];[registrationCenter removeDeliveredNotificationsWithIdentifiers:@[identifier]];}
                        if (error && generation == self.generation) { self.error = error.localizedDescription; self.notice = @"任务已保存，但提醒安排失败。请在设置中查看通知权限并重试。"; [self publish]; }
                        dispatch_group_leave(scheduled);
                    });
                }];
            }
            NSMutableArray *stale = [NSMutableArray array];
            for (UNNotificationRequest *request in pending) if (![desired containsObject:request.identifier] && ![request.identifier isEqual:@"ddl.test"]) [stale addObject:request.identifier];
            if (stale.count) [center removePendingNotificationRequestsWithIdentifiers:stale];
            if (plans.count > 60) self.notice = @"已优先安排最近 60 条提醒；保持应用运行以继续补充后续提醒。";
            dispatch_group_notify(scheduled, dispatch_get_main_queue(), ^{
                [center getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> *actual) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (generation != self.generation) {[self finishSchedule:generation];return;}
                        NSInteger count = 0; for (UNNotificationRequest *r in actual) if ([desired containsObject:r.identifier]) count++;
                        self.scheduled = count;SSDiagnostic(@"reminder",self.error ? @"failed":@"success",0); [self publish];[self finishSchedule:generation];
                    });
                }];
            });
            NSMutableSet *activeIDs = [NSMutableSet set]; for (NSDictionary *task in tasks) if (![task[@"completed"] boolValue] && ![task[@"archived"] boolValue] && ![task[@"deleted"] boolValue]) [activeIDs addObject:task[@"id"]];
            [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *notifications) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (generation != self.generation) return;
                    NSMutableArray *finished = [NSMutableArray array]; for (UNNotification *n in notifications) { NSString *taskID = [self taskIDForRequest:n.request]; if (taskID && ![activeIDs containsObject:taskID]) [finished addObject:n.request.identifier]; }
                    if (finished.count) [center removeDeliveredNotificationsWithIdentifiers:finished];
                });
            }];
        });
    }];
}
@end
