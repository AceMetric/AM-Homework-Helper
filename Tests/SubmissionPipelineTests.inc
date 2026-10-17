@interface InterruptedGit:FixtureGit
@property NSString *pauseAt;
@property dispatch_semaphore_t entered;
@end
@implementation InterruptedGit
- (SSGitResult *)run:(NSArray *)args in:(NSString *)path token:(NSString *)token error:(NSError **)error {
    BOOL pause=self.pauseAt && [args containsObject:self.pauseAt];
    if(pause){
        if([self.pauseAt isEqual:@"commit"]){SSGitResult *written=[super run:args in:path token:token error:error];if(!written || written.status)return written;}
        self.pauseAt=nil;dispatch_semaphore_signal(self.entered);
        return [super run:@[@"-c",@"alias.am-test-wait=!trap '' TERM; sleep 20 & wait",@"am-test-wait"] in:path token:nil error:error];
    }return [super run:args in:path token:token error:error];
}
@end
static void PipelineAssertions(void){
    NSMutableDictionary *fixture=Fixture();NSString *root=fixture[@"path"];FixtureGit *batch=Service(fixture);NSError *error=nil;
    Check([NSFileManager.defaultManager createDirectoryAtPath:[root stringByAppendingPathComponent:@"assignment-01/代码"] withIntermediateDirectories:YES attributes:nil error:NULL],@"create nested synthetic history");
    for(NSUInteger i=0;i<30;i++)Write([root stringByAppendingPathComponent:[NSString stringWithFormat:@"assignment-01/代码/文件-%lu.md",(unsigned long)i]],@"A complete synthetic answer\n");
    Git(root,@[@"add",@"."]);Git(root,@[@"commit",@"-m",@"Synthetic batch"]);
    Check([batch checkObjects:@"origin/main..HEAD" path:root error:&error],@"all outgoing objects and Unicode tree names pass batch inspection");
    Check([batch.commandCounts[@"cat-file"] unsignedIntegerValue]==2,@"history inspection needs two cat-file processes regardless of object count");
    SSGit *deadline=SSGit.new;deadline.commandTimeout=.2;NSDate *start=NSDate.date;
    Check(![deadline run:@[@"-c",@"alias.am-test-wait=!trap '' TERM; sleep 20 & wait",@"am-test-wait"] in:root token:nil error:&error] && error.code==NSURLErrorTimedOut && -start.timeIntervalSinceNow<5,@"timeout terminates owned Git and helper processes even while pipes are open");
    deadline.commandTimeout=10;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,150*NSEC_PER_MSEC),dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{[deadline cancelCurrentOperation];});start=NSDate.date;
    Check(![deadline run:@[@"-c",@"alias.am-test-wait=!trap '' TERM; sleep 20 & wait",@"am-test-wait"] in:root token:nil error:&error] && error.code==NSUserCancelledError && -start.timeIntervalSinceNow<5,@"force stop cancels an in-flight command without waiting for its normal deadline");
    Check(![deadline run:@[@"rev-parse",@"HEAD"] in:root token:nil error:&error],@"cancelled operation cannot start another Git step");
    deadline.operationCancelled=NO;Check([deadline run:@[@"rev-parse",@"HEAD"] in:root token:nil error:&error]!=nil,@"a new explicitly started operation can read normally");
    Cleanup(fixture);
    for(NSString *stage in @[@"commit",@"push",@"commit-with-staged"]){
        fixture=Fixture();root=fixture[@"path"];InterruptedGit *git=InterruptedGit.new;git.fixture=fixture;git.pauseAt=[stage hasPrefix:@"commit"] ? @"commit":stage;git.entered=dispatch_semaphore_create(0);
        Write([root stringByAppendingPathComponent:@"answer.md"],@"Keep this synthetic answer intact\n");NSString *teacher=Git(fixture[@"teacherBare"],@[@"rev-parse",@"main"]);
        __block NSDate *stopStarted=nil;NSObject *timing=NSObject.new;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{if(!dispatch_semaphore_wait(git.entered,dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC))){[NSThread sleepForTimeInterval:.15];@synchronized(timing){stopStarted=NSDate.date;}[git cancelCurrentOperation];}});
        NSDictionary *record=[git performRecordedCourse:fixture kind:@"submission" taskIDs:@[] paths:@[@"answer.md"] message:@"Interrupted synthetic submission" token:@"test" login:@"student" userID:@42 error:&error];NSString *commit=Git(root,@[@"rev-parse",@"HEAD"]);
        NSTimeInterval stopElapsed;@synchronized(timing){stopElapsed=stopStarted ? -stopStarted.timeIntervalSinceNow:HUGE_VAL;}
        if(![record[@"state"] isEqual:@"uncertain"] || stopElapsed>=5)fprintf(stderr,"Interrupted stage=%s state=%s stop=%.3fs error=%s\n",stage.UTF8String,[record[@"state"] UTF8String],stopElapsed,error.localizedDescription.UTF8String);
        Check([record[@"state"] isEqual:@"uncertain"] && stopElapsed<5,@"interrupted commit or push retains an uncertain journal and ends within five seconds after force stop");
        Check([[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"answer.md"] encoding:NSUTF8StringEncoding error:NULL] containsString:@"intact"],@"force stop preserves the working file");
        BOOL foreignStaged=[stage isEqual:@"commit-with-staged"];if(foreignStaged){Write([root stringByAppendingPathComponent:@"foreign.md"],@"Separate staged work\n");Git(root,@[@"add",@"foreign.md"]);}
        git.operationCancelled=NO;NSDictionary *resolved=[git verifySubmission:record course:fixture token:@"test" retry:NO error:&error];
        Check([resolved[@"commit"] isEqual:commit] && [resolved[@"state"] isEqual:@"local"],@"verification recovers the exact already-created commit after interruption");
        Check(foreignStaged ? [Git(root,@[@"diff",@"--cached",@"--name-only"]) containsString:@"foreign.md"]:!Git(root,@[@"diff",@"--cached",@"--name-only"]).length,@"recovery reconciles the original index and preserves foreign staged files");
        resolved=[git verifySubmission:resolved course:fixture token:@"test" retry:YES error:&error];
        Check([resolved[@"state"] isEqual:@"confirmed"] && [Git(root,@[@"rev-parse",@"HEAD"]) isEqual:commit],@"retry pushes and verifies the same commit without recreating it");
        Check([Git(fixture[@"teacherBare"],@[@"rev-parse",@"main"]) isEqual:teacher],@"interruption recovery never changes the teacher repository");
        Cleanup(fixture);
    }
}
