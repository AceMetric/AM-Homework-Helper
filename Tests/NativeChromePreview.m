// Local visual review application. Built only with DDL_TESTING and isolated storage.
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
#import "NativeControlGallery.inc"
@interface ChromePreviewCourse:SSCourseController
@property BOOL showingProgressSample;
@end
@implementation ChromePreviewCourse
- (void)commit:(id)sender {
    if(self.window.attachedSheet)return;
    NSArray *changes=@[@{@"path":@"report.md",@"status":@"M"},@{@"path":@"analysis.py",@"status":@"M"},@{@"path":@"images/diagram.png",@"status":@"??"}];
    self.submission=[[SSSubmissionController alloc] initWithCourse:@{@"fork":@"demo/physics",@"branch":@"main"} changes:changes];
    [self.submission configureTasks:self.tasksProvider ? self.tasksProvider():@[] selected:@[]];
    self.submission.readPreview=^(NSString *path,void(^ready)(NSString *)){ready([[@"diff --git a/report.md b/report.md\n+ # 模拟实验报告\n" stringByPaddingToLength:7000 withString:@"+ 整理实验结果，并解释单位与误差来源。\n" startingAtIndex:0] stringByAppendingString:@"+ 完整预览结束\n"]);};
    self.submission.performCheck=^NSDictionary *(NSArray *paths,NSArray *tasks,NSString *extra,NSMutableDictionary *cache,BOOL(^cancelled)(void),NSError **error){NSString *text=@"# 模拟实验报告\n\nTODO: 补充实验结论\n";NSData *data=[text dataUsingEncoding:NSUTF8StringEncoding];NSDictionary *snapshot=@{@"paths":@[@"report.md"],@"version":@"preview-only",@"files":@{@"report.md":@{@"text":text,@"data":data,@"version":AMPreflightHash(data)}}};return @{@"snapshot":snapshot,@"requirements":extra ?: @"",@"report":AMPreflightCheck(snapshot,extra,cache,cancelled)};};
    __weak typeof(self) owner=self;self.submission.submit=^(NSArray *paths,NSString *message){[owner status:@"模拟预览结束：没有暂存、提交或推送文件。"];};
    [self.window beginSheet:self.submission.window completionHandler:nil];
}
- (void)scan:(id)sender {[self status:@"模拟检查完成：真实课程未被读取。"];}
- (void)showProgressSample {
    self.showingProgressSample=YES;self.busy=YES;self.git.readsCancellable=YES;self.git.cancelledReads=NO;self.cancelReadButton.enabled=YES;self.operationFork=@"demo/physics";self.statusFork=self.operationFork;[self.progress startAnimation:nil];[self status:@"本地模型分析材料与附件：assignment.md（模拟进度，可拖动窗口检查布局）"];
}
- (void)cancelReadOperation:(id)sender {
    if(!self.showingProgressSample){[super cancelReadOperation:sender];return;}
    self.showingProgressSample=NO;self.busy=NO;self.git.readsCancellable=NO;self.operationFork=nil;[self.progress stopAnimation:nil];[self status:@"模拟检查已取消，没有读取真实课程或调用模型。"];
}
- (void)sync:(id)sender {[self status:@"界面预览不执行同步。"];}
- (void)accountSettings:(id)sender {[self status:@"界面预览无需登录，也不读取真实凭据。"];}
@end
@interface ChromePreviewApp:AppDelegate
@property AMNativeControlGallery *gallery;
@property NSString *progressSampleOperationID;
@end
@implementation ChromePreviewApp
- (BOOL)preview{return YES;}
- (SSCourseController *)makeCourseController {return [[ChromePreviewCourse alloc] initWithPreview:YES];}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [super applicationDidFinishLaunching:notification];
    for(NSArray *spec in @[@[@"模拟物理课程",@"physics"],@[@"模拟计算机课程",@"programming"],@[@"模拟数学课程",@"mathematics"]]) {
        NSString *fork=[@"demo/" stringByAppendingString:spec[1]],*upstream=[@"example/" stringByAppendingString:spec[1]];
        [self.courseWindow.courses addObject:[@{@"fork":fork,@"name":spec[0],@"upstream":upstream,@"enabled":@YES,@"defaultBranch":@"main",@"branch":@"main",@"path":SSDataDirectory().path} mutableCopy]];
        self.courseWindow.candidates[fork]=@[@{@"id":[@"visual-review-" stringByAppendingString:spec[1]],@"title":[spec[0] stringByAppendingString:@"实验报告"],@"kind":@"assignment",@"repository":upstream,@"path":@"assignment.md",@"blobSHA":@"synthetic",@"due":[NSDate dateWithTimeIntervalSinceNow:3*86400],@"summary":@"整理实验过程，解释结果并说明误差来源。",@"submissionRequirements":@"提交 Markdown 报告和对应图片。",@"snippet":@"实验报告：整理实验过程，解释结果并说明误差来源。",@"line":@1,@"timeZone":@"Asia/Shanghai"}];
    }
    [self.courseWindow refreshCourses];[self openList:nil];[self render];
    NSString *revision=[NSBundle.mainBundle objectForInfoDictionaryKey:@"AMPreviewRevision"];self.window.title=[@"AM Helper 界面预览 · " stringByAppendingString:revision ?: @""];
    NSMenu *menu=NSApp.windowsMenu;
    for(NSArray *spec in @[@[@"任务编辑表单…",@"showEditorSample:"],@[@"原生控件样例…",@"showGallery:"],@[@"任务页样例",@"showTasksSample:"],@[@"课程页样例",@"showCourseSample:"],@[@"课程检查进度样例",@"showCourseProgressSample:"],@[@"提交与预览样例…",@"showSubmissionSample:"]]){NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:spec[0] action:NSSelectorFromString(spec[1]) keyEquivalent:@""];item.target=self;[menu addItem:item];}

    __block NSString *operation;operation=AMOperationBegin(@"检查文件",@"模拟作业项目",YES,^{AMOperationFinish(operation,@"cancelled",@"模拟检查已取消");});self.progressSampleOperationID=operation;AMOperationProgress(operation,@"检查文件与图片",12,37);
    NSString *finished=AMOperationBegin(@"检查所有课程",@"模拟课程",NO,nil);AMOperationFinish(finished,@"success",@"检查完成，发现 3 项待审核作业");
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    // These samples intentionally never finish on their own. Stop only the
    // simulated work before using the normal draft and real-operation checks.
    AMOperationCancel(self.progressSampleOperationID);
    ChromePreviewCourse *course=(ChromePreviewCourse *)self.courseWindow;
    if(course.showingProgressSample)[course cancelReadOperation:nil];
    return [super applicationShouldTerminate:sender];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {return YES;}
- (void)showGallery:(id)sender{if(!self.gallery)self.gallery=AMNativeControlGallery.new;[self.gallery.window makeKeyAndOrderFront:nil];}
- (void)showEditorSample:(id)sender{if(self.editor)return;self.editor=[[EditorController alloc] initWithTask:self.tasks.firstObject owner:self];[self.window beginSheet:self.editor.window completionHandler:nil];}
- (void)showTasksSample:(id)sender{[self openList:nil];}
- (void)showCourseSample:(id)sender{NSButton *button=NSButton.new;button.identifier=@"demo/physics";[self selectSidebarCourse:button];}
- (void)showCourseProgressSample:(id)sender{[self showCourseSample:nil];[(ChromePreviewCourse *)self.courseWindow showProgressSample];}
- (void)showSubmissionSample:(id)sender{[self showCourseSample:nil];[self.courseWindow commit:nil];}
@end
#ifndef AM_PREVIEW_NO_MAIN
int main(){@autoreleasepool {
    if(![NSBundle.mainBundle objectForInfoDictionaryKey:@"DDLTestDataDirectory"])return 2;
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];ChromePreviewApp *app=ChromePreviewApp.new;NSApp.delegate=app;[NSApp run];
}return 0;}

#endif
