#import <Foundation/Foundation.h>
#import "../Sources/SSRecognition.h"
#import "../Sources/SSAssignments.h"
#import "../Sources/DDLCore.h"
#import "../Sources/SSLocalData.h"
@interface FixtureCloudClient:SSRecognitionClient @end
@implementation FixtureCloudClient
- (NSString *)cloudKeyForEndpoint:(NSString *)endpoint {return @"synthetic-api-fixture";}
@end
static NSUInteger assertions;
static void Check(BOOL pass,NSString *message){assertions++;if(!pass){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
int main(void){@autoreleasepool{
    NSCalendar *calendar=NSCalendar.currentCalendar.copy;calendar.timeZone=[NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    NSString *text=@"# 作业六\n截止：2027 年 4 月 14 日（星期三）21:00 UTC+8\n## 任务\n完成运动分析。\n提交报告，命名为 homework.md。\n";
    NSMutableDictionary *cache=NSMutableDictionary.dictionary;NSError *error=nil;
    NSArray *records=SSRecognizeDocument(text,@"teacher/course",@"homework.md",@"v1",calendar,@{@"mode":@"rules"},cache,&error);
    Check(records.count==1 && !error,@"explicit homework recognized");
    NSDictionary *sectioned=SSRecognizeDocument(@"# 作业六\n截止：2027年4月14日21:00\n## 作业目标\n分析运动过程。\n## 作业选题\n完成实验。\n## 提交要求\n提交最终报告。",@"t/c",@"s.md",@"s1",calendar,@{@"mode":@"rules"},cache,NULL).firstObject;
    Check([sectioned[@"snippet"] containsString:@"提交最终报告"] && [sectioned[@"summary"] containsString:@"分析运动"],@"generic homework subheadings do not truncate the actual activity");NSDictionary *record=records.firstObject;
    Check([record[@"summary"] containsString:@"完成运动分析"] && [record[@"submissionRequirements"] containsString:@"homework.md"],@"rules extract content and submission requirements");
    Check(SSCanAutomaticallyImport(record,@[],DDLParseDate(@"2027-04-01 00:00",NSDate.date,calendar)),@"complete future source date auto imports");
    Check(!SSCanAutomaticallyImport(record,@[],DDLParseDate(@"2028-04-01 00:00",NSDate.date,calendar)),@"historical homework stays in review");
    NSDictionary *task=SSReviewedTask(record,@{},nil,&error);Check(task && [task[@"sourceID"] isEqual:record[@"id"]],@"review shares normalization and source identity");
    Check(!SSCanAutomaticallyImport(record,@[task],NSDate.date),@"existing task never silently imports again");
    NSMutableDictionary *existing=task.mutableCopy;existing[@"title"]=@"自己编辑的标题";existing[@"notes"]=@"自己的备注";existing[@"leadDays"]=@(-1);existing[@"due"]=[task[@"due"] dateByAddingTimeInterval:-12345];
    NSDictionary *edited=SSReviewedTask(record,@{@"title":existing[@"title"]},existing,&error);
    Check([edited[@"notes"] isEqual:existing[@"notes"]] && [edited[@"due"] isEqual:existing[@"due"]],@"update preserves manually edited content and personal DDL");
    NSDictionary *dateOnly=SSRecognizeDocument(@"# 作业七\n截止：2027年4月14日\n完成报告。",@"t/c",@"a.md",@"v",calendar,@{@"mode":@"rules"},cache,NULL).firstObject;
    Check(!SSCanAutomaticallyImport(dateOnly,@[],NSDate.date),@"missing time cannot auto import");error=nil;
    Check(!SSReviewedTask(dateOnly,@{},nil,&error) && error,@"missing date completion cannot save");
    Check(SSReviewedTask(dateOnly,@{@"teacherDue":task[@"due"],@"dateConfirmed":@YES},nil,NULL)!=nil,@"explicit date completion permits review save");
    NSDictionary *relative=SSRecognizeDocument(@"# 作业八\n截止：本周日21:00\n完成报告。",@"t/c",@"a.md",@"r",calendar,@{@"mode":@"rules"},cache,NULL).firstObject;
    Check(!SSCanAutomaticallyImport(relative,@[],NSDate.date) && !relative[@"due"],@"relative dates remain review proposals");
    NSMutableString *longText=[text mutableCopy];for(NSUInteger i=0;i<30;i++)[longText appendString:@"详细说明：观察实验现象并整理数据。\n"];
    [longText appendString:@"最后提交附件：完整计算过程。\n"];
    NSDictionary *longRecord=SSRecognizeDocument(longText,@"t/c",@"long.md",@"l",calendar,@{@"mode":@"rules"},cache,NULL).firstObject;
    Check([longRecord[@"snippet"] containsString:@"最后提交附件"] && [longRecord[@"submissionRequirements"] containsString:@"完整计算过程"],@"late requirements are not truncated");
    NSDictionary *model=@{@"kind":@"assignment",@"title":@"运动分析与报告",@"summary":@"分析运动。",@"submissionRequirements":@"提交报告。",@"evidence":text,@"deadlineEvidence":@"截止：2027 年 4 月 14 日（星期三）21:00 UTC+8"};
    NSDictionary *validated=SSValidatedModelResults(@[model],text,@"teacher/course",@"homework.md",@"v1",calendar,NULL).firstObject;
    Check([validated[@"id"] isEqual:record[@"id"]] && [validated[@"suggestedTitle"] isEqual:model[@"title"]],@"generated title does not change original identity");
    NSMutableDictionary *brief=model.mutableCopy;brief[@"evidence"]=@"提交报告，命名为 homework.md。";
    Check([SSValidatedModelResults(@[brief],text,@"teacher/course",@"homework.md",@"v1",calendar,NULL).firstObject[@"id"] isEqual:record[@"id"]],@"submission evidence plus original deadline keeps existing source identity");
    NSMutableDictionary *renamed=model.mutableCopy;renamed[@"title"]=@"另一种概括";
    Check([SSValidatedModelResults(@[renamed],text,@"teacher/course",@"homework.md",@"v1",calendar,NULL).firstObject[@"id"] isEqual:record[@"id"]],@"rephrasing cannot create duplicate identity");
    renamed[@"deadlineEvidence"]=@"截止：2099年1月1日23:59";
    Check(!SSValidatedModelResults(@[renamed],text,@"t/c",@"a.md",@"v",calendar,NULL).count,@"invented deadline evidence is rejected");
    renamed=model.mutableCopy;renamed[@"evidence"]=@"not in document";
    Check(!SSValidatedModelResults(@[renamed],text,@"t/c",@"a.md",@"v",calendar,NULL).count,@"unverifiable source is rejected");
    Check(!SSValidatedModelResults(@[NSNull.null],text,@"t/c",@"a.md",@"v",calendar,NULL).count,@"malformed model item is harmless");
    NSString *exam=@"# 入门考试\n## Q1 project_assignment\n解答下列问题。\n";renamed=model.mutableCopy;renamed[@"evidence"]=exam;renamed[@"deadlineEvidence"]=@"";
    NSDictionary *examRecord=SSValidatedModelResults(@[renamed],exam,@"t/c",@"intro_exam/Q1.md",@"v",calendar,NULL).firstObject;
    Check([examRecord[@"kind"] isEqual:@"exam"] && !SSCanAutomaticallyImport(examRecord,@[],NSDate.date),@"exam context wins over assignment wording/model");
    Check(!SSValidateRecognitionSettings(@{@"mode":@"local",@"endpoint":@"http://external.example.invalid",@"model":@"test"},NULL),@"local mode cannot send to remote host");
    Check(!SSValidateRecognitionSettings(@{@"mode":@"cloud",@"endpoint":@"http://api.example.invalid/v1",@"model":@"test"},NULL),@"cloud requires TLS");
    Check(!SSValidateRecognitionSettings(@{@"mode":@"cloud",@"endpoint":[NSString stringWithFormat:@"https://%@%c%@@example.invalid/v1",@"synthetic-user",':',@"synthetic-secret"],@"model":@"test"},NULL),@"credentials cannot enter endpoint");
    Check(SSValidateRecognitionSettings(@{@"mode":@"local",@"endpoint":@"http://localhost:11434",@"model":@"installed-model"},NULL),@"local endpoint accepted");
    SSRecognitionClient *client=SSRecognitionClient.new;__block NSURLRequest *request=nil;
    client.transport=^NSData *(NSURLRequest *value,NSError **failure){request=value;NSData *content=[NSJSONSerialization dataWithJSONObject:@{@"activities":@[model]} options:0 error:NULL];return [NSJSONSerialization dataWithJSONObject:@{@"message":@{@"content":[[NSString alloc] initWithData:content encoding:NSUTF8StringEncoding]}} options:0 error:NULL];};
    Check([[client extract:text settings:@{@"mode":@"local",@"endpoint":@"http://localhost:11434",@"model":@"installed-model"} error:NULL] count]==1,@"Ollama structured transport parsed");
    Check([request.URL.path isEqual:@"/api/chat"] && ![request valueForHTTPHeaderField:@"Authorization"],@"local transport receives no API credentials");
    id body=[NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:NULL];Check(!body[@"tools"] && [body[@"format"] isEqual:@"json"],@"documents cannot invoke model tools");
    client.transport=^NSData *(NSURLRequest *value,NSError **failure){return [@"{}" dataUsingEncoding:NSUTF8StringEncoding];};error=nil;
    Check(![client extract:text settings:@{@"mode":@"local",@"endpoint":@"http://localhost:11434",@"model":@"installed-model"} error:&error] && error,@"invalid response provides fallback error");
    __block NSURLRequest *redirect=request;[client URLSession:NSURLSession.sharedSession task:[NSURLSession.sharedSession dataTaskWithRequest:request] willPerformHTTPRedirection:[[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:302 HTTPVersion:@"HTTP/1.1" headerFields:@{}] newRequest:request completionHandler:^(NSURLRequest *value){redirect=value;}];Check(!redirect,@"model requests never forward credentials across redirects");
    Check(SSValidateCourseTemplate(@{@"titlePattern":@"^Topic: (.+)$"},NULL),@"bounded local course template accepted");
    Check(!SSValidateCourseTemplate(@{@"unknown":@".*"},NULL),@"unrecognized template field rejected");
    NSArray *templated=SSRecognizeDocument(@"Topic: 实验报告\nWork: 完成运动数据分析\nBy: 2027年4月20日21:00",@"t/c",@"report.md",@"t1",calendar,@{@"mode":@"rules",@"courseTemplate":@{@"titlePattern":@"^Topic: (.+)$",@"contentPattern":@"^Work: (.+)$",@"deadlinePattern":@"^By: (.+)$"}},cache,NULL);
    Check(templated.count==1 && [templated[0][@"summary"] isEqual:@"完成运动数据分析"] && [templated[0][@"due"] isKindOfClass:NSDate.class],@"template extracts otherwise missed activity, summary, exact date");
    Check(!SSCanAutomaticallyImport(templated[0],@[],NSDate.date),@"template-only discovery requires type/date review");
    NSDictionary *basis=@{@"date":NSDate.date,@"commit":@"synthetic-commit"};NSMutableDictionary *withBasis=record.mutableCopy;withBasis[@"dateBasis"]=basis;
    Check([SSReviewedTask(withBasis,@{},nil,NULL)[@"sourceDateBasis"] isEqual:basis],@"review retains relative-date provenance");
    FixtureCloudClient *cloud=FixtureCloudClient.new;__block NSUInteger calls=0;
    cloud.transport=^NSData *(NSURLRequest *value,NSError **failure){calls++;*failure=[NSError errorWithDomain:@"Fixture" code:1 userInfo:nil];return nil;};
    NSDictionary *cloudSettings=@{@"mode":@"cloud",@"endpoint":@"https://api.example.invalid/v1",@"model":@"fixture",@"cloudConsent":@YES};
    NSMutableDictionary *withoutConsent=cloudSettings.mutableCopy;withoutConsent[@"cloudConsent"]=@NO;
    Check(![cloud extract:text settings:withoutConsent error:NULL] && calls==0,@"no course text sent without explicit cloud consent");
    for(NSUInteger i=0;i<21;i++)[cloud extract:text settings:cloudSettings error:NULL];
    Check(calls==20 && [SSReadPlist(@"recognition-usage.plist")[@"count"] unsignedIntegerValue]==20,@"failed requests count toward persisted daily cloud cap");
    error=nil;Check(![cloud extract:text settings:cloudSettings error:&error] && [error.localizedDescription containsString:@"20"],@"cap prevents more requests and explains fallback");
    SSWritePlist(@"recognition-usage.plist",@{@"day":@"2000-01-01",@"count":@20},NULL);
    [cloud extract:text settings:cloudSettings error:NULL];Check(calls==21 && [SSReadPlist(@"recognition-usage.plist")[@"count"] unsignedIntegerValue]==1,@"daily counter rolls over without storing API key");
    NSDictionary *document=@{@"repository":@"teacher/course",@"path":@"homework.md",@"blobSHA":@"v1",@"text":text,@"timeZone":@"Asia/Shanghai"};
    NSDictionary *skillDocument=@{@"repository":@"teacher/course",@"path":@"homework.md",@"blobSHA":@"v1",@"activities":@[model]};
    NSDictionary *skill=@{@"format":@"am-course-results-v1",@"documents":@[skillDocument]};error=nil;
    NSArray *skillResults=SSValidatedSkillResults(skill,@[document],@[withBasis],&error);
    Check(skillResults.count==1 && !error && [skillResults[0][@"id"] isEqual:record[@"id"]] && [skillResults[0][@"sourceID"] length]==0,@"Skill result remains a source proposal, not a persisted task");
    Check([skillResults[0][@"dateBasis"] isEqual:basis] && !SSCanAutomaticallyImport(skillResults[0],@[],NSDate.date),@"Skill retains commit provenance and always requires review");
    NSMutableDictionary *stale=skillDocument.mutableCopy;stale[@"blobSHA"]=@"old";
    Check(!SSValidatedSkillResults(@{@"format":@"am-course-results-v1",@"documents":@[stale]},@[document],@[],NULL),@"Skill cannot import stale source version");
    stale=skillDocument.mutableCopy;stale[@"repository"]=@"other/course";
    Check(!SSValidatedSkillResults(@{@"format":@"am-course-results-v1",@"documents":@[stale]},@[document],@[],NULL),@"Skill cannot import another course");
    Check(!SSValidatedSkillResults(@{@"format":@"am-course-results-v1",@"documents":@[NSNull.null]},@[document],@[],NULL),@"malformed Skill document cannot mutate tasks");
    NSDictionary *scoped=@{@"mode":@"cloud",@"cloudCourses":@[@"student/math"]};
    Check([SSCourseRecognitionSettings(scoped,@{@"fork":@"student/math"})[@"mode"] isEqual:@"cloud"],@"selected course can use cloud enhancement");
    Check([SSCourseRecognitionSettings(scoped,@{@"fork":@"student/other"})[@"mode"] isEqual:@"rules"],@"unselected course uses rules without transmitting material");
    NSMutableDictionary *linked=record.mutableCopy;linked[@"path"]=@"assignments/a.md";linked[@"snippet"]=@"阅读 [题目](../resources/exercises.md)。外链 [example](https://example.invalid/a.md)";
    NSDictionary *attachment=@{@"repository":@"teacher/course",@"path":@"resources/exercises.md",@"blobSHA":@"a1",@"text":@"解答指定题目。"};
    NSArray *withLinks=SSAttachLinkedDocuments(@[linked],@[attachment]);
    Check([withLinks[0][@"attachments"] count]==1 && [withLinks[0][@"id"] isEqual:record[@"id"]],@"repository-relative document link adds source content without changing identity or following external URL");
    printf("PASS: %lu recognition assertions\n",(unsigned long)assertions);
}return 0;}
