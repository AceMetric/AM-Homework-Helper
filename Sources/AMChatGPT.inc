#import "AMChatGPT.h"
#import <Security/Security.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <poll.h>
#import <unistd.h>
#import <stdatomic.h>

// This integration owns its OAuth registration. Desktop Codex credentials and
// private ChatGPT endpoints are deliberately outside its authentication boundary.
static NSError *AMCGError(NSString *message,NSInteger code){return [NSError errorWithDomain:@"AMChatGPT" code:code userInfo:@{NSLocalizedDescriptionKey:message}];}
static NSDictionary *CGObject(id value){return [value isKindOfClass:NSDictionary.class] ? value:@{};}
static NSArray *CGArray(id value){return [value isKindOfClass:NSArray.class] ? value:@[];}
static NSString *CGText(id value){return [value isKindOfClass:NSString.class] ? value:@"";}
static NSString *CGBase64(NSData *data){return [[[[data base64EncodedStringWithOptions:0] stringByReplacingOccurrencesOfString:@"+" withString:@"-"] stringByReplacingOccurrencesOfString:@"/" withString:@"_"] stringByReplacingOccurrencesOfString:@"=" withString:@""];}
static NSData *CGDecode(NSString *text){if(!text.length || text.length>100000)return nil;NSString *s=[[text stringByReplacingOccurrencesOfString:@"-" withString:@"+"] stringByReplacingOccurrencesOfString:@"_" withString:@"/"];while(s.length%4)s=[s stringByAppendingString:@"="];return [[NSData alloc] initWithBase64EncodedString:s options:0];}
static NSString *CGRandom(void){NSMutableData *data=[NSMutableData dataWithLength:32];return SecRandomCopyBytes(kSecRandomDefault,data.length,data.mutableBytes)==errSecSuccess ? CGBase64(data):nil;}
static NSDictionary *CGJSON(NSData *data){return data.length && data.length<=8*1024*1024 ? CGObject([NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]):@{};}
static NSString *CGForm(NSDictionary *fields){NSURLComponents *parts=NSURLComponents.new;NSMutableArray *items=NSMutableArray.array;for(NSString *key in fields)[items addObject:[NSURLQueryItem queryItemWithName:key value:fields[key]]];parts.queryItems=items;return [parts.percentEncodedQuery stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"];}
@interface CGAccount:NSObject @end
@implementation CGAccount @end
static NSDictionary *CGConnectionCache;
static BOOL CGConnectionLoading=NO;
#ifdef DDL_TESTING
static void (^CGTestBrowserOpener)(NSURL *);
void AMChatGPTSetBrowserOpener(void (^opener)(NSURL *)){CGTestBrowserOpener=opener;}
static NSData *(^CGTestTransport)(NSURLRequest *,NSInteger *,NSError **);
void AMChatGPTSetTransport(NSData *(^transport)(NSURLRequest *,NSInteger *,NSError **)){CGTestTransport=transport;}
#endif
#ifdef DDL_TESTING
static NSDictionary *(^CGTestReadSecret)(NSString *);
static BOOL (^CGTestWriteSecret)(NSString *,NSDictionary *);
void AMChatGPTSetCredentialStore(NSDictionary *(^read)(NSString *),BOOL (^write)(NSString *,NSDictionary *)){CGTestReadSecret=read;CGTestWriteSecret=write;CGConnectionCache=nil;}
#endif
static NSDictionary *CGReadSecret(NSString *key){
#ifdef DDL_TESTING
    if(CGTestReadSecret)return CGTestReadSecret(key);
#endif
    return SSReadSecret(key);
}
static BOOL CGWriteSecret(NSString *key,NSDictionary *value){
#ifdef DDL_TESTING
    if(CGTestWriteSecret){BOOL ok=CGTestWriteSecret(key,value);if(ok && [key isEqual:@"chatgpt-connections"]){@synchronized(CGAccount.class){CGConnectionCache=value.copy;}}return ok;}
#endif
    BOOL ok=SSWriteSecret(key,value);if(ok && [key isEqual:@"chatgpt-connections"]){@synchronized(CGAccount.class){CGConnectionCache=value.copy;}}return ok;
}
@interface CGTransfer:NSObject <NSURLSessionDataDelegate,NSURLSessionTaskDelegate>
@property NSMutableData *bytes;
@property NSURLSessionDataTask *task;
@property dispatch_semaphore_t done;
@property NSError *failure;
@property NSInteger status;
@end
@implementation CGTransfer
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completion {completion(nil);}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {self.status=[(NSHTTPURLResponse *)response statusCode];completion(NSURLSessionResponseAllow);}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if(self.bytes.length+data.length>8*1024*1024){self.failure=AMCGError(@"响应超过安全容量，未保存为完成结果。",1);[task cancel];return;}[self.bytes appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {if(!self.failure)self.failure=error;dispatch_semaphore_signal(self.done);}
@end
static NSData *CGHTTP(NSString *url,NSString *method,NSData *body,NSString *type,NSString *token,BOOL (^cancelled)(void),NSError **error){
    NSURL *target=[NSURL URLWithString:url];
    if(![target.scheme isEqual:@"https"] || ![@[@"api.openai.com",@"auth.openai.com"] containsObject:target.host] || target.user || target.password){if(error)*error=AMCGError(@"无效的 OpenAI 服务地址。",1);return nil;}
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:target];request.HTTPMethod=method;request.HTTPBody=body;request.timeoutInterval=[url hasSuffix:@"/responses"] ? 120:25;
    if(type)[request setValue:type forHTTPHeaderField:@"Content-Type"];if(token)[request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    NSInteger status=0;NSData *data=nil;
#ifdef DDL_TESTING
    if(CGTestTransport){data=CGTestTransport(request,&status,error);}else
#endif
    {
        CGTransfer *transfer=CGTransfer.new;transfer.bytes=NSMutableData.data;transfer.done=dispatch_semaphore_create(0);
        NSURLSessionConfiguration *configuration=NSURLSessionConfiguration.ephemeralSessionConfiguration;configuration.HTTPCookieStorage=nil;configuration.URLCredentialStorage=nil;configuration.URLCache=nil;
        NSURLSession *session=[NSURLSession sessionWithConfiguration:configuration delegate:transfer delegateQueue:nil];transfer.task=[session dataTaskWithRequest:request];[transfer.task resume];
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:request.timeoutInterval+2];
        while(dispatch_semaphore_wait(transfer.done,dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC))){if(cancelled() || deadline.timeIntervalSinceNow<=0){[transfer.task cancel];if(error)*error=AMCGError(cancelled() ? @"已取消":@"连接超时",cancelled() ? NSUserCancelledError:NSURLErrorTimedOut);[session invalidateAndCancel];return nil;}}
        [session finishTasksAndInvalidate];if(transfer.failure){if(error)*error=AMCGError(@"OpenAI 连接未完成，请重试。",transfer.failure.code);return nil;}data=transfer.bytes;status=transfer.status;
    }
    if(status<200 || status>=300){NSString *message=status==401 ? @"ChatGPT 登录已失效，请重新连接。":status==429 ? @"ChatGPT 官方额度或速率限制已达到，请稍后重试。":status==404 ? @"所选模型不可用，请在设置中选择可用替代。":@"OpenAI 请求未完成，请重试。";if(error)*error=AMCGError(message,status);return nil;}return data;
}
static NSDictionary *CGGetJSON(NSString *url,NSError **error){NSData *data=CGHTTP(url,@"GET",nil,nil,nil,^BOOL{return NO;},error);return data ? CGJSON(data):nil;}
// DER encoding for an RSA public key assembled exclusively from the trusted JWKS.
static NSData *CGDER(uint8_t tag,NSData *value){NSMutableData *out=NSMutableData.data;[out appendBytes:&tag length:1];NSUInteger n=value.length;if(n<128){uint8_t b=n;[out appendBytes:&b length:1];}else{uint8_t bytes[sizeof(NSUInteger)],count=0;for(NSUInteger v=n;v;v>>=8)bytes[count++]=v&255;uint8_t prefix=0x80|count;[out appendBytes:&prefix length:1];while(count){uint8_t b=bytes[--count];[out appendBytes:&b length:1];}}[out appendData:value];return out;}
static NSData *CGInteger(NSData *number){if(!number.length)return nil;NSMutableData *value=NSMutableData.data;if(((const uint8_t *)number.bytes)[0]&0x80){uint8_t zero=0;[value appendBytes:&zero length:1];}[value appendData:number];return CGDER(2,value);}
static NSDictionary *CGInvalidIdentity(NSError **error){if(error)*error=AMCGError(@"ChatGPT 身份验证失败，未替换现有连接。",1);return nil;}
static NSDictionary *CGValidate(NSDictionary *tokens,NSDictionary *jwks,NSString *client,NSString *nonce,NSError **error){
    NSArray *segments=[CGText(tokens[@"id_token"]) componentsSeparatedByString:@"."];if(segments.count!=3)return CGInvalidIdentity(error);
    NSDictionary *header=CGJSON(CGDecode(segments[0])),*claims=CGJSON(CGDecode(segments[1]));
    if(![header[@"alg"] isEqual:@"RS256"] || ![claims[@"iss"] isEqual:@"https://auth.openai.com"] || !CGText(claims[@"sub"]).length || ![claims[@"exp"] isKindOfClass:NSNumber.class] || [claims[@"exp"] doubleValue]<=NSDate.date.timeIntervalSince1970 || (nonce && ![claims[@"nonce"] isEqual:nonce]))return CGInvalidIdentity(error);
    id audience=claims[@"aud"];if(![audience isEqual:client] && ![CGArray(audience) containsObject:client])return CGInvalidIdentity(error);
    if(CGArray(audience).count>1 && ![claims[@"azp"] isEqual:client])return CGInvalidIdentity(error);
    for(NSDictionary *key in CGArray(jwks[@"keys"])){
        if(![key isKindOfClass:NSDictionary.class])continue;
        if(![key[@"kid"] isEqual:header[@"kid"]] || ![key[@"kty"] isEqual:@"RSA"] || (key[@"use"] && ![key[@"use"] isEqual:@"sig"]))continue;
        NSData *n=CGDecode(CGText(key[@"n"])),*e=CGDecode(CGText(key[@"e"]));if(n.length<256 || n.length>1024 || !e.length || e.length>8)continue;
        NSMutableData *pair=[CGInteger(n) mutableCopy];[pair appendData:CGInteger(e)];NSData *der=CGDER(0x30,pair);
        SecKeyRef publicKey=SecKeyCreateWithData((__bridge CFDataRef)der,(__bridge CFDictionaryRef)@{(__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeRSA,(__bridge id)kSecAttrKeyClass:(__bridge id)kSecAttrKeyClassPublic},NULL);
        NSData *message=[[NSString stringWithFormat:@"%@.%@",segments[0],segments[1]] dataUsingEncoding:NSUTF8StringEncoding];NSData *signature=CGDecode(segments[2]);
        BOOL valid=publicKey && signature && SecKeyVerifySignature(publicKey,kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256,(__bridge CFDataRef)message,(__bridge CFDataRef)signature,NULL);if(publicKey)CFRelease(publicKey);if(valid)return claims;
    }
return CGInvalidIdentity(error);
}
#ifdef DDL_TESTING
NSDictionary *AMChatGPTValidateIdentity(NSDictionary *tokens,NSDictionary *jwks,NSString *client,NSString *nonce,NSError **error){return CGValidate(tokens,jwks,client,nonce,error);}
#endif
@interface CGRefreshGate:NSObject @end
@implementation CGRefreshGate @end
static _Atomic(bool) CGLoginCancelled=false;
static BOOL CGLoginRunning=NO,CGDisconnecting=NO;
static NSUInteger CGActiveRequests=0;
static NSMutableDictionary *CGConnections(void){
    @synchronized(CGAccount.class){if(CGConnectionCache)return CGConnectionCache.mutableCopy;
        if(NSThread.isMainThread){
            if(!CGConnectionLoading){CGConnectionLoading=YES;dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSDictionary *loaded=CGObject(CGReadSecret(@"chatgpt-connections")).copy;@synchronized(CGAccount.class){if(!CGConnectionCache)CGConnectionCache=loaded;CGConnectionLoading=NO;}dispatch_async(dispatch_get_main_queue(),^{[NSNotificationCenter.defaultCenter postNotificationName:@"AMChatGPTStatusChanged" object:nil];});});}
            return NSMutableDictionary.dictionary;
        }
    }
    // Keychain may ask the user or wait on security services. Never hold the
    // UI-visible account lock across that work, including the first cold read.
    NSDictionary *loaded=CGObject(CGReadSecret(@"chatgpt-connections")).copy;
    @synchronized(CGAccount.class){if(!CGConnectionCache)CGConnectionCache=loaded;return CGConnectionCache.mutableCopy;}
}
static NSDictionary *CGPreferences(void){return CGObject(SSReadPlist(@"chatgpt-preferences.plist"));}
static void CGRecordUsage(NSDictionary *record){@synchronized(CGAccount.class){NSMutableArray *history=[CGArray(SSReadPlist(@"chatgpt-usage.plist")) mutableCopy];[history addObject:record];if(history.count>500)[history removeObjectsInRange:NSMakeRange(0,history.count-500)];SSWritePlist(@"chatgpt-usage.plist",history,NULL);SSWritePlist(@"chatgpt-last-usage.plist",record,NULL);}}
static NSUInteger CGHourlyLimit(void){NSUInteger limit=[CGPreferences()[@"hourlyLimit"] unsignedIntegerValue];return limit ?: 60;}
static NSUInteger CGConcurrency(void){NSUInteger limit=[CGPreferences()[@"concurrency"] unsignedIntegerValue];return limit ?: 2;}
static NSDictionary *CGActive(void){NSDictionary *store=CGConnections();return CGObject(CGObject(store[@"accounts"])[CGText(store[@"active"])]);}
NSDictionary *AMChatGPTStatus(void){
    NSDictionary *store=CGConnections();
    @synchronized(CGAccount.class){NSMutableArray *accounts=NSMutableArray.array;for(NSString *key in CGObject(store[@"accounts"])){NSDictionary *account=CGObject(store[@"accounts"])[key];[accounts addObject:@{@"id":key,@"label":[NSString stringWithFormat:@"%@ · %@",CGText(account[@"email"]).length ? account[@"email"]:@"ChatGPT",[key substringToIndex:MIN(8,key.length)]]}];}
        NSDictionary *active=CGObject(CGObject(store[@"accounts"])[CGText(store[@"active"])]);BOOL connected=CGText(active[@"access_token"]).length>0 && [CGArray(active[@"scopes"]) containsObject:@"chatgpt.tokens.use.direct"];
        NSUInteger used=0;NSTimeInterval now=NSDate.date.timeIntervalSince1970;for(id date in CGArray(SSReadPlist(@"chatgpt-request-ledger.plist")))if([date isKindOfClass:NSNumber.class] && [date doubleValue]>now-3600)used++;
        return @{@"connected":@(connected),@"accounts":accounts,@"active":CGText(store[@"active"]),@"hourlyLimit":@(CGHourlyLimit()),@"concurrency":@(CGConcurrency()),@"used":@(used),@"loginRunning":@(CGLoginRunning)};
    }
}
BOOL AMChatGPTSavePreferences(NSDictionary *preferences,NSError **error){
    NSUInteger limit=[preferences[@"hourlyLimit"] unsignedIntegerValue],concurrency=[preferences[@"concurrency"] unsignedIntegerValue];
    if(limit<1 || limit>10000 || concurrency<1 || concurrency>8){if(error)*error=AMCGError(@"每小时请求上限需为1–10000，并发需为1–8。",1);return NO;}
    @synchronized(CGAccount.class){if(CGActiveRequests){if(error)*error=AMCGError(@"请先结束当前模型请求，再修改模型或上限。",1);return NO;}return SSWritePlist(@"chatgpt-preferences.plist",preferences,error);}
}
static BOOL CGReserve(NSDate *date,NSError **error){
    @synchronized(CGAccount.class){NSMutableArray *ledger=NSMutableArray.array;NSTimeInterval now=date.timeIntervalSince1970;
        // Future entries are retained: moving the system clock back cannot erase a budget.
        for(id stamp in CGArray(SSReadPlist(@"chatgpt-request-ledger.plist")))if([stamp isKindOfClass:NSNumber.class] && [stamp doubleValue]>now-3600)[ledger addObject:stamp];
        if(ledger.count>=CGHourlyLimit()){if(error)*error=AMCGError(@"已达到 AM Helper 每小时请求上限；可等待恢复或调整设置。",429);return NO;}
        [ledger addObject:@(now)];return SSWritePlist(@"chatgpt-request-ledger.plist",ledger,error);
    }
}
#ifdef DDL_TESTING
BOOL AMChatGPTReserveRequest(NSDate *date,NSError **error){return CGReserve(date,error);}
#endif
static NSDictionary *CGDiscovery(NSError **error){NSDictionary *config=CGGetJSON(@"https://auth.openai.com/.well-known/openid-configuration",error);if(![config[@"issuer"] isEqual:@"https://auth.openai.com"]){if(error && !*error)*error=AMCGError(@"无法核验 OpenAI 登录服务。",1);return nil;}return config;}
static NSDictionary *CGKeys(NSError **error){NSDictionary *config=CGDiscovery(error);NSString *url=CGText(config[@"jwks_uri"]);if(![url hasPrefix:@"https://auth.openai.com/"]){if(error && !*error)*error=AMCGError(@"无效的身份密钥地址。",1);return nil;}return CGGetJSON(url,error);}
static NSDictionary *CGToken(NSError **error){
    // Refreshes for the same registration are serialized, including rotating-token persistence.
    @synchronized(CGRefreshGate.class){NSMutableDictionary *store=CGConnections();NSString *identifier=CGText(store[@"active"]);NSMutableDictionary *accounts=[CGObject(store[@"accounts"]) mutableCopy];NSMutableDictionary *account=[CGObject(accounts[identifier]) mutableCopy];
        if(!CGText(account[@"access_token"]).length || ![CGArray(account[@"scopes"]) containsObject:@"chatgpt.tokens.use.direct"]){if(error)*error=AMCGError(@"请先使用 ChatGPT 登录并授权套餐用量。",401);return nil;}
        if([account[@"expires"] doubleValue]>NSDate.date.timeIntervalSince1970+60)return account;
        NSString *body=CGForm(@{@"grant_type":@"refresh_token",@"client_id":CGText(account[@"client_id"]),@"refresh_token":CGText(account[@"refresh_token"]),@"resource":@"https://api.openai.com/v1"});
        NSData *data=CGHTTP(@"https://auth.openai.com/api/accounts/oauth/token",@"POST",[body dataUsingEncoding:NSUTF8StringEncoding],@"application/x-www-form-urlencoded",nil,^BOOL{return NO;},error);if(!data)return nil;
        NSDictionary *tokens=CGJSON(data);NSArray *scopes=[CGText(tokens[@"scope"]) componentsSeparatedByString:@" "];
        if(!CGText(tokens[@"access_token"]).length || !CGText(tokens[@"refresh_token"]).length || ![scopes containsObject:@"chatgpt.tokens.use.direct"] || ![scopes containsObject:@"resource.invoke"] || ![tokens[@"token_type"] isEqual:@"Bearer"] || [tokens[@"expires_in"] doubleValue]<=0){if(error)*error=AMCGError(@"ChatGPT 会话续期未完成，请重新登录。",401);return nil;}
        if(CGText(tokens[@"id_token"]).length){NSDictionary *identity=CGValidate(tokens,CGKeys(error),account[@"client_id"],nil,error);if(!identity || ![identity[@"sub"] isEqual:account[@"subject"]])return nil;account[@"id_token"]=tokens[@"id_token"];}
        account[@"access_token"]=tokens[@"access_token"];account[@"refresh_token"]=tokens[@"refresh_token"];account[@"scopes"]=scopes;account[@"expires"]=@(NSDate.date.timeIntervalSince1970+[tokens[@"expires_in"] doubleValue]);
        // A model-list refresh may overlap an account switch. Persist the rotated
        // token into the latest store without restoring the old active account.
        @synchronized(CGAccount.class){NSMutableDictionary *latest=CGConnections(),*latestAccounts=[CGObject(latest[@"accounts"]) mutableCopy];if(!latestAccounts[identifier]){if(error)*error=AMCGError(@"连接已移除，请重新登录。",401);return nil;}latestAccounts[identifier]=account;latest[@"accounts"]=latestAccounts;if(!CGWriteSecret(@"chatgpt-connections",latest)){if(error)*error=AMCGError(@"钥匙串保存失败，未继续发送材料。",1);return nil;}}return account;
    }
}
NSArray *AMChatGPTModels(NSError **error){NSDictionary *account=CGToken(error);if(!account)return nil;NSData *data=CGHTTP(@"https://api.openai.com/v1/models",@"GET",nil,nil,account[@"access_token"],^BOOL{return NO;},error);if(!data)return nil;NSMutableArray *models=NSMutableArray.array;for(NSDictionary *row in CGArray(CGJSON(data)[@"models"]))if([row isKindOfClass:NSDictionary.class] && [row[@"visibility"] isEqual:@"list"] && CGText(row[@"slug"]).length)[models addObject:@{@"id":row[@"slug"],@"name":CGText(row[@"display_name"]).length ? row[@"display_name"]:row[@"slug"]}];if(!models.count){if(error)*error=AMCGError(@"账号没有可用模型，请核对套餐授权。",1);return nil;}
    NSString *registration=AMPreflightHash([[NSString stringWithFormat:@"%@|%@",account[@"client_id"],account[@"subject"]] dataUsingEncoding:NSUTF8StringEncoding]);SSWritePlist(@"chatgpt-models.plist",@{@"registration":registration,@"date":NSDate.date,@"models":models},NULL);return models;
}
NSDictionary *AMChatGPTProfile(NSString *purpose){
    NSDictionary *account=CGActive();BOOL recognition=[purpose isEqual:@"recognition"];NSString *model=CGText(CGPreferences()[recognition ? @"recognitionModel":@"reviewModel"]);if(!model.length)model=recognition ? @"gpt-6-luna":@"gpt-6.1-terra";
    return @{@"provider":@"chatgpt",@"endpoint":@"https://api.openai.com/v1/responses",@"model":model,@"vision":@([@[@"gpt-6-luna",@"gpt-6.1-terra"] containsObject:model]),@"json":@YES,@"enabled":@(CGText(account[@"access_token"]).length && [CGArray(account[@"scopes"]) containsObject:@"chatgpt.tokens.use.direct"]),@"registration":AMPreflightHash([[NSString stringWithFormat:@"%@|%@",CGText(account[@"client_id"]),CGText(account[@"subject"])] dataUsingEncoding:NSUTF8StringEncoding])};
}
BOOL AMChatGPTSelectAccount(NSString *registration,NSError **error){@synchronized(CGAccount.class){if(CGActiveRequests || CGLoginRunning || CGDisconnecting){if(error)*error=AMCGError(@"请先结束正在进行的模型请求或登录。",1);return NO;}NSMutableDictionary *store=CGConnections();if(!CGObject(store[@"accounts"])[registration])return NO;store[@"active"]=registration;return CGWriteSecret(@"chatgpt-connections",store);}}
BOOL AMChatGPTSignOut(NSError **error){
    @synchronized(CGAccount.class){CGLoginCancelled=YES;if(CGActiveRequests || CGDisconnecting){if(error)*error=AMCGError(@"请先停止正在进行的模型请求。",1);return NO;}CGDisconnecting=YES;}
    @try {
        // Revocation never holds the UI/account-cache lock across network I/O.
        @synchronized(CGRefreshGate.class){
            NSMutableDictionary *store=CGConnections(),*accounts=[CGObject(store[@"accounts"]) mutableCopy];NSString *key=CGText(store[@"active"]);NSMutableDictionary *account=[CGObject(accounts[key]) mutableCopy];BOOL revoked=YES;
            if(CGText(account[@"refresh_token"]).length){NSString *url=CGText(CGDiscovery(error)[@"revocation_endpoint"]);NSString *form=CGForm(@{@"token":account[@"refresh_token"],@"token_type_hint":@"refresh_token",@"client_id":CGText(account[@"client_id"])});revoked=[url hasPrefix:@"https://auth.openai.com/"] && CGHTTP(url,@"POST",[form dataUsingEncoding:NSUTF8StringEncoding],@"application/x-www-form-urlencoded",nil,^BOOL{return NO;},error)!=nil;}
            for(NSString *field in @[@"access_token",@"refresh_token",@"id_token",@"expires"])[account removeObjectForKey:field];if(key.length)accounts[key]=account;store[@"accounts"]=accounts;[store removeObjectForKey:@"active"];
            if(!CGWriteSecret(@"chatgpt-connections",store)){if(error)*error=AMCGError(@"无法清除本机登录凭据。",1);return NO;}
            if(!revoked && error)*error=AMCGError(@"已清除本机登录；远端撤销未确认，请在 ChatGPT 设置中断开应用。",1);return revoked;
        }
    }@finally{@synchronized(CGAccount.class){CGDisconnecting=NO;}}
}
void AMChatGPTCancelSignIn(void){@synchronized(CGAccount.class){CGLoginCancelled=YES;}}
void AMChatGPTSignIn(NSString *registration,void (^completion)(NSError *)){
    @synchronized(CGAccount.class){if(CGLoginRunning || CGActiveRequests || CGDisconnecting){completion(AMCGError(@"已有登录正在进行。",1));return;}CGLoginRunning=YES;CGLoginCancelled=NO;}
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *failure=nil;int listener=-1;
        @try {
            NSString *state=CGRandom(),*nonce=CGRandom(),*verifier=CGRandom();if(!state || !nonce || !verifier){failure=AMCGError(@"无法生成安全登录请求。",1);return;}
            NSDictionary *store=CGConnections(),*old=CGObject(CGObject(store[@"accounts"])[registration ?: @""]);NSString *client=CGText(old[@"client_id"]);
            NSString *host=CGText(CGReadSecret(@"chatgpt-host")[@"id"]);if(!host.length){host=[@"urn:uuid:" stringByAppendingString:NSUUID.UUID.UUIDString.lowercaseString];if(!CGWriteSecret(@"chatgpt-host",@{@"id":host})){failure=AMCGError(@"无法保存本机登录标识。",1);return;}}
            listener=socket(AF_INET,SOCK_STREAM,0);struct sockaddr_in address={0};address.sin_len=sizeof(address);address.sin_family=AF_INET;address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);address.sin_port=0;socklen_t length=sizeof(address);
            if(listener<0 || bind(listener,(struct sockaddr *)&address,sizeof(address)) || listen(listener,4) || getsockname(listener,(struct sockaddr *)&address,&length)){failure=AMCGError(@"无法启动本机登录回调。",1);return;}
            NSString *redirect=[NSString stringWithFormat:@"http://127.0.0.1:%u/auth/callback",ntohs(address.sin_port)];unsigned char digest[CC_SHA256_DIGEST_LENGTH];NSData *verifierData=[verifier dataUsingEncoding:NSUTF8StringEncoding];CC_SHA256(verifierData.bytes,(CC_LONG)verifierData.length,digest);
            NSMutableDictionary *parameters=[@{@"client_id":client.length ? client:@"dynamic_agent_client",@"ext_agent_host_id":host,@"response_type":@"code",@"redirect_uri":redirect,@"scope":@"openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",@"resource":@"https://api.openai.com/v1",@"state":state,@"nonce":nonce,@"code_challenge_method":@"S256",@"code_challenge":CGBase64([NSData dataWithBytes:digest length:sizeof(digest)])} mutableCopy];if(!client.length)parameters[@"agent_name_hint"]=@"AM Helper";else if(CGText(old[@"id_token"]).length)parameters[@"id_token_hint"]=old[@"id_token"];
            NSURL *authorize=[NSURL URLWithString:[@"https://auth.openai.com/api/accounts/authorize?" stringByAppendingString:CGForm(parameters)]];dispatch_async(dispatch_get_main_queue(),^{
                if(CGLoginCancelled)return;
#ifdef DDL_TESTING
                if(CGTestBrowserOpener){CGTestBrowserOpener(authorize);return;}
#endif
                [NSWorkspace.sharedWorkspace openURL:authorize];});
            NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:180];NSDictionary *callback=nil;
            while(deadline.timeIntervalSinceNow>0 && !CGLoginCancelled){struct pollfd fd={listener,POLLIN,0};if(poll(&fd,1,100)<=0)continue;int connection=accept(listener,NULL,NULL);if(connection<0)continue;int noSignal=1;setsockopt(connection,SOL_SOCKET,SO_NOSIGPIPE,&noSignal,sizeof(noSignal));struct timeval timeout={2,0};setsockopt(connection,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));char bytes[8193];ssize_t count=recv(connection,bytes,8192,0);NSString *request=count>0 ? [[NSString alloc] initWithBytes:bytes length:count encoding:NSUTF8StringEncoding]:nil;NSArray *line=[[request componentsSeparatedByString:@"\r\n"].firstObject componentsSeparatedByString:@" "];NSURLComponents *url=line.count>1 ? [NSURLComponents componentsWithString:[@"http://127.0.0.1" stringByAppendingString:line[1]]]:nil;NSMutableDictionary *values=NSMutableDictionary.dictionary;BOOL valid=[line.firstObject isEqual:@"GET"] && [url.path isEqual:@"/auth/callback"];for(NSURLQueryItem *item in url.queryItems){if(values[item.name])valid=NO;values[item.name]=item.value ?: @"";}valid=valid && [values[@"state"] isEqual:state];NSString *reply=valid ? @"HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\n\r\nAM Helper: callback received. You may close this page.":@"HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\nInvalid callback.";send(connection,reply.UTF8String,strlen(reply.UTF8String),0);close(connection);if(valid){callback=values;break;}}
            if(!callback){failure=AMCGError(CGLoginCancelled ? @"登录已取消":@"登录超时，请重试。",CGLoginCancelled ? NSUserCancelledError:NSURLErrorTimedOut);return;}
            if(callback[@"error"]){failure=AMCGError(@"未授予 ChatGPT 登录或套餐用量权限。",401);return;}
            NSString *issued=CGText(callback[@"client_id"]);if(client.length && issued.length && ![client isEqual:issued]){failure=AMCGError(@"登录注册身份不匹配。",1);return;}if(!client.length)client=issued;
            if(!client.length || [client isEqual:@"dynamic_agent_client"] || !CGText(callback[@"code"]).length){failure=AMCGError(@"登录注册未完成，请重试。",1);return;}
            NSString *form=CGForm(@{@"grant_type":@"authorization_code",@"client_id":client,@"code":callback[@"code"],@"code_verifier":verifier,@"redirect_uri":redirect,@"resource":@"https://api.openai.com/v1"});NSData *data=CGHTTP(@"https://auth.openai.com/api/accounts/oauth/token",@"POST",[form dataUsingEncoding:NSUTF8StringEncoding],@"application/x-www-form-urlencoded",nil,^BOOL{return CGLoginCancelled;},&failure);if(!data)return;
            NSDictionary *tokens=CGJSON(data),*identity=CGValidate(tokens,CGKeys(&failure),client,nonce,&failure);if(!identity)return;if(old[@"subject"] && ![old[@"subject"] isEqual:identity[@"sub"]]){failure=AMCGError(@"登录账号与原连接不匹配，原连接未修改。",1);return;}
            NSArray *scopes=[CGText(tokens[@"scope"]) componentsSeparatedByString:@" "];if(!CGText(tokens[@"access_token"]).length || !CGText(tokens[@"refresh_token"]).length || ![tokens[@"token_type"] isEqual:@"Bearer"] || [tokens[@"expires_in"] doubleValue]<=0 || ![scopes containsObject:@"chatgpt.tokens.use.direct"] || ![scopes containsObject:@"resource.invoke"]){failure=AMCGError(@"未获得有效的 ChatGPT 套餐用量授权。",401);return;}
            NSString *identifier=AMPreflightHash([[NSString stringWithFormat:@"%@|%@",client,identity[@"sub"]] dataUsingEncoding:NSUTF8StringEncoding]);NSMutableDictionary *account=[tokens mutableCopy];account[@"client_id"]=client;account[@"subject"]=identity[@"sub"];account[@"email"]=CGText(identity[@"email"]);account[@"scopes"]=scopes;account[@"expires"]=@(NSDate.date.timeIntervalSince1970+[tokens[@"expires_in"] doubleValue]);
            @synchronized(CGAccount.class){if(CGLoginCancelled){failure=AMCGError(@"登录已取消",NSUserCancelledError);return;}NSMutableDictionary *next=CGConnections(),*accounts=[CGObject(next[@"accounts"]) mutableCopy];accounts[identifier]=account;next[@"accounts"]=accounts;next[@"active"]=identifier;if(!CGWriteSecret(@"chatgpt-connections",next))failure=AMCGError(@"钥匙串保存失败，登录未完成。",1);}
        }@finally{if(listener>=0)close(listener);@synchronized(CGAccount.class){CGLoginRunning=NO;}dispatch_async(dispatch_get_main_queue(),^{completion(failure);});}
    });
}
NSDictionary *AMChatGPTGenerate(NSDictionary *input,NSString *instruction,NSArray *images,NSString *purpose,BOOL (^cancelled)(void),NSError **error){
    if(cancelled())return nil;
    @synchronized(CGAccount.class){if(CGLoginRunning || CGDisconnecting || CGActiveRequests>=CGConcurrency()){if(error)*error=AMCGError(@"模型请求已达到并发上限，请稍后重试。",429);return nil;}CGActiveRequests++;}
    __block BOOL sent=NO,usageSaved=NO;NSDictionary *requestProfile=nil;
    @try {
        NSDictionary *account=CGToken(error);if(!account)return nil;NSDictionary *profile=AMChatGPTProfile(purpose);requestProfile=profile;
        NSDictionary *catalog=CGObject(SSReadPlist(@"chatgpt-models.plist"));NSArray *models=CGArray(catalog[@"models"]);
        if(![catalog[@"registration"] isEqual:profile[@"registration"]] || ![catalog[@"date"] isKindOfClass:NSDate.class] || [catalog[@"date"] timeIntervalSinceNow]<-3600)models=AMChatGPTModels(error);
        BOOL available=NO;for(NSDictionary *model in models)if([model[@"id"] isEqual:profile[@"model"]])available=YES;
        if(!available){if(error && !*error)*error=AMCGError(@"默认模型在当前账号不可用，请在设置中确认一个可用替代。",404);return nil;}
        NSData *encoded=[NSJSONSerialization dataWithJSONObject:input options:NSJSONWritingSortedKeys error:error];if(!encoded || encoded.length>500000 || SSContainsSecret(encoded)){if(error && !*error)*error=AMCGError(@"材料过大或含疑似凭据，未发送。",1);return nil;}
        NSMutableArray *content=[NSMutableArray arrayWithObject:@{@"type":@"input_text",@"text":[[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding]}];
        if(images.count && ![profile[@"vision"] boolValue]){if(error)*error=AMCGError(@"当前替代模型尚未确认图片能力，请使用默认模型或取消图片材料。",1);return nil;}
        for(NSDictionary *image in images){NSData *data=image[@"data"];if(![data isKindOfClass:NSData.class] || data.length>8*1024*1024){if(error)*error=AMCGError(@"图片材料不可读或超出容量。",1);return nil;}[content addObject:@{@"type":@"input_text",@"text":CGText(image[@"label"])}];[content addObject:@{@"type":@"input_image",@"image_url":[@"data:image/png;base64," stringByAppendingString:[data base64EncodedStringWithOptions:0]]}];}
        NSDictionary *body=@{@"model":profile[@"model"],@"instructions":instruction,@"input":@[@{@"role":@"user",@"content":content}],@"reasoning":@{@"effort":[purpose isEqual:@"recognition"] ? @"low":@"medium"},@"store":@NO,@"stream":@YES};
        NSData *wire=[NSJSONSerialization dataWithJSONObject:body options:0 error:error];if(!wire || cancelled())return nil;
        // Reserve before sending; failures and cancellation after this point still consume one request.
        if(!CGReserve(NSDate.date,error))return nil;sent=YES;
        NSData *reply=CGHTTP(@"https://api.openai.com/v1/responses",@"POST",wire,@"application/json",account[@"access_token"],cancelled,error);if(!reply)return nil;
        NSString *stream=[[NSString alloc] initWithData:reply encoding:NSUTF8StringEncoding];NSMutableString *text=NSMutableString.string;NSDictionary *usage=nil;BOOL completed=NO;
        for(NSString *line in [stream componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]){
            if(![line hasPrefix:@"data:"])continue;NSString *payload=[[line substringFromIndex:5] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];if([payload isEqual:@"[DONE]"])continue;
            NSDictionary *event=CGJSON([payload dataUsingEncoding:NSUTF8StringEncoding]);NSString *type=CGText(event[@"type"]);
            if([type isEqual:@"response.output_text.delta"])[text appendString:CGText(event[@"delta"])];
            if([type isEqual:@"response.completed"]){NSDictionary *response=CGObject(event[@"response"]);if(![response[@"status"] isEqual:@"completed"]){if(error)*error=AMCGError(@"模型响应未完成。",1);return nil;}completed=YES;usage=CGObject(response[@"usage"]);}
            if([@[@"response.failed",@"response.incomplete",@"error"] containsObject:type]){NSString *code=CGText(CGObject(CGObject(event[@"response"])[@"error"])[@"code"]);if(!code.length)code=CGText(CGObject(event[@"error"])[@"code"]);if(!code.length)code=CGText(event[@"code"]);BOOL quota=[code hasPrefix:@"subscription_sharing_usage_"] || [@[@"rate_limit_exceeded",@"insufficient_quota",@"usage_limit_reached"] containsObject:code];if(error)*error=AMCGError(quota ? @"ChatGPT 套餐额度不可用或已耗尽，请查看官方用量设置。":@"模型响应未完成，已保留原有结果。",quota ? 429:1);return nil;}
        }
        if(!completed || cancelled()){if(error)*error=AMCGError(cancelled() ? @"已取消":@"响应中断，未保存为完成结果。",cancelled() ? NSUserCancelledError:1);return nil;}
        NSDictionary *result=CGJSON([text dataUsingEncoding:NSUTF8StringEncoding]);if(!result.count){if(error)*error=AMCGError(@"模型没有返回有效的结构化结果。",1);return nil;}
        NSDictionary *record=@{@"date":NSDate.date,@"model":profile[@"model"],@"purpose":purpose,@"known":@(usage.count>0),@"input":usage[@"input_tokens"] ?: @0,@"output":usage[@"output_tokens"] ?: @0};CGRecordUsage(record);usageSaved=YES;return result;
    }@finally{
        // A sent request may consume quota even without a completed usage event.
        if(sent && !usageSaved)CGRecordUsage(@{@"date":NSDate.date,@"model":CGText(requestProfile[@"model"]),@"purpose":purpose,@"known":@NO});
        @synchronized(CGAccount.class){CGActiveRequests--;}
    }
}
