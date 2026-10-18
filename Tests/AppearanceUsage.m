#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
static NSTextView *VisibleNotes(NSView *view){if([view isKindOfClass:NSTextView.class] && [(NSTextView *)view isEditable])return (id)view;for(NSView *child in view.subviews){NSTextView *found=VisibleNotes(child);if(found)return found;}return nil;}
static CGFloat Luminance(NSColor *color){NSColor *rgb=[color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];return .2126*rgb.redComponent+.7152*rgb.greenComponent+.0722*rgb.blueComponent;}
static CGFloat EventBackgroundLuminance(NSDictionary *task){NSColor *color=EventFill(task);CGFloat alpha=color.alphaComponent;return alpha*Luminance(color)+(1-alpha)*Luminance(Card());}
static void CheckCalendarPalette(void){
 CalendarDayCell *weekend=CalendarDayCell.new,*holiday=CalendarDayCell.new,*outside=CalendarDayCell.new,*weekday=CalendarDayCell.new;
 weekend.inMonth=holiday.inMonth=weekday.inMonth=YES;weekend.weekend=holiday.weekend=YES;holiday.dayKind=@"holiday";
 NSArray *cells=@[weekend,holiday,outside,weekday];
 // Configure under the opposite appearance before attaching to any window.
 [[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] performAsCurrentDrawingAppearance:^{for(CalendarDayCell *cell in cells)ConfigureCalendarCell(cell,NO);}];
 for(NSString *name in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua,NSAppearanceNameAqua]){
  [[NSAppearance appearanceNamed:name] performAsCurrentDrawingAppearance:^{
   BOOL dark=[name isEqual:NSAppearanceNameDarkAqua];CGFloat ink=Luminance(Ink());
   for(CalendarDayCell *cell in cells){CGFloat fill=Luminance(cell.fill);Check(dark ? fill<.32:fill>.90,@"calendar background follows drawing appearance even when created in the opposite theme");Check(fabs(fill-ink)>.65,@"date labels retain clear contrast on every day background");Check(cell.gradientEnd==nil,@"calendar backgrounds do not retain a gradient with stale resolved colors");}
   NSColor *rest=[weekend.fill colorUsingColorSpace:NSColorSpace.sRGBColorSpace],*festival=[holiday.fill colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
   Check(festival.blueComponent-festival.redComponent>rest.blueComponent-rest.redComponent+.02,@"holiday blue tint is distinct from neutral weekend shading");
   for(NSDictionary *task in @[@{@"completed":@YES},@{@"due":[NSDate dateWithTimeIntervalSinceNow:86400]},@{@"due":[NSDate dateWithTimeIntervalSinceNow:-86400]}])Check(dark ? EventBackgroundLuminance(task)<.4:EventBackgroundLuminance(task)>.85,@"completed, upcoming and overdue task fills follow the active appearance");
  }];
 }
 ConfigureCalendarCell(holiday,YES);Check(holiday.selected && [holiday.stroke isEqual:Accent()],@"selection preserves the holiday background and adds a separate accent outline");
}
int main(){@autoreleasepool{[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];CheckCalendarPalette();AppDelegate *app=AppDelegate.new;NSApp.delegate=app;[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];Check(NSApp.appearance==nil && app.window.appearance==nil,@"production launch inherits system appearance");
 NSButton *route=NSButton.new;route.tag=2;[app navigate:route];NSDictionary *task=app.tasks.firstObject;NSButton *selection=NSButton.new;selection.identifier=task[@"id"];[app selectTask:selection];[app editTask:selection];Check(app.editor!=nil,@"task editor opens while no course operation owns the task");EditorController *editor=app.editor;[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.2]];NSTextView *notes=VisibleNotes(editor.sharedForm.view);Check(notes!=nil,@"shared form contains a native notes editor");notes.string=@"Draft must survive style changes\nSecond line";[notes didChangeText];[notes.window makeFirstResponder:notes];notes.selectedRange=NSMakeRange(6,4);[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];NSView *content=app.root;NSString *selected=app.selectedTaskID;NSPoint scroll=app.scroll.contentView.bounds.origin;
 NSWindow *systemSurface=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,160,24) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];systemSurface.backgroundColor=NSColor.clearColor;systemSurface.opaque=NO;
 NSWindow *statusWindow=app.statusItem.button.window;NSColor *statusBackground=statusWindow.backgroundColor;
 for(NSString *appearance in @[NSAppearanceNameDarkAqua,NSAppearanceNameAqua]){NSApp.appearance=[NSAppearance appearanceNamed:appearance];[app refreshAppearance];Check([systemSurface.backgroundColor isEqual:NSColor.clearColor] && !systemSurface.opaque,@"theme refresh preserves borderless system surface transparency");Check(statusWindow!=nil && [statusWindow.backgroundColor isEqual:statusBackground],@"theme refresh leaves actual menu bar status window background to macOS");Check(app.editor==editor && app.root==content && [app.selectedTaskID isEqual:selected] && NSEqualPoints(app.scroll.contentView.bounds.origin,scroll),@"restyling retains editor, content, task selection and scroll");Check([editor.notesField.string hasPrefix:@"Draft must survive"] && NSEqualRanges(notes.selectedRange,NSMakeRange(6,4)) && notes.window.firstResponder==notes,@"draft, caret selection and focus survive restyling");}
 Check(app.window.contentViewController==app.mainSplit && app.navigationItem.behavior==NSSplitViewItemBehaviorSidebar && app.sidebar.fill==nil,@"native split-view sidebar owns its system material without an opaque overlay");
 if(@available(macOS 26.0,*)){Check(Button(@"Primary",nil,NULL,1).bezelStyle==NSBezelStyleRounded && Button(@"Secondary",nil,NULL,0).bezelStyle==NSBezelStyleRounded,@"content actions retain the system standard button style");ThemeSegmentedControl *tabs=Segments(@[@"Today",@"Week"],nil,NULL);Check(tabs.segmentStyle==NSSegmentStyleAutomatic && [[tabs valueForKey:@"borderShape"] integerValue]==1,@"segmented navigation uses automatic native styling and capsule shape");if(@available(macOS 27.0,*))Check([[tabs valueForKey:@"role"] integerValue]==1,@"segmented navigation declares its public tab role");}
 AMShowOperations(app.window);NSWindow *operations=nil;for(NSWindow *window in NSApp.windows)if([window.title isEqual:@"后台任务"])operations=window;NSString *operation=AMOperationBegin(@"Synthetic pending operation",@"Test",NO,nil);[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];Check([[(NSScrollView *)[operations valueForKey:@"operationScroll"] documentView] subviews].count>0,@"open background panel receives newly started operations");AMOperationFinish(operation,@"success",@"Synthetic complete");[operations orderOut:nil];
 NSApp.appearance=nil;[app.window endSheet:editor.window];[editor.window orderOut:nil];app.editor=nil;[app.window orderOut:nil];printf("PASS: %lu appearance inheritance and draft assertions\n",(unsigned long)checks);
}return 0;}
