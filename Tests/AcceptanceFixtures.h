#import <Foundation/Foundation.h>
// Launch Services does not promise the repository as the working directory.
// Check resource existence and shape before JSON parsing; nil NSData throws.
static inline NSArray *AMAcceptanceCases(NSURL *url,NSUInteger expected,NSError **error){
    NSData *data=url ? [NSData dataWithContentsOfURL:url options:0 error:error]:nil;
    id cases=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:error]:nil;
    BOOL valid=[cases isKindOfClass:NSArray.class] && [cases count]==expected;
    if(valid)for(id item in cases)if(![item isKindOfClass:NSDictionary.class] || ![item[@"id"] isKindOfClass:NSString.class] || ![item[@"teacher"] isKindOfClass:NSString.class]){valid=NO;break;}
    if(!valid){if(error && !*error)*error=[NSError errorWithDomain:@"AMAcceptance" code:1 userInfo:@{NSLocalizedDescriptionKey:@"合成样例缺失或格式不正确，未发送模型请求。"}];return nil;}
    return cases;
}
