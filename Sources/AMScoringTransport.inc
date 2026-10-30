// Independent grading request. Extraction/review prompts cannot be used for grading.
- (id)scoreJSON:(NSDictionary *)input instruction:(NSString *)instruction images:(NSArray *)images settings:(NSDictionary *)settings error:(NSError **)error {
    if(self.scoringCancelled){if(error)*error=[NSError errorWithDomain:@"AMScoring" code:NSUserCancelledError userInfo:@{NSLocalizedDescriptionKey:@"评分已停止"}];return nil;}
    NSUInteger remaining=settings[@"remainingRequests"] ? [settings[@"remainingRequests"] unsignedIntegerValue]:1;
    if(!remaining){if(error)*error=RError(@"已达到本次请求上限，未发送");return nil;}
    if(!SSValidateRecognitionSettings(settings,error) || [settings[@"mode"] isEqual:@"rules"])return nil;
    if(!AMScoringImagesValid(images)){if(error)*error=RError(@"评分图片无效、重复或超过24MB，未发送");return nil;}
    NSData *inputData=[NSJSONSerialization dataWithJSONObject:input options:0 error:error];if(!inputData || inputData.length>500000 || SSContainsSecret(inputData)){if(error && !*error)*error=RError(@"评分材料过大或含疑似凭据，未发送");return nil;}
    BOOL cloud=[settings[@"mode"] isEqual:@"cloud"];NSString *key=cloud ? [self cloudKeyForEndpoint:settings[@"endpoint"]]:nil;
    if(cloud && (![settings[@"cloudConsent"] boolValue] || !key.length)){if(error)*error=RError(@"请确认发送范围并配置评分模型密钥");return nil;}

    NSMutableArray *messages=[NSMutableArray arrayWithObject:@{@"role":@"system",@"content":instruction}],*parts=NSMutableArray.array;
    for(NSDictionary *segment in AMScoringSegments(input,images)){if(segment[@"text"]){if(cloud)[parts addObject:@{@"type":@"text",@"text":segment[@"text"]}];else [messages addObject:@{@"role":@"user",@"content":segment[@"text"]}];}else{NSDictionary *image=segment[@"image"];if(cloud)[parts addObject:@{@"type":@"image_url",@"image_url":@{@"url":[NSString stringWithFormat:@"data:%@;base64,%@",image[@"mime"],image[@"base64"]]}}];else [messages addObject:@{@"role":@"user",@"content":image[@"path"],@"images":@[image[@"base64"]]}];}}
    if(cloud)[messages addObject:@{@"role":@"user",@"content":parts}];
    NSMutableDictionary *body=[@{@"model":settings[@"model"],@"messages":messages,@"stream":@NO} mutableCopy];if(cloud){body[@"response_format"]=@{@"type":@"json_object"};body[@"max_tokens"]=@8192;}else{body[@"think"]=@NO;body[@"format"]=@"json";body[@"options"]=@{@"temperature":@0,@"num_predict":@8192};}
    NSString *base=[settings[@"endpoint"] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];NSString *route=cloud ? @"/chat/completions":@"/api/chat";
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:[base stringByAppendingString:route]]];request.HTTPMethod=@"POST";request.timeoutInterval=180;[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];if(cloud)[request setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];request.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:error];
    // 构造多模态内容可能耗时；真正发送前再次检查取消，尚未发出的请求不计数。
    if(self.scoringCancelled || AMCurrentOperationCancelled()){if(error)*error=RError(@"评分已停止，未发送请求");return nil;}
    if(cloud){@synchronized(SSRecognitionClient.class){NSString *day=DDLFormatDate(NSDate.date,@"yyyy-MM-dd");NSDictionary *saved=SSReadPlist(@"recognition-usage.plist");NSUInteger count=[saved[@"day"] isEqual:day] ? [saved[@"count"] unsignedIntegerValue]:0;if(count>=20 || !SSWritePlist(@"recognition-usage.plist",@{@"day":day,@"count":@(count+1)},error)){if(error && !*error)*error=RError(@"今日生成请求额度已用完");return nil;}}}
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:180];
    NSMutableSet *capabilities=RUnsupportedFormats();NSString *capability=RFormatKey(base,settings);
    @synchronized(capabilities){if(!cloud && [capabilities containsObject:capability])[body removeObjectForKey:@"format"];}
    __block NSData *data=nil;__block NSError *failure=nil;__block NSInteger status=200;
    for(NSUInteger attempt=0;attempt<MIN(remaining,2);attempt++){
        if(self.scoringCancelled || AMCurrentOperationCancelled()){if(error)*error=RError(@"评分已停止");return nil;}
        request.timeoutInterval=MAX(0.1,deadline.timeIntervalSinceNow);request.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:error];
        self.scoringRequestsUsed++;failure=nil;data=nil;status=200;
        if(self.transport){data=self.transport(request,&failure);if([failure.domain isEqual:@"AMScoringHTTP"])status=failure.code;}
        else{
            NSURLSessionConfiguration *configuration=NSURLSessionConfiguration.ephemeralSessionConfiguration;configuration.URLCache=nil;configuration.HTTPCookieStorage=nil;configuration.URLCredentialStorage=nil;configuration.timeoutIntervalForResource=MAX(0.1,deadline.timeIntervalSinceNow);
            NSURLSession *session=[NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];dispatch_semaphore_t signal=dispatch_semaphore_create(0);
            NSURLSessionDataTask *task=[session dataTaskWithRequest:request completionHandler:^(NSData *bytes,NSURLResponse *response,NSError *problem){data=bytes;failure=problem;status=[(NSHTTPURLResponse *)response statusCode];dispatch_semaphore_signal(signal);}];[task resume];
            while(dispatch_semaphore_wait(signal,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC))){if(self.scoringCancelled || AMCurrentOperationCancelled() || deadline.timeIntervalSinceNow<=0){[session invalidateAndCancel];if(error)*error=RError(self.scoringCancelled || AMCurrentOperationCancelled() ? @"评分已停止":@"评分超时，完整结果已保留");return nil;}}[session finishTasksAndInvalidate];
        }
        // 仅本机明确拒绝 JSON 约束时兼容一次；仍用相同截止时间、证据校验和用户请求上限。
        // 云端错误不自动重发，也不把格式失败当作评分完成。
        if(!cloud && status==501 && body[@"format"]){@synchronized(capabilities){[capabilities addObject:capability];}[body removeObjectForKey:@"format"];if(attempt+1<MIN(remaining,2) && deadline.timeIntervalSinceNow>0)continue;}
        break;
    }
    if(self.scoringCancelled || AMCurrentOperationCancelled() || failure || status!=200 || data.length>2*1024*1024){
        NSString *message=@"评分响应过大，未计入排名";
        if(self.scoringCancelled || AMCurrentOperationCancelled())message=@"评分已停止";
        else if(failure && ![failure.domain isEqual:@"AMScoringHTTP"])message= failure.code==NSURLErrorTimedOut ? @"评分超时，请稍后继续未完成部分":@"无法连接评分服务，请检查网络或本地服务";
        else if(status==401 || status==403)message=@"评分服务拒绝访问，请核对模型授权及密钥";
        else if(status==404)message=@"未找到评分模型，请检查设置中的模型名称";
        else if(status==429)message=@"评分服务限流，请稍后继续未完成部分";
        else if(status==501)message=@"本地模型不支持 JSON 约束，已记住兼容模式；可继续检查";
        else if(status!=200)message=[NSString stringWithFormat:@"评分服务返回 HTTP %ld，请检查服务后重试",(long)status];
        if(error)*error=RError(message);return nil;
    }
    id envelope=[NSJSONSerialization JSONObjectWithData:data options:0 error:error];if(![envelope isKindOfClass:NSDictionary.class])return nil;
    id choices=envelope[@"choices"];NSDictionary *first=[choices isKindOfClass:NSArray.class] && [choices count] && [choices[0] isKindOfClass:NSDictionary.class] ? choices[0]:nil;
    NSString *finish=cloud ? first[@"finish_reason"]:envelope[@"done_reason"];
    if(![finish isEqual:@"stop"] || (!cloud && ![envelope[@"done"] boolValue])){if(error)*error=RError([finish isEqual:@"length"] ? @"评分输出达到上限，未计入排名；可缩小范围后继续":@"评分被拦截或未完整结束，未计入排名");return nil;}
    id message=cloud ? first[@"message"]:envelope[@"message"];NSString *content=[message isKindOfClass:NSDictionary.class] ? message[@"content"]:nil;id result=SSRecognitionJSONObject(content,!cloud);if(![result isKindOfClass:NSDictionary.class]){if(error)*error=RError(@"评分未返回完整 JSON，未计入排名");return nil;}return result;
}
