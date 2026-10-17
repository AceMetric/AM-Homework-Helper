#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#include <stdio.h>
#include <stdlib.h>
static NSInteger assertions;
@interface EditorOutsideEvent:NSObject
@property NSWindow *window;
@property NSPoint locationInWindow;
@end
@implementation EditorOutsideEvent @end
static void Check(BOOL passed, NSString *message) { assertions++; if (!passed) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); } }
static void Snapshot(NSView *view, NSString *path) {
    (void)path;[view layoutSubtreeIfNeeded];Check(!NSIsEmptyRect(view.bounds),@"synthetic form lays out without image capture");
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
            Check(!editor.hasUnsavedChanges,@"opening a prefilled task form is not an edit");
            NSDate *initialDate=editor.nativeDeadlinePicker.dateValue;
            editor.nativeDeadlinePicker.dateValue=[initialDate dateByAddingTimeInterval:3600];
            Check(editor.hasUnsavedChanges,@"dirty comparison reads the actual native date control before its action callback");
            editor.nativeDeadlinePicker.dateValue=initialDate;
            Check(!editor.hasUnsavedChanges,@"restoring the native deadline clears the edit without moving focus");
            Check(editor.titleField.isBezeled && !editor.titleField.isBordered && editor.titleField.bezelStyle == NSTextFieldRoundedBezel, @"final shared field state retains rounded bezel instead of square border");
            Check(editor.nativeDeadlinePicker.superview != nil && editor.timePicker.superview == nil && editor.deadlineField.superview == nil, @"ordinary task shows one native date and time control without duplicate text inputs");
            Check([DDLParseReminderOffsets(editor.reminderField.stringValue) isEqual:DDLDefaultReminderOffsets()] && !editor.notesField.string.length, @"new form has five default reminders and blank notes");
            [editor.window makeKeyAndOrderFront:nil]; [editor.window makeFirstResponder:editor.reminderField];
            [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            NSTextView *fieldEditor = (NSTextView *)editor.reminderField.currentEditor;
            Check(fieldEditor != nil, @"reminder accepts keyboard focus");
            Check(SameColor(fieldEditor.selectedTextAttributes[NSBackgroundColorAttributeName], NSColor.selectedTextBackgroundColor, editor.window.effectiveAppearance), @"field selection follows system appearance");
            Check(SameColor(fieldEditor.insertionPointColor, NSColor.controlAccentColor, editor.window.effectiveAppearance), @"field caret follows system appearance");
            [fieldEditor setSelectedRange:NSMakeRange(fieldEditor.string.length, 0)];
            Snapshot(editor.window.contentView, [NSString stringWithFormat:@"build/qa/form-%@.png", [appearance isEqual:NSAppearanceNameAqua] ? @"light" : @"dark"]);
            PastelPopUpButton *preset = (PastelPopUpButton *)editor.reminderPreset;
            [preset menuWillOpen:preset.menu];
            Check([preset itemAtIndex:2].view == nil, @"popup retains native macOS menu presentation"); [preset selectItemAtIndex:2]; [editor reminderPresetChanged:preset];
            Check([editor.reminderField.stringValue isEqual:@"7天"] && preset.indexOfSelectedItem == 0, @"native menu dispatches reminder selection and resets placeholder");
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
            Check(SameColor(editor.notesField.insertionPointColor, NSColor.controlAccentColor, editor.window.effectiveAppearance), @"notes use the system adaptive caret");
            Check([editor.saveButton.keyEquivalent isEqual:@"\r"], @"Return saves unified editor");
            Surface *notesContainer=(Surface *)editor.notesField.enclosingScrollView.superview;
            Check([notesContainer isKindOfClass:Surface.class] && notesContainer.radius==10 && editor.notesField.enclosingScrollView.borderType==NSNoBorder, @"multiline notes retain rounded container without square scroll bezel");
            for(NSValue *size in @[[NSValue valueWithSize:NSMakeSize(560,500)],[NSValue valueWithSize:NSMakeSize(680,620)],[NSValue valueWithSize:NSMakeSize(1000,800)]]){
                [editor.window setContentSize:size.sizeValue];[editor.window.contentView layoutSubtreeIfNeeded];
                NSRect button=[editor.saveButton convertRect:editor.saveButton.bounds toView:editor.window.contentView];
                NSRect footer=[editor.saveButton.superview.superview convertRect:editor.saveButton.superview.superview.bounds toView:editor.window.contentView];
                // Auto Layout pins system controls by their alignment rect. Older
                // rounded buttons include extra transparent shadow in their frame.
                NSRect alignment=[editor.saveButton.superview convertRect:[editor.saveButton alignmentRectForFrame:editor.saveButton.frame] toView:editor.window.contentView];
                BOOL insets=NSMaxX(alignment)<=NSWidth(editor.window.contentView.bounds)-23 && NSMinX(alignment)>=24 && NSContainsRect(footer,alignment) && NSMaxX(button)<=NSWidth(editor.window.contentView.bounds)-12;
                if(!insets)fprintf(stderr,"Footer geometry: content=%s footer=%s button=%s alignment=%s\n",NSStringFromRect(editor.window.contentView.bounds).UTF8String,NSStringFromRect(footer).UTF8String,NSStringFromRect(button).UTF8String,NSStringFromRect(alignment).UTF8String);
                Check(insets, @"save action retains visible footer insets through resize");
                Check(NSMaxY(alignment)<=NSHeight(editor.window.contentView.bounds)-15 && NSMaxY(button)<=NSHeight(editor.window.contentView.bounds)-8, @"save action stays above bottom edge through resize");
            }
            Check([editor.window.title isEqual:@"新建任务"] && editor.datePopover == nil, @"new task uses unified sheet with collapsed date picker");
            editor.titleField.stringValue = @"尚未保存的标题"; editor.notesField.string = @"尚未保存的备注";
            app.editor = editor; NSApp.appearance = [NSAppearance appearanceNamed:[appearance isEqual:NSAppearanceNameAqua] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]; [app refreshAppearance];
            Check([editor.titleField.stringValue isEqual:@"尚未保存的标题"] && [editor.notesField.string isEqual:@"尚未保存的备注"], @"live appearance change preserves unsaved input");
            editor.reminderField.stringValue = @"错误提醒"; beforeSave = app.tasks.count; [editor save:nil]; Check(app.tasks.count == beforeSave, @"invalid reminder blocks unified editor save");
            [editor applyImportedText:@"物理作业：实验报告\n截止时间：2026-10-11 21:00" source:@"模拟公告"];
            Check([editor.deadlineLabel.stringValue isEqual:@"作业 DDL"] && [editor.deadlineField.stringValue isEqual:@"2026-10-11 21:00"] && [editor.notesField.string isEqual:@"尚未保存的备注"], @"announcement prefills one deadline and preserves user notes");
            NSString *longTitle = [@"很长的模拟任务标题" stringByPaddingToLength:1500 withString:@"很长的模拟任务标题" startingAtIndex:0]; NSString *longNotes = [@"模拟备注\n" stringByPaddingToLength:8000 withString:@"模拟备注\n" startingAtIndex:0]; editor.titleField.stringValue = longTitle; editor.notesField.string = longNotes;
            Check([editor.titleField.stringValue isEqual:longTitle] && [editor.notesField.string isEqual:longNotes] && editor.notesField.enclosingScrollView.hasVerticalScroller, @"long title and notes remain editable and scrollable");
            Check(NSMaxY(editor.notesField.enclosingScrollView.superview.frame) <= NSHeight(editor.notesField.enclosingScrollView.superview.superview.frame), @"long form fits its scrolling document");
            [editor.window orderOut:nil]; app.editor = nil;
        }
        for(NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){
            NSApp.appearance=[NSAppearance appearanceNamed:appearance];
            EditorController *compact=[[EditorController alloc] initWithTask:app.tasks.firstObject owner:app];
            [app.window beginSheet:compact.window completionHandler:nil];
            CGFloat titleHeight=0,regularNotesHeight=0,regularNotesTop=0;
            for(NSValue *size in @[[NSValue valueWithSize:NSMakeSize(680,620)],[NSValue valueWithSize:NSMakeSize(720,640)],[NSValue valueWithSize:NSMakeSize(1000,800)],[NSValue valueWithSize:NSMakeSize(560,500)],[NSValue valueWithSize:NSMakeSize(680,620)]]){
                [compact.window setContentSize:size.sizeValue];[compact layoutEditor];
                [compact.window makeFirstResponder:compact.titleField];
                [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
                NSView *root=compact.window.contentView;
                NSRect title=[compact.titleField.superview convertRect:compact.titleField.superview.bounds toView:root];
                if(fabs(NSMinY(title)-16)>1)fprintf(stderr,"Editor top geometry: root=%s title=%s body=%s clip=%s\n",NSStringFromRect(root.bounds).UTF8String,NSStringFromRect(title).UTF8String,NSStringFromRect(compact.editorBody.frame).UTF8String,NSStringFromRect(compact.editorScroll.contentView.bounds).UTF8String);
                Check(fabs(NSMinY(title)-16)<=1 && NSHeight(title)>30,@"short form starts at the top inset after focus and resize");
                NSRect save=[compact.saveButton.superview convertRect:[compact.saveButton alignmentRectForFrame:compact.saveButton.frame] toView:root];
                Check(fabs(NSMaxX(save)-(NSWidth(root.bounds)-24))<=1,@"save action is anchored to the trailing footer inset");
                NSRect dateRow=[compact.dateRepeatRow convertRect:compact.dateRepeatRow.bounds toView:root];
                Check(fabs(NSMinX(dateRow)-24)<=1 && fabs(NSMaxX(dateRow)-(NSWidth(root.bounds)-24))<=1,@"date and recurrence row fills the same width as the title");
                NSRect subject=[compact.subjectField.superview convertRect:compact.subjectField.superview.bounds toView:root];
                Check(NSWidth(subject)>NSWidth(root.bounds)/2,@"course field receives the remaining row width");
                if(size.sizeValue.width>=640){NSRect repeat=[compact.repeatModeSection convertRect:compact.repeatModeSection.bounds toView:root];Check(fabs(NSMaxX(repeat)-NSMaxX(dateRow))<=1,@"repeat controls reach the trailing edge in a wide form");}
                if(size.sizeValue.width>=680){BOOL fits=NSHeight(compact.editorBody.bounds)<=NSHeight(compact.editorScroll.contentView.bounds)+1;if(!fits)fprintf(stderr,"compact body=%s viewport=%s\n",NSStringFromRect(compact.editorBody.bounds).UTF8String,NSStringFromRect(compact.editorScroll.contentView.bounds).UTF8String);Check(fits,@"ordinary editor fits 680 by 620 without outer scrolling");}
                NSView *notesBox=compact.notesField.enclosingScrollView.superview;
                NSRect notesRect=[notesBox convertRect:notesBox.bounds toView:root];
                CGFloat bottomGap=NSMaxY(compact.editorScroll.frame)-NSMaxY(notesRect);
                if(size.sizeValue.width>=680){if(fabs(bottomGap-16)>1)fprintf(stderr,"Adaptive form gap=%.1f body=%s notes=%s viewport=%s\n",bottomGap,NSStringFromRect(compact.editorBody.frame).UTF8String,NSStringFromRect(notesRect).UTF8String,NSStringFromRect(compact.editorScroll.contentView.bounds).UTF8String);Check(fabs(bottomGap-16)<=1,@"notes use remaining viewport height instead of leaving a blank block above the footer");}
                Check(NSHeight(notesBox.bounds)>=80,@"notes keep their readable minimum at small window sizes");
                Check(NSHeight(compact.notesField.bounds)>=NSHeight(compact.notesField.enclosingScrollView.contentView.bounds)-1,@"entire expanded notes area remains an editable text view");
                if(!titleHeight){titleHeight=NSHeight(compact.titleField.bounds);regularNotesHeight=NSHeight(notesBox.bounds);regularNotesTop=NSMinY(notesRect);}
                if(size.sizeValue.width>=680)Check(fabs(NSMinY(notesRect)-regularNotesTop)<=1,@"larger windows preserve field spacing and label positions");
                Check(fabs(NSHeight(compact.titleField.bounds)-titleHeight)<=1,@"extra height expands notes without stretching single-line controls");
                if(size.sizeValue.height==800)Check(NSHeight(notesBox.bounds)>regularNotesHeight+150,@"notes grow with the actual taller window without a fixed height cap");
                NSRect date=[compact.dateSection convertRect:compact.dateSection.bounds toView:compact.editorBody],repeat=[compact.repeatModeSection convertRect:compact.repeatModeSection.bounds toView:compact.editorBody];Check(!NSIntersectsRect(date,repeat),@"date and recurrence remain separate through width changes");
                NSRect footer=[compact.saveButton convertRect:compact.saveButton.bounds toView:compact.window.contentView];Check(NSMaxY(footer)<=NSHeight(compact.window.contentView.bounds),@"compact save stays visible when content overflows");
            }
            Check(!compact.hasUnsavedChanges,@"resizing and focus changes do not modify saved field values");
            compact.notesField.string=[@"这是一段用于核对长备注的中文内容。\n" stringByPaddingToLength:16000 withString:@"这是一段用于核对长备注的中文内容。\n" startingAtIndex:0];[compact.notesField didChangeText];[compact.notesField.layoutManager ensureLayoutForTextContainer:compact.notesField.textContainer];[compact layoutEditor];
            Check(NSHeight(compact.notesField.bounds)>NSHeight(compact.notesField.enclosingScrollView.contentView.bounds) && NSHeight(compact.editorScroll.documentView.bounds)<=NSHeight(compact.editorScroll.contentView.bounds)+1,@"long notes scroll internally without creating an outer form scrollbar");
            compact.validation.stringValue=@"请检查提醒时间。";[compact layoutEditor];
            NSRect error=[compact.validation convertRect:compact.validation.bounds toView:compact.window.contentView];
            NSRect action=[compact.saveButton convertRect:compact.saveButton.bounds toView:compact.window.contentView];
            Check(!compact.validation.hidden && NSMinY(error)>=NSMaxY(compact.editorScroll.frame) && NSMaxY(error)<NSMinY(action),@"current error remains in the fixed footer above actions");
            compact.repeatMode.enabled=YES;[compact.repeatMode selectItemAtIndex:1];[NSApp sendAction:compact.repeatMode.action to:compact.repeatMode.target from:compact.repeatMode];
            [compact.editorScroll layoutSubtreeIfNeeded];
            NSRect notes=[compact.notesField.enclosingScrollView.superview convertRect:compact.notesField.enclosingScrollView.superview.bounds toView:compact.editorScroll.documentView];
            Check(NSHeight(compact.editorScroll.documentView.bounds)>NSHeight(compact.editorScroll.contentView.bounds) && NSMaxY(notes)<=NSHeight(compact.editorScroll.documentView.bounds),@"expanded recurrence grows the document and keeps notes reachable");
            [compact.repeatMode selectItemAtIndex:0];[NSApp sendAction:compact.repeatMode.action to:compact.repeatMode.target from:compact.repeatMode];[compact.editorScroll layoutSubtreeIfNeeded];
            [compact.window makeFirstResponder:compact.titleField];
            NSRect restored=[compact.titleField.superview convertRect:compact.titleField.superview.bounds toView:compact.window.contentView];
            Check(fabs(NSMinY(restored)-16)<=1 && NSHeight(compact.editorScroll.documentView.bounds)<=NSHeight(compact.editorScroll.contentView.bounds)+1,@"collapsing recurrence restores the compact top aligned document");
            [app.window endSheet:compact.window];
            [compact.window orderOut:nil];
        }
        EditorOutsideEvent *outside=EditorOutsideEvent.new;outside.window=app.window;outside.locationInWindow=NSMakePoint(NSWidth(app.window.frame)-4,4);
        for(NSUInteger attempt=0;attempt<2;attempt++){
            app.editor=[[EditorController alloc] initWithTask:app.tasks.firstObject owner:app];NSWindow *sheet=app.editor.window;[sheet setFrame:NSMakeRect(NSMinX(app.window.frame)+40,NSMinY(app.window.frame)+40,560,500) display:NO];[app.window beginSheet:sheet completionHandler:nil];
            EditorOutsideEvent *inside=EditorOutsideEvent.new;inside.window=sheet;inside.locationInWindow=NSMakePoint(80,80);Check(![app dismissEditorForMouseEvent:(id)inside] && app.editor,@"inside editor click cannot dismiss the sheet");
            if(attempt){app.editor.titleField.stringValue=@"未保存的新名称";[AMQuietDialogChoices addObject:@(NSAlertThirdButtonReturn)];Check([app dismissEditorForMouseEvent:(id)outside] && app.editor && [app.editor.titleField.stringValue isEqual:@"未保存的新名称"],@"outside click preserves dirty editor when continuing");[AMQuietDialogChoices addObject:@(NSAlertSecondButtonReturn)];}
            Check([app dismissEditorForMouseEvent:(id)outside] && !app.editor && !app.window.attachedSheet,@"outside gray-area click closes unchanged or explicitly discarded editor");
        }
        [app.ticker invalidate]; [app.searchTimer invalidate]; [app.window orderOut:nil]; [NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];
        printf("PASS: %ld form assertions\n", (long)assertions);
    }
    return 0;
}
