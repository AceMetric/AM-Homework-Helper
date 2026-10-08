#import "SSGitHub.h"
#import "SSLocalData.h"
#import "SSSecurity.h"

static NSError *GHError(NSString *message) { return [NSError errorWithDomain:@"SSGitHub" code:1 userInfo:@{NSLocalizedDescriptionKey:SSRedactedText(message ?: @"GitHub 请求失败")}]; }

#import "SSGitHubCLI.inc"

@interface SSGitHub () <NSURLSessionTaskDelegate>
@property (atomic) BOOL loginCancelled;
@property SSGitHubCLILogin *cliLogin;
@property NSString *responseScopes;
@end

@implementation SSGitHub
- (instancetype)init {
    if ((self = [super init])) {
        id settings = SSReadPlist(@"settings.plist");
        NSString *configured = [settings isKindOfClass:NSDictionary.class] ? settings[@"clientID"] : nil;
        NSString *oauth = [NSBundle.mainBundle objectForInfoDictionaryKey:@"SSOAuthClientID"];
        NSString *helper=[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/Helpers/gh"];
        BOOL official=[[NSBundle.mainBundle objectForInfoDictionaryKey:@"SSDefaultAuthentication"] isEqual:@"githubCLI"] || [NSFileManager.defaultManager isExecutableFileAtPath:helper];
        NSString *choice=[settings[@"authSelectionVersion"] integerValue]>=2 ? settings[@"authType"] : nil;
        self.authType = official && (!choice.length || [choice isEqual:@"githubCLI"]) ? @"githubCLI" : [settings[@"authType"] isEqual:@"githubApp"] || !oauth.length ? @"githubApp" : @"oauth";
        self.clientID = [self.authType isEqual:@"githubCLI"] ? @"github-cli" : [self.authType isEqual:@"oauth"] ? oauth : ([configured isKindOfClass:NSString.class] ? configured : ([NSBundle.mainBundle objectForInfoDictionaryKey:@"SSGitHubClientID"] ?: @""));
        NSString *install = [settings isKindOfClass:NSDictionary.class] ? settings[@"installationURL"] : nil;
        self.installationURL = [install isKindOfClass:NSString.class] ? install : ([NSBundle.mainBundle objectForInfoDictionaryKey:@"SSGitHubInstallationURL"] ?: @"");
    }
    return self;
}

- (id)requestURL:(NSURL *)url form:(NSDictionary *)form token:(NSString *)token error:(NSError **)error {
    if (![url.scheme isEqual:@"https"] || ![@[@"github.com", @"api.github.com"] containsObject:url.host]) { if (error) *error = GHError(@"拒绝向非 GitHub 地址发送授权请求"); return nil; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 30;
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];
    if (token.length) [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    if (form) {
        request.HTTPMethod = @"POST";
        NSMutableArray *parts = [NSMutableArray array];
        NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
        for (NSString *key in form) [parts addObject:[NSString stringWithFormat:@"%@=%@", [key stringByAddingPercentEncodingWithAllowedCharacters:allowed], [[form[key] description] stringByAddingPercentEncodingWithAllowedCharacters:allowed]]];
        request.HTTPBody = [[parts componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding];
        [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    }
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSData *responseData = nil; __block NSURLResponse *response = nil; __block NSError *networkError = nil;
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.URLCache = nil; configuration.HTTPShouldSetCookies = NO; configuration.HTTPCookieStorage = nil; configuration.URLCredentialStorage = nil;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
        responseData = data; response = res; networkError = err; dispatch_semaphore_signal(done);
    }]; [task resume];
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 35 * NSEC_PER_SEC)) != 0) {
        [session invalidateAndCancel]; if (error) *error = GHError(@"GitHub 请求超时，请稍后重试"); return nil;
    }
    [session finishTasksAndInvalidate];
    if (networkError) { if (error) *error = GHError(networkError.localizedDescription); return nil; }
    id object = responseData ? [NSJSONSerialization JSONObjectWithData:responseData options:0 error:NULL] : nil;
    NSInteger status = [(NSHTTPURLResponse *)response statusCode];
    self.responseScopes=nil;
    for(NSString *key in [(NSHTTPURLResponse *)response allHeaderFields])if([key.lowercaseString isEqual:@"x-oauth-scopes"])self.responseScopes=[[(NSHTTPURLResponse *)response allHeaderFields][key] description];
    if (status < 200 || status >= 300 || !object) {
        if (error) {
            NSString *detail = [object isKindOfClass:NSDictionary.class] ? (object[@"message"] ?: object[@"error_description"] ?: @"GitHub 请求失败") : @"GitHub 响应无效";
            NSDictionary *headers = [(NSHTTPURLResponse *)response allHeaderFields]; NSString *sso = @"";
            for (NSString *key in headers) if ([key.lowercaseString isEqual:@"x-github-sso"]) sso = [headers[key] description];
            NSString *kind = status == 401 ? @"login" : ([sso containsString:@"required"] ? @"sso" : (status == 403 && ([detail.lowercaseString containsString:@"oauth"] || [detail.lowercaseString containsString:@"organization"]) ? @"approval" : (status == 404 || status == 403 ? @"permission" : @"network")));
            if([self.authType isEqual:@"githubCLI"] && [kind isEqual:@"approval"])kind=@"permission";
            NSString *message = [kind isEqual:@"login"] ? @"GitHub 登录已失效，请重新登录。" : ([kind isEqual:@"sso"] ? @"学校要求单点登录，请在浏览器登录学校组织后重新检测。" : ([kind isEqual:@"approval"] ? @"学校组织尚未允许此应用，请申请批准后重新检测。" : ([kind isEqual:@"permission"] ? @"无法访问该仓库，请核对课程权限及学校组织授权。" : @"GitHub 暂时无法连接，请稍后重试。")));
            *error = [NSError errorWithDomain:@"SSGitHub" code:status userInfo:@{NSLocalizedDescriptionKey:message,@"SSIssue":kind,@"SSDetail":SSRedactedText(detail)}];
        }
        return nil;
    }
    return object;
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    completionHandler(nil); // Authenticated requests never follow redirects.
}
- (NSString *)credentialAccount { return [self.authType isEqual:@"githubCLI"] ? @"github.cli" : [self.authType isEqual:@"oauth"] ? @"github.oauth" : @"github"; }
- (NSDictionary *)loadCredentials { return SSReadSecret([self credentialAccount]); }
- (BOOL)storeCredentials:(NSDictionary *)credentials { return SSWriteSecret([self credentialAccount], credentials); }
- (BOOL)hasCredentials { NSDictionary *stored=[self loadCredentials];return [stored[@"client_id"] isEqual:self.clientID] && [stored[@"access_token"] length]>0; }
- (BOOL)selectAuthentication:(NSString *)type error:(NSError **)error {
    if (![@[@"githubCLI",@"oauth",@"githubApp"] containsObject:type]) {if(error)*error=GHError(@"登录方式无效");return NO;}
    NSString *client=[type isEqual:@"githubCLI"] ? @"github-cli" : [type isEqual:@"oauth"] ? [NSBundle.mainBundle objectForInfoDictionaryKey:@"SSOAuthClientID"] : (SSReadPlist(@"settings.plist")[@"clientID"] ?: [NSBundle.mainBundle objectForInfoDictionaryKey:@"SSGitHubClientID"]);
    if(!client.length){if(error)*error=GHError(@"此构建尚未配置该登录方式");return NO;}
    NSMutableDictionary *settings=[SSReadPlist(@"settings.plist") mutableCopy] ?: NSMutableDictionary.dictionary;settings[@"authType"]=type;settings[@"authSelectionVersion"]=@2;
    if(!SSWritePlist(@"settings.plist",settings,error))return NO;
    [self cancelDeviceLogin];self.authType=type;self.clientID=client;return YES;
}
- (BOOL)waitForPollingInterval:(NSTimeInterval)interval {
    for (NSInteger second = 0; second < ceil(interval); second++) { if (self.loginCancelled) return NO; [NSThread sleepForTimeInterval:1]; }
    return !self.loginCancelled;
}

