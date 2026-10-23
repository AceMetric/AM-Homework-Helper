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
    NSMutableDictionary *cacheOnly=settings.mutableCopy;cacheOnly[@"cacheOnly"]=@YES;
    NSDictionary *deferred=[git enhanceScan:scan course:course settings:cacheOnly paths:nil cache:cache];Check(Calls(settings)==0 && ![deferred[@"modelCompleted"] boolValue] && [deferred[@"modelSummary"][@"pending"] integerValue]==3,@"rules phase never sends pending model work and reports it accurately");
    NSDictionary *enhanced=[git enhanceScan:scan course:course settings:settings paths:nil cache:cache];
    if([enhanced[@"candidates"] count]!=2 || [enhanced[@"materials"] count]!=1)fprintf(stderr,"fixture groups: assignments=%lu materials=%lu calls=%lu\n",(unsigned long)[enhanced[@"candidates"] count],(unsigned long)[enhanced[@"materials"] count],(unsigned long)Calls(settings));
    Check(Calls(settings)==3 && [enhanced[@"candidates"] count]==2 && [enhanced[@"materials"] count]==1,@"serial enhancement preserves homework count and grouped exam");
    Check([enhanced[@"modelCompleted"] boolValue] && [enhanced[@"candidates"][0][@"summary"] length]>0,@"model result has validated summary and completion state");
    NSData *saved=[NSPropertyListSerialization dataWithPropertyList:cache format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];cache=[[NSPropertyListSerialization propertyListWithData:saved options:NSPropertyListImmutable format:NULL error:NULL] mutableCopy];
    [git enhanceScan:scan course:course settings:settings paths:nil cache:cache];Check(Calls(settings)==3,@"unchanged source reuses model cache");
    NSMutableDictionary *manual=settings.mutableCopy;manual[@"manualLocal"]=@YES;manual[@"forceRecognition"]=@YES;manual[@"localAutomatic"]=@NO;
    [git enhanceScan:scan course:course settings:manual paths:@[paths[0]] cache:cache];Check(Calls(settings)==4,@"manual selection bypasses only that source cache");
    NSMutableDictionary *disabled=settings.mutableCopy;disabled[@"localAutomatic"]=@NO;
    Check([[git enhanceScan:scan course:course settings:disabled paths:nil cache:cache] isEqual:scan] && Calls(settings)==4,@"disabled automatic does not contact model");
    NSMutableDictionary *changed=settings.mutableCopy;changed[@"modelDigest"]=@"replacement-digest";
    [git enhanceScan:scan course:course settings:changed paths:nil cache:cache];Check(Calls(settings)==4,@"model digest change preserves completed unchanged sources until explicit reanalysis");
    changed[@"model"]=@"invalid-fixture";changed[@"forceRecognition"]=@YES;NSDictionary *failed=[git enhanceScan:scan course:course settings:changed paths:nil cache:cache];
    Check([failed[@"recognitionMessages"] count]==3 && [failed[@"candidates"] count]==2 && ![failed[@"modelCompleted"] boolValue],@"invalid responses retain rules and remain retryable");
    [git enhanceScan:scan course:course settings:changed paths:@[paths[0]] cache:cache];Check(Calls(settings)==12,@"failed analysis is not cached as success");
    NSString *partialText=@"# Assignment A\nWrite a report.\n# Assignment B\nDraw a diagram.";NSDictionary *partialDoc=@{@"repository":@"teacher/fixture",@"path":@"assignment/README.md",@"blobSHA":@"partial-v1",@"text":partialText,@"timeZone":calendar.timeZone.name};
    NSDictionary *partialScan=@{@"documents":@[partialDoc],@"candidates":SSRecognizeDocument(partialText,@"teacher/fixture",partialDoc[@"path"],@"partial-v1",calendar,@{@"mode":@"rules"},cache,NULL),@"materials":@[],@"commit":@"partial-head"};NSMutableDictionary *partialSettings=settings.mutableCopy;partialSettings[@"model"]=@"partial-fixture";NSMutableDictionary *partialCache=NSMutableDictionary.dictionary;
    NSDictionary *part=[git enhanceScan:partialScan course:course settings:partialSettings paths:nil cache:partialCache];BOOL kept=NO;for(NSDictionary *row in part[@"candidates"])if([row[@"suggestedTitle"] isEqual:@"第一份报告"] && [row[@"summary"] isEqual:@"写报告。"])kept=YES;
    Check(kept && [part[@"modelSummary"][@"failed"] integerValue]==1 && [part[@"modelFailures"] count]==1,@"scanner retains valid model proposal despite a rejected peer and counts one failed document");
    NSData *partialData=[NSPropertyListSerialization dataWithPropertyList:partialCache format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];partialCache=[[NSPropertyListSerialization propertyListWithData:partialData options:NSPropertyListImmutable format:NULL error:NULL] mutableCopy];NSUInteger beforeRestart=Calls(settings);partialSettings[@"cacheOnly"]=@YES;NSDictionary *restored=[git enhanceScan:partialScan course:course settings:partialSettings paths:nil cache:partialCache];kept=NO;for(NSDictionary *row in restored[@"candidates"])if([row[@"suggestedTitle"] isEqual:@"第一份报告"])kept=YES;Check(kept && Calls(settings)==beforeRestart && [restored[@"modelSummary"][@"failed"] integerValue]==1,@"restarting into cache-only scan restores partial proposals and concrete failure without a model call");
    git.scanCheckpoint=^BOOL(NSDictionary *stored,NSError **problem){*problem=[NSError errorWithDomain:@"fixture-storage" code:1 userInfo:@{NSLocalizedDescriptionKey:@"模拟写入失败"}];return NO;};NSMutableDictionary *saveSettings=settings.mutableCopy;saveSettings[@"forceRecognition"]=@YES;NSDictionary *notSaved=[git enhanceScan:scan course:course settings:saveSettings paths:@[paths[0]] cache:cache];Check(![notSaved[@"modelCompleted"] boolValue] && [notSaved[@"modelSummary"][@"unsaved"] integerValue]>=1 && [notSaved[@"persistenceIssue"] length]>0 && [notSaved[@"candidates"] count]>=2,@"checkpoint write failure never reports successful completion");git.scanCheckpoint=nil;
    NSMutableDictionary *compatibility=settings.mutableCopy;compatibility[@"model"]=@"no-schema-fixture";NSUInteger beforeCapability=Calls(settings);NSError *capabilityError=nil;[SSRecognitionClient.new extract:texts[0] settings:compatibility error:&capabilityError];Check(!capabilityError && Calls(settings)==beforeCapability+2,@"unsupported schema falls back once within original budget");[SSRecognitionClient.new extract:texts[1] settings:compatibility error:&capabilityError];Check(!capabilityError && Calls(settings)==beforeCapability+3,@"capability is reused across client instances and documents");compatibility[@"modelDigest"]=@"new-model-identity";[SSRecognitionClient.new extract:texts[0] settings:compatibility error:&capabilityError];Check(!capabilityError && Calls(settings)==beforeCapability+5,@"changed model identity invalidates capability cache");
    printf("PASS: %lu local model integration assertions\n",(unsigned long)checks);
}return 0;}
