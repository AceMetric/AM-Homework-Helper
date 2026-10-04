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
static BOOL SameColor(NSColor *a, NSColor *b, NSAppearance *appearance) {
    __block NSColor *ca, *cb; [appearance performAsCurrentDrawingAppearance:^{ ca = [a colorUsingColorSpace:NSColorSpace.sRGBColorSpace]; cb = [b colorUsingColorSpace:NSColorSpace.sRGBColorSpace]; }];
    return ca && cb && fabs(ca.redComponent - cb.redComponent) < 0.01 && fabs(ca.greenComponent - cb.greenComponent) < 0.01 && fabs(ca.blueComponent - cb.blueComponent) < 0.01;
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.arguments containsObject:@"--preview"]) return 2;
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        AppDelegate *app = [AppDelegate new]; NSApp.delegate = app;
        [app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
        for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            NSApp.appearance = [NSAppearance appearanceNamed:appearance];
            EditorController *editor = [[EditorController alloc] initWithTask:nil owner:app];
            [editor.window makeKeyAndOrderFront:nil]; [editor.window makeFirstResponder:editor.reminderField];
            [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            NSTextView *fieldEditor = (NSTextView *)editor.reminderField.currentEditor;
            Check(fieldEditor != nil, @"reminder accepts keyboard focus");
            Check(SameColor(fieldEditor.selectedTextAttributes[NSBackgroundColorAttributeName], Emphasis(), editor.window.effectiveAppearance), @"selection follows palette");
            Check(SameColor(fieldEditor.insertionPointColor, Accent(), editor.window.effectiveAppearance), @"caret follows palette");
            [fieldEditor setSelectedRange:NSMakeRange(fieldEditor.string.length, 0)];
            Snapshot(editor.window.contentView, [NSString stringWithFormat:@"build/qa/form-%@.png", [appearance isEqual:NSAppearanceNameAqua] ? @"light" : @"dark"]);
            PastelPopUpButton *preset = (PastelPopUpButton *)editor.reminderPreset;
            [preset menuWillOpen:preset.menu];
            Check([preset itemAtIndex:2].view == nil, @"popup retains native macOS menu presentation"); [preset selectItemAtIndex:2]; [editor reminderPresetChanged:preset];
            Check([editor.reminderField.stringValue isEqual:@"5小时、1小时、到期"] && preset.indexOfSelectedItem == 0, @"native menu dispatches reminder selection and resets placeholder");
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
            Check(SameColor(editor.notesField.insertionPointColor, Accent(), editor.window.effectiveAppearance), @"notes use adaptive caret");
            Check([editor.saveButton.keyEquivalent isEqual:@"\r"], @"Return saves unified editor");
            Check([editor.window.title isEqual:@"新建任务"] && editor.datePopover == nil, @"new task uses unified sheet with collapsed date picker");
            editor.titleField.stringValue = @"尚未保存的标题"; editor.notesField.string = @"尚未保存的备注";
            app.editor = editor; NSApp.appearance = [NSAppearance appearanceNamed:[appearance isEqual:NSAppearanceNameAqua] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]; [app refreshAppearance];
            Check([editor.titleField.stringValue isEqual:@"尚未保存的标题"] && [editor.notesField.string isEqual:@"尚未保存的备注"], @"live appearance change preserves unsaved input");
            editor.reminderField.stringValue = @"错误提醒"; beforeSave = app.tasks.count; [editor save:nil]; Check(app.tasks.count == beforeSave, @"invalid reminder blocks unified editor save");
            [editor applyImportedText:@"物理作业：实验报告\n截止时间：2026-10-11 21:00" source:@"模拟公告"];
            Check(editor.announcedDue != nil && !editor.leadMenu.hidden && NSMaxY(editor.leadMenu.frame) <= NSMinY(editor.deadlineField.frame), @"announcement import expands teacher controls without overlapping date field");
            NSString *longTitle = [@"很长的模拟任务标题" stringByPaddingToLength:1500 withString:@"很长的模拟任务标题" startingAtIndex:0]; NSString *longNotes = [@"模拟备注\n" stringByPaddingToLength:8000 withString:@"模拟备注\n" startingAtIndex:0]; editor.titleField.stringValue = longTitle; editor.notesField.string = longNotes;
            Check([editor.titleField.stringValue isEqual:longTitle] && [editor.notesField.string isEqual:longNotes] && editor.notesField.enclosingScrollView.hasVerticalScroller, @"long title and notes remain editable and scrollable");
            Check(NSMaxY(editor.notesField.enclosingScrollView.superview.frame) <= NSHeight(editor.notesField.enclosingScrollView.superview.superview.frame), @"long form fits its scrolling document");
            [editor.window orderOut:nil]; app.editor = nil;
        }
        [app.ticker invalidate]; [app.searchTimer invalidate]; [app.window orderOut:nil]; [NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];
        printf("PASS: %ld form assertions\n", (long)assertions);
    }
    return 0;
}
