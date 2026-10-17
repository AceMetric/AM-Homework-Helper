#import "../Sources/DDLCore.h"
#include <stdio.h>
#include <stdlib.h>
static int assertions;
static void Check(BOOL value,NSString *message){assertions++;if(!value){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
static NSCalendar *C(void){NSCalendar *c=[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];c.timeZone=[NSTimeZone timeZoneWithName:@"Asia/Shanghai"];return c;}
static NSDate *D(NSString *s){return DDLParseDate(s,NSDate.date,C());}
static NSMutableDictionary *R(NSString *anchor,NSString *unit){return [@{@"mode":@"fixed",@"unit":unit,@"interval":@1,@"anchor":D(anchor),@"timeZone":@"Asia/Shanghai",@"holidayPolicy":@"keep"} mutableCopy];}
static void ListPresentation(void){
    NSDate *now=D(@"2026-10-17 12:00");NSMutableArray *items=NSMutableArray.array;
    for(NSInteger i=5;i>=0;i--)[items addObject:[@{@"id":[NSString stringWithFormat:@"a-%ld",(long)i],@"seriesID":@"a",@"title":@"同名安排",@"due":[now dateByAddingTimeInterval:(i+1)*86400]} mutableCopy]];
    NSMutableDictionary *done=[@{@"id":@"done",@"seriesID":@"a",@"due":[now dateByAddingTimeInterval:3600],@"completed":@YES} mutableCopy];
    NSDictionary *late=@{@"id":@"late",@"seriesID":@"a",@"due":[now dateByAddingTimeInterval:-86400]},*boundary=@{@"id":@"now",@"seriesID":@"a",@"due":now};
    NSDictionary *archived=@{@"id":@"archived",@"seriesID":@"a",@"due":[now dateByAddingTimeInterval:1],@"archived":@YES},*deleted=@{@"id":@"deleted",@"seriesID":@"a",@"due":[now dateByAddingTimeInterval:2],@"deleted":@YES};
    [items addObjectsFromArray:@[done,late,boundary,archived,deleted]];
    for(NSInteger i=0;i<3;i++){[items addObject:@{@"id":[NSString stringWithFormat:@"b-%ld",(long)i],@"seriesID":@"b",@"title":@"同名安排",@"due":[now dateByAddingTimeInterval:(i+1)*86400]}];[items addObject:@{@"id":[NSString stringWithFormat:@"plain-%ld",(long)i],@"title":@"同名安排",@"due":[now dateByAddingTimeInterval:(i+1)*86400]}];}
    NSArray *snapshot=[[NSArray alloc] initWithArray:items copyItems:YES],*visible=DDLTaskListItems(items,now);NSArray *ids=[visible valueForKey:@"id"];
    Check([ids containsObject:@"a-0"] && [ids containsObject:@"a-1"] && ![ids containsObject:@"a-2"] && ![ids containsObject:@"a-5"],@"list chooses nearest two dates independently of stored order");
    Check([ids containsObject:@"done"] && [ids containsObject:@"late"] && [ids containsObject:@"now"],@"completed and overdue history does not consume upcoming slots");
    Check([ids containsObject:@"archived"] && [ids containsObject:@"deleted"],@"archive and trash remain available to their existing filters");
    Check([ids containsObject:@"b-0"] && [ids containsObject:@"b-1"] && ![ids containsObject:@"b-2"] && [ids containsObject:@"plain-2"],@"separate series and unrelated same-title tasks are independent");
    Check([visible.firstObject[@"id"] isEqual:@"a-1"] && [items isEqual:snapshot],@"presentation preserves incoming order and never mutates stored occurrences");
    NSMutableDictionary *first=items[5];first[@"completed"]=@YES;ids=[DDLTaskListItems(items,now) valueForKey:@"id"];
    Check([ids containsObject:@"a-0"] && [ids containsObject:@"a-2"] && ![ids containsObject:@"a-3"],@"completion retains history and reveals the next occurrence");
    first[@"completed"]=@NO;Check(![[DDLTaskListItems(items,now) valueForKey:@"id"] containsObject:@"a-2"],@"restoring pending status restores the same nearest two");
    ids=[DDLTaskListItems(items,[now dateByAddingTimeInterval:4*86400]) valueForKey:@"id"];
    Check([ids containsObject:@"a-0"] && [ids containsObject:@"a-3"] && [ids containsObject:@"a-4"] && [ids containsObject:@"a-5"],@"clock advancement retains every newly overdue occurrence");
    Check(DDLCalendarTasks(items,0,@"").count==items.count-2,@"calendar retains future occurrences hidden from the task list");
    NSArray *ties=@[@{@"id":@"c",@"seriesID":@"tie",@"due":[now dateByAddingTimeInterval:1]},@{@"id":@"b",@"seriesID":@"tie",@"due":[now dateByAddingTimeInterval:1]},@{@"id":@"a",@"seriesID":@"tie",@"due":[now dateByAddingTimeInterval:1]}];
    Check([[DDLTaskListItems(ties,now) valueForKey:@"id"] isEqual:@[@"b",@"a"]],@"holiday collisions select stable occurrence identities without merging them");
}
int main(){@autoreleasepool {
    ListPresentation();
    NSMutableDictionary *r=R(@"2026-01-31 20:00",@"month");NSArray *dates=DDLRecurrenceDates(r,D(@"2026-01-01 00:00"),D(@"2026-04-01 00:00"),@{},NULL);
    Check(dates.count==3,@"monthly range contains three dates");Check([dates[1][@"due"] isEqual:D(@"2026-02-28 20:00")] && [dates[2][@"due"] isEqual:D(@"2026-03-31 20:00")],@"month end clamps without anchor drift");
    r=R(@"2024-02-29 09:00",@"year");r[@"count"]=@5;dates=DDLRecurrenceDates(r,D(@"2024-01-01 00:00"),D(@"2029-01-01 00:00"),@{},NULL);Check([dates[4][@"due"] isEqual:D(@"2028-02-29 09:00")],@"leap anchor restores Feb 29");
    r=R(@"2026-10-12 18:00",@"week");r[@"weekdays"]=@[@2,@4];r[@"interval"]=@2;dates=DDLRecurrenceDates(r,D(@"2026-10-12 00:00"),D(@"2026-10-31 23:59"),@{},NULL);Check(dates.count==4 && [dates[2][@"due"] isEqual:D(@"2026-10-26 18:00")],@"multiple weekdays respect interval weeks");
    Check(![DDLChinaDayInfo(D(@"2026-10-10 12:00"),C(),@{})[@"rest"] boolValue],@"Saturday makeup is workday");Check([DDLChinaDayInfo(D(@"2026-10-01 12:00"),C(),@{})[@"rest"] boolValue],@"national holiday is rest day");Check(![DDLChinaDayInfo(D(@"2027-01-01 12:00"),C(),@{})[@"known"] boolValue],@"unknown year not invented");
    r=R(@"2026-10-01 21:00",@"day");r[@"count"]=@2;r[@"holidayPolicy"]=@"next";dates=DDLRecurrenceDates(r,D(@"2026-09-30 00:00"),D(@"2026-10-15 00:00"),@{},NULL);Check(dates.count==2 && [dates[0][@"due"] isEqual:D(@"2026-10-08 21:00")] && ![dates[0][@"key"] isEqual:dates[1][@"key"]],@"holiday collision keeps distinct nominal identities");
    r[@"holidayPolicy"]=@"previous";dates=DDLRecurrenceDates(r,D(@"2026-09-29 00:00"),D(@"2026-10-03 00:00"),@{},NULL);Check([dates[0][@"due"] isEqual:D(@"2026-09-30 21:00")],@"previous workday preserves time");
    r[@"holidayPolicy"]=@"skip";dates=DDLRecurrenceDates(r,D(@"2026-09-29 00:00"),D(@"2026-10-12 00:00"),@{},NULL);Check(dates.count==0,@"skip still consumes nominal count");
    r=R(@"2027-01-01 09:00",@"day");r[@"holidayPolicy"]=@"next";NSError *error=nil;Check(DDLRecurrenceDates(r,D(@"2027-01-01 00:00"),D(@"2027-01-02 23:59"),@{},&error)==nil && error!=nil,@"unknown holiday avoidance needs confirmation");
    r[@"allowedUnknownYears"]=@[@2027];error=nil;Check(DDLRecurrenceDates(r,D(@"2027-01-01 00:00"),D(@"2027-01-02 23:59"),@{},&error)!=nil && !error,@"explicit per-year weekend fallback");
    NSDictionary *overrides=@{@"2026-10-10":@{@"rest":@YES,@"name":@"学校假期",@"reason":@"模拟学校通知"}};Check([DDLChinaDayInfo(D(@"2026-10-10 12:00"),C(),overrides)[@"rest"] boolValue],@"local school override wins");
    r=R(@"2026-10-14 20:00",@"day");r[@"count"]=@3;NSDictionary *template=@{@"id":NSUUID.UUID.UUIDString,@"title":@"复习",@"due":r[@"anchor"],@"completed":@NO};NSDictionary *series=@{@"id":NSUUID.UUID.UUIDString,@"rule":r,@"template":template};NSArray *tasks=DDLMaterializeRecurringTasks(@[],@[series],D(@"2026-10-14 00:00"),D(@"2026-10-20 23:59"),@{},NULL);Check(tasks.count==3,@"fixed materializes future range");Check(DDLMaterializeRecurringTasks(tasks,@[series],D(@"2026-10-14 00:00"),D(@"2026-10-20 23:59"),@{},NULL).count==3,@"repeat scan idempotent");
    NSMutableDictionary *deleted=[tasks[0] mutableCopy];deleted[@"deleted"]=@YES;NSMutableArray *t=tasks.mutableCopy;t[0]=deleted;Check(DDLMaterializeRecurringTasks(t,@[series],D(@"2026-10-14 00:00"),D(@"2026-10-20 23:59"),@{},NULL).count==3,@"skipped occurrence stays skipped");
    r=R(@"2026-10-14 20:00",@"week");r[@"mode"]=@"completion";series=@{@"id":NSUUID.UUID.UUIDString,@"rule":r,@"template":template};tasks=DDLMaterializeRecurringTasks(@[],@[series],D(@"2026-10-14 00:00"),D(@"2026-12-01 00:00"),@{},NULL);Check(tasks.count==1,@"completion mode starts with one occurrence");NSMutableDictionary *done=[tasks[0] mutableCopy];done[@"completed"]=@YES;done[@"completedAt"]=D(@"2026-10-16 22:00");tasks=DDLMaterializeRecurringTasks(@[done],@[series],D(@"2026-10-16 00:00"),D(@"2026-12-01 00:00"),@{},NULL);Check(tasks.count==2 && [tasks[1][@"due"] isEqual:D(@"2026-10-23 20:00")],@"successor uses completion date with selected wall time");Check(DDLMaterializeRecurringTasks(tasks,@[series],D(@"2026-10-16 00:00"),D(@"2026-12-01 00:00"),@{},NULL).count==2,@"completion retrigger does not duplicate");done[@"completed"]=@NO;tasks=@[done,tasks[1]];Check(DDLMaterializeRecurringTasks(tasks,@[series],D(@"2026-10-16 00:00"),D(@"2026-12-01 00:00"),@{},NULL).count==2,@"undo completion preserves generated successor");
    printf("PASS: %d recurrence assertions\n",assertions);
}return 0;}
