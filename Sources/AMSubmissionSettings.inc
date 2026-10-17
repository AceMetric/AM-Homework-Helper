// Submission completion is a local decision over verified Git evidence. No model calls.
static BOOL AMCompletionHash(id v){return [v isKindOfClass:NSString.class] && [v rangeOfString:@"^[a-f0-9]{40,64}$" options:NSRegularExpressionSearch].location!=NSNotFound;}
static NSString *AMCompletionCourseKey(NSDictionary *course){return [NSString stringWithFormat:@"%@|%@",[course[@"fork"] lowercaseString] ?: @"",course[@"branch"] ?: @""];}
static BOOL AMValidSubmissionAutomation(id state){
    if(![state isKindOfClass:NSDictionary.class] || (state[@"epoch"] && ![state[@"epoch"] isKindOfClass:NSString.class]) || ![state[@"enabled"] isKindOfClass:NSNumber.class] || ![state[@"baselines"] isKindOfClass:NSDictionary.class])return NO;
    for(id key in state[@"baselines"]){NSDictionary *b=state[@"baselines"][key];if(![key isKindOfClass:NSString.class] || ![b isKindOfClass:NSDictionary.class] || !AMCompletionHash(b[@"anchor"]) || !AMCompletionHash(b[@"tip"]))return NO;}return YES;
}
NSDictionary *AMSubmissionAutomation(NSError **error){
    id state=SSReadPlist(@"submission-automation.plist");if(!state && ![NSFileManager.defaultManager fileExistsAtPath:[[SSDataDirectory() URLByAppendingPathComponent:@"submission-automation.plist"] path]])return @{@"enabled":@YES,@"baselines":@{},@"epoch":@"initial"};
    BOOL valid=AMValidSubmissionAutomation(state);
    if(!valid){if(error)*error=StoreError(@"自动完成设置无法读取，请重试或恢复设置。");return nil;}return state;
}
BOOL AMSubmissionAutoCompletionEnabled(void){return [AMSubmissionAutomation(NULL)[@"enabled"] boolValue];}
BOOL AMSetSubmissionAutoCompletionEnabled(BOOL enabled,NSError **error){
    @synchronized(NSFileManager.defaultManager){NSDictionary *old=AMSubmissionAutomation(error);if(!old)return NO;if([old[@"enabled"] boolValue]==enabled)return YES;return SSWritePlist(@"submission-automation.plist",@{@"enabled":@(enabled),@"baselines":@{},@"epoch":NSUUID.UUID.UUIDString},error);}
}
NSDictionary *AMSubmissionBaseline(NSDictionary *course,NSError **error){NSDictionary *state=AMSubmissionAutomation(error);return state ? (state[@"baselines"][AMCompletionCourseKey(course)] ?: @{}):nil;}
BOOL AMStoreSubmissionBaseline(NSDictionary *course,NSDictionary *baseline,NSDictionary *expected,NSString *epoch,NSError **error){
    @synchronized(NSFileManager.defaultManager){NSDictionary *state=AMSubmissionAutomation(error);if(!state)return NO;NSString *key=AMCompletionCourseKey(course);if(![(state[@"epoch"] ?: @"initial") isEqual:epoch] || ![(state[@"baselines"][key] ?: @{}) isEqual:expected]){if(error)*error=StoreError(@"提交核验状态已更新，将在下次检查重试。");return NO;}
        if(!AMCompletionHash(baseline[@"anchor"]) || !AMCompletionHash(baseline[@"tip"]))return NO;NSMutableDictionary *next=state.mutableCopy,*baselines=[state[@"baselines"] mutableCopy];baselines[key]=baseline;next[@"baselines"]=baselines;return SSWritePlist(@"submission-automation.plist",next,error);}
}
BOOL AMResetSubmissionBaselines(NSError **error){@synchronized(NSFileManager.defaultManager){NSDictionary *old=AMSubmissionAutomation(error);return old && SSWritePlist(@"submission-automation.plist",@{@"enabled":old[@"enabled"],@"baselines":@{},@"epoch":NSUUID.UUID.UUIDString},error);}}
