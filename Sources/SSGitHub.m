#import "SSGitHub.h"
#import "SSLocalData.h"
#import "SSSecurity.h"

static NSError *GHError(NSString *message) { return [NSError errorWithDomain:@"SSGitHub" code:1 userInfo:@{NSLocalizedDescriptionKey:SSRedactedText(message ?: @"GitHub 请求失败")}]; }

@interface SSGitHub () <NSURLSessionTaskDelegate>
@property (atomic) BOOL loginCancelled;
@end

@implementation SSGitHub
- (instancetype)init {
    if ((self = [super init])) {
        id settings = SSReadPlist(@"settings.plist");
        NSString *configured = [settings isKindOfClass:NSDictionary.class] ? settings[@"clientID"] : nil;
        self.clientID = [configured isKindOfClass:NSString.class] ? configured : ([NSBundle.mainBundle objectForInfoDictionaryKey:@"SSGitHubClientID"] ?: @"");
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
    configuration.URLCache = nil; configuration.HTTPShouldSetCookies = NO;
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
    if (status < 200 || status >= 300 || !object) {
        if (error) *error = GHError([object isKindOfClass:NSDictionary.class] ? (object[@"message"] ?: object[@"error_description"] ?: @"GitHub 请求失败") : @"GitHub 响应无效");
        return nil;
    }
    return object;
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    completionHandler(nil); // Authenticated requests never follow redirects.
}
- (NSDictionary *)loadCredentials { return SSReadSecret(@"github"); }
- (BOOL)storeCredentials:(NSDictionary *)credentials { return SSWriteSecret(@"github", credentials); }
- (BOOL)waitForPollingInterval:(NSTimeInterval)interval {
    for (NSInteger second = 0; second < ceil(interval); second++) { if (self.loginCancelled) return NO; [NSThread sleepForTimeInterval:1]; }
    return !self.loginCancelled;
}

- (NSDictionary *)beginDeviceLogin:(NSError **)error {
    self.loginCancelled = NO;
    if (!self.clientID.length) { if (error) *error = GHError(@"请先填写公开的 GitHub App Client ID"); return nil; }
    id result = [self requestURL:[NSURL URLWithString:@"https://github.com/login/device/code"] form:@{@"client_id":self.clientID} token:nil error:error];
    if (![result isKindOfClass:NSDictionary.class] || ![result[@"device_code"] isKindOfClass:NSString.class] || ![result[@"user_code"] isKindOfClass:NSString.class]) { if (error) *error = GHError(@"无法申请设备授权，请检查 Client ID 和 Enable Device Flow 设置"); return nil; }
    return result;
}

- (BOOL)completeDeviceLogin:(NSDictionary *)challenge error:(NSError **)error {
    NSString *deviceCode = challenge[@"device_code"];
    if (!deviceCode.length) { if (error) *error = GHError(@"授权码无效"); return NO; }
    NSTimeInterval interval = MAX(5, [challenge[@"interval"] doubleValue]);
    NSDate *expiry = [NSDate dateWithTimeIntervalSinceNow:MAX(60, [challenge[@"expires_in"] doubleValue])];
    while ([expiry timeIntervalSinceNow] > 0) {
        if (![self waitForPollingInterval:interval]) { if (error) *error = GHError(@"已取消 GitHub 登录"); return NO; }
        id result = [self requestURL:[NSURL URLWithString:@"https://github.com/login/oauth/access_token"] form:@{@"client_id":self.clientID, @"device_code":deviceCode, @"grant_type":@"urn:ietf:params:oauth:grant-type:device_code"} token:nil error:error];
        if (!result) return NO;
        NSString *issue = result[@"error"];
        if ([issue isEqual:@"authorization_pending"]) continue;
        if ([issue isEqual:@"slow_down"]) { interval = MAX(interval + 5, [result[@"interval"] doubleValue]); continue; }
        if (issue.length) { if (error) *error = GHError(result[@"error_description"] ?: issue); return NO; }
        NSString *token = result[@"access_token"];
        if (!token.length) { if (error) *error = GHError(@"GitHub 没有返回访问令牌"); return NO; }
        NSMutableDictionary *stored = [@{@"access_token":token, @"client_id":self.clientID} mutableCopy];
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
    NSDictionary *next = @{@"access_token":result[@"access_token"], @"refresh_token":result[@"refresh_token"] ?: refresh, @"client_id":self.clientID, @"expires_at":[NSDate dateWithTimeIntervalSinceNow:[result[@"expires_in"] doubleValue] - 60]};
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
- (void)cancelDeviceLogin { self.loginCancelled = YES; }
- (void)signOut { self.loginCancelled = YES; SSDeleteSecret(@"github"); }
@end
