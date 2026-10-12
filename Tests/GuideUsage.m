#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
static NSUInteger count;
static void Check(BOOL value,NSString *label){count++;if(!value){fprintf(stderr,"FAIL: %s\n",label.UTF8String);exit(1);}}
static void Wait(BOOL(^ready)(void)){NSDate *end=[NSDate dateWithTimeIntervalSinceNow:4];while(!ready() && end.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];Check(ready(),@"operation completes");}
static void Capture(NSView *v,NSString *name){[v layoutSubtreeIfNeeded];[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];NSBitmapImageRep *b=[v bitmapImageRepForCachingDisplayInRect:v.bounds];[v cacheDisplayInRect:v.bounds toBitmapImageRep:b];Check([[b representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[@"build/qa/" stringByAppendingString:name] atomically:YES],@"synthetic interface capture");}
@interface GuideHub:SSGitHub @end
@implementation GuideHub
- (NSArray *)accessibleForks:(NSError **)error {return @[@{@"full_name":@"student/course"}];}
@end
@interface GuideGit:SSGit @end
@implementation GuideGit
- (BOOL)linkCourse:(NSDictionary *)course error:(NSError **)error {return [course[@"path"] hasPrefix:@"/synthetic/"];}
@end
@interface GuideController:SSCourseController
@property NSUInteger scans;
@property NSArray *scanned;
@end
@implementation GuideController
- (void)work:(NSString *)message forCourse:(NSDictionary *)course operation:(id(^)(NSError **))op completion:(void(^)(id,NSError *))done {self.busy=YES;dispatch_async(self.queue,^{NSError *error=nil;id value=op(&error);dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;done(value,error);});});}
- (void)scanCourses:(NSArray *)courses {self.scans++;self.scanned=courses;self.firstCheckRunning=NO;[self updateCourseSetup:@"模拟检查完成，未发现新作业。"];}
@end
int main(void){@autoreleasepool{
    Check([NSProcessInfo.processInfo.arguments containsObject:@"--preview"],@"preview only");[NSApplication sharedApplication];
    AppDelegate *app=AppDelegate.new;NSApp.delegate=app;[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
    [app startUsing:nil];Check(app.page==5 && !app.helpController.view.hidden && app.courseWindow.view.hidden && !app.window.attachedSheet,@"getting started opens embedded help without a modal chooser");
    for(NSString *name in @[@"light",@"dark",@"compact"]){app.window.appearance=[NSAppearance appearanceNamed:[name isEqual:@"dark"] ? NSAppearanceNameDarkAqua:NSAppearanceNameAqua];[app.window setContentSize:[name isEqual:@"compact"] ? NSMakeSize(960,640):NSMakeSize(1280,840)];[app layout];Capture(app.window.contentView,[NSString stringWithFormat:@"help-%@.png",name]);Check(app.helpController.view.frame.size.width>600,@"help fits minimum main window");}
    GuideController *guide=[[GuideController alloc] initWithPreview:YES];guide.git=GuideGit.new;NSWindow *host=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1000,800) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];host.contentView=guide.view;
    __block BOOL local=NO;guide.localStart=^{local=YES;};[guide setup:nil];Check(guide.setupStep==0 && guide.setupWindow.sheetParent==host,@"new user reaches welcome without authentication");
    for(NSString *name in @[@"light",@"dark"]){guide.setupWindow.appearance=[NSAppearance appearanceNamed:[name isEqual:@"dark"] ? NSAppearanceNameDarkAqua:NSAppearanceNameAqua];Capture(guide.setupWindow.contentView,[NSString stringWithFormat:@"welcome-%@.png",name]);}
    [guide handleSetupAction:@{@"action":@"local"}];Check(local && !guide.setupWindow && guide.courses.count==0,@"local start needs neither login nor course and preserves data");
    guide.connected=YES;[guide saveConfiguredCourse:@{@"fork":@"student/course",@"upstream":@"teacher/course"} error:NULL];guide.setupStep=2;guide.setupRecords=[@[[ @{@"fork":@"student/course",@"course":@{@"fork":@"student/course",@"upstream":@"teacher/course"},@"path":@"/synthetic/course",@"ready":@NO} mutableCopy]] mutableCopy];[guide presentCourseSetup];
    [guide handleSetupAction:@{@"action":@"link-check",@"selected":@[@"student/course"],@"paths":@{@"student/course":@"/synthetic/course"}}];Wait(^BOOL{return guide.scans==1;});Check(guide.courses.count==1 && guide.setupStep==3 && guide.scanned.count==1,@"one confirmation links and starts first check once");
    guide.setupRecords[0][@"checkFailed"]=@YES;[guide handleSetupAction:@{@"action":@"retry-check"}];Check(guide.scans==2 && guide.scanned.count==1,@"retry targets failed ready course");guide.setupRecords[0][@"checkFailed"]=@NO;[guide handleSetupAction:@{@"action":@"retry-check"}];Check(guide.scans==2,@"successful courses not rescanned by failure retry");
    guide.firstCheckRunning=YES;[guide finishSetupScan:nil error:[NSError errorWithDomain:@"Test" code:NSUserCancelledError userInfo:@{NSLocalizedDescriptionKey:@"检查取消"}] courses:guide.scanned];Check(!guide.firstCheckRunning && [guide.setupRecords[0][@"checkFailed"] boolValue] && [guide.setupRecords[0][@"status"] containsString:@"取消"],@"cancelled first check is recoverable and never presented as zero homework");
    guide.busy=YES;[guide handleSetupAction:@{@"action":@"close"}];Check(!guide.setupWindow && guide.busy,@"guide can close while background operation continues");guide.busy=NO;guide.preview=NO;SSWritePlist(@"onboarding.plist",@{@"completed":@YES,@"localOnly":@YES},NULL);[guide presentCourseSetup];Check(![SSReadPlist(@"onboarding.plist")[@"completed"] boolValue],@"reopening configuration after local-only use permits resumable progress");guide.preview=YES;[guide closeCourseSetup];guide.github=GuideHub.new;[guide presentCourseSetup];[guide addFork:nil];[guide handleSetupAction:@{@"action":@"close"}];Wait(^BOOL{return !guide.busy && guide.availableForks.count==1;});Check(!guide.setupWindow,@"background course-list completion does not reopen a dismissed guide");
    [host orderOut:nil];[app.window orderOut:nil];printf("PASS: %lu guide, local-start and embedded-help assertions\n",(unsigned long)count);
}return 0;}
