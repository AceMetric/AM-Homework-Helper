// The visible SwiftUI form replaces geometry assertions about detached legacy
// controls. Persistence adapters are exercised through real native save targets.
#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
static NSButton *SaveButton(NSView *view){if([view isKindOfClass:NSButton.class] && [view.accessibilityIdentifier isEqual:@"task-save"])return (id)view;for(NSView *child in view.subviews){NSButton *button=SaveButton(child);if(button)return button;}return nil;}
static void Settle(void){[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.12]];}
int main(){@autoreleasepool{
    Check(NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"]!=nil,@"isolated storage");[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];AppDelegate *app=AppDelegate.new;NSApp.delegate=app;[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];[app openList:nil];
    for(NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){
        NSApp.appearance=[NSAppearance appearanceNamed:appearance];
        EditorController *editor=[[EditorController alloc] initWithTask:nil owner:app];app.editor=editor;[app.window beginSheet:editor.window completionHandler:nil];Settle();
        Check(editor.sharedForm && editor.sharedForm.view.superview==editor.window.contentView,@"manual new hosts the shared form");
        Check(!editor.hasUnsavedChanges && !editor.sharedForm.hasUnsavedChanges,@"prefilled form is clean");
        Check([editor.sharedForm.snapshot[@"reminderOffsets"] isEqual:DDLDefaultReminderOffsets()],@"reminder defaults survive shared bridge");
        NSUInteger before=app.tasks.count;NSButton *save=SaveButton(editor.sharedForm.view);Check(save!=nil,@"visible save is a native action target");[save performClick:nil];Check(app.tasks.count==before && app.editor==editor,@"empty title cannot save");
        for(NSValue *size in @[[NSValue valueWithSize:NSMakeSize(560,500)],[NSValue valueWithSize:NSMakeSize(720,640)],[NSValue valueWithSize:NSMakeSize(1100,900)]]){
            [editor.window setContentSize:size.sizeValue];[editor layoutEditor];Settle();
            NSView *form=editor.sharedForm.view;Check(NSEqualSizes(form.bounds.size,editor.window.contentView.bounds.size),@"form fills the actual window without a fixed top or bottom gap");
            NSButton *action=SaveButton(form);NSRect bounds=[action convertRect:action.bounds toView:form];Check(action && NSContainsRect(NSInsetRect(form.bounds,-2,-2),bounds),@"save remains in the fixed visible footer through resize");
            Check(!editor.hasUnsavedChanges,@"layout and appearance never edit values");
        }
        editor.titleField.stringValue=@"完整任务";editor.subjectField.stringValue=@"物理";editor.notesField.string=@"保留中文输入与备注";[editor layoutEditor];
        Check([editor.sharedForm.snapshot[@"title"] isEqual:@"完整任务"] && editor.hasUnsavedChanges,@"adapter and shared form use the same draft");
        [AMQuietDialogChoices addObject:@(NSAlertThirdButtonReturn)];[app requestCloseTaskEditor];Check(app.editor==editor,@"continue editing protects a dirty form");
        [editor layoutEditor];[SaveButton(editor.sharedForm.view) performClick:nil];Check(app.tasks.count==before+1 && !app.editor,@"visible save persists one task and closes editor");
        NSDictionary *task=app.tasks.lastObject;Check([task[@"notes"] isEqual:@"保留中文输入与备注"] && [task[@"subject"] isEqual:@"物理"],@"all shared fields survive save");
    }
    [app.window setContentSize:NSMakeSize(1500,1000)];[app layout];NSButton *select=NSButton.new;select.identifier=app.tasks.firstObject[@"id"];[app selectTask:select];Settle();
    EditorController *inlineEditor=app.editor;Check(inlineEditor.embedded && inlineEditor.sharedForm.view.superview==app.taskDetails && !app.window.attachedSheet,@"selection directly edits in the right pane");
    inlineEditor.notesField.string=@"窗口缩放期间保留的草稿";[inlineEditor layoutEditor];
    [app.window setContentSize:NSMakeSize(960,640)];[app layout];Settle();Check(app.editor==inlineEditor && app.window.attachedSheet==inlineEditor.window,@"narrow window moves the same editor to a sheet");
    Check([inlineEditor.sharedForm.snapshot[@"notes"] isEqual:@"窗口缩放期间保留的草稿"],@"responsive container switch preserves draft");
    [app.window setContentSize:NSMakeSize(1500,1000)];[app layout];Settle();Check(app.editor==inlineEditor && inlineEditor.sharedForm.view.superview==app.taskDetails && !app.window.attachedSheet,@"widening restores one editor without duplicates");
    [AMQuietDialogChoices addObject:@(NSAlertSecondButtonReturn)];[app closeTaskDetails:nil];Check(!app.editor && !app.selectedTaskID,@"explicit discard closes dirty inline editor");
    [app selectTask:select];EditorController *fresh=app.editor;NSString *old=fresh.titleField.stringValue;fresh.titleField.stringValue=[old stringByAppendingString:@"修改"];Check(fresh.hasUnsavedChanges,@"real edit is detected");fresh.titleField.stringValue=old;Check(!fresh.hasUnsavedChanges,@"reverting clears modification");
    fresh.titleField.stringValue=[@" " stringByAppendingString:old];Check(!fresh.hasUnsavedChanges,@"saved title normalization excludes whitespace-only change");fresh.titleField.stringValue=old;
    [app closeTaskDetails:nil];NSApp.appearance=nil;[app.ticker invalidate];[app.quickTimer invalidate];[app.window orderOut:nil];[NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];printf("PASS: %lu shared form and responsive editing assertions\n",(unsigned long)checks);
}return 0;}
