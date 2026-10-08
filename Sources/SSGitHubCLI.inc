// Included by SSGitHub.m. The official binary is never given a token or a writable
// credential configuration. Only this adapter reads shared keychain items.
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>

static NSString *SSCLIProfile(void) {
    NSString *directory=[[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Keychains"] stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    directory=[directory stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    // security's legacy keyring implementation needs encrypted keychain-file writes.
    // No ordinary directory (including GH_CONFIG_DIR and temporary files) is writable.
    return [NSString stringWithFormat:@"(version 1)(allow default)(deny file-write*)(allow file-write* (literal \"/dev/null\") (subpath \"%@\"))",directory];
}
static NSString *SSCLIDecode(NSData *data) {
    NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSString *prefix=@"go-keyring-base64:";
    if([text hasPrefix:prefix])return [[NSString alloc] initWithData:[[NSData alloc] initWithBase64EncodedString:[text substringFromIndex:prefix.length] options:0] encoding:NSUTF8StringEncoding];
    if([text hasPrefix:@"go-keyring-encoded:"]){NSString *hex=[text substringFromIndex:19];if(hex.length%2)return nil;NSMutableData *decoded=NSMutableData.data;for(NSUInteger n=0;n<hex.length;n+=2){unsigned int value=0;NSScanner *scan=[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(n,2)]];if(![scan scanHexInt:&value] || !scan.isAtEnd)return nil;unsigned char byte=value;[decoded appendBytes:&byte length:1];}return [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding];}
    return text;
}
static NSDictionary *SSCLIEnvironment(NSString *directory) {
    // Allow-list rather than filtering inherited tokens, debug flags and proxies.
    return @{@"HOME":NSHomeDirectory(),@"PATH":@"/usr/bin:/bin:/usr/sbin:/sbin",@"TMPDIR":NSTemporaryDirectory(),@"LANG":@"en_US.UTF-8",@"GH_CONFIG_DIR":directory,@"GH_HOST":@"github.com",@"GH_PROMPT_DISABLED":@"1",@"GH_NO_UPDATE_NOTIFIER":@"1",@"GH_NO_EXTENSION_UPDATE_NOTIFIER":@"1",@"GH_TELEMETRY":@"false",@"DO_NOT_TRACK":@"true",@"NO_COLOR":@"1",@"TERM":@"dumb"};
}

@interface SSGitHubCLILogin : NSObject
@property NSTask *task;
@property NSPipe *output;
@property NSMutableData *transcript;
@property NSDictionary *before;
@property NSDictionary *owned;
@property NSString *sessionID;
@property NSDate *expiry;
@property BOOL cancelled;
@property int lockFD;
- (NSString *)executable;
- (NSString *)keychainService;
- (BOOL)verifyExecutable:(NSString *)path;
- (NSData *)security:(NSArray *)arguments input:(NSData *)input status:(int *)status;
- (OSStatus)replaceAccount:(NSString *)account previous:(NSDictionary *)previous;
- (NSDictionary *)snapshot:(NSError **)error;
- (BOOL)restore:(NSError **)error;
- (NSDictionary *)begin:(NSError **)error;
- (NSDictionary *)finish:(NSDictionary *)challenge error:(NSError **)error;
- (void)cancel;
@end
@implementation SSGitHubCLILogin
- (instancetype)init {if((self=[super init]))_lockFD=-1;return self;}
- (NSString *)executable {return [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/Helpers/gh"];}
- (BOOL)verifyExecutable:(NSString *)path {
    NSData *binary=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];if(!binary.length || binary.length>UINT32_MAX)return NO;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(binary.bytes,(CC_LONG)binary.length,digest);NSMutableString *hash=NSMutableString.string;for(NSUInteger n=0;n<CC_SHA256_DIGEST_LENGTH;n++)[hash appendFormat:@"%02x",digest[n]];
    return [hash isEqual:@"aa97dfb4a82f7c56063cdcbfaa39a738b923c1bdca29bd5a041b8e959ca38e04"];
}
- (NSString *)keychainService {return @"gh:github.com";}
- (NSDictionary *)snapshot:(NSError **)error {
    CFTypeRef result=NULL;
    OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:[self keychainService],(__bridge id)kSecMatchLimit:(__bridge id)kSecMatchLimitAll,(__bridge id)kSecReturnAttributes:@YES},&result);
    if(status==errSecItemNotFound)return @{};
    if(status!=errSecSuccess){if(error)*error=[NSError errorWithDomain:@"SSGitHubCLI" code:status userInfo:@{NSLocalizedDescriptionKey:@"无法保护现有 GitHub CLI 钥匙串登录。请允许钥匙串访问后重试。"}];return nil;}
    NSArray *items=CFBridgingRelease(result);NSMutableDictionary *snapshot=NSMutableDictionary.dictionary;
    for(NSDictionary *item in items){
        NSString *account=item[(__bridge id)kSecAttrAccount] ?: @"";
        if(snapshot[account]){if(error)*error=GHError(@"检测到多个同名官方钥匙串项，无法安全保护原登录。");return nil;}
        if(account.length && [account rangeOfString:@"^[A-Za-z0-9][A-Za-z0-9-]{0,38}$" options:NSRegularExpressionSearch].location==NSNotFound){if(error)*error=GHError(@"官方钥匙串账户格式无法核验，请先检查其他 GitHub 工具登录。");return nil;}
        // Use the same trusted macOS reader as the official keyring. Raw output is
        // captured only in memory, never forwarded to a console or log.
        NSData *raw=[self security:@[@"find-generic-password",@"-s",[self keychainService],@"-wa",account] input:nil status:NULL];
        NSString *value=[[[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if(!value.length || [value rangeOfString:@"^[A-Za-z0-9:_=+/-]+$" options:NSRegularExpressionSearch].location==NSNotFound){if(error)*error=GHError(@"无法读取官方钥匙串凭据，请检查系统钥匙串权限。");return nil;}
        NSMutableDictionary *complete=item.mutableCopy;complete[(__bridge id)kSecValueData]=[value dataUsingEncoding:NSUTF8StringEncoding];snapshot[account]=complete;
    }
    return snapshot;
}
- (BOOL)restore:(NSError **)error {
    NSDictionary *current=[self snapshot:error];if(!current)return NO;
    for(NSString *account in self.owned){
        NSDictionary *expected=self.owned[account],*actual=current[account],*previous=self.before[account];
        // A different value/modification date belongs to another process. Leave it alone.
        if(![actual[(__bridge id)kSecValueData] isEqual:expected[(__bridge id)kSecValueData]] || ![actual[(__bridge id)kSecAttrModificationDate] isEqual:expected[(__bridge id)kSecAttrModificationDate]])continue;
        OSStatus status=[self replaceAccount:account previous:previous];
        if(status!=errSecSuccess && status!=errSecItemNotFound){if(error)*error=GHError(@"无法恢复原有 GitHub CLI 登录，已停止连接。请检查钥匙串访问权限。");return NO;}
    }
    self.owned=nil;self.before=nil;return YES;
}
- (NSData *)security:(NSArray *)arguments input:(NSData *)input status:(int *)status {
    NSTask *task=NSTask.new;task.executableURL=[NSURL fileURLWithPath:@"/usr/bin/security"];task.arguments=arguments;
    task.environment=@{@"HOME":NSHomeDirectory(),@"PATH":@"/usr/bin:/bin",@"LANG":@"en_US.UTF-8"};
    NSPipe *output=NSPipe.pipe,*pipe=NSPipe.pipe;task.standardOutput=output;task.standardError=NSFileHandle.fileHandleWithNullDevice;task.standardInput=input ? pipe:NSFileHandle.fileHandleWithNullDevice;
    if(![task launchAndReturnError:NULL]){if(status)*status=-1;return nil;}
    if(input){[pipe.fileHandleForWriting writeData:input];[pipe.fileHandleForWriting closeFile];}
    NSData *raw=[output.fileHandleForReading readDataToEndOfFile];[task waitUntilExit];if(status)*status=task.terminationStatus;return task.terminationStatus==0 ? raw:nil;
}
- (OSStatus)replaceAccount:(NSString *)account previous:(NSDictionary *)previous {
    int status=0;
    if(!previous){[self security:@[@"delete-generic-password",@"-s",[self keychainService],@"-a",account] input:nil status:&status];return status==0 ? errSecSuccess:errSecAuthFailed;}
    NSString *raw=[[NSString alloc] initWithData:previous[(__bridge id)kSecValueData] encoding:NSUTF8StringEncoding];
    if(!raw.length || [raw rangeOfString:@"^[A-Za-z0-9:_=+/-]+$" options:NSRegularExpressionSearch].location==NSNotFound)return errSecParam;
    // GitHub login names and encoded keyring values were checked before interpolation.
    NSString *command=[NSString stringWithFormat:@"add-generic-password -U -s '%@' -a '%@' -w '%@'\n",[self keychainService],account,raw];
    [self security:@[@"-i"] input:[command dataUsingEncoding:NSUTF8StringEncoding] status:&status];return status==0 ? errSecSuccess:errSecAuthFailed;
}
- (void)releaseLock {if(self.lockFD>=0){flock(self.lockFD,LOCK_UN);close(self.lockFD);self.lockFD=-1;}}
- (NSDictionary *)begin:(NSError **)error {
    NSString *executable=[self executable];if(![NSFileManager.defaultManager isExecutableFileAtPath:executable] || ![self verifyExecutable:executable]){if(error)*error=GHError(@"内置 GitHub 官方登录工具缺失，请重新安装完整应用。");return nil;}
    NSString *directory=[SSDataDirectory().path stringByAppendingPathComponent:@"official-login"];
    if(![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error])return nil;
    self.lockFD=open([[directory stringByAppendingPathComponent:@"login.lock"] fileSystemRepresentation],O_CREAT|O_RDWR|O_NOFOLLOW,0600);
    if(self.lockFD<0 || flock(self.lockFD,LOCK_EX|LOCK_NB)!=0){[self releaseLock];if(error)*error=GHError(@"另一窗口正在登录，请完成或取消后重试。");return nil;}
    // Public preferences only; login is denied ordinary filesystem writes, including fallback.
    NSString *config=[directory stringByAppendingPathComponent:@"config.yml"];
    if(![@"version: 1\nclipboard: disabled\nprompt: disabled\n" writeToFile:config atomically:YES encoding:NSUTF8StringEncoding error:error]){[self releaseLock];return nil;}
    self.before=[self snapshot:error];if(!self.before){[self releaseLock];return nil;}
    self.transcript=NSMutableData.data;self.output=NSPipe.pipe;self.task=NSTask.new;self.task.executableURL=[NSURL fileURLWithPath:@"/usr/bin/sandbox-exec"];
    self.task.arguments=@[@"-p",SSCLIProfile(),executable,@"auth",@"login",@"--hostname",@"github.com",@"--web",@"--skip-ssh-key"];
    self.task.environment=SSCLIEnvironment(directory);self.task.currentDirectoryURL=[NSURL fileURLWithPath:directory];self.task.standardInput=[NSFileHandle fileHandleWithNullDevice];self.task.standardOutput=self.output;self.task.standardError=self.output;
    __weak typeof(self) weakSelf=self;
    self.output.fileHandleForReading.readabilityHandler=^(NSFileHandle *handle){NSData *data=handle.availableData;if(!data.length){handle.readabilityHandler=nil;return;}@synchronized(weakSelf){if(weakSelf.transcript.length+data.length<=65536)[weakSelf.transcript appendData:data];else [weakSelf cancel];}};
    if(![self.task launchAndReturnError:error]){self.output.fileHandleForReading.readabilityHandler=nil;[self releaseLock];return nil;}
    self.sessionID=NSUUID.UUID.UUIDString;self.expiry=[NSDate dateWithTimeIntervalSinceNow:900];
    NSRegularExpression *pattern=[NSRegularExpression regularExpressionWithPattern:@"(?:one-time code|code):\\s*([A-Z0-9]{4}-[A-Z0-9]{4})" options:NSRegularExpressionCaseInsensitive error:NULL];
    for(NSInteger n=0;n<450 && !self.cancelled;n++){
        NSString *text;@synchronized(self){text=[[NSString alloc] initWithData:self.transcript.copy encoding:NSUTF8StringEncoding] ?: @"";}
        NSTextCheckingResult *match=[pattern firstMatchInString:text options:0 range:NSMakeRange(0,text.length)];
        if(match)return @{@"device_code":self.sessionID,@"user_code":[text substringWithRange:[match rangeAtIndex:1]],@"verification_uri":@"https://github.com/login/device",@"expires_at":self.expiry};
        if(!self.task.running)break;[NSThread sleepForTimeInterval:0.1];
    }
    [self cancel];[self.task waitUntilExit];self.output.fileHandleForReading.readabilityHandler=nil;[self releaseLock];
    if(error)*error=GHError(@"无法开始安全登录。请检查网络；系统必须允许内置工具的写入保护。");return nil;
}
- (NSDictionary *)finish:(NSDictionary *)challenge error:(NSError **)error {
    if(![challenge[@"device_code"] isEqual:self.sessionID]){if(error)*error=GHError(@"登录会话已变化，请重新开始。");return nil;}
    while(self.task.running && !self.cancelled && self.expiry.timeIntervalSinceNow>0)[NSThread sleepForTimeInterval:0.1];
    if(self.task.running)[self cancel];[self.task waitUntilExit];self.output.fileHandleForReading.readabilityHandler=nil;
    NSData *tail=[self.output.fileHandleForReading readDataToEndOfFile];@synchronized(self){if(self.transcript.length+tail.length<=65536)[self.transcript appendData:tail];}
    // Success text precedes storage in gh; keychain changes are the source of truth.
    NSDictionary *after=[self snapshot:error];NSMutableDictionary *changed=NSMutableDictionary.dictionary;
    for(NSString *account in after)if(![after[account][(__bridge id)kSecValueData] isEqual:self.before[account][(__bridge id)kSecValueData]] || ![after[account][(__bridge id)kSecAttrModificationDate] isEqual:self.before[account][(__bridge id)kSecAttrModificationDate]])changed[account]=after[account];
    NSArray *users=[[changed allKeys] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *account,NSDictionary *bindings){return account.length>0;}]];
    NSString *account=users.count==1 ? users.firstObject:nil;NSString *token=account ? SSCLIDecode(changed[account][(__bridge id)kSecValueData]):nil;
    NSString *active=SSCLIDecode(after[@""][(__bridge id)kSecValueData]);
    NSString *text;@synchronized(self){text=[[NSString alloc] initWithData:self.transcript.copy encoding:NSUTF8StringEncoding] ?: @"";}
    if(token.length && [text containsString:@"Authentication complete"]){NSMutableDictionary *owned=[@{account:changed[account]} mutableCopy];if([token isEqual:active])owned[@""]=after[@""];self.owned=owned;}
    BOOL valid=!self.cancelled && token.length && self.owned.count==2;
    // Nonzero config-write exit is expected. It cannot turn keychain failure into success.
    if(![self restore:error])valid=NO;[self releaseLock];self.transcript=nil;
    if(!valid){if(error && !*error)*error=GHError(self.cancelled ? @"已取消登录；已保存课程保留。":@"未取得可核验的本次钥匙串凭据，登录未完成。请关闭其他正在登录的 GitHub 工具后重试。");return nil;}
    return @{@"access_token":token,@"login":account};
}
- (void)cancel {
    self.cancelled=YES;BOOL storing=NO;@synchronized(self){NSString *text=[[NSString alloc] initWithData:self.transcript.copy encoding:NSUTF8StringEncoding];storing=[text containsString:@"Authentication complete"];}
    // Once authentication is complete, finish the short keychain transaction and
    // restore shared state before returning cancellation. Never orphan a writer.
    if(self.task.running && !storing)[self.task terminate];
}
- (void)dealloc {if(self.task.running)[self.task terminate];self.output.fileHandleForReading.readabilityHandler=nil;[self releaseLock];}
@end
