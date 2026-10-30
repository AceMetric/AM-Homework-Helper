// 只累计用户主动开启的计时。磁盘只保存已累计时长，启动时不会根据上次时间戳补算。
BOOL AMValidTimeEntries(id value) {
    if(![value isKindOfClass:NSArray.class] || [value count]>100000)return NO;
    NSMutableSet *ids=NSMutableSet.set;
    for(id row in value){
        if(![row isKindOfClass:NSDictionary.class] || ![row[@"id"] isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:row[@"id"]] || [ids containsObject:row[@"id"]] || ![row[@"taskID"] isKindOfClass:NSString.class] || ![row[@"taskID"] length] || ![row[@"date"] isKindOfClass:NSDate.class] || ![row[@"seconds"] isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)row[@"seconds"])==CFBooleanGetTypeID() || !isfinite([row[@"seconds"] doubleValue]) || [row[@"seconds"] doubleValue]<0 || [row[@"seconds"] doubleValue]>366*86400)return NO;
        for(NSString *key in row)if(![@[@"id",@"taskID",@"date",@"seconds",@"manual"] containsObject:key])return NO;
        if(row[@"manual"] && ![row[@"manual"] isKindOfClass:NSNumber.class])return NO;
        [ids addObject:row[@"id"]];
    }return YES;
}
NSArray *AMTimeEntries(NSError **error){
    id value=SSReadPlist(@"task-time.plist");
    if(!value && ![NSFileManager.defaultManager fileExistsAtPath:[SSDataDirectory() URLByAppendingPathComponent:@"task-time.plist"].path])return @[];
    if(AMValidTimeEntries(value))return value;
    if(error)*error=[NSError errorWithDomain:@"AMTaskTime" code:1 userInfo:@{NSLocalizedDescriptionKey:@"用时记录无法读取，原文件已保留"}];return nil;
}
BOOL AMSaveTimeEntries(NSArray *entries,NSError **error){
    @synchronized(NSFileManager.defaultManager){if(!AMTimeEntries(error))return NO;if(!AMValidTimeEntries(entries)){if(error)*error=[NSError errorWithDomain:@"AMTaskTime" code:6 userInfo:@{NSLocalizedDescriptionKey:@"用时记录格式或范围无效，未保存"}];return NO;}return SSWritePlist(@"task-time.plist",entries,error);}
}
@interface AMTimeTracker ()
@property(readwrite) NSString *taskID;
@property(readwrite) NSError *lastError;
@property NSString *entryID;
@property NSDate *startedAt;
@property NSTimeInterval lastTick;
@property NSTimeInterval accumulated;
@property BOOL frozen;
@property NSTimer *timer;
@end
@implementation AMTimeTracker
+ (instancetype)shared {static AMTimeTracker *tracker;static dispatch_once_t once;dispatch_once(&once,^{tracker=AMTimeTracker.new;});return tracker;}
- (instancetype)init {if((self=[super init])){
    // 系统睡眠由 AppKit 层转发，存储模块保持只依赖 Foundation，便于独立测试和恢复工具使用。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(suspend:) name:@"AMSystemWillSleep" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(suspend:) name:@"NSApplicationWillTerminateNotification" object:nil];
    __weak typeof(self) weak=self;self.timer=[NSTimer scheduledTimerWithTimeInterval:5 repeats:YES block:^(NSTimer *timer){(void)timer;AMTimeTracker *owner=weak;if(owner.taskID){[owner tasksChanged:SSReadPlist(@"tasks.plist") ?: @[]];[owner checkpoint:NULL];}}];[NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}return self;}
- (void)suspend:(NSNotification *)note {[self pause:NULL];}
- (BOOL)running {return self.taskID.length>0 && !self.frozen;}
- (void)tasksChanged:(NSArray *)tasks {if(!self.taskID)return;BOOL valid=NO;if([tasks isKindOfClass:NSArray.class])for(id task in tasks)if([task isKindOfClass:NSDictionary.class] && [task[@"id"] isEqual:self.taskID] && ![task[@"completed"] boolValue] && ![task[@"deleted"] boolValue] && ![task[@"archived"] boolValue])valid=YES;if(!valid)[self pause:NULL];}
- (BOOL)startTask:(NSString *)identifier error:(NSError **)error {
    if(!NSThread.isMainThread){if(error)*error=[NSError errorWithDomain:@"AMTaskTime" code:5 userInfo:@{NSLocalizedDescriptionKey:@"计时状态必须在主线程更新"}];return NO;}
    if(!identifier.length)return NO;if([identifier isEqual:self.taskID])return YES;
    if(![self pause:error])return NO;
    NSArray *tasks=SSReadPlist(@"tasks.plist");BOOL valid=NO;if([tasks isKindOfClass:NSArray.class])for(id task in tasks)if([task isKindOfClass:NSDictionary.class] && [task[@"id"] isEqual:identifier] && ![task[@"completed"] boolValue] && ![task[@"deleted"] boolValue] && ![task[@"archived"] boolValue])valid=YES;
    if(!valid){if(error)*error=[NSError errorWithDomain:@"AMTaskTime" code:2 userInfo:@{NSLocalizedDescriptionKey:@"只有未完成的现有任务可以开始计时"}];return NO;}
    if(!AMTimeEntries(error))return NO;self.taskID=identifier;self.entryID=NSUUID.UUID.UUIDString;self.startedAt=NSDate.date;self.lastTick=NSProcessInfo.processInfo.systemUptime;self.accumulated=0;self.frozen=NO;return [self checkpoint:error];
}
- (BOOL)checkpoint:(NSError **)error {
    // 用单调时钟计算本段增量；保存失败后冻结计时，避免把睡眠或等待修复的时间算进去。
    if(!self.taskID)return YES;NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;if(!self.frozen)self.accumulated+=MAX(0,now-self.lastTick);self.lastTick=now;
    @synchronized(NSFileManager.defaultManager){NSError *failure=nil;NSArray *stored=AMTimeEntries(&failure);NSMutableArray *next=stored.mutableCopy;
        if(next){NSUInteger index=[next indexOfObjectPassingTest:^BOOL(NSDictionary *entry,NSUInteger i,BOOL *stop){(void)i;(void)stop;return [entry[@"id"] isEqual:self.entryID];}];NSDictionary *entry=@{@"id":self.entryID,@"taskID":self.taskID,@"date":self.startedAt,@"seconds":@(self.accumulated),@"manual":@NO};if(index==NSNotFound)[next addObject:entry];else next[index]=entry;if(!AMSaveTimeEntries(next,&failure))next=nil;}
        self.lastError=failure;if(!next){self.frozen=YES;if(error)*error=failure;[NSNotificationCenter.defaultCenter postNotificationName:@"AMTaskTimeChanged" object:self];return NO;}
    }[NSNotificationCenter.defaultCenter postNotificationName:@"AMTaskTimeChanged" object:self];return YES;
}
// 写入失败时保留 entryID 和内存增量，重试只能更新原记录，不能再生成一份计时。
- (BOOL)pause:(NSError **)error {BOOL saved=[self checkpoint:error];self.frozen=YES;if(!saved)return NO;self.taskID=nil;self.entryID=nil;self.accumulated=0;[NSNotificationCenter.defaultCenter postNotificationName:@"AMTaskTimeChanged" object:self];return YES;}
- (NSTimeInterval)secondsForTask:(NSString *)identifier {NSTimeInterval seconds=0;for(NSDictionary *entry in AMTimeEntries(NULL))if([entry[@"taskID"] isEqual:identifier] && ![entry[@"id"] isEqual:self.entryID])seconds+=[entry[@"seconds"] doubleValue];if([self.taskID isEqual:identifier])seconds+=self.accumulated+(self.frozen ? 0:MAX(0,NSProcessInfo.processInfo.systemUptime-self.lastTick));return seconds;}
@end
