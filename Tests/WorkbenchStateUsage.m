#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
static NSUInteger checks;
static void Check(BOOL value,NSString *message){checks++;if(!value){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
static NSString *Git(NSString *root,NSArray *args){NSTask *task=NSTask.new;task.executableURL=[NSURL fileURLWithPath:@"/usr/bin/git"];task.currentDirectoryURL=[NSURL fileURLWithPath:root];task.arguments=[@[@"-c",@"core.hooksPath=/dev/null",@"-c",@"commit.gpgSign=false"] arrayByAddingObjectsFromArray:args];NSMutableDictionary *env=NSProcessInfo.processInfo.environment.mutableCopy;env[@"GIT_CONFIG_GLOBAL"]=@"/dev/null";env[@"GIT_CONFIG_NOSYSTEM"]=@"1";task.environment=env;NSPipe *output=NSPipe.pipe;task.standardOutput=output;task.standardError=output;Check([task launchAndReturnError:NULL],@"synthetic git starts");NSData *data=[output.fileHandleForReading readDataToEndOfFile];[task waitUntilExit];Check(task.terminationStatus==0,@"synthetic git succeeds");return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];}
static NSView *Load(SSCourseController *controller,NSString *path){__block NSView *view=nil;__block NSDictionary *result=nil;[controller loadAssignmentWorkbench:@"task-cache" path:path mode:@"working" completion:^(NSDictionary *value,NSView *preview){result=value;view=preview;}];NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:8];while(!result && limit.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];if(!view)fprintf(stderr,"preview failure: %s\n",result.description.UTF8String);Check(result && view,@"actual working preview loads within budget");return view;}
int main(){@autoreleasepool{
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSString *root=NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"];Check(root.length>0,@"isolated synthetic repository required");
    Git(root,@[@"init",@"-b",@"main"]);Git(root,@[@"remote",@"add",@"origin",@"https://github.com/student/cache.git"]);Git(root,@[@"remote",@"add",@"upstream",@"https://github.com/teacher/cache.git"]);
    NSString *scope=[root stringByAppendingPathComponent:@"assignment-1"];[NSFileManager.defaultManager createDirectoryAtPath:scope withIntermediateDirectories:YES attributes:nil error:NULL];NSString *file=[scope stringByAppendingPathComponent:@"README.md"];
    [@"# Assignment\nSubmit report.md.\n" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:NULL];Git(root,@[@"add",@"."]);Git(root,@[@"-c",@"user.name=Synthetic",@"-c",@"user.email=synthetic@example.invalid",@"commit",@"-m",@"Synthetic template"]);
    NSString *head=Git(root,@[@"rev-parse",@"HEAD"]);
    SSCourseController *controller=[[SSCourseController alloc] initWithPreview:YES];NSMutableDictionary *course=[@{@"fork":@"student/cache",@"upstream":@"teacher/cache",@"branch":@"main",@"upstreamBranch":@"main",@"path":root,@"teacherCommit":head} mutableCopy];[controller.courses addObject:course];
    controller.tasksProvider=^NSArray *{return @[@{@"id":@"task-cache",@"title":@"Synthetic assignment",@"due":NSDate.date,@"sourceRepository":@"teacher/cache",@"sourcePath":@"assignment-1/README.md",@"completed":@YES}];};
    [controller selectCourseID:course[@"fork"]];[controller refreshPresentation];
    NSView *first=Load(controller,@"assignment-1/README.md"),*again=Load(controller,@"assignment-1/README.md");Check(first==again,@"unchanged material reuses the actual preview and reading state");
    [@"# Assignment\nSubmit report.md and explain the result.\n" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:NULL];NSView *changed=Load(controller,@"assignment-1/README.md");Check(changed!=first,@"changed content cannot reuse stale preview");
    __block NSDictionary *oldResult=nil,*newResult=nil;__block NSView *oldView=nil,*newView=nil;
    [controller loadAssignmentWorkbench:@"task-cache" path:@"assignment-1/README.md" mode:@"working" completion:^(NSDictionary *value,NSView *view){oldResult=value;oldView=view;}];
    [controller loadAssignmentWorkbench:@"task-cache" path:@"assignment-1/README.md" mode:@"working" completion:^(NSDictionary *value,NSView *view){newResult=value;newView=view;}];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:8];while((!oldResult || !newResult) && deadline.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    Check([oldResult[@"cancelled"] boolValue] && !oldView && newResult && newView,@"superseded reads never create or install another preview");
    Check([Git(root,@[@"rev-parse",@"HEAD"]) isEqual:head],@"preview never writes a commit or changes the branch");
    printf("PASS: %lu workbench version and preview reuse assertions\n",(unsigned long)checks);
}}
