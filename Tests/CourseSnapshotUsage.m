#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
@interface SnapshotChangeReader:SSGit @end
@implementation SnapshotChangeReader
- (NSArray *)changesForCourse:(NSDictionary *)course error:(NSError **)error{return @[@{@"path":@"assignment/answer.md",@"status":@"M",@"sensitive":@NO}];}
@end
int main(){@autoreleasepool{
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    SSCourseController *controller=[[SSCourseController alloc] initWithPreview:YES];(void)controller.view;
    controller.inbox=YES;controller.tableRows=@[@{@"id":@"synthetic-a",@"title":@"Old snapshot",@"tableDisplayState":@"待审核"}];
    NSTableColumn *column=[[NSTableColumn alloc] initWithIdentifier:@"title"];
    Check([controller numberOfRowsInTableView:controller.table]==1,@"row count uses persistent table snapshot");
    NSTextField *cell=(id)[controller tableView:controller.table viewForTableColumn:column row:0];Check([cell.stringValue isEqual:@"Old snapshot"],@"drawing uses same generation");
    controller.presentationRows=@[];[controller endPresentationSnapshot];
    cell=(id)[controller tableView:controller.table viewForTableColumn:column row:0];Check([cell.stringValue isEqual:@"Old snapshot"],@"ending render scope does not discard table data");
    controller.tableRows=@[];Check([controller tableView:controller.table viewForTableColumn:column row:0]==nil,@"late callback after deletion is safe");
    Check([controller tableView:controller.table viewForTableColumn:column row:-1]==nil,@"negative row is safe");
    controller.tableRows=@[@"malformed"];Check([controller tableView:controller.table viewForTableColumn:column row:0]==nil,@"invalid record type is safe");
    controller.inbox=NO;controller.sections.selectedSegment=0;Check([controller numberOfRowsInTableView:controller.table]==0,@"hidden legacy table has zero rows on board");
    Check([controller tableView:controller.table viewForTableColumn:column row:0]==nil,@"board cannot draw legacy rows");
    SSSubmissionController *session=[[SSSubmissionController alloc] initWithCourse:@{@"fork":@"student/synthetic",@"branch":@"main"} changes:@[@{@"path":@"answer.md",@"status":@"M"}]];
    session.embeddedPane=[[AMSubmissionPane alloc] initWithFrame:NSMakeRect(0,0,320,650)];session.embeddedPane.session=session;[session publishEmbeddedState];
    Check(session.embeddedPane.buttons.count==1,@"embedded adapter shows actual session changes");
    NSButton *check=session.embeddedPane.buttons[0];[check performClick:nil];Check(check.state==session.checks[0].state,@"native file click updates session selection");
    session.embeddedPane.message.stringValue=@"User draft";[session.embeddedPane controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:session.embeddedPane.message]];
    Check(session.messageEdited && [session.message.stringValue isEqual:@"User draft"],@"embedded edits update the shared draft");
    [session replaceFileChanges:@[@{@"path":@"answer.md",@"status":@"M"},@{@"path":@"second.md",@"status":@"?"}]];[session publishEmbeddedState];
    Check([session.embeddedPane.message.stringValue isEqual:@"User draft"],@"refresh preserves edited message");
    session.submissionInFlight=YES;[session publishEmbeddedState];Check(!session.embeddedPane.primary.enabled && !session.embeddedPane.message.enabled,@"only submission form locks during its write");
    session.submissionInFlight=NO;session.closed=NO;
    NSWindow *formWindow=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,320,650) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];formWindow.releasedWhenClosed=NO;formWindow.contentView=session.embeddedPane;
    __block NSUInteger safetyChecks=0,submissions=0;
    session.performCheck=^NSDictionary *(NSArray *paths,NSArray *ids,NSString *extra,NSMutableDictionary *cache,BOOL(^cancelled)(void),NSError **error){safetyChecks++;Check([cache[@"submissionSafetyOnly"] boolValue],@"embedded click uses shared submission safety phase");return @{@"snapshot":@{@"version":@"synthetic",@"files":@{}}};};
    session.submit=^(NSArray *paths,NSString *message){submissions++;Check(paths.count>0 && [message isEqual:@"User draft"],@"shared transaction receives exact embedded selection and draft");};
    [session.embeddedPane.all performClick:nil];[session publishEmbeddedState];Check(session.embeddedPane.primary.enabled,@"form can submit selected changes");[session.embeddedPane.primary performClick:nil];
    NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:5];while(!submissions && limit.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    Check(safetyChecks==1 && submissions==1,@"native embedded submit click runs one safety check and one transaction");
    SSSubmissionController *owned=[[SSSubmissionController alloc] initWithCourse:@{@"fork":@"student/synthetic",@"branch":@"main"} changes:@[]];owned.selectOwnedNewFiles=YES;owned.scopePaths=@[@"assignment"];
    [owned replaceFileChanges:@[@{@"path":@"assignment/answer.md",@"status":@"M"},@{@"path":@"other.md",@"status":@"M"}]];
    Check([[owned chosenPaths] isEqual:@[@"assignment/answer.md"]],@"only unambiguously owned changes are selected by default");owned.checks[0].state=NSControlStateValueOff;[owned selectionChanged:nil];[owned replaceFileChanges:owned.allFileChanges];Check(![owned chosenPaths].count,@"refresh preserves explicit deselection of an owned file");
    NSDictionary *course=@{@"fork":@"student/synthetic-refresh",@"upstream":@"teacher/synthetic-refresh",@"branch":@"main",@"upstreamBranch":@"main",@"path":@"/synthetic/no-real-repository"};[controller.courses addObject:course.mutableCopy];controller.preview=NO;controller.git=SnapshotChangeReader.new;controller.embeddingSubmission=YES;[controller openSubmissionForCourse:course preserving:nil];controller.embeddingSubmission=NO;
    NSDate *readLimit=[NSDate dateWithTimeIntervalSinceNow:5];while(controller.submission.filesPreparing && readLimit.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    SSSubmissionController *embedded=controller.submission;embedded.embeddedPane=[[AMSubmissionPane alloc] initWithFrame:NSMakeRect(0,0,320,650)];embedded.embeddedPane.session=embedded;embedded.submittedSuccessfully=YES;[embedded publishEmbeddedState];[embedded.embeddedPane.reload performClick:nil];
    readLimit=[NSDate dateWithTimeIntervalSinceNow:5];while(embedded.filesPreparing && readLimit.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    if(embedded.filesPreparing || controller.submission!=embedded || embedded.window.sheetParent)fprintf(stderr,"refresh debug: preparing=%d same=%d parent=%s status=%s\n",embedded.filesPreparing,controller.submission==embedded,embedded.window.sheetParent.description.UTF8String,embedded.filesValidation.stringValue.UTF8String);
    Check(!embedded.filesPreparing && controller.submission==embedded && !embedded.window.sheetParent,@"native embedded refresh preserves session and never opens a sheet");Check(!embedded.submittedSuccessfully,@"fresh changes after success start a new eligible transaction");
    [formWindow orderOut:nil];
    printf("PASS: %lu snapshot and embedded submission assertions\n",(unsigned long)checks);
}}
