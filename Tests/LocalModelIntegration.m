#import <Foundation/Foundation.h>
#import "../Sources/SSRecognition.h"
#import "../Sources/SSGit.h"
#import "../Sources/SSAssignments.h"
static NSUInteger checks;
static void Check(BOOL pass,NSString *message){checks++;if(!pass){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
static NSUInteger Calls(NSDictionary *settings){return [[SSRecognitionClient.new localModels:settings error:NULL].firstObject[@"digest"] integerValue];}
int main(int argc,const char *argv[]){@autoreleasepool{
    if(argc!=2)return 2;NSDictionary *settings=@{@"mode":@"local",@"endpoint":@(argv[1]),@"model":@"installed-fixture"};
    NSCalendar *calendar=NSCalendar.currentCalendar.copy;calendar.timeZone=[NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    NSArray *texts=@[@"# 作业一\n截止：2027年4月14日21:00 UTC+8\n完成报告。",@"# 作业二\n截止：2027年4月15日21:00 UTC+8\n完成实验。",@"# 入门考试\n## Q1 project_assignment\n解答本题。"];
    NSArray *paths=@[@"assignment/a.md",@"assignment/b.md",@"intro_exam/Q1.md"];
    NSMutableArray *documents=NSMutableArray.array,*assignments=NSMutableArray.array,*materials=NSMutableArray.array;NSMutableDictionary *cache=NSMutableDictionary.dictionary;
    for(NSUInteger i=0;i<texts.count;i++){[documents addObject:@{@"repository":@"teacher/fixture",@"path":paths[i],@"blobSHA":@"source-v1",@"text":texts[i],@"timeZone":calendar.timeZone.name}];for(NSDictionary *record in SSRecognizeDocument(texts[i],@"teacher/fixture",paths[i],@"source-v1",calendar,@{@"mode":@"rules"},cache,NULL))if([record[@"kind"] isEqual:@"assignment"])[assignments addObject:record];else[materials addObject:record];}
    NSDictionary *scan=@{@"documents":documents,@"candidates":assignments,@"materials":SSGroupMaterials(materials),@"commit":@"fixed-version"};
    NSDictionary *course=@{@"fork":@"student/fixture",@"upstream":@"teacher/fixture",@"path":@"/synthetic/fixture"};SSGit *git=SSGit.new;
    Check(assignments.count==2 && [scan[@"materials"] count]==1 && Calls(settings)==0,@"rules are ready before any model request");
    NSDictionary *enhanced=[git enhanceScan:scan course:course settings:settings paths:nil cache:cache];
    Check(Calls(settings)==3 && [enhanced[@"candidates"] count]==2 && [enhanced[@"materials"] count]==1,@"serial enhancement preserves homework count and grouped exam");
    Check([enhanced[@"modelCompleted"] boolValue] && [enhanced[@"candidates"][0][@"summary"] length]>0,@"model result has validated summary and completion state");
    [git enhanceScan:scan course:course settings:settings paths:nil cache:cache];Check(Calls(settings)==3,@"unchanged source reuses model cache");
    NSMutableDictionary *manual=settings.mutableCopy;manual[@"manualLocal"]=@YES;manual[@"forceRecognition"]=@YES;manual[@"localAutomatic"]=@NO;
    [git enhanceScan:scan course:course settings:manual paths:@[paths[0]] cache:cache];Check(Calls(settings)==4,@"manual selection bypasses only that source cache");
    NSMutableDictionary *disabled=settings.mutableCopy;disabled[@"localAutomatic"]=@NO;
    Check([[git enhanceScan:scan course:course settings:disabled paths:nil cache:cache] isEqual:scan] && Calls(settings)==4,@"disabled automatic does not contact model");
    NSMutableDictionary *changed=settings.mutableCopy;changed[@"modelDigest"]=@"replacement-digest";
    [git enhanceScan:scan course:course settings:changed paths:nil cache:cache];Check(Calls(settings)==7,@"model digest change reanalyzes unchanged sources");
    changed[@"model"]=@"invalid-fixture";NSDictionary *failed=[git enhanceScan:scan course:course settings:changed paths:nil cache:cache];
    Check([failed[@"recognitionMessages"] count]==3 && [failed[@"candidates"] count]==2 && ![failed[@"modelCompleted"] boolValue],@"invalid responses retain rules and remain retryable");
    [git enhanceScan:scan course:course settings:changed paths:@[paths[0]] cache:cache];Check(Calls(settings)==11,@"failed analysis is not cached as success");
    printf("PASS: %lu local model integration assertions\n",(unsigned long)checks);
}return 0;}
