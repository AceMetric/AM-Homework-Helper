#import <Security/Security.h>
#import <signal.h>
#import "AMOperation.h"

static NSError *AMReminderMigrationError(NSString *message) {
    return [NSError errorWithDomain:@"AMReminderMigration" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
// Fixed executables and structured arguments only; every child belongs to this
// private maintenance workspace. No shell, old main(), task writes or Git work.
static BOOL AMReminderChild(NSString *executable,NSArray *arguments,NSDictionary *environment,NSTimeInterval limit,BOOL (^cancelled)(void),NSData **output) {
    NSTask *task=NSTask.new;task.executableURL=[NSURL fileURLWithPath:executable];task.arguments=arguments;
    if(environment)task.environment=environment;
    NSPipe *pipe=NSPipe.pipe;task.standardOutput=pipe;task.standardError=NSFileHandle.fileHandleWithNullDevice;
    if(![task launchAndReturnError:nil])return NO;
    // Listing output is bounded by the fixed capsule format (< 64 KB).
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:limit];
    while(task.running && deadline.timeIntervalSinceNow>0 && !(cancelled && cancelled()))[NSThread sleepForTimeInterval:.02];
    if(task.running){[task terminate];[NSThread sleepForTimeInterval:.05];if(task.running)kill(task.processIdentifier,SIGKILL);[task waitUntilExit];return NO;}
    [task waitUntilExit];NSData *data=[pipe.fileHandleForReading readDataToEndOfFile];if(output)*output=data;
    return task.terminationStatus==0;
}
static BOOL AMReminderRelativePath(NSString *path) {
    if(![path isKindOfClass:NSString.class] || ![path hasPrefix:@"Contents/"] || [path.pathComponents containsObject:@".."] || [path isAbsolutePath])return NO;
    return YES;
}
static NSArray *AMClearHistoricalReminderSources(NSURL *resources,NSURL *workspace,NSData *activeCodeHash,BOOL (^cancelled)(void),void (^progress)(NSInteger,NSInteger),NSError **error) {
    NSFileManager *fm=NSFileManager.defaultManager;
    NSURL *capsule=[resources URLByAppendingPathComponent:@"ReminderIdentities.zip"],*bridge=[resources URLByAppendingPathComponent:@"ReminderMaintenance.dylib"];
    NSData *listing=nil;
    if(!AMReminderChild(@"/usr/bin/unzip",@[@"-Z1",capsule.path],nil,10,cancelled,&listing)){if(error)*error=AMReminderMigrationError(@"无法读取旧版提醒维护文件。");return nil;}
    NSString *names=[[NSString alloc] initWithData:listing encoding:NSUTF8StringEncoding];
    NSRegularExpression *entry=[NSRegularExpression regularExpressionWithPattern:@"^(manifest\\.json|blobs/[0-9a-f]{64})$" options:0 error:nil];
    if(!names.length){if(error)*error=AMReminderMigrationError(@"旧版提醒维护文件为空。");return nil;}
    for(NSString *name in [names componentsSeparatedByString:@"\n"])if(name.length && [entry numberOfMatchesInString:name options:0 range:NSMakeRange(0,name.length)]!=1){if(error)*error=AMReminderMigrationError(@"旧版提醒维护文件路径无效。");return nil;}
    NSURL *store=[workspace URLByAppendingPathComponent:@"store"];
    if(!AMReminderChild(@"/usr/bin/ditto",@[@"-x",@"-k",capsule.path,store.path],nil,20,cancelled,NULL)){if(error)*error=AMReminderMigrationError(@"无法展开旧版提醒维护文件。");return nil;}
    NSData *manifestData=[NSData dataWithContentsOfURL:[store URLByAppendingPathComponent:@"manifest.json"]];
    NSDictionary *manifest=manifestData ? [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:nil]:nil;
    if(![manifest isKindOfClass:NSDictionary.class] || ![manifest[@"bundleID"] isEqual:@"io.github.acemetric.sshomeworkmanager"] || ![manifest[@"format"] isEqual:@1] || ![manifest[@"hosts"] isKindOfClass:NSArray.class]){if(error)*error=AMReminderMigrationError(@"旧版提醒维护身份无效。");return nil;}
    NSMutableArray *results=NSMutableArray.array;NSMutableSet *versions=NSMutableSet.set;
    for(id host in manifest[@"hosts"]){if(![host isKindOfClass:NSDictionary.class] || ![host[@"version"] isKindOfClass:NSString.class] || ![host[@"executable"] isKindOfClass:NSString.class]){if(error)*error=AMReminderMigrationError(@"旧版提醒应用清单无效。");return nil;}[versions addObject:host[@"version"]];}
    if(!versions.count || versions.count!=[manifest[@"hosts"] count] || versions.count>64){if(error)*error=AMReminderMigrationError(@"旧版提醒维护清单无效。");return nil;}
    for(NSDictionary *host in manifest[@"hosts"]){
        if(![host isKindOfClass:NSDictionary.class] || ![host[@"version"] isKindOfClass:NSString.class] || ![host[@"executable"] isKindOfClass:NSString.class]){if(error)*error=AMReminderMigrationError(@"旧版提醒应用清单无效。");return nil;}
        if(cancelled && cancelled()){if(error)*error=AMReminderMigrationError(@"已取消整理历史提醒。");return nil;}
        NSURL *app=[workspace URLByAppendingPathComponent:@"Historical.app"];[fm removeItemAtURL:app error:nil];
        NSArray *files=host[@"files"];if(![files isKindOfClass:NSArray.class]){if(error)*error=AMReminderMigrationError(@"旧版提醒文件清单无效。");return nil;}
        for(NSDictionary *row in files){
            if(![row isKindOfClass:NSDictionary.class] || ![row[@"mode"] isKindOfClass:NSNumber.class] || ![row[@"link"] isKindOfClass:NSNumber.class]){if(error)*error=AMReminderMigrationError(@"旧版提醒文件清单无效。");return nil;}
            NSString *path=row[@"path"],*blob=row[@"blob"];
            if(!AMReminderRelativePath(path) || ![blob isKindOfClass:NSString.class] || blob.length!=64 || [blob rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location!=NSNotFound){if(error)*error=AMReminderMigrationError(@"旧版提醒文件路径无效。");return nil;}
            NSData *data=[NSData dataWithContentsOfURL:[store URLByAppendingPathComponent:[@"blobs/" stringByAppendingString:blob]]];
            if(!data || ![AMPreflightHash(data) isEqual:blob]){if(error)*error=AMReminderMigrationError(@"旧版提醒维护文件校验失败。");return nil;}
            if([row[@"link"] boolValue])continue;
            NSURL *target=[app URLByAppendingPathComponent:path];
            if(![fm createDirectoryAtURL:[target URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error] || ![data writeToURL:target options:NSDataWritingAtomic error:error] || ![fm setAttributes:@{NSFilePosixPermissions:@([row[@"mode"] unsignedIntegerValue]&0777)} ofItemAtPath:target.path error:error])return nil;
        }
        for(NSDictionary *row in files)if([row[@"link"] boolValue]){
            NSData *data=[NSData dataWithContentsOfURL:[store URLByAppendingPathComponent:[@"blobs/" stringByAppendingString:row[@"blob"]]]];NSString *link=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];NSURL *target=[app URLByAppendingPathComponent:row[@"path"]];
            NSString *resolved=[[[target URLByDeletingLastPathComponent] URLByAppendingPathComponent:link] URLByStandardizingPath].path;
            if(!link.length || [link isAbsolutePath] || ![resolved hasPrefix:[app.path stringByAppendingString:@"/"]]){if(error)*error=AMReminderMigrationError(@"旧版提醒链接路径无效。");return nil;}
            if(![fm createDirectoryAtURL:[target URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error] || ![fm createSymbolicLinkAtPath:target.path withDestinationPath:link error:error])return nil;
        }
        NSDictionary *info=[NSDictionary dictionaryWithContentsOfURL:[app URLByAppendingPathComponent:@"Contents/Info.plist"]];
        NSString *executable=info[@"CFBundleExecutable"];
        if(![info[@"CFBundleIdentifier"] isEqual:@"io.github.acemetric.sshomeworkmanager"] || ![info[@"CFBundleShortVersionString"] isEqual:host[@"version"]] || ![executable isEqual:host[@"executable"]] || ![executable isEqual:executable.lastPathComponent]){if(error)*error=AMReminderMigrationError(@"旧版提醒应用身份不符。");return nil;}
        SecStaticCodeRef code=NULL;CFDictionaryRef signing=NULL;BOOL valid=SecStaticCodeCreateWithPath((__bridge CFURLRef)app,kSecCSDefaultFlags,&code)==errSecSuccess;
        if(valid)valid=SecStaticCodeCheckValidity(code,kSecCSStrictValidate,NULL)==errSecSuccess && SecCodeCopySigningInformation(code,kSecCSSigningInformation,&signing)==errSecSuccess;
        NSDictionary *details=CFBridgingRelease(signing);if(code)CFRelease(code);
        // Only ordinary ad-hoc historical hosts support this controlled loader.
        // Reject hardened/restricted/platform code rather than run an old UI.
        if(!valid || [details[(__bridge NSString *)kSecCodeInfoFlags] unsignedIntegerValue]!=2){if(error)*error=AMReminderMigrationError(@"旧版提醒签名无法验证。");return nil;}
        if(activeCodeHash && [details[(__bridge NSString *)kSecCodeInfoUnique] isEqual:activeCodeHash]){[results addObject:@{@"version":host[@"version"],@"activeIdentity":@YES}];if(progress)progress(results.count,versions.count);continue;}
        NSURL *result=[workspace URLByAppendingPathComponent:@"result.plist"];[fm removeItemAtURL:result error:nil];
        NSDictionary *environment=@{@"HOME":NSHomeDirectory(),@"PATH":@"/usr/bin:/bin:/usr/sbin:/sbin",@"TMPDIR":workspace.path,@"DYLD_INSERT_LIBRARIES":bridge.path,@"AM_REMINDER_MAINTENANCE":@"1"};
        BOOL ok=AMReminderChild([app URLByAppendingPathComponent:[@"Contents/MacOS/" stringByAppendingString:executable]].path,@[@"--am-reminder-maintenance",result.path],environment,8,cancelled,NULL);
        NSDictionary *report=[NSDictionary dictionaryWithContentsOfURL:result];
        if(!ok || ![report[@"confirmed"] boolValue] || [report[@"remaining"] unsignedIntegerValue]!=0){if(error)*error=AMReminderMigrationError(@"历史提醒尚未确认清理完成。");return nil;}
        NSMutableDictionary *row=report.mutableCopy;row[@"version"]=host[@"version"];[results addObject:row];if(progress)progress(results.count,versions.count);
    }
    [fm removeItemAtURL:[workspace URLByAppendingPathComponent:@"Historical.app"] error:nil];return results;
}

@interface AMReminderMigration:NSObject
@property BOOL running;
@property BOOL finished;
@property(atomic) BOOL cancelled;
@property NSError *error;
- (void)start:(void (^)(void))completion;
@end
@implementation AMReminderMigration
- (void)start:(void (^)(void))completion {
    if(self.running || self.finished)return;self.running=YES;
    NSURL *resources=NSBundle.mainBundle.resourceURL;
    __weak typeof(self) weakSelf=self;
    NSString *operation=AMOperationBegin(@"整理历史提醒",@"本机提醒",YES,^{weakSelf.cancelled=YES;});
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSFileManager *fm=NSFileManager.defaultManager;NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"am-reminders-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
        NSError *error=nil;NSArray *results=nil;
        NSData *payload=[NSData dataWithContentsOfURL:[resources URLByAppendingPathComponent:@"ReminderIdentities.zip"]];NSString *capsule=payload ? AMPreflightHash(payload):nil;
        NSDictionary *attrs=[fm attributesOfItemAtPath:NSBundle.mainBundle.bundlePath error:nil];
        NSDictionary *identity=capsule ? @{@"capsule":capsule,@"installation":attrs[NSFileSystemFileNumber] ?: @0,@"path":NSBundle.mainBundle.bundlePath}:nil;
        if(identity && [SSReadPlist(@"reminder-identity-migration.plist") isEqual:identity])results=@[];
        else if(![fm createDirectoryAtURL:root withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&error]){}
        else {results=AMClearHistoricalReminderSources(resources,root,nil,^BOOL{return self.cancelled;},^(NSInteger done,NSInteger total){AMOperationProgress(operation,@"清理旧版提醒",done,total);},&error);if(results && !SSWritePlist(@"reminder-identity-migration.plist",identity,&error))results=nil;}
        [fm removeItemAtURL:root error:nil];
        dispatch_async(dispatch_get_main_queue(),^{self.running=NO;self.finished=YES;self.error=results ? nil:(error ?: AMReminderMigrationError(@"历史提醒整理失败。"));AMOperationFinish(operation,results ? @"completed":(self.cancelled ? @"cancelled":@"failed"),results ? @"历史提醒已整理":self.error.localizedDescription);if(completion)completion();});
    });
}
@end
