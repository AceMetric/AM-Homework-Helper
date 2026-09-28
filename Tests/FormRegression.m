#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#include <stdio.h>
#include <stdlib.h>
static NSInteger assertions;
static void Check(BOOL passed, NSString *message) { assertions++; if (!passed) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); } }
static void Snapshot(NSView *view, NSString *path) {
    [view.window displayIfNeeded];
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:NO], @"screenshot saved");
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.arguments containsObject:@"--preview"]) return 2;
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        AppDelegate *app = [AppDelegate new]; NSApp.delegate = app;
        [app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
        for (NSInteger theme = 0; theme < 6; theme++) {
            CurrentTheme = theme;
            EditorController *editor = [[EditorController alloc] initWithTask:nil owner:app];
            [editor.window makeKeyAndOrderFront:nil]; [editor.window makeFirstResponder:editor.reminderField];
            [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            NSTextView *fieldEditor = (NSTextView *)editor.reminderField.currentEditor;
            Check(fieldEditor != nil, @"reminder accepts keyboard focus");
            Check([fieldEditor.selectedTextAttributes[NSBackgroundColorAttributeName] isEqual:Emphasis()], @"selection follows palette");
            Check([fieldEditor.insertionPointColor isEqual:Accent()], @"caret follows palette");
            [fieldEditor setSelectedRange:NSMakeRange(fieldEditor.string.length, 0)];
            Snapshot(editor.window.contentView, [NSString stringWithFormat:@"QA/form-%@.png", ThemeIDs()[theme]]);
            PastelPopUpButton *preset = (PastelPopUpButton *)editor.reminderPreset;
            [preset menuWillOpen:preset.menu];
            [(PastelMenuRow *)[preset itemAtIndex:2].view activate];
            Check([editor.reminderField.stringValue isEqual:@"5小时、1小时、到期"] && preset.indexOfSelectedItem == 0, @"custom menu row dispatches reminder selection and resets placeholder");
            [editor.window makeFirstResponder:editor.timePicker]; editor.timePicker.stringValue = @"09:30"; [editor timeChanged:editor.timePicker];
            Check([DDLFormatDate(editor.selectedDate, @"HH:mm") isEqual:@"09:30"] && [editor.deadlineField.stringValue hasSuffix:@"09:30"], @"time text syncs deadline");
            NSDate *valid = editor.selectedDate; editor.timePicker.stringValue = @"25:90"; [editor timeChanged:editor.timePicker];
            Check([editor.selectedDate isEqual:valid] && [editor parsedTime] == nil, @"invalid time preserves previous date and fails validation");
            editor.titleField.stringValue = @"test"; NSUInteger beforeSave = app.tasks.count; [editor save:nil];
            Check(app.tasks.count == beforeSave, @"invalid time blocks saving");
            [editor updateDate:DDLParseDate(@"明天 23:59", NSDate.date, Cal())];
            NSButton *step = [NSButton new]; step.tag = 1; NSDate *beforeStep = editor.selectedDate; [editor stepTime:step];
            Check([editor.selectedDate timeIntervalSinceDate:beforeStep] == 60 && [editor.timePicker.stringValue isEqual:@"00:00"], @"time stepper crosses midnight correctly");
            [editor.window makeFirstResponder:editor.notesField];
            Check([editor.notesField.insertionPointColor isEqual:Accent()], @"notes use theme caret");
            [editor.window orderOut:nil];
        }
        [app.ticker invalidate]; [app.searchTimer invalidate]; [app.window orderOut:nil]; [NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];
        printf("PASS: %ld form assertions\n", (long)assertions);
    }
    return 0;
}
