#import "AMPrompts.h"
// Gemini review is separate from teacher-document extraction. No tool execution.
static NSString *const ORModel=@"gemini-3.8-flash";
static BOOL ORBusy=NO;
static BOOL ORCompatibleModel(NSString *name){return [name isKindOfClass:NSString.class] && RMatch(name,@"^gemini-(?:3(?:\\.[0-9]+)?|2\\.5)-(?:flash(?:-lite)?|pro)(?:-preview(?:-[0-9-]+)?)?$");}
NSString *AMOnlineReviewCurrentModel(void){NSString *model=SSReadPlist(@"online-review-settings.plist")[@"model"];return ORCompatibleModel(model) ? model:ORModel;}
static NSError *ORError(NSString *message,NSInteger code){return [NSError errorWithDomain:@"AMOnlineReview" code:code userInfo:@{NSLocalizedDescriptionKey:message}];}
static BOOL ORURL(NSURL *url){return [url.scheme isEqual:@"https"] && [url.host isEqual:@"generativelanguage.googleapis.com"] && (!url.port || url.port.integerValue==443) && !url.user && !url.password && !url.fragment;}
static BOOL ORName(id name){return [name isKindOfClass:NSString.class] && RMatch(name,@"^files/[a-zA-Z0-9_-]+$");}
static BOOL ORPrivatePath(id value){
    if([value isKindOfClass:NSString.class])return RMatch(value,@"/(?:Users|home)/[^/\\s]+/");
    if([value isKindOfClass:NSDictionary.class]){for(id key in value)if(ORPrivatePath(key) || ORPrivatePath(value[key]))return YES;}
    else if([value isKindOfClass:NSArray.class])for(id row in value)if(ORPrivatePath(row))return YES;
    return NO;
}
// Provider keys are opaque: validate header safety, not an assumed legacy alphabet.
static NSString *ORNormalizedKey(id value){return [value isKindOfClass:NSString.class] ? [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]:nil;}
static BOOL ORKey(NSString *key){
    if(![key isKindOfClass:NSString.class] || !key.length || key.length>4096)return NO;
    for(NSUInteger i=0;i<key.length;i++){unichar c=[key characterAtIndex:i];if(c<33 || c>126)return NO;}
    return YES;
}
static BOOL ORProviderKeyError(NSData *data){
    id envelope=data.length && data.length<=8*1024*1024 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
    id problem=[envelope isKindOfClass:NSDictionary.class] ? envelope[@"error"]:nil;
    id details=[problem isKindOfClass:NSDictionary.class] ? problem[@"details"]:nil;
    if([details isKindOfClass:NSArray.class])for(id detail in details)if([detail isKindOfClass:NSDictionary.class] && [detail[@"reason"] isKindOfClass:NSString.class] && [@[@"API_KEY_INVALID",@"API_KEY_EXPIRED",@"API_KEY_SERVICE_BLOCKED"] containsObject:detail[@"reason"]])return YES;
    return NO;
}
static NSString *ORStage(NSURL *url,NSString *method){
    if([url.path hasSuffix:@":generateContent"])return @"generation";
    if([url.path hasSuffix:@":countTokens"])return @"capacity";
    if([url.path hasPrefix:@"/upload/"])return @"upload";
    if([method isEqual:@"DELETE"])return @"cleanup";
    if([url.path hasPrefix:@"/v1beta/files/"])return @"file_check";
    return @"connection";
}
static NSError *ORRequestFailure(NSString *stage,NSInteger http,NSInteger network,NSString *message,NSData *data){
    NSDictionary *names=@{@"generation":@"生成复核报告",@"capacity":@"核对材料容量",@"upload":@"上传图片",@"cleanup":@"清理上传副本",@"file_check":@"核验上传图片",@"connection":@"连接测试"};
    NSMutableDictionary *record=[@{@"date":NSDate.date,@"stage":stage,@"httpStatus":@(http),@"networkCode":@(network)} mutableCopy];
    id envelope=data.length && data.length<=8*1024*1024 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
    id problem=[envelope isKindOfClass:NSDictionary.class] ? envelope[@"error"]:nil;id status=[problem isKindOfClass:NSDictionary.class] ? problem[@"status"]:nil;
    if([status isKindOfClass:NSString.class] && [@[@"INVALID_ARGUMENT",@"FAILED_PRECONDITION",@"UNAUTHENTICATED",@"PERMISSION_DENIED",@"NOT_FOUND",@"RESOURCE_EXHAUSTED",@"INTERNAL",@"UNAVAILABLE",@"DEADLINE_EXCEEDED"] containsObject:status])record[@"apiStatus"]=status;
    // Only fixed stages, numeric codes and allowlisted enums; no raw body, URL or material.
    SSWritePlist([stage isEqual:@"cleanup"] ? @"online-review-cleanup-diagnostic.plist":@"online-review-diagnostic.plist",record,NULL);
    NSString *code=http ? [NSString stringWithFormat:@"HTTP %ld",(long)http]:[NSString stringWithFormat:@"网络 %ld",(long)network];
    NSMutableDictionary *info=record.mutableCopy;info[NSLocalizedDescriptionKey]=[NSString stringWithFormat:@"%@失败（%@）：%@",names[stage],code,message];
    return [NSError errorWithDomain:@"AMOnlineReview" code:http ?: network userInfo:info];
}
static NSString *ORKeyHint(void){return @"密钥为空或含内部空白／不可见字符。请用 AI Studio 的复制按钮复制完整密钥；首尾空白会自动清理。";}
NSDictionary *AMOnlineReviewSettings(void){id saved=SSReadPlist(@"online-review-settings.plist");return [saved isKindOfClass:NSDictionary.class] ? saved:@{@"enabled":@NO};}
BOOL AMOnlineReviewSaveSettings(BOOL enabled,NSString *key,NSError **error){
    key=ORNormalizedKey(key);
    if(key.length && !ORKey(key)){if(error)*error=ORError(ORKeyHint(),1);return NO;}
    @synchronized(AMOnlineReviewClient.class){
        if(ORBusy){if(error)*error=ORError(@"请等待在线复核或文件清理结束，再修改设置。",1);return NO;}
        NSDictionary *old=SSReadSecret(@"preflight-gemini");
        if(enabled && !key.length && ![old[@"key"] length]){if(error)*error=ORError(@"请填写自己的 Gemini API 密钥。",1);return NO;}
        if(key.length && ![key isEqual:old[@"key"]] && [SSReadPlist(@"online-review-uploads.plist") count]){if(error)*error=ORError(@"仍有上传文件待清理。请先用原密钥重试清理，再更换密钥。",1);return NO;}
        if(key.length && !SSWriteSecret(@"preflight-gemini",@{@"key":key,@"identity":NSUUID.UUID.UUIDString})){if(error)*error=ORError(@"无法将密钥存入钥匙串，设置未保存。请检查系统钥匙串访问提示。",1);return NO;}
        return SSWritePlist(@"online-review-settings.plist",@{@"enabled":@(enabled),@"model":AMOnlineReviewCurrentModel(),@"policyVersion":@1},error);
    }
}
static NSArray *ORUploads(void){id rows=SSReadPlist(@"online-review-uploads.plist");if(![rows isKindOfClass:NSArray.class])return @[];NSMutableArray *safe=NSMutableArray.array;for(id row in rows)if([row isKindOfClass:NSDictionary.class] && ORName(row[@"name"]) && [row[@"date"] isKindOfClass:NSDate.class] && [row[@"fingerprint"] isKindOfClass:NSString.class] && [row[@"hash"] isKindOfClass:NSString.class] && [row[@"uri"] isKindOfClass:NSString.class])[safe addObject:row];return safe;}
static BOOL ORStoreUpload(NSDictionary *record,BOOL remove,NSError **error){
    @synchronized(AMOnlineReviewClient.class){NSMutableArray *next=ORUploads().mutableCopy;NSIndexSet *old=[next indexesOfObjectsPassingTest:^BOOL(id row,NSUInteger i,BOOL *stop){return [row[@"name"] isEqual:record[@"name"]];}];[next removeObjectsAtIndexes:old];if(!remove)[next addObject:record];return SSWritePlist(@"online-review-uploads.plist",next,error);}
}
BOOL AMOnlineReviewRegister(NSDictionary *context,NSDictionary *report,NSString *courseID,NSError **error){return AMOnlineReviewRegisterWithModel(context,report,courseID,AMOnlineReviewCurrentModel(),error);}
BOOL AMOnlineReviewRegisterWithModel(NSDictionary *context,NSDictionary *report,NSString *courseID,NSString *model,NSError **error){
    @synchronized(NSSpellChecker.class){if(!AMPreflightRegister(context,report,courseID,error))return NO;NSMutableArray *jobs=PFJobsRead().mutableCopy;NSMutableDictionary *last=[jobs.lastObject mutableCopy];last[@"provider"]=@"Gemini";last[@"model"]=model;last[@"state"]=@"在线复核中";last[@"message"]=@"Gemini：准备／等待在线复核";jobs[jobs.count-1]=last;return SSWritePlist(@"preflight-jobs.plist",jobs,error);}
}
void AMOnlineReviewFailed(NSString *batch){@synchronized(NSSpellChecker.class){NSArray *old=PFJobsRead();if(!old)return;NSMutableArray *jobs=NSMutableArray.array;for(NSDictionary *row in old){NSMutableDictionary *job=row.mutableCopy;if([job[@"id"] isEqual:batch] && !job[@"result"]){job[@"state"]=@"需处理";job[@"message"]=@"Gemini 复核未完成，可在检查报告中重试；保留本机报告。";}[jobs addObject:job];}SSWritePlist(@"preflight-jobs.plist",jobs,NULL);}}
BOOL AMOnlineReviewSelectModel(NSString *model,NSError **error){
    if(!ORCompatibleModel(model)){if(error)*error=ORError(@"请选择兼容的 Gemini 文本／图片模型。",1);return NO;}
    @synchronized(AMOnlineReviewClient.class){if(ORBusy){if(error)*error=ORError(@"请等待正在进行的复核结束再切换模型。",1);return NO;}NSMutableDictionary *settings=AMOnlineReviewSettings().mutableCopy;settings[@"model"]=model;return SSWritePlist(@"online-review-settings.plist",settings,error);}
}
NSDictionary *AMOnlineReviewUploadSummary(void){NSUInteger reusable=0,expired=0,pending=0;for(NSDictionary *record in ORUploads()){if([record[@"keepUntil"] isKindOfClass:NSDate.class] && [record[@"keepUntil"] timeIntervalSinceNow]>0)reusable++;else if([record[@"date"] timeIntervalSinceNow]<-48*3600)expired++;else pending++;}return @{@"reusable":@(reusable),@"pending":@(pending),@"expired":@(expired)};}
static BOOL ORClaim(NSError **error){@synchronized(AMOnlineReviewClient.class){if(ORBusy){if(error)*error=ORError(@"另一项在线复核或文件清理正在进行，请稍后重试。",1);return NO;}ORBusy=YES;return YES;}}
static void ORRelease(void){@synchronized(AMOnlineReviewClient.class){ORBusy=NO;}}
@interface AMOnlineReviewClient ()
@property NSString *key;
@property NSURLSession *session;
@property BOOL cleaning;
@property NSTimeInterval retryAfter;
@property NSString *credentialIdentity;
@end
NSUInteger AMOnlineReviewPendingUploads(void){return ORUploads().count;}
@implementation AMOnlineReviewClient
- (void)cancelImmediately{self.cancelled=YES;[self.session invalidateAndCancel];}
- (NSString *)credential {
#ifdef DDL_TESTING
    if(self.credentialProvider)return ORNormalizedKey(self.credentialProvider());
#endif
    NSDictionary *credential=SSReadSecret(@"preflight-gemini");self.credentialIdentity=credential[@"identity"] ?: @"legacy";return ORNormalizedKey(credential[@"key"]);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {completionHandler(nil);}
- (NSData *)request:(NSString *)method url:(NSURL *)url data:(NSData *)body headers:(NSDictionary *)headers response:(NSHTTPURLResponse **)response error:(NSError **)error {
    if(!ORURL(url) || self.cancelled){if(error)*error=ORError(self.cancelled ? @"在线复核已取消。":@"拒绝未经允许的凭据目标。",self.cancelled ? -999:1);return nil;}
    BOOL finishing=[headers[@"X-Goog-Upload-Command"] isEqual:@"upload, finalize"];
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url];request.HTTPMethod=method;request.HTTPBody=body;request.timeoutInterval=self.cleaning ? 10:(finishing ? 30:180);[request setValue:self.key forHTTPHeaderField:@"x-goog-api-key"];for(NSString *field in headers)[request setValue:headers[field] forHTTPHeaderField:field];
    NSData *data=nil;NSHTTPURLResponse *reply=nil;NSError *failure=nil;
#ifdef DDL_TESTING
    if(self.transport)data=self.transport(request,&reply,&failure);
    else
#endif
    {
        if(!self.session){NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;config.URLCache=nil;config.HTTPCookieStorage=nil;config.URLCredentialStorage=nil;config.timeoutIntervalForResource=240;self.session=[NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];}
        __block NSData *bytes=nil;__block NSHTTPURLResponse *meta=nil;__block NSError *networkError=nil;dispatch_semaphore_t signal=dispatch_semaphore_create(0);
        NSURLSessionDataTask *task=[self.session dataTaskWithRequest:request completionHandler:^(NSData *result,NSURLResponse *metadata,NSError *problem){bytes=result;meta=(NSHTTPURLResponse *)metadata;networkError=problem;dispatch_semaphore_signal(signal);}];[task resume];
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:self.cleaning ? 12:(finishing ? 35:245)];while(dispatch_semaphore_wait(signal,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC))){if((self.cancelled && !finishing) || deadline.timeIntervalSinceNow<=0){[task cancel];failure=ORError(self.cancelled ? @"在线复核已取消；已发送请求可能仍消耗额度。":@"请求超时，可恢复重试。",self.cancelled ? -999:-1001);break;}}
        if(!failure){data=bytes;reply=meta;failure=networkError;}
    }
    if(response)*response=reply;self.retryAfter=0;for(NSString *header in reply.allHeaderFields)if([header.lowercaseString isEqual:@"retry-after"]){NSString *value=[reply.allHeaderFields[header] description];if(RMatch(value,@"^[0-9]{1,6}$"))self.retryAfter=value.doubleValue;else{NSDateFormatter *format=NSDateFormatter.new;format.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];format.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0];format.dateFormat=@"EEE, dd MMM yyyy HH:mm:ss zzz";self.retryAfter=MAX(0,[[format dateFromString:value] timeIntervalSinceNow]);}}
    if(failure || (self.cancelled && !finishing)){
        NSInteger code=self.cancelled ? -999:([failure.domain isEqual:NSURLErrorDomain] || [failure.domain isEqual:@"AMOnlineReview"] ? failure.code:-1001);
        NSString *message=code==-999 ? @"复核已取消；已发送请求可能仍消耗额度。":(code==-1009 ? @"网络已离线，请恢复连接后重试。":(code==-1001 ? @"请求超时，保留本机报告；可稍后重试。":(code==-1003 ? @"无法解析服务地址，请检查网络或DNS。":(code==-1200 || code==-1202 ? @"安全连接失败，请检查系统时间或网络；不会跳过证书验证。":@"连接中断，请检查网络后重试。"))));
        if(error)*error=ORRequestFailure(ORStage(url,method),0,code,message,nil);return nil;
    }
    NSInteger status=reply.statusCode;if(status<200 || status>=300){NSString *message=status==429 ? @"免费额度或速率受限，已停止请求；请按供应商额度恢复时间重试。":(status==401 || status==403 ? @"密钥、账户资格或访问权限无效，请检查 Gemini 项目。":(status==400 || status==413 ? @"材料或请求超出接口支持范围，本次未完整检查。":@"Gemini 请求失败，可重试；没有切换其他服务。"));if(ORProviderKeyError(data))message=@"Google 拒绝了此密钥，请从 AI Studio 重新复制完整密钥，并检查是否已撤销、过期或限制了接口。";else if(status==400 && [method isEqual:@"GET"] && [url.path hasPrefix:@"/v1beta/models/"])message=@"Google 拒绝密钥或模型访问请求（HTTP 400）。请核对 AI Studio 密钥及模型权限；不是作业材料错误。";if(status==500)message=@"Google 服务内部错误，未得到复核结果；可稍后重试。";else if(status==502 || status==503)message=@"Google 服务暂时繁忙或不可用，可稍后重试。";else if(status==408 || status==504)message=@"Google 服务处理超时，未得到复核结果。";else if(status==404)message=@"指定模型或上传文件不可用，请核对模型访问权限，或重新准备材料。";else if(status>=300 && status<400)message=@"服务返回重定向，出于密钥保护已拒绝跟随。";NSString *retry=reply.allHeaderFields[@"Retry-After"] ?: reply.allHeaderFields[@"retry-after"];if(status==429 && [retry isKindOfClass:NSString.class] && RMatch(retry,@"^[0-9]{1,6}$"))message=[message stringByAppendingFormat:@" Retry-After：%@",retry];if(error)*error=ORRequestFailure(ORStage(url,method),status,0,message,data);return nil;}
    if(data.length>8*1024*1024){if(error)*error=ORError(@"响应超过安全限制，本次未完整检查。",1);return nil;}return data ?: NSData.data;
}
- (NSDictionary *)json:(NSString *)method path:(NSString *)path body:(NSDictionary *)body error:(NSError **)error {
    NSData *bytes=body ? [NSJSONSerialization dataWithJSONObject:body options:0 error:error]:nil;if(body && !bytes)return nil;
    NSData *data=[self request:method url:[NSURL URLWithString:[@"https://generativelanguage.googleapis.com" stringByAppendingString:path]] data:bytes headers:@{@"Content-Type":@"application/json"} response:NULL error:error];if(!data)return nil;
    if(!data.length)return @{};id result=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];if(![result isKindOfClass:NSDictionary.class]){if(error)*error=ORError(@"接口没有返回有效 JSON，已保留本机报告。",1);return nil;}return result;
}
- (NSArray *)modelsWithKey:(NSString *)key error:(NSError **)error {
    if(!ORClaim(error))return nil;self.cleaning=NO;@try{key=ORNormalizedKey(key);self.key=key.length ? key:[self credential];if(!ORKey(self.key)){if(error)*error=ORError(ORKeyHint(),1);return nil;}NSMutableArray *models=NSMutableArray.array;NSString *page=@"";
        for(NSUInteger n=0;n<10;n++){NSString *path=[@"/v1beta/models?pageSize=1000" stringByAppendingString:page.length ? [@"&pageToken=" stringByAppendingString:[page stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.alphanumericCharacterSet]]:@""];NSDictionary *reply=[self json:@"GET" path:path body:nil error:error];if(!reply)return nil;if(![reply[@"models"] isKindOfClass:NSArray.class]){if(error)*error=ORError(@"模型列表格式无效，可重试。",1);return nil;}for(id row in reply[@"models"])if([row isKindOfClass:NSDictionary.class] && [row[@"name"] isKindOfClass:NSString.class] && [row[@"supportedGenerationMethods"] isKindOfClass:NSArray.class] && [row[@"supportedGenerationMethods"] containsObject:@"generateContent"]){NSString *name=[row[@"name"] hasPrefix:@"models/"] ? [row[@"name"] substringFromIndex:7]:row[@"name"];if(ORCompatibleModel(name))[models addObject:@{@"id":name,@"title":name}];}page=[reply[@"nextPageToken"] isKindOfClass:NSString.class] ? reply[@"nextPageToken"]:@"";if(!page.length)break;}
        return models;
    }@finally{[self.session invalidateAndCancel];self.session=nil;self.key=nil;ORRelease();}
}
- (BOOL)testGenerationWithKey:(NSString *)key image:(BOOL)image error:(NSError **)error {
    if(!ORClaim(error))return NO;self.cleaning=NO;self.model=self.model ?: AMOnlineReviewCurrentModel();@try{key=ORNormalizedKey(key);self.key=key.length ? key:[self credential];if(!ORKey(self.key)){if(error)*error=ORError(ORKeyHint(),1);return NO;}if(![self consume:error])return NO;
        NSMutableArray *parts=[NSMutableArray arrayWithObject:@{@"text":@"Synthetic connectivity test, no coursework. Return JSON only: {\"status\":\"ok\"}."}];if(image){NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:32 pixelsHigh:32 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];memset(bitmap.bitmapData,255,bitmap.bytesPerRow*32);NSData *png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];[parts addObject:@{@"inlineData":@{@"mimeType":@"image/png",@"data":[png base64EncodedStringWithOptions:0]}}];}
        NSDictionary *reply=[self json:@"POST" path:[NSString stringWithFormat:@"/v1beta/models/%@:generateContent",self.model] body:@{@"contents":@[@{@"role":@"user",@"parts":parts}],@"generationConfig":@{@"responseMimeType":@"application/json",@"maxOutputTokens":@256},@"store":@NO} error:error];if(!reply)return NO;
        id candidate=[reply[@"candidates"] isKindOfClass:NSArray.class] ? [reply[@"candidates"] firstObject]:nil;NSMutableString *text=NSMutableString.string;if([candidate isKindOfClass:NSDictionary.class] && [candidate[@"content"] isKindOfClass:NSDictionary.class] && [candidate[@"content"][@"parts"] isKindOfClass:NSArray.class])for(id part in candidate[@"content"][@"parts"])if([part isKindOfClass:NSDictionary.class] && [part[@"text"] isKindOfClass:NSString.class])[text appendString:part[@"text"]];id result=[NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];BOOL ok=[result isKindOfClass:NSDictionary.class] && [result[@"status"] isEqual:@"ok"] && [candidate[@"finishReason"] isEqual:@"STOP"];if(!ok && error)*error=ORError(@"模型可访问，但合成生成未返回完整有效结果。",1);return ok;
    }@finally{[self.session invalidateAndCancel];self.session=nil;self.key=nil;ORRelease();}
}
- (BOOL)testConnectionWithKey:(NSString *)key error:(NSError **)error {
    if(!ORClaim(error))return NO;self.cleaning=NO;@try{key=ORNormalizedKey(key);self.key=key.length ? key:[self credential];if(!ORKey(self.key)){if(error)*error=ORError(ORKeyHint(),1);return NO;}NSDictionary *model=[self json:@"GET" path:[@"/v1beta/models/" stringByAppendingString:self.model ?: AMOnlineReviewCurrentModel()] body:nil error:error];BOOL available=[model[@"supportedGenerationMethods"] isKindOfClass:NSArray.class] && [model[@"supportedGenerationMethods"] containsObject:@"generateContent"];if(model && !available && error)*error=ORError(@"当前项目无法使用指定模型，请核对模型和账户资格。",1);return available;}@finally{[self.session invalidateAndCancel];self.session=nil;self.key=nil;ORRelease();}
}
- (NSUInteger)cleanupWithKey:(NSString *)key error:(NSError **)error {
    if(!ORClaim(error))return ORUploads().count;self.cleaning=YES;@try{key=ORNormalizedKey(key);self.key=key.length ? key:[self credential];if(!ORKey(self.key)){if(error)*error=ORError(@"无法读取有效密钥，副本仍待清理。",1);return ORUploads().count;}
        NSDate *cleanupDeadline=[NSDate dateWithTimeIntervalSinceNow:15];
        NSArray *records=ORUploads();NSUInteger processed=0;for(NSDictionary *record in records){
            AMOperationProgress(self.operationID,@"核对与清理上传副本",processed++,records.count);if(self.cancelled || cleanupDeadline.timeIntervalSinceNow<=0)break;if(!ORName(record[@"name"]))continue;
            // Expired service copies need no delete; pending retries expire after one hour.
            NSDate *date=record[@"date"],*keep=record[@"keepUntil"];if(!self.forceCleanup && [keep isKindOfClass:NSDate.class] && keep.timeIntervalSinceNow>0)continue;
            NSError *problem=nil;BOOL expired=[date isKindOfClass:NSDate.class] && date.timeIntervalSinceNow < -48*3600;
            if(expired || [self json:@"DELETE" path:[@"/v1beta/" stringByAppendingString:record[@"name"]] body:nil error:&problem] || problem.code==404)ORStoreUpload(record,YES,error);else {if(error)*error=problem;break;}
        }AMOperationProgress(self.operationID,@"上传副本处理结束",processed,records.count);return ORUploads().count;
    }@finally{[self.session invalidateAndCancel];self.session=nil;self.key=nil;ORRelease();}
}
- (NSDictionary *)upload:(NSDictionary *)asset folder:(NSURL *)folder fingerprint:(NSString *)fingerprint error:(NSError **)error {
    for(NSDictionary *record in ORUploads())if((![record[@"credential"] length] || [record[@"credential"] isEqual:self.credentialIdentity ?: @"test"]) && [record[@"hash"] isEqual:asset[@"resourceHash"]] && [record[@"date"] timeIntervalSinceNow]>-47*3600){
        NSDictionary *file=[self json:@"GET" path:[@"/v1beta/" stringByAppendingString:record[@"name"]] body:nil error:NULL];if([file[@"state"] isEqual:@"ACTIVE"] && [file[@"uri"] isKindOfClass:NSString.class] && ORURL([NSURL URLWithString:file[@"uri"]]) && [[NSURL URLWithString:file[@"uri"]].path isEqual:[@"/v1beta/" stringByAppendingString:record[@"name"]]]){NSMutableDictionary *reused=record.mutableCopy;reused[@"fingerprint"]=fingerprint;ORStoreUpload(reused,NO,NULL);return reused;}
    }
    NSData *data=PFRead([folder URLByAppendingPathComponent:asset[@"resource"]],64*1024*1024);if(!data || ![AMPreflightHash(data) isEqual:asset[@"resourceHash"]]){if(error)*error=ORError(@"图片快照已变化，未上传。请重新检查。",1);return nil;}
    NSData *metadata=[NSJSONSerialization dataWithJSONObject:@{@"file":@{@"display_name":NSUUID.UUID.UUIDString}} options:0 error:error];NSHTTPURLResponse *response=nil;
    NSData *start=[self request:@"POST" url:[NSURL URLWithString:@"https://generativelanguage.googleapis.com/upload/v1beta/files"] data:metadata headers:@{@"Content-Type":@"application/json",@"X-Goog-Upload-Protocol":@"resumable",@"X-Goog-Upload-Command":@"start",@"X-Goog-Upload-Header-Content-Length":[NSString stringWithFormat:@"%lu",(unsigned long)data.length],@"X-Goog-Upload-Header-Content-Type":@"image/png"} response:&response error:error];if(!start)return nil;
    NSString *location=nil;for(NSString *field in response.allHeaderFields)if([field.lowercaseString isEqual:@"x-goog-upload-url"])location=response.allHeaderFields[field];NSURL *url=[NSURL URLWithString:location ?: @""];
    if(!ORURL(url) || ![url.path isEqual:@"/upload/v1beta/files"]){if(error)*error=ORError(@"上传地址不安全，已停止，未向其他目标发送密钥。",1);return nil;}
    NSData *reply=[self request:@"POST" url:url data:data headers:@{@"Content-Type":@"image/png",@"X-Goog-Upload-Offset":@"0",@"X-Goog-Upload-Command":@"upload, finalize"} response:NULL error:error];
    id envelope=reply ? [NSJSONSerialization JSONObjectWithData:reply options:0 error:NULL]:nil;NSDictionary *file=[envelope isKindOfClass:NSDictionary.class] && [envelope[@"file"] isKindOfClass:NSDictionary.class] ? envelope[@"file"]:nil;
    if(!ORName(file[@"name"])){if(reply && error)*error=ORError(@"上传结果无法核验，可能存在未识别的服务端副本；供应商会按其保留期限清理。",1);return nil;}
    NSDictionary *record=@{@"name":file[@"name"],@"uri":[file[@"uri"] isKindOfClass:NSString.class] ? file[@"uri"]:@"",@"date":NSDate.date,@"fingerprint":fingerprint,@"credential":self.credentialIdentity ?: @"test",@"hash":asset[@"resourceHash"]};
    if(!ORStoreUpload(record,NO,error)){BOOL was=self.cancelled;self.cancelled=NO;[self json:@"DELETE" path:[@"/v1beta/" stringByAppendingString:file[@"name"]] body:nil error:NULL];self.cancelled=was;return nil;}
    if(self.cancelled){if(error)*error=ORError(@"在线复核已取消，正在清理上传副本。",-999);return nil;}
    NSURL *uri=[NSURL URLWithString:record[@"uri"]];if(!ORURL(uri) || ![uri.path isEqual:[@"/v1beta/" stringByAppendingString:record[@"name"]]] || ![file[@"state"] isEqual:@"ACTIVE"]){if(error)*error=ORError(@"上传文件尚未就绪或来源无效，可重试。",1);return nil;}return record;
}
- (BOOL)hasBudget:(NSError **)error {
    NSDictionary *old=SSReadPlist(@"online-review-usage.plist");if(old && (![old isKindOfClass:NSDictionary.class] || ![old[@"day"] isKindOfClass:NSString.class] || ![old[@"count"] isKindOfClass:NSNumber.class])){if(error)*error=ORError(@"本机用量记录无法读取，已停止请求。",1);return NO;}if([old isKindOfClass:NSDictionary.class] && [old[@"day"] isEqual:DDLFormatDate(NSDate.date,@"yyyy-MM-dd")] && [old[@"count"] unsignedIntegerValue]>=20){if(error)*error=ORError(@"今日已达本机20次生成请求上限，未上传新材料。",429);return NO;}return YES;
}
- (BOOL)consume:(NSError **)error {
    if(![self hasBudget:error])return NO;
    @synchronized(AMOnlineReviewClient.class){NSString *day=DDLFormatDate(NSDate.date,@"yyyy-MM-dd");NSDictionary *old=SSReadPlist(@"online-review-usage.plist");NSUInteger count=[old[@"day"] isEqual:day] ? [old[@"count"] unsignedIntegerValue]:0;if(count>=20){if(error)*error=ORError(@"今日已达本机20次生成请求上限，已停止；供应商免费额度可能更低。",429);return NO;}return SSWritePlist(@"online-review-usage.plist",@{@"day":day,@"count":@(count+1)},error);}
}
- (NSDictionary *)generateParts:(NSArray *)parts context:(NSDictionary *)context instruction:(NSString *)instruction progress:(void (^)(NSString *))progress error:(NSError **)error {
    NSMutableDictionary *config=[@{@"responseMimeType":@"application/json",@"maxOutputTokens":@16384} mutableCopy];NSString *model=self.model ?: AMOnlineReviewCurrentModel();if([model hasPrefix:@"gemini-3"])config[@"thinkingConfig"]=@{@"thinkingLevel":@"medium"};else if(![model containsString:@"lite"])config[@"thinkingConfig"]=@{@"thinkingBudget":@1024};
    NSDictionary *body=@{@"contents":@[@{@"role":@"user",@"parts":parts}],@"systemInstruction":@{@"parts":@[@{@"text":instruction}]},@"generationConfig":config,@"store":@NO};
    NSDictionary *envelope=nil;
    for(NSUInteger attempt=0;attempt<3;attempt++){
        if(self.cancelled){if(error)*error=ORError(@"在线复核已取消。",-999);return nil;}
        if(![self consume:error])return nil;NSError *problem=nil;
        envelope=[self json:@"POST" path:[NSString stringWithFormat:@"/v1beta/models/%@:generateContent",self.model ?: AMOnlineReviewCurrentModel()] body:body error:&problem];if(envelope)break;
        if(attempt>=2 || ![@[@408,@500,@502,@503,@504] containsObject:@(problem.code)] || self.cancelled){if(error)*error=problem;return nil;}
        NSTimeInterval delay=MAX(self.retryAfter,(attempt ? 15:5)*(0.9+(double)arc4random_uniform(201)/1000));
        if(delay>60){if(error)*error=ORError([problem.localizedDescription stringByAppendingFormat:@" 服务要求至少等待 %.0f 秒，请稍后手动重试。",delay],problem.code);return nil;}
#ifdef DDL_TESTING
        if(self.waitForRetry){if(progress)progress(@"等待重试");if(self.cancelled || !self.waitForRetry(delay)){self.cancelled=YES;break;}continue;}
#endif
        NSDate *resume=[NSDate dateWithTimeIntervalSinceNow:delay];NSInteger last=-1;while(!self.cancelled && resume.timeIntervalSinceNow>0){NSInteger seconds=(NSInteger)ceil(resume.timeIntervalSinceNow);if(last!=seconds){last=seconds;NSString *message=[NSString stringWithFormat:@"服务临时故障（HTTP %ld），%ld秒后重试 %lu/2；计入请求上限…",(long)problem.code,(long)seconds,(unsigned long)attempt+1];if(progress)progress(message);AMOperationProgress(self.operationID,message,0,0);}[NSThread sleepForTimeInterval:.05];}

    }
    if(!envelope){if(self.cancelled && error)*error=ORError(@"复核已取消。",-999);return nil;}
    NSArray *candidates=[envelope[@"candidates"] isKindOfClass:NSArray.class] ? envelope[@"candidates"]:@[];NSDictionary *candidate=[candidates.firstObject isKindOfClass:NSDictionary.class] ? candidates.firstObject:nil;
    if(![candidate[@"finishReason"] isEqual:@"STOP"]){if(error)*error=ORError(@"模型输出被截断、阻止或未完成，不能视为检查通过，可重试。",1);return nil;}
    NSMutableString *output=NSMutableString.string;for(id p in ([candidate[@"content"] isKindOfClass:NSDictionary.class] && [candidate[@"content"][@"parts"] isKindOfClass:NSArray.class] ? candidate[@"content"][@"parts"]:@[]))if([p isKindOfClass:NSDictionary.class] && (!p[@"thought"] || ([p[@"thought"] isKindOfClass:NSNumber.class] && ![p[@"thought"] boolValue])) && [p[@"text"] isKindOfClass:NSString.class])[output appendString:p[@"text"]];
    id raw=[NSJSONSerialization JSONObjectWithData:[output dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];return AMPreflightValidateResult(raw,context,error);
}
- (NSDictionary *)reviewContext:(NSDictionary *)context folder:(NSURL *)folder focus:(NSDictionary *)focus progress:(void (^)(NSString *))progress error:(NSError **)error {
    void (^originalProgress)(NSString *)=[progress copy];progress=^(NSString *stage){if(![stage hasPrefix:@"上传／复用图片"])AMOperationProgress(self.operationID,stage,0,0);if(originalProgress)originalProgress(stage);};
    if(!ORClaim(error))return nil;self.cleaning=NO;self.model=self.model ?: AMOnlineReviewCurrentModel();NSString *fingerprint=nil;BOOL complete=NO;BOOL retryable=NO;
    @try {
        if(![AMOnlineReviewSettings()[@"enabled"] boolValue]){if(error)*error=ORError(@"请先配置并启用在线复核。",1);return nil;}
        self.key=[self credential];if(!ORKey(self.key)){if(error)*error=ORError(@"无法读取有效钥匙串密钥，请重新配置。",1);return nil;}
        NSData *stored=PFRead([folder URLByAppendingPathComponent:@"context.local.json"],32*1024*1024);NSData *expected=[NSJSONSerialization dataWithJSONObject:context options:NSJSONWritingSortedKeys error:NULL];id decoded=stored ? [NSJSONSerialization JSONObjectWithData:stored options:0 error:NULL]:nil;
        if(![decoded isEqual:context] || !expected || SSContainsSecret(expected) || ORPrivatePath(context) ){if(error)*error=ORError(@"材料版本或隐私检查未通过，未发送。",1);return nil;}
        for(NSDictionary *asset in context[@"images"]){NSString *resource=asset[@"resource"];if(![resource isKindOfClass:NSString.class] || ![resource isEqual:resource.lastPathComponent] || ![AMPreflightHash(PFRead([folder URLByAppendingPathComponent:resource],64*1024*1024) ?: NSData.data) isEqual:asset[@"resourceHash"]]){if(error)*error=ORError(@"图片快照已变化，请重新准备材料。",1);return nil;}}
        fingerprint=AMPreflightHash([NSJSONSerialization dataWithJSONObject:@{@"context":@{@"documents":context[@"documents"],@"images":context[@"images"],@"requirements":context[@"requirements"],@"excluded":context[@"unverifiedImages"] ?: @[]},@"focus":focus ?: @{},@"model":self.model ?: AMOnlineReviewCurrentModel(),@"prompt":AMReviewPromptVersion(),@"validation":AMReviewValidationVersion()} options:NSJSONWritingSortedKeys error:NULL]);
        NSString *cacheName=[NSString stringWithFormat:@"online-review-%@.plist",fingerprint];NSDictionary *cache=SSReadPlist(cacheName);
        if([cache isKindOfClass:NSDictionary.class] && [cache[@"result"] isKindOfClass:NSDictionary.class]){NSMutableDictionary *raw=[cache[@"result"] mutableCopy];raw[@"batchID"]=context[@"batchID"];raw[@"reportVersion"]=context[@"reportVersion"];NSDictionary *validated=AMPreflightValidateResult(raw,context,error);if(validated){if(!PFWrite([NSJSONSerialization dataWithJSONObject:raw options:0 error:error],[folder URLByAppendingPathComponent:@"results.local.json"],error))return nil;complete=YES;NSMutableDictionary *answer=validated.mutableCopy;answer[@"cached"]=@YES;answer[@"model"]=self.model ?: AMOnlineReviewCurrentModel();return answer;}}
        if(![self hasBudget:error])return nil;
        if(progress)progress(@"准备整份项目与图片快照…");NSMutableArray *parts=NSMutableArray.array;
        NSMutableDictionary *metadata=context.mutableCopy;[metadata removeObjectForKey:@"images"];[metadata removeObjectForKey:@"excluded"];[metadata removeObjectForKey:@"unverifiedImages"];NSMutableArray *images=NSMutableArray.array;
        for(NSDictionary *asset in context[@"images"]){NSMutableDictionary *row=asset.mutableCopy;[row removeObjectForKey:@"resourceHash"];[images addObject:row];}metadata[@"images"]=images;
        NSData *text=[NSJSONSerialization dataWithJSONObject:metadata options:NSJSONWritingPrettyPrinted error:error];if(!text)return nil;
        [parts addObject:@{@"text":[[NSString alloc] initWithData:text encoding:NSUTF8StringEncoding]}];
        if(focus){NSData *selection=[NSJSONSerialization dataWithJSONObject:focus options:0 error:error];if(!selection || SSContainsSecret(selection) || ORPrivatePath(focus)){if(error)*error=ORError(@"疑点含无效或敏感内容，未发送。",1);return nil;}[parts addObject:@{@"text":[@"请结合整份项目重新核对这个疑点；允许撤回原判断：" stringByAppendingString:[[NSString alloc] initWithData:selection encoding:NSUTF8StringEncoding]]}];}
        NSUInteger index=0;
        for(NSDictionary *asset in context[@"images"]){if(self.cancelled){if(error)*error=ORError(@"在线复核已取消。",-999);return nil;}if(progress)progress([NSString stringWithFormat:@"上传／复用图片 %lu／%lu…",(unsigned long)++index,(unsigned long)[context[@"images"] count]]);AMOperationProgress(self.operationID,@"上传／复用图片",index-1,[context[@"images"] count]);NSDictionary *file=[self upload:asset folder:folder fingerprint:fingerprint error:error];if(!file){retryable=YES;return nil;}[parts addObject:@{@"text":[NSString stringWithFormat:@"图片 %@，对应 %@，引用于 %@:%@",asset[@"id"],asset[@"path"],asset[@"document"],asset[@"line"]]}];[parts addObject:@{@"fileData":@{@"mimeType":@"image/png",@"fileUri":file[@"uri"]}}];}
        NSString *instruction=AMReviewPrompt();
        NSDictionary *contents=@{@"role":@"user",@"parts":parts};
        if(progress)progress(@"核对整份项目的接口容量…");NSDictionary *tokens=[self json:@"POST" path:[NSString stringWithFormat:@"/v1beta/models/%@:countTokens",self.model ?: AMOnlineReviewCurrentModel()] body:@{@"contents":@[contents]} error:error];if(!tokens){retryable=YES;return nil;}
        if(![tokens[@"totalTokens"] isKindOfClass:NSNumber.class]){if(error)*error=ORError(@"无法核对接口容量，本次未完整检查。",1);return nil;}
        NSDictionary *validated=nil;
        if([tokens[@"totalTokens"] unsignedIntegerValue]<=900000){AMOperationProgress(self.operationID,@"等待模型综合复核（不会运行代码）",0,0);if(progress)progress(@"等待 Gemini 综合复核（不会运行代码）…");validated=[self generateParts:parts context:context instruction:instruction progress:progress error:error];}
        else {
            if(progress)progress(@"整份项目超出容量，按文档／自然章节复核；跨文件结论将标为未验证…");
            NSMutableArray *groups=NSMutableArray.array,*allIssues=NSMutableArray.array,*allChecked=NSMutableArray.array,*unverified=NSMutableArray.array;NSMutableArray *overview=NSMutableArray.array;NSMutableSet *used=NSMutableSet.set;
            for(NSDictionary *doc in context[@"documents"])[overview addObject:@{@"path":doc[@"path"],@"version":doc[@"version"]}];
            // Natural Markdown headings are preferred boundaries. A single huge section
            // may be divided at a line boundary, preserving original evidence offsets.
            for(NSDictionary *doc in context[@"documents"]){NSArray *lines=[doc[@"text"] componentsSeparatedByString:@"\n"];NSUInteger from=0,size=0;
                for(NSUInteger i=0;i<=lines.count;i++){BOOL boundary=i==lines.count || (i>from && (size>=512000 || (size>=256000 && RMatch(lines[i],@"^#{1,6} "))));
                    if(boundary){NSMutableDictionary *section=doc.mutableCopy;section[@"text"]=[[lines subarrayWithRange:NSMakeRange(from,i-from)] componentsJoinedByString:@"\n"];section[@"startLine"]=@(from+1);[groups addObject:@{@"documents":@[section],@"images":@[]}];from=i;size=0;}if(i<lines.count)size+=[lines[i] lengthOfBytesUsingEncoding:NSUTF8StringEncoding]+1;}
            }
            for(NSUInteger i=0;i<groups.count;i++){NSMutableDictionary *group=[groups[i] mutableCopy];NSMutableArray *assets=NSMutableArray.array;NSString *path=[group[@"documents"] firstObject][@"path"];
                for(NSDictionary *asset in images)if([asset[@"document"] isEqual:path]){[assets addObject:asset];[used addObject:asset[@"id"]];}group[@"images"]=assets;groups[i]=group;}
            NSMutableArray *orphans=NSMutableArray.array;for(NSDictionary *asset in images)if(![used containsObject:asset[@"id"]])[orphans addObject:asset];if(orphans.count)[groups addObject:@{@"documents":@[],@"images":orphans}];
            NSUInteger i=0;for(NSDictionary *group in groups){if(self.cancelled){if(error)*error=ORError(@"在线复核已取消。",-999);return nil;}if(progress)progress([NSString stringWithFormat:@"文档／章节 %lu／%lu…",(unsigned long)++i,(unsigned long)groups.count]);
                NSMutableDictionary *piece=metadata.mutableCopy;piece[@"documents"]=group[@"documents"];piece[@"images"]=group[@"images"];piece[@"projectFiles"]=overview;piece[@"coverageNote"]=@"超过整体容量，仅检查本组全文；文件清单不是其他文件全文。startLine 是原文件的1-based行号。不能声称已核对跨组一致性。";
                NSMutableArray *sectionParts=NSMutableArray.array;[sectionParts addObject:@{@"text":[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:piece options:0 error:NULL] encoding:NSUTF8StringEncoding]}];
                if(focus)[sectionParts addObject:parts[1]];
                for(NSDictionary *asset in group[@"images"]){NSUInteger imageIndex=[images indexOfObject:asset];NSUInteger offset=1+(focus ? 1:0)+imageIndex*2;[sectionParts addObject:parts[offset]];[sectionParts addObject:parts[offset+1]];}
                NSDictionary *count=[self json:@"POST" path:[NSString stringWithFormat:@"/v1beta/models/%@:countTokens",self.model ?: AMOnlineReviewCurrentModel()] body:@{@"contents":@[@{@"role":@"user",@"parts":sectionParts}]} error:error];
                if(![count[@"totalTokens"] isKindOfClass:NSNumber.class] || [count[@"totalTokens"] unsignedIntegerValue]>900000){if(error && !*error)*error=ORError(@"单个文档／章节及关联图片仍超出容量；请缩小范围。本次没有完整报告。",413);return nil;}
                NSMutableDictionary *validationContext=context.mutableCopy;NSMutableArray *sourceDocs=NSMutableArray.array;for(NSDictionary *sent in group[@"documents"])for(NSDictionary *original in context[@"documents"])if([sent[@"path"] isEqual:original[@"path"]])[sourceDocs addObject:original];validationContext[@"documents"]=sourceDocs;validationContext[@"images"]=group[@"images"];validationContext[@"unverifiedImages"]=@[];
                NSDictionary *part=[self generateParts:sectionParts context:validationContext instruction:instruction progress:progress error:error];if(!part){retryable=YES;return nil;}[allIssues addObjectsFromArray:part[@"issues"]];[allChecked addObjectsFromArray:part[@"checked"]];[unverified addObjectsFromArray:part[@"unverified"]];
            }
            [unverified addObject:@"材料超出整体容量，已按文档／自然章节处理；跨组推导和项目整体一致性未能完整核对。"];
            validated=@{@"issues":allIssues,@"checked":[NSOrderedSet orderedSetWithArray:allChecked].array,@"unverified":[NSOrderedSet orderedSetWithArray:unverified].array,@"excluded":context[@"excluded"] ?: @[],@"partial":@YES,@"reportVersion":context[@"reportVersion"]};
        }
        if(!validated){retryable=YES;return nil;}if(progress)progress(@"核验位置、原文证据与图片区域…");
        // Only validated evidence is persisted; discard invalid or secret-bearing provider fields.
        NSMutableArray *safeFindings=NSMutableArray.array;for(NSDictionary *issue in validated[@"issues"]){NSMutableDictionary *copy=NSMutableDictionary.dictionary;for(NSString *field in @[@"path",@"version",@"category",@"severity",@"message",@"reason",@"suggestion",@"line",@"evidence",@"region"])if(issue[field])copy[field]=issue[field];[safeFindings addObject:copy];}
        NSMutableArray *checked=NSMutableArray.array;for(NSString *path in validated[@"checked"]){for(NSDictionary *source in [context[@"documents"] arrayByAddingObjectsFromArray:context[@"images"]])if([source[@"path"] isEqual:path]){[checked addObject:@{@"path":path,@"version":source[@"version"]}];break;}}
        NSDictionary *safe=@{@"format":@"am-preflight-results-v1",@"batchID":context[@"batchID"],@"reportVersion":context[@"reportVersion"],@"findings":safeFindings,@"checked":checked,@"unverified":validated[@"unverified"]};
        if(!SSWritePlist(cacheName,@{@"result":safe,@"date":NSDate.date},error))return nil;
        if(!PFWrite([NSJSONSerialization dataWithJSONObject:safe options:0 error:error],[folder URLByAppendingPathComponent:@"results.local.json"],error))return nil;
        complete=YES;NSMutableDictionary *answer=validated.mutableCopy;answer[@"model"]=self.model ?: AMOnlineReviewCurrentModel();answer[@"cached"]=@NO;return answer;
    }@finally {
        BOOL cancelled=self.cancelled;self.cleaning=YES;BOOL cleanupFailed=NO;NSDate *cleanupDeadline=[NSDate dateWithTimeIntervalSinceNow:15];
        AMOperationProgress(self.operationID,@"清理／保留可复用上传副本",0,0);
        for(NSDictionary *record in ORUploads())if(fingerprint && [record[@"fingerprint"] isEqual:fingerprint]){
            NSMutableDictionary *next=record.mutableCopy;if(!complete && !cancelled && retryable){next[@"keepUntil"]=[NSDate dateWithTimeIntervalSinceNow:3600];ORStoreUpload(next,NO,NULL);continue;}
            [next removeObjectForKey:@"keepUntil"];ORStoreUpload(next,NO,NULL);NSError *cleanupError=nil;
            if(!cancelled && !self.cancelled && !cleanupFailed && cleanupDeadline.timeIntervalSinceNow>0){if([self json:@"DELETE" path:[@"/v1beta/" stringByAppendingString:record[@"name"]] body:nil error:&cleanupError] || cleanupError.code==404)ORStoreUpload(record,YES,NULL);else cleanupFailed=YES;}
        }
        [self.session invalidateAndCancel];self.session=nil;self.key=nil;ORRelease();
    }
}
@end
void AMOnlineReviewCleanup(void){if(!ORUploads().count)return;AMOnlineReviewClient *client=AMOnlineReviewClient.new;client.operationID=AMOperationBegin(@"清理上传副本",@"Gemini",NO,nil);NSError *error=nil;NSUInteger remaining=[client cleanupWithKey:@"" error:&error];AMOperationFinish(client.operationID,error ? @"failed":@"success",error ? @"副本清理未完成，可在在线设置重试":[NSString stringWithFormat:@"副本核对完成，%lu 个仍保留供重试",(unsigned long)remaining]);}
