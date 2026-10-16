#import <CommonCrypto/CommonDigest.h>
// A decision belongs to source evidence, never an AI summary or a Git commit.
static NSString *AMReviewEvidenceText(id value){NSString *text=[value isKindOfClass:NSString.class] ? value : @"";return [[text stringByReplacingOccurrencesOfString:@"\\s+" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0,text.length)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];}
static NSString *AMReviewDecisionKey(NSDictionary *record){
    NSMutableArray *evidence=NSMutableArray.array;
    NSString *snippet=record[@"snippet"] ?: record[@"text"] ?: record[@"notes"] ?: @"";
    [evidence addObject:AMReviewEvidenceText(snippet)];[evidence addObject:record[@"dateText"] ?: @""];
    for(NSDictionary *attachment in [record[@"attachments"] sortedArrayUsingComparator:^NSComparisonResult(id a,id b){return [a[@"path"] compare:b[@"path"]];}])
        [evidence addObject:@[attachment[@"path"] ?: @"",attachment[@"blobSHA"] ?: @"",AMReviewEvidenceText(attachment[@"snippet"])]];
    if(!snippet.length)[evidence addObject:record[@"blobSHA"] ?: @""];
    NSArray *identity=@[record[@"repository"] ?: record[@"sourceType"] ?: @"local",record[@"path"] ?: @"",evidence];
    NSData *data=[NSJSONSerialization dataWithJSONObject:identity options:NSJSONWritingSortedKeys error:NULL];unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);NSMutableString *key=NSMutableString.string;for(NSUInteger i=0;i<sizeof(digest);i++)[key appendFormat:@"%02x",digest[i]];return key;
}
static NSObject *AMReviewDecisionLock(void){static NSObject *lock;static dispatch_once_t once;dispatch_once(&once,^{lock=NSObject.new;});return lock;}
static NSDictionary *AMDecisionCache;static NSString *AMDecisionDirectory;
NSDictionary *AMReviewDecisions(NSError **error){@synchronized(AMReviewDecisionLock()){
    NSString *directory=SSDataDirectory().path;if([directory isEqual:AMDecisionDirectory] && AMDecisionCache)return AMDecisionCache;
    NSURL *url=[SSDataDirectory() URLByAppendingPathComponent:@"review-decisions.plist"];
    NSDictionary *value=@{};
    if([NSFileManager.defaultManager fileExistsAtPath:url.path]){
        NSData *data=[NSData dataWithContentsOfURL:url options:0 error:error];if(!data)return nil;
        id decoded=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:error];
        if(![decoded isKindOfClass:NSDictionary.class]){if(error && !*error)*error=[NSError errorWithDomain:@"AMReview" code:1 userInfo:@{NSLocalizedDescriptionKey:@"无法读取已删除审核记录；原记录保留，请恢复文件后重试。"}];return nil;}
        for(id key in decoded){id entry=decoded[key];if(![key isKindOfClass:NSString.class] || ![entry isKindOfClass:NSDictionary.class] || ![entry[@"record"] isKindOfClass:NSDictionary.class]){if(error)*error=[NSError errorWithDomain:@"AMReview" code:2 userInfo:@{NSLocalizedDescriptionKey:@"已删除审核记录格式无效，原文件保留。请从本机备份恢复后重试。"}];return nil;}}
        value=decoded;
    }
    AMDecisionDirectory=directory;AMDecisionCache=value;return value;
}}
BOOL AMReviewIsDeleted(NSDictionary *record){return AMReviewDecisions(NULL)[AMReviewDecisionKey(record)]!=nil;}
BOOL AMReviewSetDeleted(NSArray *records,BOOL deleted,NSError **error){@synchronized(AMReviewDecisionLock()){
    NSDictionary *stored=AMReviewDecisions(error);if(!stored)return NO;NSMutableDictionary *next=stored.mutableCopy;
    for(NSDictionary *record in records){NSString *key=AMReviewDecisionKey(record);if(deleted){NSMutableDictionary *snapshot=record.mutableCopy;[snapshot removeObjectForKey:@"existingTask"];snapshot[@"reviewDeleted"]=@YES;next[key]=@{@"record":snapshot,@"date":NSDate.date};}else [next removeObjectForKey:key];}
    if(!SSWritePlist(@"review-decisions.plist",next,error))return NO;AMDecisionCache=next.copy;return YES;
}}
NSArray *AMReviewDeletedRecords(void){NSMutableArray *result=NSMutableArray.array;for(NSDictionary *entry in AMReviewDecisions(NULL).allValues)if([entry[@"record"] isKindOfClass:NSDictionary.class])[result addObject:entry[@"record"]];return result;}
