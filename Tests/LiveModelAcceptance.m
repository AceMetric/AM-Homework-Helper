#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
#import "../Sources/AMPrompts.h"
#import "AcceptanceFixtures.h"
@interface LiveAcceptance:NSObject
@property NSWindow *window;
@property NSTextField *status;
@property NSButton *run;
@end
@implementation LiveAcceptance
- (void)login:(id)sender {AMShowChatGPTSettings(self.window);}
- (void)start:(id)sender {
    if(![AMChatGPTStatus()[@"connected"] boolValue]){self.status.stringValue=@"请先登录。";return;}
    NSURL *url=[NSBundle.mainBundle URLForResource:@"acceptance-plan" withExtension:@"json"];NSError *loadError=nil;NSArray *plan=AMAcceptanceCases(url,24,&loadError);if(!plan){self.status.stringValue=loadError.localizedDescription;return;}
    self.run.enabled=NO;self.status.stringValue=@"正在复验合成作业；不会读取真实课程。";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSURL *destination=[SSDataDirectory() URLByAppendingPathComponent:@"model-quality-phase2.json"];NSData *existing=[NSData dataWithContentsOfURL:destination];id saved=existing ? [NSJSONSerialization JSONObjectWithData:existing options:0 error:NULL]:nil;NSMutableArray *records=[saved isKindOfClass:NSArray.class] ? [saved mutableCopy]:NSMutableArray.array;
        for(NSDictionary *fixture in plan){@autoreleasepool{
            BOOL done=NO;for(NSDictionary *record in records)if([record[@"id"] isEqual:fixture[@"id"]] && !record[@"error"]){done=YES;break;}if(done)continue;
            NSString *teacher=fixture[@"teacher"],*mode=fixture[@"mode"];NSString *purpose=[mode isEqual:@"review"] ? @"review":@"recognition";NSError *error=nil;NSDictionary *output=nil;NSDate *started=NSDate.date;
            if([mode isEqual:@"recognition"]){NSMutableArray *lines=NSMutableArray.array;NSArray *original=[teacher componentsSeparatedByString:@"\n"];for(NSUInteger i=0;i<original.count;i++)[lines addObject:@{@"line":@(i+1),@"text":original[i]}];output=AMChatGPTGenerate(@{@"lines":lines,@"sourcePath":@"assignment/README.md",@"sourceScopes":@[]},AMCoursePrompt(),@[],purpose,^BOOL{return NO;},&error);}
            else if([mode isEqual:@"fields"]){AMOnlineReviewClient *client=AMOnlineReviewClient.new;NSDictionary *raw=[client recognizeFields:teacher profile:AMChatGPTProfile(@"recognition") error:&error];if(raw)output=@{@"raw":raw,@"validated":AMValidateRecognizedFields(teacher,raw)};}
            else {NSMutableArray *documents=NSMutableArray.array;for(NSDictionary *document in fixture[@"documents"]){NSMutableDictionary *bound=document.mutableCopy;bound[@"version"]=AMPreflightHash([document[@"text"] dataUsingEncoding:NSUTF8StringEncoding]);bound[@"role"]=@"answer";[documents addObject:bound];}NSString *batch=NSUUID.UUID.UUIDString;NSDictionary *context=@{@"format":@"am-preflight-context-v1",@"batchID":batch,@"reportVersion":batch,@"snapshotVersion":@"live-synthetic-v2",@"requirements":teacher,@"verifiedTextRequirements":@[teacher],@"documents":documents,@"images":@[],@"unverifiedImages":@[]};NSURL *folder=AMPreflightFolder(batch);[NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error];[[NSJSONSerialization dataWithJSONObject:context options:0 error:NULL] writeToURL:[folder URLByAppendingPathComponent:@"context.local.json"] atomically:YES];AMOnlineReviewClient *client=AMOnlineReviewClient.new;client.profile=AMChatGPTProfile(@"review");client.requestLimit=1;output=[client reviewContext:context folder:folder focus:nil progress:nil error:&error];}
            NSMutableDictionary *usage=[SSReadPlist(@"chatgpt-last-usage.plist") mutableCopy] ?: NSMutableDictionary.dictionary;[usage removeObjectForKey:@"date"];NSMutableDictionary *record=[@{@"id":fixture[@"id"],@"set":fixture[@"set"],@"purpose":purpose,@"mode":mode,@"seconds":@(-started.timeIntervalSinceNow),@"usage":usage,@"profile":AMChatGPTProfile(purpose)} mutableCopy];if(output)record[@"output"]=output;if(error || !output)record[@"error"]=error.localizedDescription ?: @"未完成";
            [records addObject:record];NSError *saveError=nil;NSData *data=[NSJSONSerialization isValidJSONObject:records] ? [NSJSONSerialization dataWithJSONObject:records options:NSJSONWritingPrettyPrinted error:&saveError]:nil;BOOL stored=data && [data writeToURL:destination options:NSDataWritingAtomic error:&saveError];NSUInteger count=records.count;
            dispatch_async(dispatch_get_main_queue(),^{self.status.stringValue=stored ? [NSString stringWithFormat:@"已记录 %lu 项；结果待人工核对。",(unsigned long)count]:@"结果保存失败，已停止。";});if(error || !stored){dispatch_async(dispatch_get_main_queue(),^{self.status.stringValue=error.localizedDescription ?: @"结果保存失败";self.run.enabled=YES;});return;}
        }}
        dispatch_async(dispatch_get_main_queue(),^{self.status.stringValue=@"复验完成，等待逐项审阅。";self.run.enabled=YES;});
    });
}
@end
int main(){@autoreleasepool{[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    // Read only this acceptance app's own OAuth records. A repaired test binary
    // may require a macOS Keychain authorization; desktop app credentials are never used.
    AMChatGPTSetCredentialStore(^NSDictionary *(NSString *account){NSMutableDictionary *query=[@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"io.github.ddl-manager.model-acceptance-120",(__bridge id)kSecAttrAccount:account,(__bridge id)kSecReturnData:@YES,(__bridge id)kSecMatchLimit:(__bridge id)kSecMatchLimitOne} mutableCopy];CFTypeRef value=NULL;if(SecItemCopyMatching((__bridge CFDictionaryRef)query,&value)!=errSecSuccess)return nil;NSData *data=CFBridgingRelease(value);return [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];},^BOOL(NSString *key,NSDictionary *value){return SSWriteSecret(key,value);});
    LiveAcceptance *controller=LiveAcceptance.new;controller.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,650,230) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];controller.window.title=@"AM Helper · 模型验收（隔离数据）";controller.window.releasedWhenClosed=NO;NSStackView *stack=NSStackView.new;stack.frame=NSMakeRect(24,24,602,185);stack.orientation=NSUserInterfaceLayoutOrientationVertical;stack.alignment=NSLayoutAttributeLeading;stack.spacing=14;[controller.window.contentView addSubview:stack];NSTextField *notice=[NSTextField wrappingLabelWithString:@"只测试随代码提供的合成作业，最多发送24次请求到官方 OpenAI 接口。登录凭据仅存入独立验收钥匙串。不会读取真实课程，也不会发布版本。请先登录，再主动运行。 "];[notice.widthAnchor constraintEqualToConstant:600].active=YES;[stack addArrangedSubview:notice];[stack addArrangedSubview:[NSButton buttonWithTitle:@"ChatGPT 登录与模型…" target:controller action:@selector(login:)]];controller.run=[NSButton buttonWithTitle:@"复验24次合成样例" target:controller action:@selector(start:)];[stack addArrangedSubview:controller.run];controller.status=[NSTextField wrappingLabelWithString:@"尚未发送任何请求。"];[controller.status.widthAnchor constraintEqualToConstant:600].active=YES;[stack addArrangedSubview:controller.status];[controller.window center];[controller.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];if([NSProcessInfo.processInfo.arguments containsObject:@"--resume-acceptance"])dispatch_async(dispatch_get_main_queue(),^{[controller start:nil];});[NSApp run];}}