- (NSDictionary *)beginDeviceLogin:(NSError **)error {
    self.loginCancelled = NO;
    if([self.authType isEqual:@"githubCLI"]){[self.cliLogin cancel];self.cliLogin=SSGitHubCLILogin.new;return [self.cliLogin begin:error];}
    if (!self.clientID.length) { if (error) *error = GHError(@"请先填写公开的 GitHub App Client ID"); return nil; }
    NSMutableDictionary *form=[@{@"client_id":self.clientID} mutableCopy];if([self.authType isEqual:@"oauth"])form[@"scope"]=@"repo";
    id result = [self requestURL:[NSURL URLWithString:@"https://github.com/login/device/code"] form:form token:nil error:error];
    if (![result isKindOfClass:NSDictionary.class] || ![result[@"device_code"] isKindOfClass:NSString.class] || ![result[@"user_code"] isKindOfClass:NSString.class]) { if (error) *error = GHError(@"无法申请设备授权，请检查 Client ID 和 Enable Device Flow 设置"); return nil; }
    NSMutableDictionary *challenge=[result mutableCopy];challenge[@"expires_at"]=[NSDate dateWithTimeIntervalSinceNow:MAX(0,[result[@"expires_in"] doubleValue])];return challenge;
}

- (BOOL)completeDeviceLogin:(NSDictionary *)challenge error:(NSError **)error {
    if([self.authType isEqual:@"githubCLI"]){
        NSDictionary *credential=[self.cliLogin finish:challenge error:error];self.cliLogin=nil;if(!credential || self.loginCancelled)return NO;
        NSDictionary *me=[self requestURL:[NSURL URLWithString:@"https://api.github.com/user"] form:nil token:credential[@"access_token"] error:error];
        NSArray *scopes=[[self.responseScopes stringByReplacingOccurrencesOfString:@"," withString:@" "] componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if(![me[@"id"] isKindOfClass:NSNumber.class] || ![me[@"login"] isKindOfClass:NSString.class] || [me[@"login"] caseInsensitiveCompare:credential[@"login"]]!=NSOrderedSame){if(error && !*error)*error=GHError(@"官方登录账户核验失败，请重试。");return NO;}
        if(![scopes containsObject:@"repo"] || ![scopes containsObject:@"read:org"] || ![scopes containsObject:@"gist"]){if(error)*error=GHError(@"官方登录未提供所需权限，请重新完成 GitHub CLI 浏览器授权。");return NO;}
        if(self.loginCancelled)return NO;
        if(![self storeCredentials:@{@"client_id":@"github-cli",@"authType":@"githubCLI",@"access_token":credential[@"access_token"],@"userID":me[@"id"],@"login":me[@"login"],@"scope":self.responseScopes}]){if(error)*error=GHError(@"无法保存本应用钥匙串凭据，登录未完成；不会改为文件保存。");return NO;}return YES;
    }
    NSString *deviceCode = challenge[@"device_code"];
    if (!deviceCode.length) { if (error) *error = GHError(@"授权码无效"); return NO; }
    NSTimeInterval interval = MAX(5, [challenge[@"interval"] doubleValue]);
    NSDate *expiry=[challenge[@"expires_at"] isKindOfClass:NSDate.class] ? challenge[@"expires_at"] : [NSDate dateWithTimeIntervalSinceNow:MAX(0,[challenge[@"expires_in"] doubleValue])];
    while ([expiry timeIntervalSinceNow] > 0) {
        if (![self waitForPollingInterval:interval]) { if (error) *error = GHError(@"已取消 GitHub 登录"); return NO; }
        id result = [self requestURL:[NSURL URLWithString:@"https://github.com/login/oauth/access_token"] form:@{@"client_id":self.clientID, @"device_code":deviceCode, @"grant_type":@"urn:ietf:params:oauth:grant-type:device_code"} token:nil error:error];
        if (!result) return NO;
        NSString *issue = result[@"error"];
        if ([issue isEqual:@"authorization_pending"]) continue;
        if ([issue isEqual:@"slow_down"]) { interval = MAX(interval + 5, [result[@"interval"] doubleValue]); continue; }
        if (issue.length) { if (error) *error = GHError([issue isEqual:@"access_denied"] ? @"你取消了 GitHub 授权，可以重新登录。" : ([issue isEqual:@"expired_token"] ? @"设备验证码已过期，请重新登录获取新代码。" : (result[@"error_description"] ?: issue))); return NO; }
        NSString *token = result[@"access_token"];
        if (![token isKindOfClass:NSString.class] || !token.length) { if (error) *error = GHError(@"GitHub 没有返回访问令牌"); return NO; }
        NSMutableDictionary *stored = [@{@"access_token":token, @"client_id":self.clientID, @"authType":self.authType ?: @"githubApp"} mutableCopy];
        if ([self.authType isEqual:@"oauth"]) {
            NSString *scope=[result[@"scope"] isKindOfClass:NSString.class] ? result[@"scope"] : @"";
            NSArray *scopes=[[scope stringByReplacingOccurrencesOfString:@"," withString:@" "] componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if(![scopes containsObject:@"repo"]){if(error)*error=GHError(@"未授予私有仓库访问权限，请重新登录并授权 repo。");return NO;}
            NSDictionary *me=[self requestURL:[NSURL URLWithString:@"https://api.github.com/user"] form:nil token:token error:error];
            if(![me[@"id"] isKindOfClass:NSNumber.class] || ![me[@"login"] isKindOfClass:NSString.class]){if(error && !*error)*error=GHError(@"无法核验登录账户");return NO;}
            stored[@"userID"]=me[@"id"];stored[@"login"]=me[@"login"];stored[@"scope"]=result[@"scope"];
        }
        if ([result[@"refresh_token"] isKindOfClass:NSString.class]) stored[@"refresh_token"] = result[@"refresh_token"];
        if (result[@"expires_in"]) stored[@"expires_at"] = [NSDate dateWithTimeIntervalSinceNow:[result[@"expires_in"] doubleValue] - 60];
        if (self.loginCancelled) return NO;
        if (![self storeCredentials:stored]) { if (error) *error = GHError(@"无法把登录信息保存到 macOS 钥匙串"); return NO; }
        return YES;
    }
    if (error) *error = GHError(@"设备授权已过期，请重新登录");
    return NO;
}

- (NSString *)accessToken:(NSError **)error {
    NSDictionary *stored = [self loadCredentials];
    NSString *token = stored[@"access_token"];
    if (!token.length) { if (error) *error = GHError(@"请先登录 GitHub"); return nil; }
    if (![stored[@"client_id"] isEqual:self.clientID]) { if (error) *error = GHError(@"应用身份已变化，请重新登录 GitHub"); return nil; }
    NSDate *expiry = stored[@"expires_at"];
    if (!expiry || [expiry timeIntervalSinceNow] > 0) return token;
    NSString *refresh = stored[@"refresh_token"];
    if (!refresh.length) { if (error) *error = GHError(@"GitHub 登录已过期，请重新登录"); return nil; }
    id result = [self requestURL:[NSURL URLWithString:@"https://github.com/login/oauth/access_token"] form:@{@"client_id":stored[@"client_id"] ?: self.clientID, @"grant_type":@"refresh_token", @"refresh_token":refresh} token:nil error:error];
    if (![result[@"access_token"] isKindOfClass:NSString.class]) { if (error && !*error) *error = GHError(@"刷新登录失败，请重新登录"); return nil; }
    NSMutableDictionary *next=[stored mutableCopy];next[@"access_token"]=result[@"access_token"];next[@"refresh_token"]=result[@"refresh_token"] ?: refresh;next[@"expires_at"]=[NSDate dateWithTimeIntervalSinceNow:MAX(60,[result[@"expires_in"] doubleValue])-60];
    if (![self storeCredentials:next]) { if (error) *error = GHError(@"无法更新钥匙串令牌"); return nil; }
    return next[@"access_token"];
}

- (id)api:(NSString *)path error:(NSError **)error {
    NSString *token = [self accessToken:error]; if (!token) return nil;
    NSURL *url = [NSURL URLWithString:[@"https://api.github.com" stringByAppendingString:path]];
    return [self requestURL:url form:nil token:token error:error];
}

- (NSDictionary *)user:(NSError **)error { id item = [self api:@"/user" error:error]; return [item isKindOfClass:NSDictionary.class] ? item : nil; }
- (NSDictionary *)repository:(NSString *)fullName error:(NSError **)error {
    if (![SSCanonicalRepository([NSString stringWithFormat:@"https://github.com/%@.git", fullName]) isEqual:fullName.lowercaseString]) { if (error) *error = GHError(@"仓库名称无效"); return nil; }
    id item = [self api:[@"/repos/" stringByAppendingString:fullName] error:error];
    return [item isKindOfClass:NSDictionary.class] ? item : nil;
}
- (NSArray<NSDictionary *> *)accessibleForks:(NSError **)error {
    NSDictionary *me = [self user:error]; if (!me) return nil;
    NSString *login = me[@"login"];
    NSMutableArray *forks = [NSMutableArray array];
    if([@[@"oauth",@"githubCLI"] containsObject:self.authType]){
        for(NSInteger page=1;;page++){
            id repos=[self api:[NSString stringWithFormat:@"/user/repos?affiliation=owner&per_page=100&page=%ld",(long)page] error:error];
            if(![repos isKindOfClass:NSArray.class])return nil;
            for(NSDictionary *repo in repos)if([repo[@"fork"] boolValue] && [repo[@"owner"][@"login"] caseInsensitiveCompare:login]==NSOrderedSame)[forks addObject:repo];
            if([repos count]<100)break;
        }return forks;
    }
    for (NSInteger page = 1; page <= 20; page++) {
        id installations = [self api:[NSString stringWithFormat:@"/user/installations?per_page=100&page=%ld", (long)page] error:error];
        if (![installations isKindOfClass:NSDictionary.class]) return nil;
        NSArray *items = installations[@"installations"]; if (![items isKindOfClass:NSArray.class]) break;
        for (NSDictionary *installation in items) {
            NSNumber *iid = installation[@"id"]; if (!iid) continue;
            for (NSInteger repoPage = 1; repoPage <= 20; repoPage++) {
                id pageResult = [self api:[NSString stringWithFormat:@"/user/installations/%@/repositories?per_page=100&page=%ld", iid, (long)repoPage] error:error];
                if (![pageResult isKindOfClass:NSDictionary.class]) return nil;
                NSArray *repos = pageResult[@"repositories"]; if (![repos isKindOfClass:NSArray.class]) break;
                for (NSDictionary *repo in repos) if ([repo[@"fork"] boolValue] && [repo[@"owner"][@"login"] caseInsensitiveCompare:login] == NSOrderedSame) [forks addObject:repo];
                if (repos.count < 100) break;
            }
        }
        if (items.count < 100) break;
    }
    return forks;
}
- (NSDictionary *)verifyCourse:(NSDictionary *)course error:(NSError **)error {
    NSDictionary *user = [self user:error]; if (!user) return nil;
    NSDictionary *repo = [self repository:course[@"fork"] error:error]; if (!repo) return nil;
    NSDictionary *parent = repo[@"parent"];
    BOOL valid = [repo[@"fork"] boolValue] && [repo[@"id"] isEqual:course[@"forkID"]] && [repo[@"owner"][@"id"] isEqual:user[@"id"]] && [user[@"id"] isEqual:course[@"ownerID"]] && [parent[@"id"] isEqual:course[@"upstreamID"]] && [repo[@"full_name"] caseInsensitiveCompare:course[@"fork"]] == NSOrderedSame && [parent[@"full_name"] caseInsensitiveCompare:course[@"upstream"]] == NSOrderedSame && ![repo[@"id"] isEqual:parent[@"id"]];
    if (!valid) { if (error) *error = GHError(@"当前账户、个人 fork 或老师上游身份变化，已阻止写操作。请重新添加课程。"); return nil; }
    return user;
}
- (NSDictionary *)readableTeacher:(NSDictionary *)course error:(NSError **)error {
    if(![self verifyCourse:course error:error])return nil;
    NSDictionary *teacher=[self repository:course[@"upstream"] error:error];
    if(!teacher || ![teacher[@"id"] isEqual:course[@"upstreamID"]] || [teacher[@"full_name"] caseInsensitiveCompare:course[@"upstream"]]!=NSOrderedSame){if(error && !*error)*error=GHError(@"老师仓库身份已变化，请重新核验课程。");return nil;}
    NSString *branch=teacher[@"default_branch"];
    if(!SSValidBranch(branch)){if(error)*error=GHError(@"老师仓库默认分支无效。");return nil;}
    // Metadata alone does not prove content access. Verify the current teacher branch.
    NSString *ref=[NSString stringWithFormat:@"/repos/%@/git/ref/heads/%@",course[@"upstream"],[branch stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet]];
    if(![self api:ref error:error])return nil;
    return teacher;
}
- (void)cancelDeviceLogin { self.loginCancelled = YES; [self.cliLogin cancel]; }
- (void)signOut { [self cancelDeviceLogin]; SSDeleteSecret([self credentialAccount]); }
@end
