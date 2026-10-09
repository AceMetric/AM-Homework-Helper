#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
static NSUInteger checks;
static void Check(BOOL value,NSString *label){checks++;if(!value){fprintf(stderr,"FAIL: %s\n",label.UTF8String);exit(1);}}
static void Drain(void){[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.12]];}
// Persist real tasks to the test directory, without scheduling system notifications.
@interface UsageApp:AppDelegate @end
@implementation UsageApp
- (void)refreshReminders {}
- (BOOL)replaceTasks:(NSArray *)tasks action:(NSString *)action error:(NSError **)error {
    self.preview=NO;BOOL ok=[super replaceTasks:tasks action:action error:error];self.preview=YES;return ok;
}
@end
static id Element(NSView *root,NSString *identity){
    NSMutableArray *pending=[NSMutableArray arrayWithObject:root];NSHashTable *seen=[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    while(pending.count){id object=pending.lastObject;[pending removeLastObject];if([seen containsObject:object])continue;[seen addObject:object];
        if([object respondsToSelector:@selector(accessibilityIdentifier)] && [[object accessibilityIdentifier] isEqual:identity])return object;
        if([object respondsToSelector:@selector(accessibilityChildren)])[pending addObjectsFromArray:[object accessibilityChildren] ?: @[]];
        if([object isKindOfClass:NSView.class])[pending addObjectsFromArray:[object subviews]];
    }return nil;
}
static void Press(NSView *root,NSString *identity){[root layoutSubtreeIfNeeded];NSBitmapImageRep *bitmap=[root bitmapImageRepForCachingDisplayInRect:root.bounds];[root cacheDisplayInRect:root.bounds toBitmapImageRep:bitmap];Drain();id button=Element(root,identity);Check([button isKindOfClass:NSButton.class] && [button isEnabled],@"real review button is enabled offscreen");[button performClick:nil];Drain();}
int main(int argc,const char *argv[]){@autoreleasepool{
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    UsageApp *app=UsageApp.new;NSApp.delegate=app;[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
    NSString *fixture=NSProcessInfo.processInfo.environment[@"AM_USAGE_FIXTURE"];
    NSDictionary *data=fixture ? [NSDictionary dictionaryWithContentsOfFile:fixture]:nil;
    NSArray *realCourses=data[@"courses"] ?: @[@{@"fork":@"student/course",@"upstream":@"teacher/course",@"enabled":@YES}];
    NSDictionary *discoveries=data[@"discoveries"];
    for(NSDictionary *document in data[@"documents"] ?: @[]){
        NSArray *found=SSRecognizeDocument(document[@"text"],document[@"repository"],document[@"path"],document[@"blob"],Cal(),@{@"mode":@"rules"},NSMutableDictionary.dictionary,NULL);
        Check(found.count>0,@"fixed upstream document remains recognized");
        if([document[@"path"] containsString:@"intro_exam"])for(NSDictionary *record in found)Check(![record[@"kind"] isEqual:@"assignment"],@"fixed exam material never becomes homework");
    }
    SSCourseController *courses=app.courseWindow;[courses.courses removeAllObjects];
    for(NSDictionary *course in realCourses){NSMutableDictionary *copy=course.mutableCopy;[copy removeObjectForKey:@"path"];[courses.courses addObject:copy];}
    if(discoveries){courses.candidates=[discoveries[@"candidates"] mutableCopy];courses.materials=[discoveries[@"materials"] mutableCopy];}
    else {courses.candidates[@"student/course"]=@[@{@"id":@"source",@"kind":@"assignment",@"repository":@"teacher/course",@"path":@"assignment.md",@"blobSHA":@"v1",@"title":@"模拟报告",@"due":[NSDate dateWithTimeIntervalSinceNow:86400]}];}
    courses.kindOverrides=[data[@"overrides"] mutableCopy] ?: NSMutableDictionary.dictionary;
    NSArray *tasks=DDLNormalizeTasks(data[@"tasks"] ?: @[]);app.tasks=NSMutableArray.array;
    NSButton *route=NSButton.new;route.tag=3;[app navigate:route];[courses refreshPresentation];
    NSUInteger discovered=courses.allPendingReviewCandidates.count;
    Check(discovered>0,@"local fixed course fixture has assignments");
    for(NSDictionary *source in courses.allPendingReviewCandidates.copy){
        Check([courses.reviewWorkspace selectRecordWithID:source[@"id"]],@"inbox source selected");Drain();
        NSDate *due=source[@"due"] ?: source[@"suggestedDue"];
        BOOL valid=[due isKindOfClass:NSDate.class] && ![source[@"needsTime"] boolValue] && ![source[@"warnings"] count];
        NSUInteger before=app.tasks.count;
        Press(courses.reviewWorkspace.view,@"review-save");
        if(valid)Check(app.tasks.count==before+1,@"inbox complete-date click persists one task");
        else Check(app.tasks.count==before,@"incomplete date remains pending with visible feedback");
    }
    Check([SSReadPlist(@"tasks.plist") isEqual:app.snapshot],@"persisted tasks reload exactly after inbox button use");
    // Repeat through the second actual button using a fresh copy of the task data.
    app.tasks=NSMutableArray.array;route.tag=4;[app navigate:route];
    for(NSDictionary *course in courses.courses){[courses selectCourseID:course[@"fork"]];courses.sections.selectedSegment=0;[courses refreshPresentation];
        for(NSDictionary *source in courses.pendingReviewCandidates.copy){
            if(!source[@"due"] || [source[@"needsDate"] boolValue] || [source[@"needsTime"] boolValue])continue;
            Check([courses.courseWorkspace selectRecordWithID:source[@"id"]],@"course source selected without popup");Drain();
            NSUInteger before=app.tasks.count;Press(courses.courseWorkspace.view,@"review-save");Check(app.tasks.count==before+1,@"course confirmation click persists one task");
        }
    }
    Check([SSReadPlist(@"tasks.plist") isEqual:app.snapshot],@"course button persistence survives reload");
    // Batch preview is an inline view, never a modal dialog.
    app.tasks=NSMutableArray.array;route.tag=3;[app navigate:route];[courses selectCourseID:nil];[courses refreshPresentation];Drain();
    Press(courses.reviewWorkspace.view,@"review-select-all");
    Press(courses.reviewWorkspace.view,@"review-preview-batch");
    Press(courses.reviewWorkspace.view,@"review-confirm-batch");Check(app.tasks.count>0 && !app.window.attachedSheet,@"batch button saves valid current results without sheet");
    Check([SSReadPlist(@"tasks.plist") isEqual:app.snapshot],@"batch results reload exactly");
    // The same button must preserve the form when atomic storage fails.
    app.tasks=NSMutableArray.array;[courses refreshPresentation];
    NSDictionary *ready=nil;for(NSDictionary *record in courses.allPendingReviewCandidates)if(record[@"due"] && ![record[@"needsDate"] boolValue] && ![record[@"needsTime"] boolValue]){ready=record;break;}
    if(ready){
        Check([courses.reviewWorkspace selectRecordWithID:ready[@"id"]],@"failure scenario selects a valid form");
        NSURL *target=[SSDataDirectory() URLByAppendingPathComponent:@"tasks.plist"];[NSFileManager.defaultManager removeItemAtURL:target error:NULL];[NSFileManager.defaultManager createDirectoryAtURL:target withIntermediateDirectories:NO attributes:nil error:NULL];
        Press(courses.reviewWorkspace.view,@"review-save");Check(app.tasks.count==0 && Element(courses.reviewWorkspace.view,@"review-save")!=nil,@"failed disk write retains form and saves no task");
        [NSFileManager.defaultManager removeItemAtURL:target error:NULL];Press(courses.reviewWorkspace.view,@"review-save");Check(app.tasks.count==1,@"retry button succeeds after storage recovery");
    }
    // Existing task copies remain editable and compatible; notes are never generated.
    app.tasks=tasks.mutableCopy;[courses refreshPresentation];[app render];
    [app.ticker invalidate];[NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];
    printf("PASS: %lu quiet usage assertions (%lu fixed assignments)\n",(unsigned long)checks,(unsigned long)discovered);
}return 0;}
