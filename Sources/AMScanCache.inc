// Sessions merge only their own changes, so independent background jobs cannot
// replace a newer result with an older copy of the shared cache.
static NSObject *AMScanCacheLock(void){static NSObject *lock;static dispatch_once_t once;dispatch_once(&once,^{lock=NSObject.new;});return lock;}
static NSMapTable *AMScanCacheBases(void){static NSMapTable *bases;static dispatch_once_t once;dispatch_once(&once,^{bases=[[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsStrongMemory capacity:0];});return bases;}
static NSDictionary *AMReadScanCache(NSError **error){
    NSURL *url=[SSDataDirectory() URLByAppendingPathComponent:@"scan-cache.plist"];
    if(![NSFileManager.defaultManager fileExistsAtPath:url.path])return @{};
    NSData *data=[NSData dataWithContentsOfURL:url options:0 error:error];if(!data)return nil;
    id value=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:error];
    if(![value isKindOfClass:NSDictionary.class]){if(error && !*error)*error=[NSError errorWithDomain:@"AMScanCache" code:1 userInfo:@{NSLocalizedDescriptionKey:@"本机检查记录无法读取，已保留原文件。请恢复检查记录后重试，或主动重新分析材料。"}];return nil;}return value;
}
NSMutableDictionary *AMScanCacheLoad(NSError **error){@synchronized(AMScanCacheLock()){
    NSDictionary *disk=AMReadScanCache(error);if(!disk)return nil;NSMutableDictionary *cache=disk.mutableCopy;[AMScanCacheBases() setObject:disk forKey:cache];return cache;
}}
BOOL AMScanCacheSave(NSMutableDictionary *cache,NSError **error){@synchronized(AMScanCacheLock()){
    NSDictionary *disk=AMReadScanCache(error);if(!disk)return NO;NSDictionary *base=[AMScanCacheBases() objectForKey:cache] ?: @{};
    NSMutableDictionary *merged=disk.mutableCopy;BOOL changed=NO;
    for(NSString *key in cache)if(![cache[key] isEqual:base[key]]){merged[key]=cache[key];changed=YES;}
    for(NSString *key in base)if(!cache[key]){[merged removeObjectForKey:key];changed=YES;}
    if(changed && !SSWritePlist(@"scan-cache.plist",merged,error))return NO;
    [AMScanCacheBases() setObject:cache.copy forKey:cache];return YES;
}}
