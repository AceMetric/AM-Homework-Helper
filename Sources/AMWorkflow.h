#pragma once
#import <Foundation/Foundation.h>
#import "SSSecurity.h"
// Private workflow vocabulary. Exchange files and stored task schemas are unchanged.
typedef NS_ENUM(NSInteger, AMCourseWorkKind){AMCourseWorkGit,AMCourseWorkLocal,AMCourseWorkModel,AMCourseWorkSubmission};
static inline NSError *AMWorkflowError(NSString *issue,NSString *message,NSError *underlying){
    NSMutableDictionary *info=[@{NSLocalizedDescriptionKey:message,@"SSIssue":issue,@"SSDetail":SSRedactedText(underlying.userInfo[@"SSDetail"] ?: underlying.localizedDescription ?: message)} mutableCopy];if(underlying)info[NSUnderlyingErrorKey]=underlying;return [NSError errorWithDomain:@"AMWorkflow" code:[issue isEqual:@"cancelled"] ? NSUserCancelledError:([issue isEqual:@"timeout"] ? NSURLErrorTimedOut:(underlying ? underlying.code:1)) userInfo:info];
}
static inline NSString *AMWorkflowIssue(NSError *error){
    NSString *issue=error.userInfo[@"SSIssue"];if(issue.length)return issue;
    if(error.code==NSUserCancelledError || error.code==NSURLErrorCancelled)return @"cancelled";
    if(error.code==NSURLErrorTimedOut)return @"timeout";
    if([error.domain isEqual:NSURLErrorDomain])return @"network";
    if([error.domain isEqual:NSCocoaErrorDomain] || [error.domain isEqual:@"AMSubmissionStore"] || [error.domain isEqual:@"SSLocalData"])return @"storage";
    if([error.userInfo[@"SSPreflightStale"] boolValue] || [error.userInfo[@"SSSelectionStale"] boolValue])return @"files-changed";
    return @"unknown";
}
static inline BOOL AMWorkflowTransient(NSError *error){return [@[@"network",@"service",@"rate-limit",@"timeout"] containsObject:AMWorkflowIssue(error)];}
static inline BOOL AMWorkflowRetryDelay(NSTimeInterval delay,NSDate *deadline,BOOL (^cancelled)(void)){
    if(delay>5 || delay<0 || deadline.timeIntervalSinceNow<=delay)return NO;NSDate *ready=[NSDate dateWithTimeIntervalSinceNow:delay];while(ready.timeIntervalSinceNow>0){if(cancelled && cancelled())return NO;[NSThread sleepForTimeInterval:MIN(.05,ready.timeIntervalSinceNow)];}return !(cancelled && cancelled());
}
static inline NSDictionary *AMWorkflowProblem(NSError *error,NSString *stage,NSDictionary *record){
    NSString *issue=AMWorkflowIssue(error),*title=@"操作未完成",*effect=@"已有文件保留",*action=@"重试",*command=@"retry";
    if([@[@"login",@"ssh"] containsObject:issue]){title=@"需要重新登录";action=@"重新登录";command=@"login";}
    else if([@[@"permission",@"sso",@"approval"] containsObject:issue]){title=@"无法访问课程仓库";action=@"检查访问";command=@"access";}
    else if([issue isEqual:@"rate-limit"]){title=@"GitHub 请求受限";action=@"重试";}
    else if([@[@"network",@"service",@"timeout"] containsObject:issue]){title=[issue isEqual:@"timeout"] ? @"当前步骤超时":@"连接暂时失败";}
    else if([@[@"directory",@"sandbox"] containsObject:issue]){title=@"课程文件夹不可用";action=@"重新关联";command=@"relink";}
    else if([issue isEqual:@"branch"]){title=@"课程分支不匹配";action=@"打开文件夹";command=@"folder";}
    else if([issue isEqual:@"dirty"]){title=@"本地修改需要处理";action=@"查看修改";command=@"changes";}
    else if([issue isEqual:@"merge-conflict"]){title=@"课程文件存在冲突";action=@"处理冲突";command=@"conflicts";}
    else if([issue isEqual:@"diverged"]){title=@"个人远端已有更新";action=@"查看差异";command=@"difference";}
    else if([@[@"source-changed",@"files-changed"] containsObject:issue]){title=@"材料版本已变化";action=@"刷新并检查";command=@"refresh";}
    else if([issue isEqual:@"recognition"]){title=error.userInfo[@"AMRecognitionSummary"] ?: @"部分材料未完成增强";effect=@"可用结果已保留";action=@"重试失败项";command=@"recognition";}
    else if([issue isEqual:@"storage"]){title=@"结果尚未保存";action=@"重试保存";command=@"save";}
    else if([issue isEqual:@"cancelled"]){title=@"已停止";action=@"";command=@"none";}
    if([record[@"localUpdated"] boolValue])effect=@"本地已更新，老师更新尚未合并";
    if([record[@"commit"] length] || [record[@"before"] length] || [record[@"state"] isEqual:@"uncertain"] || [error.userInfo[@"SSPendingPush"] boolValue]){effect=[record[@"commit"] length] ? @"本地提交已保留":@"提交结果待核验";if(![@[@"storage",@"login",@"ssh",@"permission",@"sso",@"approval",@"directory",@"sandbox",@"merge-conflict"] containsObject:issue]){action=@"核验推送";command=@"verify";}}
    if([record[@"state"] isEqual:@"failed"] && [record[@"issue"] isEqual:@"not-committed"]){effect=@"未创建提交";action=@"查看修改";command=@"changes";}
    if([record[@"state"] isEqual:@"confirmed"]){effect=@"远端已确认，记录尚未保存";action=@"重试保存";command=@"save";}
    NSString *detail=SSRedactedText(error.userInfo[@"SSDetail"] ?: error.localizedDescription ?: @"未返回有效结果");
    NSString *result=[record[@"state"] isEqual:@"uncertain"] ? @"uncertain":([issue isEqual:@"cancelled"] ? @"cancelled":([@[@"login",@"ssh",@"permission",@"sso",@"approval",@"directory",@"dirty",@"merge-conflict",@"diverged"] containsObject:issue] ? @"needs-action":@"failed"));
    return @{@"issue":issue,@"title":title,@"effect":effect,@"action":action,@"command":command,@"stage":stage ?: @"",@"details":detail,@"result":result,@"recordID":record[@"id"] ?: @"",@"retryAt":error.userInfo[@"AMRetryAt"] ?: NSDate.distantPast};
}
