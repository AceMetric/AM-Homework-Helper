#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
static int checks;
static void Check(BOOL value,NSString *message){checks++;if(!value){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
@interface EnhancementGit:SSGit
@property NSDictionary *scan;
@property NSArray *selectedPaths;
@property NSDictionary *approvedSettings;
@property NSUInteger calls;
@end
@implementation EnhancementGit
- (NSDictionary *)scanCourse:(NSDictionary *)course cache:(NSMutableDictionary *)cache error:(NSError **)error{return self.scan;}
- (NSDictionary *)enhanceScan:(NSDictionary *)scan course:(NSDictionary *)course settings:(NSDictionary *)settings paths:(NSArray *)paths cache:(NSMutableDictionary *)cache{self.calls++;self.selectedPaths=paths;self.approvedSettings=settings;return scan;}
@end
@interface EnhancementController:SSCourseController @end
@implementation EnhancementController
- (void)work:(NSString *)message forCourse:(NSDictionary *)course requestKey:(NSString *)key priority:(NSInteger)priority operation:(id (^)(NSError **))op completion:(void (^)(id,NSError *))done{[self work:message forCourse:course operation:op completion:done];}
- (void)work:(NSString *)message forCourse:(NSDictionary *)course operation:(id (^)(NSError **))operation completion:(void (^)(id,NSError *))completion{NSError *error=nil;id value=operation(&error);completion(value,error);}
@end
int main(){@autoreleasepool {
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    SSWritePlist(@"recognition-settings.plist",@{@"mode":@"cloud",@"endpoint":@"https://api.example.invalid/v1",@"model":@"mock",@"cloudConsent":@YES,@"cloudCourses":@[@"student/example"]},NULL);
    EnhancementController *controller=[[EnhancementController alloc] initWithPreview:YES];NSMutableDictionary *course=[@{@"fork":@"student/example",@"upstream":@"teacher/example",@"branch":@"main",@"upstreamBranch":@"main",@"path":@"/synthetic/teacher-scope"} mutableCopy];[controller.courses addObject:course];[controller selectCourseID:course[@"fork"]];
    EnhancementGit *git=EnhancementGit.new;git.scan=@{@"documents":@[@{@"path":@"a.md",@"text":@"# Assignment A\nSubmit a report.",@"blobSHA":@"a"},@{@"path":@"b.md",@"text":@"# Assignment B\nSubmit a diagram.",@"blobSHA":@"b"}],@"candidates":@[],@"materials":@[],@"commit":@"v"};controller.git=git;
    __block NSUInteger previews=0;controller.recognitionScopeSelector=^NSArray *(PFMaterials *materials){previews++;return @[];};[controller.assistantButton performClick:nil];Check(previews==1 && git.calls==0,@"empty confirmed scope makes no model request");
    controller.recognitionScopeSelector=^NSArray *(PFMaterials *materials){previews++;[materials.excluded addObject:@"b.md"];return [materials selectedSnapshot][@"paths"];};[controller.assistantButton performClick:nil];Check(previews==2 && git.calls==1 && [git.selectedPaths isEqual:@[@"a.md"]],@"real AI button uses only selected teacher material");Check([git.approvedSettings[@"manualCloud"] boolValue],@"manual approval passed only for this operation");
    NSDictionary *routine=SSCourseRecognitionSettings(SSRecognitionSettings(),course);Check([routine[@"mode"] isEqual:@"rules"],@"scope approval never changes background scan consent");Check(controller.tasksProvider==nil,@"enhancement cannot import or complete personal tasks");
    printf("PASS: %d AI enhancement interaction assertions\n",checks);
}return 0;}
