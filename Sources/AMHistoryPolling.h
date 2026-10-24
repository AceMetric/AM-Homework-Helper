#pragma once
#import "AMPreflight.h"
#import "AMWorkflow.h"
// Background polling is scoped to both the repository binding and account.
static inline NSString *AMHistoryPollingKey(NSDictionary *course,NSDictionary *account){
    NSMutableArray *parts=NSMutableArray.array;for(NSString *key in @[@"fork",@"branch",@"upstream",@"upstreamBranch",@"path",@"forkID",@"upstreamID",@"ownerID"])[parts addObject:course[key] ?: @""];
    [parts addObject:account ?: @{}];return AMPreflightHash([NSJSONSerialization dataWithJSONObject:parts options:NSJSONWritingSortedKeys error:NULL]);
}
static inline NSDate *AMHistoryServerRetry(id state){id date=[state isKindOfClass:NSDictionary.class] ? state[@"retryAt"]:nil;return [date isKindOfClass:NSDate.class] ? date:NSDate.distantPast;}
static inline BOOL AMHistoryPollDue(NSDictionary *state,NSDate *now){if(![state isKindOfClass:NSDictionary.class])return YES;return ![state[@"next"] isKindOfClass:NSDate.class] || [state[@"next"] compare:now]!=NSOrderedDescending;}
static inline NSDictionary *AMHistoryPollResult(NSDictionary *old,NSError *error,BOOL cancelled,NSDate *now){
    if(![old isKindOfClass:NSDictionary.class])old=@{};
    NSUInteger failures=error && !cancelled ? MIN(7,[old[@"failures"] isKindOfClass:NSNumber.class] ? [old[@"failures"] unsignedIntegerValue]:0)+1:0;
    NSTimeInterval wait=failures ? MIN(1800,300*(1UL<<MIN(failures-1,3))):60;
    NSDate *next=[now dateByAddingTimeInterval:wait],*limited=error.userInfo[@"AMRetryAt"];if([limited isKindOfClass:NSDate.class] && [limited compare:next]==NSOrderedDescending)next=limited;
    return @{@"failures":@(failures),@"next":next,@"retryAt":[limited isKindOfClass:NSDate.class] ? limited:NSDate.distantPast,@"issue":error && !cancelled ? AMWorkflowIssue(error):@""};
}
