#import "QuietUI.h"
int main(void){@autoreleasepool{
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    pid_t before=NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
    NSWindow *parent=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,500,300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    NSWindow *sheet=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,300,200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    [parent makeKeyAndOrderFront:nil];[parent orderFront:nil];[NSApp activateIgnoringOtherApps:YES];
    if(parent.visible || parent.keyWindow || NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier!=before)return 1;
    __block BOOL ended=NO;[parent beginSheet:sheet completionHandler:^(NSModalResponse answer){ended=YES;}];
    if(parent.attachedSheet!=sheet || sheet.sheetParent!=parent || sheet.visible)return 1;
    [parent endSheet:sheet];if(parent.attachedSheet || sheet.sheetParent || !ended)return 1;
    [AMQuietDialogChoices addObject:@(NSAlertSecondButtonReturn)];if([NSAlert.new runModal]!=NSAlertSecondButtonReturn)return 1;
    [AMQuietDialogChoices addObject:@(NSAlertFirstButtonReturn)];__block BOOL selected=NO;
    [NSAlert.new beginSheetModalForWindow:parent completionHandler:^(NSModalResponse answer){selected=answer==NSAlertFirstButtonReturn;}];
    if(!selected || AMQuietDialogChoices.count || NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier!=before)return 1;
    puts("PASS: 5 quiet harness assertions");
}return 0;}
