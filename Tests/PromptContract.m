#import "../Sources/AMPrompts.h"
#import "../Sources/SSRecognition.h"
#import "../Sources/AMPreflight.h"
int main(int argc,const char *argv[]){@autoreleasepool{
 NSDictionary *out=nil;if(argc==2 && [@(argv[1]) isEqual:@"--export"]){out=@{@"course":AMCoursePrompt(),@"review":AMReviewPrompt(),@"notice":AMLocalNoticeGuidance(),@"focus":AMReviewFocusGuidance(),@"courseSchema":AMCourseOutputSchema(),@"reviewSchema":AMReviewOutputSchema(),@"examples":AMCourseExamples()};}
 else if(argc==2){NSDictionary *input=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:NULL];if(input[@"decode"]){id value=SSRecognitionJSONObject(input[@"decode"],YES);out=value ? @{@"valid":@YES,@"object":value}:@{@"valid":@NO};}
 else if(input[@"noticeText"]){NSDate *date=[NSISO8601DateFormatter.new dateFromString:@"2026-10-18T00:00:00Z"];NSMutableDictionary *m=[AMQuickMaterial(input[@"noticeText"],date,@"Asia/Shanghai") mutableCopy];m[@"referenceDate"]=[NSISO8601DateFormatter.new stringFromDate:date];out=m;}
 else if([input[@"kind"] isEqual:@"notice"]){NSMutableDictionary *m=[input[@"material"] mutableCopy];m[@"referenceDate"]=[NSISO8601DateFormatter.new dateFromString:m[@"referenceDate"]];NSError *error=nil;NSDictionary *r=AMQuickValidateResult(input[@"answer"],m,@{@"id":@"synthetic-batch",@"version":m[@"version"]},&error);out=@{@"complete":@(r!=nil && [r[@"issues"] count]==0),@"count":@([r[@"entries"] count])};}
 else if([input[@"kind"] isEqual:@"review"]){NSError *error=nil;NSDictionary *r=AMPreflightValidateResult(input[@"answer"],input[@"context"],&error);out=@{@"valid":@(r!=nil),@"complete":@(r!=nil && ![r[@"partial"] boolValue]),@"count":@([r[@"issues"] count])};}
 else {NSCalendar *cal=[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];cal.timeZone=[NSTimeZone timeZoneWithName:@"Asia/Shanghai"];NSDictionary *r=SSModelValidationReport(input[@"activities"],input[@"text"],@"teacher/synthetic",@"assignment/README.md",@"synthetic-v1",cal);out=@{@"count":@([r[@"records"] count]),@"complete":r[@"complete"],@"issues":r[@"issues"]};}}
 if(!out)return 2;NSData *data=[NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingSortedKeys error:NULL];fwrite(data.bytes,1,data.length,stdout);
}return 0;}
