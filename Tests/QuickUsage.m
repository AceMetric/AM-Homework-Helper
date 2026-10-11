#ifndef AM_FOREGROUND_TEST
#import "QuietUI.h"
#endif
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
static NSUInteger checks;
static void Check(BOOL ok,NSString *label){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",label.UTF8String);exit(1);}}
#ifdef AM_FOREGROUND_TEST
static id CaptureElement(id root,NSString *identity){NSMutableArray *pending=[NSMutableArray arrayWithObject:root];NSHashTable *seen=[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];while(pending.count){id object=pending.lastObject;[pending removeLastObject];if([seen containsObject:object])continue;[seen addObject:object];if([object respondsToSelector:@selector(accessibilityIdentifier)] && [[object accessibilityIdentifier] isEqual:identity])return object;if([object respondsToSelector:@selector(accessibilityChildren)])[pending addObjectsFromArray:[object accessibilityChildren] ?: @[]];if([object isKindOfClass:NSView.class])[pending addObjectsFromArray:[object subviews]];if([object isKindOfClass:NSWindow.class])[pending addObject:[object contentView]];}return nil;}
static void CaptureView(NSView *view,NSString *path){NSBitmapImageRep *image=[view bitmapImageRepForCachingDisplayInRect:view.bounds];[view cacheDisplayInRect:view.bounds toBitmapImageRep:image];Check([[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],@"synthetic capture screenshot");}
#endif
@interface CaptureApp:AppDelegate @end
@implementation CaptureApp
- (void)loadPreview {}
- (void)refreshReminders {}
@end
int main(void){@autoreleasepool{
    Check(NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"].length>0,@"isolated capture UI");[NSApplication sharedApplication];
#ifdef AM_FOREGROUND_TEST
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
#else
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
#endif
    CaptureApp *app=CaptureApp.new;NSApp.delegate=app;[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
    [app quickEntry:nil];Check(app.quickController && app.quickWindow.sheetParent==app.window,@"capture opens without GitHub");
#ifdef AM_FOREGROUND_TEST
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.3]];
    CaptureView(app.quickController.view,@"build/qa/capture-probe.png");
    id input=CaptureElement(app.quickWindow,@"quick-input"),parse=CaptureElement(app.quickWindow,@"quick-parse");Check(input && parse,@"quick controls reachable through accessibility");
    [(NSTextView *)input setString:@"完成数学作业\n截止：2026-10-20 18:00"];[(NSTextView *)input didChangeText];[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.2]];Check([parse isKindOfClass:NSButton.class] && [(NSButton *)parse isEnabled],@"real parse button enabled");[(NSButton *)parse performClick:nil];[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.2]];Check([app.quickState[@"entries"] count]==1,@"real input and button produce a candidate");
    for(NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){app.quickWindow.appearance=[NSAppearance appearanceNamed:appearance];[app.quickController.view layoutSubtreeIfNeeded];[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.2]];CaptureView(app.quickController.view,[NSString stringWithFormat:@"build/qa/capture-%@.png",[appearance isEqual:NSAppearanceNameAqua] ? @"light":@"dark"]);}
    [app.quickWindow setContentSize:NSMakeSize(650,640)];[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.2]];CaptureView(app.quickController.view,@"build/qa/capture-compact.png");
