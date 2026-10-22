#import <spawn.h>
#import <poll.h>
#import <sys/wait.h>
// All pipes are nonblocking; an escaped descendant cannot hold a reader forever.
static SSGitResult *AMRunGitProcess(NSArray<NSString *> *arguments,NSDictionary *environment,NSString *path,NSData *input,NSTimeInterval budget,BOOL (^cancelled)(void),void (^launched)(pid_t),NSError **error){
    int out[2]={-1,-1},err[2]={-1,-1},in[2]={-1,-1};pid_t pid=0;int status=0;BOOL stopped=NO,expired=NO,reaped=NO,drainExpired=NO;
    if(pipe(out) || pipe(err) || pipe(in)){if(error)*error=[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];goto cleanup;}
    for(NSUInteger i=0;i<2;i++){fcntl(out[i],F_SETFD,FD_CLOEXEC);fcntl(err[i],F_SETFD,FD_CLOEXEC);fcntl(in[i],F_SETFD,FD_CLOEXEC);}
    {
        posix_spawn_file_actions_t actions;posix_spawnattr_t attributes;posix_spawn_file_actions_init(&actions);posix_spawnattr_init(&attributes);
        posix_spawnattr_setflags(&attributes,POSIX_SPAWN_SETPGROUP);posix_spawnattr_setpgroup(&attributes,0);
        if(path.length)posix_spawn_file_actions_addchdir_np(&actions,path.fileSystemRepresentation);
        posix_spawn_file_actions_adddup2(&actions,in[0],STDIN_FILENO);posix_spawn_file_actions_adddup2(&actions,out[1],STDOUT_FILENO);posix_spawn_file_actions_adddup2(&actions,err[1],STDERR_FILENO);
        for(NSUInteger i=0;i<2;i++){posix_spawn_file_actions_addclose(&actions,out[i]);posix_spawn_file_actions_addclose(&actions,err[i]);posix_spawn_file_actions_addclose(&actions,in[i]);}
        NSMutableArray *argvStrings=[NSMutableArray arrayWithObject:@"/usr/bin/git"];[argvStrings addObjectsFromArray:arguments];NSMutableArray *envStrings=NSMutableArray.array;for(NSString *key in environment)[envStrings addObject:[NSString stringWithFormat:@"%@=%@",key,environment[key]]];
        char **argv=calloc(argvStrings.count+1,sizeof(char *)),**envp=calloc(envStrings.count+1,sizeof(char *));for(NSUInteger i=0;i<argvStrings.count;i++)argv[i]=(char *)[argvStrings[i] UTF8String];for(NSUInteger i=0;i<envStrings.count;i++)envp[i]=(char *)[envStrings[i] UTF8String];
        int code=posix_spawn(&pid,"/usr/bin/git",&actions,&attributes,argv,envp);free(argv);free(envp);posix_spawn_file_actions_destroy(&actions);posix_spawnattr_destroy(&attributes);
        if(code){if(error)*error=AMWorkflowError(@"directory",@"无法打开课程文件夹",[NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil]);goto cleanup;}
    }
    close(out[1]);out[1]=-1;close(err[1]);err[1]=-1;close(in[0]);in[0]=-1;
    fcntl(out[0],F_SETFL,O_NONBLOCK);fcntl(err[0],F_SETFL,O_NONBLOCK);fcntl(in[1],F_SETFL,O_NONBLOCK);fcntl(in[1],F_SETNOSIGPIPE,1);
    if(launched)launched(pid);
    {
        NSMutableData *stdoutData=NSMutableData.data,*stderrData=NSMutableData.data;NSUInteger written=0;NSDate *start=NSDate.date,*ended=nil,*killed=nil;
        while(!reaped || out[0]>=0 || err[0]>=0){
            BOOL stop=cancelled && cancelled();BOOL timeout=-start.timeIntervalSinceNow>=budget;
            if((stop || timeout) && !stopped && !expired){stopped=stop;expired=timeout;killed=NSDate.date;kill(-pid,SIGKILL);}
            if(killed && !reaped && -killed.timeIntervalSinceNow>=2)break;
            if(!reaped){pid_t waited=waitpid(pid,&status,WNOHANG);if(waited==pid || (waited<0 && errno==ECHILD)){reaped=YES;ended=NSDate.date;}}
            if(reaped && -ended.timeIntervalSinceNow>=2){drainExpired=out[0]>=0 || err[0]>=0;kill(-pid,SIGKILL);break;}
            for(NSUInteger channel=0;channel<2;channel++){
                int *fd=channel==0 ? &out[0]:&err[0];if(*fd<0)continue;char buffer[65536];ssize_t count;
                NSUInteger chunks=0;while(chunks++<16 && (count=read(*fd,buffer,sizeof(buffer)))>0){[(channel==0 ? stdoutData:stderrData) appendBytes:buffer length:(NSUInteger)count];}
                if(count==0 || (count<0 && errno!=EAGAIN && errno!=EWOULDBLOCK && errno!=EINTR)){close(*fd);*fd=-1;}
            }
            if(in[1]>=0){if(written<input.length && !stopped && !expired){ssize_t count=write(in[1],(const char *)input.bytes+written,MIN((NSUInteger)65536,input.length-written));if(count>0)written+=(NSUInteger)count;else if(errno!=EAGAIN && errno!=EINTR){close(in[1]);in[1]=-1;}}
                if(in[1]>=0 && (written>=input.length || reaped || stopped || expired)){close(in[1]);in[1]=-1;}}
            if(!reaped || out[0]>=0 || err[0]>=0){struct pollfd fds[2]={{out[0],POLLIN,0},{err[0],POLLIN,0}};poll(fds,2,20);}
        }
        if(launched)launched(0);
        if(stopped || expired || drainExpired){if(error)*error=[NSError errorWithDomain:@"SSGit" code:stopped ? NSUserCancelledError:NSURLErrorTimedOut userInfo:@{NSLocalizedDescriptionKey:stopped ? @"当前步骤已停止":@"当前步骤超时",@"SSIssue":stopped ? @"cancelled":@"timeout",@"SSDetail":drainExpired ? @"子进程退出后输出未结束，已关闭读取通道":@"当前进程已停止；写入结果需按检查点核验"}];}
        else {SSGitResult *result=SSGitResult.new;result.status=WIFEXITED(status) ? WEXITSTATUS(status):128+WTERMSIG(status);result.data=stdoutData;result.diagnostic=SSRedactedText([[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding] ?: @"");for(NSUInteger i=0;i<2;i++){if(out[i]>=0)close(out[i]);if(err[i]>=0)close(err[i]);if(in[i]>=0)close(in[i]);}return result;}
    }
cleanup:
    if(pid>0 && !reaped){kill(-pid,SIGKILL);NSDate *until=[NSDate dateWithTimeIntervalSinceNow:2];while(until.timeIntervalSinceNow>0){pid_t waited=waitpid(pid,&status,WNOHANG);if(waited==pid || (waited<0 && errno==ECHILD)){reaped=YES;break;}struct pollfd ignored={-1,0,0};poll(&ignored,0,10);}if(!reaped){pid_t orphan=pid;dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{int ignoredStatus;while(waitpid(orphan,&ignoredStatus,0)<0 && errno==EINTR){};});}}if(launched)launched(0);
    for(NSUInteger i=0;i<2;i++){if(out[i]>=0)close(out[i]);if(err[i]>=0)close(err[i]);if(in[i]>=0)close(in[i]);}return nil;
}
