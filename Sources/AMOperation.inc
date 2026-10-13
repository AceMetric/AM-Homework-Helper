NSNotificationName const AMOperationsChanged=@"AMOperationsChanged";
static NSMutableDictionary *AMOperationRows,*AMOperationCancels;
static NSObject *AMOperationLock(void){static NSObject *lock;static dispatch_once_t once;dispatch_once(&once,^{lock=NSObject.new;AMOperationRows=NSMutableDictionary.dictionary;AMOperationCancels=NSMutableDictionary.dictionary;});return lock;}
static void AMOperationNotify(void){dispatch_async(dispatch_get_main_queue(),^{[NSNotificationCenter.defaultCenter postNotificationName:AMOperationsChanged object:nil];});}
NSString *AMOperationBegin(NSString *kind,NSString *target,BOOL cancellable,void (^cancel)(void)){
    NSString *key=NSUUID.UUID.UUIDString;@synchronized(AMOperationLock()){
        AMOperationRows[key]=[@{@"id":key,@"kind":kind,@"target":target ?: @"",@"stage":kind,@"started":NSDate.date,@"state":@"running",@"completed":@0,@"total":@0,@"cancellable":@(cancellable)} mutableCopy];
        if(cancel && cancellable)AMOperationCancels[key]=[cancel copy];
        if(AMOperationRows.count>40){NSArray *sorted=[AMOperationRows.allValues sortedArrayUsingComparator:^NSComparisonResult(id a,id b){return [a[@"started"] compare:b[@"started"]];}];for(NSDictionary *row in sorted)if(AMOperationRows.count>40 && ![row[@"state"] isEqual:@"running"])[AMOperationRows removeObjectForKey:row[@"id"]];}
    }AMOperationNotify();return key;
}
void AMOperationProgress(NSString *identifier,NSString *stage,NSInteger completed,NSInteger total){if(!identifier)return;@synchronized(AMOperationLock()){NSMutableDictionary *row=AMOperationRows[identifier];if(![row[@"state"] isEqual:@"running"])return;row[@"stage"]=stage ?: @"";row[@"completed"]=@(MAX(0,completed));row[@"total"]=@(MAX(0,total));}AMOperationNotify();}
void AMOperationFinish(NSString *identifier,NSString *state,NSString *message){if(!identifier)return;@synchronized(AMOperationLock()){NSMutableDictionary *row=AMOperationRows[identifier];if(!row || ![row[@"state"] isEqual:@"running"])return;row[@"state"]=state;row[@"stage"]=message ?: @"";row[@"finished"]=NSDate.date;row[@"cancellable"]=@NO;[AMOperationCancels removeObjectForKey:identifier];}AMOperationNotify();}
void AMOperationCancel(NSString *identifier){void (^cancel)(void);@synchronized(AMOperationLock()){cancel=AMOperationCancels[identifier];if(cancel){[AMOperationCancels removeObjectForKey:identifier];AMOperationRows[identifier][@"cancellable"]=@NO;AMOperationRows[identifier][@"stage"]=@"正在安全取消…";}}if(cancel)cancel();AMOperationNotify();}
NSArray *AMOperations(void){@synchronized(AMOperationLock()){NSMutableArray *rows=NSMutableArray.array;for(NSDictionary *row in AMOperationRows.allValues)[rows addObject:row.copy];return [rows sortedArrayUsingComparator:^NSComparisonResult(id a,id b){return [b[@"started"] compare:a[@"started"]];}];}}