#endif
    NSMutableDictionary *payload=app.quickController.snapshot.mutableCopy;payload[@"text"]=@"完成数学作业\n截止：2026-10-20 18:00";[app quickAction:@"parse" payload:payload];Check([app.quickState[@"entries"] count]==1,@"real quick action parses notice");NSDictionary *entry=app.quickState[@"entries"][0];Check([app.quickController.snapshot[@"entries"][0][@"dateText"] length]>10,@"automatic deadline reaches real editor");
    app.preview=NO;Check([app persistQuick:NULL],@"draft persists before close");[app closeQuick];[app quickEntry:nil];Check([app.quickController.snapshot[@"text"] isEqual:payload[@"text"]],@"close and reopen keep draft");
    NSDictionary *material=app.quickState[@"material"];NSString *batch=NSUUID.UUID.UUIDString;NSDictionary *job=@{@"id":batch,@"version":material[@"version"],@"sourceID":material[@"id"],@"state":@"等待助手",@"date":NSDate.date};app.quickState[@"jobs"]=@{batch:job};
    NSMutableDictionary *edited=entry.mutableCopy;edited[@"notes"]=@"";edited[@"title"]=@"我的标题";edited[@"edited"]=@YES;app.quickState[@"entries"]=@[edited];[app refreshQuick:nil];
    NSDictionary *result=@{@"format":@"am-local-results-v1",@"batchID":batch,@"documents":@[@{@"sourceID":material[@"id"],@"version":material[@"version"],@"activities":@[@{@"kind":@"assignment",@"title":@"模型标题",@"summary":@"概括",@"submissionRequirements":@"",@"evidence":material[@"text"],@"deadlineEvidence":@"截止：2026-10-20 18:00"}]}]};
    NSURL *draftURL=[SSDataDirectory() URLByAppendingPathComponent:@"quick-entry.plist"];NSData *draftData=[NSData dataWithContentsOfURL:draftURL];[NSFileManager.defaultManager removeItemAtURL:draftURL error:NULL];[NSFileManager.defaultManager createDirectoryAtURL:draftURL withIntermediateDirectories:NO attributes:nil error:NULL];
    [app receiveQuickResult:result batch:job];Check(![app.quickState[@"jobs"][batch][@"received"] boolValue],@"failed result persistence does not consume batch");[NSFileManager.defaultManager removeItemAtURL:draftURL error:NULL];[draftData writeToURL:draftURL atomically:YES];
    [app receiveQuickResult:result batch:job];Check([app.quickState[@"entries"][0][@"title"] isEqual:@"我的标题"] && [app.quickState[@"entries"][0][@"notes"] isEqual:@""],@"late assistant preserves edited title and cleared notes");Check([app.courseWindow allPendingReviewCandidates].count==1,@"local proposal enters shared review without course scan");
    NSDictionary *record=[app.courseWindow allPendingReviewCandidates].firstObject;NSDate *changed=DDLParseDate(@"2026-10-22 20:00",NSDate.date,NSCalendar.currentCalendar);NSURL *tasksURL=[SSDataDirectory() URLByAppendingPathComponent:@"tasks.plist"];[NSFileManager.defaultManager removeItemAtURL:tasksURL error:NULL];[NSFileManager.defaultManager createDirectoryAtURL:tasksURL withIntermediateDirectories:NO attributes:nil error:NULL];
    NSString *failed=[app saveReviewItems:@[@{@"record":record,@"draft":@{@"title":@"最终作业",@"notes":@"我的说明",@"assignmentDue":changed,@"dateConfirmed":@YES}}] automatic:NO];Check(failed.length && app.tasks.count==0 && [app quickPendingEntries].count==1,@"failed task persistence preserves review and draft");[NSFileManager.defaultManager removeItemAtURL:tasksURL error:NULL];
    NSString *failure=[app saveReviewItems:@[@{@"record":record,@"draft":@{@"title":@"最终作业",@"notes":@"我的说明",@"assignmentDue":changed,@"dateConfirmed":@YES}}] automatic:NO];Check(!failure.length && app.tasks.count==1,@"shared review saves local homework");Check([app.tasks[0][@"due"] isEqual:changed] && [app.tasks[0][@"notes"] isEqual:@"我的说明"],@"edited deadline and notes persisted");Check([app.courseWindow allPendingReviewCandidates].count==0,@"saved capture leaves review immediately");
    [app receiveQuickResult:result batch:job];Check(app.tasks.count==1 && [app quickPendingEntries].count==0,@"late repeated result cannot duplicate saved work");Check([SSLoadTasks(NULL) count]==1,@"saved quick task reloads from disk");
    [app refreshQuick:nil];Check(![app.quickController.snapshot[@"entries"] count],@"capture editor removes entries saved through shared review");
    [app parseQuick];Check([app quickPendingEntries].count==1 && ![app.quickState[@"material"][@"id"] isEqual:material[@"id"]],@"intentional repeat capture receives new identity for duplicate preview");
    NSURL *finished=[app quickFolder:batch];[NSFileManager.defaultManager createDirectoryAtURL:finished withIntermediateDirectories:YES attributes:nil error:NULL];[app cleanQuickJobs:YES];Check(![NSFileManager.defaultManager fileExistsAtPath:finished.path] && [app.quickState[@"jobs"][batch][@"cleaned"] boolValue],@"completed local packages cleaned without losing progress");
#ifndef AM_FOREGROUND_TEST
    NSMutableDictionary *repeat=[app.quickState[@"entries"][0] mutableCopy];repeat[@"title"]=@"最终作业";repeat[@"dateText"]=AMQuickDateText(changed,repeat[@"timeZone"]);app.quickState[@"entries"]=@[repeat];
    [AMQuietDialogChoices addObject:@(NSAlertFirstButtonReturn)];[app saveQuick];Check(app.tasks.count==1 && [app quickPendingEntries].count==1,@"duplicate preview can skip existing task");
    [AMQuietDialogChoices addObject:@(NSAlertThirdButtonReturn)];[app saveQuick];Check(app.tasks.count==2 && ![app quickPendingEntries].count,@"user can deliberately add repeated notice");
#endif
    NSDictionary *backup=AMBackupEnvelope(app.tasks,NULL);Check([backup[@"format"] isEqual:@"am-helper-backup-v2"] && AMDecodeBackup(app.tasks,NULL),@"new and legacy backup formats accepted");Check(AMRestoreBackup(app.tasks,app.tasks,@[],NULL),@"restore tasks and empty records transaction");Check([SSLoadTasks(NULL)[0][@"notes"] isEqual:@"我的说明"],@"backup restore retains notes and local source");
    Check(!AMDecodeBackup(@{@"format":@"am-helper-backup-v2",@"tasks":app.tasks,@"submissions":@[@{}]},NULL),@"malformed record blocks entire import");
    app.preview=YES;[app closeQuick];[app.quickTimer invalidate];[app.ticker invalidate];[NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];printf("PASS: %lu quick capture UI, Skill and backup assertions\n",(unsigned long)checks);
}return 0;}
