#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
#include <stdio.h>
static int assertions;
static void Check(BOOL v,NSString *message){assertions++;if(!v){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
int main(){@autoreleasepool {
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];AppDelegate *app=AppDelegate.new;NSApp.delegate=app;[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
    app.recurrenceSeries=@[];NSUInteger before=app.tasks.count;EditorController *e=[[EditorController alloc] initWithTask:nil owner:app];app.editor=e;[app.window beginSheet:e.window completionHandler:nil];e.titleField.stringValue=@"模拟每日复习";[e updateDate:[Cal() dateBySettingHour:20 minute:0 second:0 ofDate:NSDate.date options:0]];[e.repeatMode selectItemAtIndex:1];[e.repeatUnit selectItemAtIndex:0];[e.repeatEnd selectItemAtIndex:2];e.repeatCount.stringValue=@"3";[e recurrenceChanged:nil];[e.saveButton performClick:nil];
    Check(app.editor==nil && app.tasks.count==before+3 && app.recurrenceSeries.count==1,@"native Save creates bounded recurrence and three occurrences");
    [app.taskUndo undo];Check(app.recurrenceSeries.count==0 && app.tasks.count==before,@"undo creation removes series as well as occurrences");[app.taskUndo redo];Check(app.recurrenceSeries.count==1 && app.tasks.count==before+3,@"redo restores stable series and occurrences");
    NSArray *snapshot=[app snapshot];[app generateRecurrencesThrough:nil];Check(app.tasks.count==snapshot.count,@"activation cannot duplicate occurrences");
    NSDictionary *first=nil;for(NSDictionary *task in app.tasks)if(task[@"seriesID"]){first=task;break;}NSButton *toggle=NSButton.new;toggle.identifier=first[@"id"];[app toggleTask:toggle];Check([app taskWithID:first[@"id"]][@"completedAt"]!=nil,@"real completion action stores timestamp");
    e=[[EditorController alloc] initWithTask:[app taskWithID:first[@"id"]] owner:app];Check(e.seriesScope.superview!=nil && [e.repeatPreview.stringValue containsString:@"2026"],@"existing occurrence exposes edit scope and preview");[e.window setContentSize:NSMakeSize(900,760)];[e.window.contentView layoutSubtreeIfNeeded];Check(NSWidth(e.titleField.bounds)>600,@"form fields grow with window");
    NSError *error=nil;Check(SSSaveScheduledTasks(@[],app.tasks,app.recurrenceSeries,@{},&error),@"series and tasks persist transactionally in isolated data");NSDictionary *backup=AMBackupEnvelope(app.tasks,&error);Check([backup[@"format"] isEqual:@"am-helper-backup-v3"] && [AMDecodeBackup(backup,&error)[@"series"] count]==1,@"v3 backup round-trips rules and tasks");Check(AMDecodeBackup(@{@"format":@"am-helper-backup-v2",@"tasks":app.tasks,@"submissions":@[]},&error)!=nil,@"v2 backup still accepted");Check(AMRestoreScheduledBackup(app.tasks,backup,&error) && SSRecurrenceSeries(&error).count==1,@"restore retains series identity");
    NSMutableDictionary *bad=backup.mutableCopy;bad[@"series"]=@[@{}];Check(!AMDecodeBackup(bad,NULL),@"malformed rule blocks restore rather than dropping tasks");
    NSMutableArray *occurrences=NSMutableArray.array;for(NSDictionary *task in app.tasks)if([task[@"seriesID"] isEqual:first[@"seriesID"]])[occurrences addObject:task];[occurrences sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"due"] compare:b[@"due"]];}];
    NSDictionary *protected=occurrences[2];Check([app applyPlanning:@"set-plan" task:protected[@"id"] subtask:@"" value:DDLPlanKey(protected[@"due"],Cal())],@"user planning action marks occurrence edited");
    NSMutableDictionary *changed=[occurrences[1] mutableCopy],*rule=[app.recurrenceSeries[0][@"rule"] mutableCopy];rule[@"anchor"]=changed[@"due"];rule[@"count"]=@2;changed[@"_recurrenceRule"]=rule;changed[@"_seriesScope"]=@YES;changed[@"title"]=@"新的系列名称";Check([app commitTask:changed originalID:changed[@"id"]],@"future series edit commits");
    NSUInteger sameDay=0;for(NSDictionary *task in app.tasks)if(![task[@"deleted"] boolValue] && [Cal() isDate:task[@"due"] inSameDayAsDate:protected[@"due"]])sameDay+=(task[@"seriesID"]!=nil);Check(sameDay==1 && [app taskWithID:protected[@"id"]][@"plannedDate"],@"future edit preserves planned occurrence without regenerating a duplicate");
    [app.ticker invalidate];[app.searchTimer invalidate];[app.window orderOut:nil];[NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];printf("PASS: %d scheduled interaction assertions\n",assertions);
}return 0;}
