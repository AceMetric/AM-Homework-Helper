#import "../Sources/DDLCore.h"
#import "../Sources/SSLocalData.h"
#import "../Sources/SSRecognition.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *text){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",text.UTF8String);exit(1);}}
int main(void){@autoreleasepool{
    NSCalendar *cal=[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];cal.timeZone=[NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    NSDate *now=DDLParseDate(@"2026-10-11 12:00",NSDate.date,cal),*due=DDLParseDate(@"2026-10-18 21:00",now,cal);
    Check(DDLPlanDate(@"2026-02-28",cal)!=nil && !DDLPlanDate(@"2026-02-30",cal),@"civil date validity");Check(!DDLPlanDate(@"2026-2-03",cal),@"canonical plan keys only");
    NSMutableDictionary *task=[@{@"id":@"task",@"title":@"模拟报告",@"due":due,@"notes":@"用户备注",@"plannedDate":@"2026-10-12",@"subtasks":@[@{@"id":@"sub",@"title":@"完成实验",@"completed":@NO,@"plannedDate":@"2026-10-13"}]} mutableCopy];
    Check(DDLPlanningValid(task),@"new planning fields accepted");NSMutableDictionary *broken=task.mutableCopy;broken[@"subtasks"]=@[@{@"id":@"bad",@"title":@"",@"completed":@NO}];Check(!DDLPlanningValid(broken),@"invalid children rejected without silent loss");
    broken[@"subtasks"]=@[task[@"subtasks"][0],task[@"subtasks"][0]];Check(!DDLPlanningValid(broken),@"duplicate child IDs rejected");Check(DDLNormalizeTasks(@[broken]).count==0,@"normalization rejects invalid planning record");
    NSArray *week=DDLWeekSections(@[task],now,1,cal,@"");Check([week[0][@"id"] isEqual:@"2026-10-12"] && [week[6][@"id"] isEqual:@"2026-10-18"],@"week runs Monday to Sunday");Check([week[0][@"items"] count]==1 && [week[1][@"items"] count]==1,@"parent and child have independent plans");
    Check([DDLWeekSections(@[task],now,1,cal,@"实验")[1][@"items"] count]==1,@"search includes child title");
    NSDictionary *completed=DDLTaskCompletion(task,YES);Check([completed[@"completed"] boolValue] && [completed[@"subtasks"][0][@"completed"] boolValue],@"parent completion completes remaining steps");Check(![task[@"subtasks"][0][@"completed"] boolValue],@"completion leaves original snapshot unchanged");Check([DDLWeekSections(@[completed],now,1,cal,@"")[0][@"items"] count]==0,@"completed work hidden from weekly plan");
    for(NSString *field in @[@"deleted",@"archived"]){NSMutableDictionary *hidden=task.mutableCopy;hidden[field]=@YES;Check([DDLWeekSections(@[hidden],now,1,cal,@"")[1][@"items"] count]==0,@"hidden parent hides child plan");}
    task[@"plannedDate"]=@"2026-10-01";Check([DDLWeekSections(@[task],now,0,cal,@"")[7][@"items"] count]==1,@"past incomplete plans need rescheduling");[task removeObjectForKey:@"plannedDate"];Check([DDLWeekSections(@[task],now,0,cal,@"")[8][@"items"] count]==1,@"unplanned work has its own section");
    cal.timeZone=[NSTimeZone timeZoneWithName:@"America/Los_Angeles"];Check([DDLPlanKey(DDLPlanDate(@"2026-10-13",cal),cal) isEqual:@"2026-10-13"],@"plan date remains same in another timezone");
    task[@"plannedDate"]=@"2026-10-12";
    NSDictionary *record=@{@"id":@"source",@"title":@"新名称",@"kind":@"assignment",@"due":due,@"blobSHA":@"v2",@"repository":@"teacher/course",@"path":@"report.md"};NSDictionary *updated=SSReviewedTask(record,@{@"title":@"新名称",@"assignmentDue":due,@"dateConfirmed":@YES},task,NULL);Check([updated[@"subtasks"] isEqual:task[@"subtasks"]] && [updated[@"notes"] isEqual:task[@"notes"]] && [updated[@"plannedDate"] isEqual:task[@"plannedDate"]],@"source update preserves user steps and notes");
    Check(SSSaveTasks(@[],@[task],NULL),@"plan and steps persist through task store");Check([SSLoadTasks(NULL) isEqual:@[task]],@"all planning fields survive restart");
    NSData *backup=[NSPropertyListSerialization dataWithPropertyList:@[task] format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];NSArray *imported=DDLNormalizeTasks([NSPropertyListSerialization propertyListWithData:backup options:0 format:NULL error:NULL]);Check([imported[0][@"subtasks"] isEqual:task[@"subtasks"]],@"backup roundtrip preserves planning fields");
    Check(DDLPlanningValid(@{@"id":@"legacy",@"title":@"旧任务",@"due":due}),@"legacy tasks remain unplanned and childless");
    printf("PASS: %lu planning and compatibility assertions\n",(unsigned long)checks);
}return 0;}
