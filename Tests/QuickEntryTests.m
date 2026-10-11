#import <Cocoa/Cocoa.h>
#import "../Sources/SSRecognition.h"
#import "../Sources/DDLCore.h"
#import "../Sources/DDLImport.h"
#import "../Sources/SSLocalData.h"
static NSUInteger assertions;
static void Check(BOOL ok,NSString *label){assertions++;if(!ok){fprintf(stderr,"FAIL: %s\n",label.UTF8String);exit(1);}}
int main(void){@autoreleasepool{
    NSCalendar *cal=[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];cal.timeZone=[NSTimeZone timeZoneWithName:@"Asia/Shanghai"];NSDate *now=DDLParseDate(@"2026-10-11 09:00",NSDate.date,cal);
    NSString *text=@"物理作业：完成运动报告\n截止：2026 年 10 月 20 日 18:00";NSArray *entries=AMQuickParse(text,@"source",now,cal);Check(entries.count==1,@"one notice captured");NSDictionary *task=AMQuickTask(entries.firstObject,NULL);Check(task && [AMQuickDateText(task[@"due"],cal.timeZone.name) isEqual:@"2026-10-20 18:00"],@"spaced date auto filled");Check([task[@"entryReferenceDate"] isEqual:now] && [task[@"entryTimeZone"] isEqual:cal.timeZone.name],@"message date basis and zone survive task persistence");Check(!task[@"sourceRepository"] && task[@"entrySourceID"],@"local source does not fake GitHub identity");
    entries=AMQuickParse(@"完成数学作业\n截止：2026年10月20日",@"s",now,cal);Check(entries.count==1 && !AMQuickTask(entries.firstObject,NULL),@"missing clock remains draft, not 23:59");Check(!DDLFieldsFromAnnouncement(@"完成数学作业，截止2026年10月20日",now,cal)[@"due"],@"legacy announcement parser also rejects missing clock");
    entries=AMQuickParse(@"物理实验报告\n截止：明天21:00",@"s",now,cal);Check(AMQuickTask(entries.firstObject,NULL)!=nil && [entries.firstObject[@"hint"] containsString:@"推算"],@"relative date uses explicit reference with warning");
    entries=AMQuickParse(@"1. 完成数学作业\n截止：2026-10-20 18:00\n2. 完成物理报告\n截止：2026-10-21 20:00",@"s",now,cal);Check(entries.count==2,@"multiple homework candidates");
    NSArray *ambiguous=AMQuickParse(@"完成作业\n截止：2026-10-20 18:00 或 2026-10-21 20:00",@"dates",now,cal);Check(!AMQuickTask(ambiguous.firstObject,NULL),@"ambiguous deadlines require confirmation");
    NSDictionary *material=AMQuickMaterial(text,now,cal.timeZone.name),*batch=@{@"id":@"batch",@"version":material[@"version"]};NSDictionary *activity=@{@"kind":@"assignment",@"title":@"运动报告",@"summary":@"分析实验数据。",@"submissionRequirements":@"提交报告。",@"evidence":text,@"deadlineEvidence":@"截止：2026 年 10 月 20 日 18:00"};
    NSDictionary *result=@{@"format":@"am-local-results-v1",@"batchID":@"batch",@"documents":@[@{@"sourceID":material[@"id"],@"version":material[@"version"],@"activities":@[activity]}]};NSDictionary *valid=AMQuickValidateResult(result,material,batch,NULL);Check([valid[@"entries"] count]==1,@"local Skill evidence accepted without Git");Check([valid[@"entries"][0][@"notes"] containsString:@"分析实验数据"],@"summary prefilled in editable notes");
    NSMutableDictionary *bad=result.mutableCopy;bad[@"batchID"]=@"other";Check(!AMQuickValidateResult(bad,material,batch,NULL),@"wrong batch rejected");NSMutableDictionary *a=activity.mutableCopy;a[@"evidence"]=@"invented text";bad=result.mutableCopy;bad[@"documents"]=@[@{@"sourceID":material[@"id"],@"version":material[@"version"],@"activities":@[a]}];Check(![AMQuickValidateResult(bad,material,batch,NULL)[@"entries"] count],@"invented evidence rejected");
    Check(!AMQuickValidateResult(@{},@{},batch,NULL),@"missing local material rejected without crash");
    NSArray *invalid=AMQuickParse(@"完成作业\n截止：2026-02-30 18:00",@"x",now,cal);Check(!AMQuickTask(invalid.firstObject,NULL),@"invalid civil date remains draft");
    NSArray *utc=AMQuickParse(@"完成作业\n截止：2026-10-20 18:00 UTC+0",@"utc",now,cal);Check([AMQuickDateText(AMQuickTask(utc.firstObject,NULL)[@"due"],@"GMT") isEqual:@"2026-10-20 18:00"],@"explicit time zone survives parse and save");
    NSMutableDictionary *entry=[valid[@"entries"][0] mutableCopy];entry[@"notes"]=@"";entry[@"edited"]=@YES;task=AMQuickTask(entry,NULL);Check([task[@"notes"] isEqual:@""] && [task[@"notesUserEdited"] boolValue],@"explicitly cleared notes preserved");Check(SSWritePlist(@"quick-entry.plist",@{@"entries":@[entry]},NULL) && [SSReadPlist(@"quick-entry.plist")[@"entries"][0][@"notes"] isEqual:@""],@"draft persistence retains cleared notes");
    printf("PASS: %lu quick entry assertions\n",(unsigned long)assertions);
}return 0;}
