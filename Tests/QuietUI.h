// Test-only interception. Never linked into the distributable application.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
static NSUInteger AMQuietSuppressed;
static NSMutableArray<NSNumber *> *AMQuietDialogChoices;
static char AMQuietParentKey,AMQuietSheetKey,AMQuietCompletionKey;
static void AMQuietReplace(Class cls, SEL selector, IMP implementation) {
    Method method=class_getInstanceMethod(cls,selector);
    if(method) class_replaceMethod(cls,selector,implementation,method_getTypeEncoding(method));
}
@interface AMQuietUI : NSObject @end
@implementation AMQuietUI
+ (void)load {
    @autoreleasepool {
        if(![NSProcessInfo.processInfo.arguments containsObject:@"--quiet-test"]) {fprintf(stderr,"UI tests require the quiet runner\n");exit(2);}
        AMQuietDialogChoices=NSMutableArray.array;
        pid_t frontBefore=NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
        AMQuietReplace(NSApplication.class,@selector(activateIgnoringOtherApps:),imp_implementationWithBlock(^(id obj,BOOL flag){AMQuietSuppressed++;}));
        AMQuietReplace(NSApplication.class,NSSelectorFromString(@"activate"),imp_implementationWithBlock(^(id obj){AMQuietSuppressed++;}));
        AMQuietReplace(NSRunningApplication.class,@selector(activateWithOptions:),imp_implementationWithBlock(^BOOL(id obj,NSApplicationActivationOptions options){AMQuietSuppressed++;return NO;}));
        AMQuietReplace(NSWindow.class,@selector(orderWindow:relativeTo:),imp_implementationWithBlock(^(id obj,NSWindowOrderingMode mode,NSInteger number){AMQuietSuppressed++;}));
        AMQuietReplace(NSWindow.class,@selector(makeKeyWindow),imp_implementationWithBlock(^(id obj){AMQuietSuppressed++;}));
        AMQuietReplace(NSWindow.class,@selector(makeMainWindow),imp_implementationWithBlock(^(id obj){AMQuietSuppressed++;}));
        // Model the sheet lifecycle instead of invoking WindowServer animations.
        AMQuietReplace(NSWindow.class,@selector(beginSheet:completionHandler:),imp_implementationWithBlock(^(NSWindow *parent,NSWindow *sheet,void (^completion)(NSModalResponse)){
            objc_setAssociatedObject(parent,&AMQuietSheetKey,sheet,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(sheet,&AMQuietParentKey,parent,OBJC_ASSOCIATION_ASSIGN);
            objc_setAssociatedObject(sheet,&AMQuietCompletionKey,completion,OBJC_ASSOCIATION_COPY_NONATOMIC);
        }));
        AMQuietReplace(NSWindow.class,@selector(attachedSheet),imp_implementationWithBlock(^NSWindow *(id obj){return objc_getAssociatedObject(obj,&AMQuietSheetKey);}));
        AMQuietReplace(NSWindow.class,@selector(sheetParent),imp_implementationWithBlock(^NSWindow *(id obj){return objc_getAssociatedObject(obj,&AMQuietParentKey);}));
        void (^endSheet)(NSWindow *,NSWindow *,NSModalResponse)=^(NSWindow *parent,NSWindow *sheet,NSModalResponse response){
            void (^completion)(NSModalResponse)=objc_getAssociatedObject(sheet,&AMQuietCompletionKey);
            objc_setAssociatedObject(parent,&AMQuietSheetKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(sheet,&AMQuietParentKey,nil,OBJC_ASSOCIATION_ASSIGN);
            objc_setAssociatedObject(sheet,&AMQuietCompletionKey,nil,OBJC_ASSOCIATION_COPY_NONATOMIC);
            if(completion)completion(response);
        };
        AMQuietReplace(NSWindow.class,@selector(endSheet:),imp_implementationWithBlock(^(NSWindow *parent,NSWindow *sheet){endSheet(parent,sheet,NSModalResponseOK);}));
        AMQuietReplace(NSWindow.class,@selector(endSheet:returnCode:),imp_implementationWithBlock(endSheet));
        AMQuietReplace(NSAlert.class,@selector(runModal),imp_implementationWithBlock(^NSModalResponse(id obj){
            if(!AMQuietDialogChoices.count){fprintf(stderr,"Unexpected modal: skipped; add an explicit test choice\n");exit(3);}
            NSModalResponse result=AMQuietDialogChoices.firstObject.integerValue;[AMQuietDialogChoices removeObjectAtIndex:0];return result;
        }));
        AMQuietReplace(NSAlert.class,@selector(beginSheetModalForWindow:completionHandler:),imp_implementationWithBlock(^(id obj,NSWindow *parent,void (^completion)(NSModalResponse)){
            if(!AMQuietDialogChoices.count){fprintf(stderr,"Unexpected alert sheet: skipped\n");exit(3);}
            NSModalResponse response=AMQuietDialogChoices.firstObject.integerValue;[AMQuietDialogChoices removeObjectAtIndex:0];if(completion)completion(response);
        }));
        AMQuietReplace(NSSavePanel.class,@selector(runModal),imp_implementationWithBlock(^NSModalResponse(id obj){fprintf(stderr,"File chooser requires a test adapter; skipped\n");exit(3);return NSModalResponseCancel;}));
        AMQuietReplace(NSSavePanel.class,@selector(beginSheetModalForWindow:completionHandler:),imp_implementationWithBlock(^(id obj,NSWindow *parent,void (^completion)(NSModalResponse)){fprintf(stderr,"File chooser sheet requires a test adapter; skipped\n");exit(3);}));
        AMQuietReplace(NSWorkspace.class,@selector(openURL:),imp_implementationWithBlock(^BOOL(id obj,NSURL *url){fprintf(stderr,"Browser-dependent test is not allowed in quiet mode\n");exit(3);return NO;}));
        [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidActivateApplicationNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){
            if([note.userInfo[NSWorkspaceApplicationKey] processIdentifier]==NSProcessInfo.processInfo.processIdentifier){fprintf(stderr,"FAIL: test became foreground\n");exit(4);}
        }];
        atexit_b(^{pid_t frontAfter=NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;if(frontAfter==NSProcessInfo.processInfo.processIdentifier){fprintf(stderr,"FAIL: test foreground at exit\n");_exit(4);}fprintf(stdout,"QUIET: suppressed %lu window/activation requests; no foreground activation; foreground unchanged=%s\n",(unsigned long)AMQuietSuppressed,frontBefore==frontAfter ? "yes":"user/external switch");});
    }
}
@end
