#import "../Sources/SSRecognition.h"
#import "../Sources/SSAssignments.h"
#import "../Sources/DDLCore.h"
#import "../Sources/AMPrompts.h"
#include <stdio.h>
static int assertions;
static void Check(BOOL v,NSString *message){assertions++;if(!v){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
int main(){@autoreleasepool {
    NSCalendar *calendar=[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];calendar.timeZone=[NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    NSString *text=@"# Assignment A\nSubmit a short report.\n# Assignment B\nSubmit a diagram.\nDue: 2026-12-08 18:00\n";
    NSArray *rules=SSDiscoveriesFromDocument(text,@"teacher/example",@"notice.md",@"v1",NSDate.date,calendar);
    NSDictionary *a=@{@"kind":@"assignment",@"title":@"Short report",@"evidence":@"Submit a short report.",@"deadlineEvidence":@"Due: 2026-12-08 18:00"};
    NSDictionary *validated=SSValidatedModelResults(@[a],text,@"teacher/example",@"notice.md",@"v1",calendar,NULL).firstObject;
    Check(rules.count==2,@"two independent activities recognized");
#ifdef AM_EXPECT_OLD_BOUNDARY
    Check([validated[@"id"] isEqual:rules[1][@"id"]] && validated[@"due"],@"baseline reproduces wrong activity identity and borrowed deadline");
#else
    Check([validated[@"id"] isEqual:rules[0][@"id"]] && !validated[@"due"] && [validated[@"requiresReview"] boolValue],@"neighbor deadline cannot change ownership or fill missing date");
    NSString *repeated=@"# Assignment A\nSubmit a report.\nDue: 2026-12-08 18:00\n# Assignment B\nSubmit a report.\nDue: 2026-12-08 18:00\n";
    NSDictionary *ambiguous=@{@"kind":@"assignment",@"title":@"Report",@"evidence":@"Submit a report.",@"deadlineEvidence":@"Due: 2026-12-08 18:00"};
    Check(!SSValidatedModelResults(@[ambiguous],repeated,@"teacher/example",@"notice.md",@"v",calendar,NULL).count,@"repeated evidence without a span is not guessed");
    NSMutableDictionary *span=ambiguous.mutableCopy;span[@"startLine"]=@4;span[@"endLine"]=@6;NSArray *rr=SSDiscoveriesFromDocument(repeated,@"teacher/example",@"notice.md",@"v",NSDate.date,calendar);validated=SSValidatedModelResults(@[span],repeated,@"teacher/example",@"notice.md",@"v",calendar,NULL).firstObject;Check([validated[@"id"] isEqual:rr[1][@"id"]],@"verified original span disambiguates identical deadlines");
    NSString *shared=@"All assignments below are due: 2026-12-08 18:00\n# Assignment A\nSubmit a short report.\n# Assignment B\nSubmit a diagram.\n";NSMutableDictionary *m=a.mutableCopy;m[@"deadlineEvidence"]=@"All assignments below are due: 2026-12-08 18:00";m[@"deadlineShared"]=@YES;validated=SSValidatedModelResults(@[m],shared,@"teacher/example",@"notice.md",@"v",calendar,NULL).firstObject;Check(validated[@"due"]!=nil,@"explicit all-assignment original wording allows shared deadline");
    NSString *project=@"# Project: garden sensor\nBuild a sensor prototype.\n## Objectives\nMeasure light.\n## Submission requirements\nSubmit source and observations.\n";Check(SSActivityBlocks(project,@"project.md",NO).count==1,@"project goals and submission remain one activity");
    Check([AMCoursePrompt() containsString:@"shared deadline"] && [AMReviewPrompt() containsString:@"first invalid step"] && ![AMCoursePromptVersion() isEqual:AMCourseValidationVersion()],@"versioned prompts cover activity and project reasoning constraints");
#endif
    printf("PASS: %d activity boundary assertions\n",assertions);
}return 0;}
