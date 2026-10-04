#import <Cocoa/Cocoa.h>
#import "../Sources/SSGit.m"
#import "../Sources/SSGitHub.m"
#import "../Sources/DDLCore.h"

static NSUInteger assertions = 0;
static void Check(BOOL condition, NSString *label) { assertions++; if (!condition) { fprintf(stderr, "FAIL: %s\n", label.UTF8String); exit(1); } }
static NSString *Git(NSString *path, NSArray *args) {
    NSTask *task = NSTask.new; task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/git"];
    task.arguments = [@[@"-c", @"commit.gpgSign=false", @"-c", @"core.hooksPath=/dev/null"] arrayByAddingObjectsFromArray:args];
    task.currentDirectoryURL = [NSURL fileURLWithPath:path];
    NSMutableDictionary *env = NSProcessInfo.processInfo.environment.mutableCopy;
    env[@"GIT_CONFIG_GLOBAL"] = @"/dev/null"; env[@"GIT_CONFIG_NOSYSTEM"] = @"1"; task.environment = env;
    NSPipe *pipe = NSPipe.pipe; task.standardOutput = pipe; task.standardError = pipe;
    NSError *error = nil; Check([task launchAndReturnError:&error], @"launch fixture git");
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile]; [task waitUntilExit];
    NSString *value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    Check(task.terminationStatus == 0, [NSString stringWithFormat:@"fixture %@: %@", args.firstObject, value]);
    return Trim(value);
}
static void Write(NSString *path, NSString *value) { Check([value writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"write fixture"); }
static NSMutableDictionary *Fixture(void) {
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"ss-homework-test-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    Check([NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL], @"create fixture");
    NSString *seed = [root stringByAppendingPathComponent:@"seed"], *teacher = [root stringByAppendingPathComponent:@"teacher.git"], *fork = [root stringByAppendingPathComponent:@"fork.git"], *local = [root stringByAppendingPathComponent:@"local"];
    Git(root, @[@"init", @"-b", @"main", seed]);
    Git(seed, @[@"config", @"user.name", @"Teacher"]); Git(seed, @[@"config", @"user.email", @"teacher@example.invalid"]);
    Write([seed stringByAppendingPathComponent:@"README.md"], @"# Homework 1\nDue: 2026-10-08 23:59\n");
    Write([seed stringByAppendingPathComponent:@"shared.txt"], @"base\n");
    Git(seed, @[@"add", @"."]); Git(seed, @[@"commit", @"-m", @"initial"]);
    Git(root, @[@"clone", @"--bare", seed, teacher]); Git(root, @[@"clone", @"--bare", teacher, fork]); Git(root, @[@"clone", fork, local]);
    Git(local, @[@"remote", @"set-url", @"origin", @"https://github.com/student/course.git"]);
    Git(local, @[@"remote", @"add", @"upstream", @"git@github.com:teacher/course.git"]);
    Git(local, @[@"config", @"user.name", @"Local User"]); Git(local, @[@"config", @"user.email", @"private@example.invalid"]);
    return [@{@"path":local, @"fork":@"student/course", @"upstream":@"teacher/course", @"branch":@"main", @"upstreamBranch":@"main", @"forkID":@12, @"upstreamID":@11, @"ownerID":@42, @"timeZone":@"Asia/Shanghai", @"root":root, @"teacherBare":teacher, @"forkBare":fork, @"seed":seed} mutableCopy];
}
@interface FixtureGit : SSGit
@property NSDictionary *fixture;
@property BOOL denyTeacher;
@property BOOL rejectPush;
@property BOOL wrongAccount;
@property NSMutableArray *pushTargets;
@end
@implementation FixtureGit
- (instancetype)init {
    if ((self = [super init])) {
        self.pushTargets = NSMutableArray.array;
        __weak typeof(self) weakSelf = self;
        self.identityVerifier = ^NSDictionary *(NSDictionary *course, NSError **error) { return @{@"login":@"student", @"id":weakSelf.wrongAccount ? @99 : @42}; };
    } return self;
}
- (SSGitResult *)run:(NSArray *)args in:(NSString *)path token:(NSString *)token error:(NSError **)error {
    NSMutableArray *mapped = args.mutableCopy;
    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i], *repo = SSCanonicalRepository(arg);
        if (!repo) continue;
        if ([repo isEqual:@"teacher/course"]) {
            Check(!token.length, @"teacher read never receives application token");
            if (self.denyTeacher) { SSGitResult *r = SSGitResult.new; r.status = 128; r.data = NSData.data; r.diagnostic = @"private upstream access denied"; return r; }
            mapped[i] = [@"file://" stringByAppendingString:self.fixture[@"teacherBare"]];
        } else if ([repo isEqual:@"student/course"]) mapped[i] = [@"file://" stringByAppendingString:self.fixture[@"forkBare"]];
        else Check(NO, @"unexpected repository target");
        if ([args containsObject:@"push"]) { [self.pushTargets addObject:repo]; Check([repo isEqual:@"student/course"], @"push target must be own fork"); }
    }
    if (self.rejectPush && [args containsObject:@"push"]) { SSGitResult *r = SSGitResult.new; r.status = 1; r.data = NSData.data; r.diagnostic = @"push rejected"; return r; }
    return [super run:mapped in:path token:nil error:error];
}
@end
static FixtureGit *Service(NSDictionary *fixture) { FixtureGit *git = FixtureGit.new; git.fixture = fixture; return git; }
static void Cleanup(NSDictionary *fixture) { [NSFileManager.defaultManager removeItemAtPath:fixture[@"root"] error:NULL]; }

@interface FixtureAPI : SSGitHub
@property NSDictionary *credentials;
@property NSDictionary *responses;
@property NSMutableArray *forms;
@property NSMutableArray *intervals;
@property NSUInteger tokenStep;
@end
@implementation FixtureAPI
- (instancetype)init { if ((self = [super init])) { self.clientID = @"Iv1publicClient"; self.forms = NSMutableArray.array; self.intervals = NSMutableArray.array; } return self; }
- (NSDictionary *)loadCredentials { return self.credentials; }
- (BOOL)storeCredentials:(NSDictionary *)value { self.credentials = value; return YES; }
- (BOOL)waitForPollingInterval:(NSTimeInterval)interval { [self.intervals addObject:@(interval)]; return !self.loginCancelled; }
- (id)requestURL:(NSURL *)url form:(NSDictionary *)form token:(NSString *)token error:(NSError **)error {
    if (form) { [self.forms addObject:form]; Check(!form[@"client_secret"], @"device flow and refresh never include client secret"); }
    if ([url.path isEqual:@"/login/device/code"]) return @{@"device_code":@"device", @"user_code":@"ABCD-EFGH", @"expires_in":@900, @"interval":@5};
    if ([url.path isEqual:@"/login/oauth/access_token"]) {
        if ([form[@"grant_type"] isEqual:@"refresh_token"]) return @{@"access_token":@"new-access", @"refresh_token":@"new-refresh", @"expires_in":@28800};
        self.tokenStep++;
        if (self.tokenStep == 1) return @{@"error":@"authorization_pending"};
        if (self.tokenStep == 2) return @{@"error":@"slow_down", @"interval":@10};
        return @{@"access_token":@"test-access", @"refresh_token":@"test-refresh", @"expires_in":@28800};
    }
    NSString *key = [url.path stringByAppendingFormat:@"%@%@", url.query.length ? @"?" : @"", url.query ?: @""];
    id result = self.responses[key]; if (!result && error) *error = GHError(@"simulated API failure"); return result;
}
@end

static void ParserTests(void) {
    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]; cal.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    NSDate *now = DDLParseDate(@"2026-10-04 12:00", NSDate.date, cal);
    NSArray *items = SSAssignmentsFromDocument(@"# Homework 1\nDue: 2026-10-08 23:59\n# Homework 2\nDeadline: 2026-10-10\n# 实验三\n截止：10月12日 20:00\n", @"teacher/course", @"README.md", @"v1", now, cal);
    Check(items.count == 3, @"multiple assignments per document");
    Check([items[0][@"title"] isEqual:@"Homework 1"], @"heading gives task title");
    Check(![items[0][@"needsTime"] boolValue], @"explicit deadline time");
    Check([items[1][@"needsTime"] boolValue], @"date-only requires time confirmation");
    Check([items[2][@"needsDate"] boolValue], @"missing year requires date confirmation");
    NSArray *updated = SSAssignmentsFromDocument(@"# Homework 1\nDue: 2026-10-09 23:59\n", @"teacher/course", @"README.md", @"v2", now, cal);
    Check([items[0][@"id"] isEqual:updated[0][@"id"]], @"DDL change retains identity");
    Check(![items[0][@"due"] isEqual:updated[0][@"due"]], @"DDL change is observed");
    Check(SSAssignmentsFromDocument(@"# Homework\nPublished: 2026-10-01\n```\nDue: 2026-10-05 20:00\n```\n", @"t/r", @"README.md", @"v", now, cal).count == 0, @"publication date and code fences are ignored");
    Check(SSAssignmentsFromDocument(@"# 作业\n截止：2026-02-30 20:00", @"t/r", @"README.md", @"v", now, cal).count == 0, @"invalid date ignored");
    NSArray *tba = SSAssignmentsFromDocument(@"# Homework\nDeadline: TBD", @"t/r", @"README.md", @"v", now, cal);
    Check(tba.count == 1 && !tba[0][@"due"] && [tba[0][@"needsDate"] boolValue], @"TBD deadline requires manual date");
    NSArray *relative = SSAssignmentsFromDocument(@"# 实验\n明天20:00前提交", @"t/r", @"README.md", @"v", now, cal);
    Check(relative.count == 1 && [relative[0][@"needsDate"] boolValue], @"relative date requires confirmation");
    Check(SSIsSupportedDocument(@"README") && SSIsSupportedDocument(@"a.md") && !SSIsSupportedDocument(@"README.pdf") && !SSIsSupportedDocument(@"answer.py"), @"document coverage excludes binary and code");
    NSArray *iso = SSAssignmentsFromDocument(@"# Homework\nDue: 2026-10-08T15:59Z", @"t/r", @"a.md", @"v", now, cal);
    Check(iso.count == 1 && [iso[0][@"due"] isEqual:DDLParseDate(@"2026-10-08 23:59", now, cal)], @"ISO timezone respected");
    NSString *rules = @"# 规则\n\n- 截止时间：本周日 21:00\n- 提交单个 Markdown 文件，命名格式：assignment-04.md。\n\n# 任务\n\n## 1.\n解答：为什么数值求解时，时间步长较大更容易发散？\n## 2.\n完成附件作业：1. 运动学基础 和 2. 牛顿定律作业\n";
    NSArray *weekly = SSAssignmentsFromDocument(rules, @"teacher/course", @"assignment-04.md", @"v1", now, cal);
    Check(weekly.count == 1, @"rules section with this Sunday deadline is discovered");
    Check([weekly[0][@"title"] isEqual:@"assignment-04"], @"generic rules/task headings fall back to assignment filename");
    Check([weekly[0][@"deadlineText"] isEqual:@"本周日 21:00"] && [weekly[0][@"needsDate"] boolValue] && ![weekly[0][@"needsTime"] boolValue], @"weekday wording and explicit time retained for review");
    Check(!weekly[0][@"due"], @"teacher's relative date is never anchored to the scan day");
    Check([weekly[0][@"snippet"] containsString:@"牛顿定律作业"], @"review snippet contains following tasks and attachment instructions");
    Check([weekly[0][@"line"] integerValue] == 3, @"deadline source line remains accurate");
    NSArray *later = SSAssignmentsFromDocument(rules, @"teacher/course", @"assignment-04.md", @"v1", [now dateByAddingTimeInterval:14 * 86400], cal);
    Check([weekly isEqual:later], @"old relative deadline is stable across later weeks");
    for (NSString *day in @[@"本周日", @"本周天", @"这周日", @"周日", @"星期天", @"下周一", @"下星期五", @"礼拜天", @"下礼拜日", @"本周末", @"一周后", @"3天后"]) {
        NSString *document = [NSString stringWithFormat:@"# 物理作业四\n## 规则\n- **截止时间**：%@ 21：00\n## 任务\n完成附件习题。", day];
        NSArray *found = SSAssignmentsFromDocument(document, @"t/r", @"README.md", @"v", now, cal);
        Check(found.count == 1 && [found[0][@"title"] isEqual:@"物理作业四"] && [found[0][@"needsDate"] boolValue] && ![found[0][@"needsTime"] boolValue] && !found[0][@"due"], [@"relative weekday variant: " stringByAppendingString:day]);
    }
    NSArray *split = SSAssignmentsFromDocument(@"# 作业四\n截止时间：\n本周日 21:00\n", @"t/r", @"a.md", @"v", now, cal);
    Check(split.count == 1 && [split[0][@"title"] isEqual:@"作业四"], @"deadline can be on the following line");
    NSArray *noTime = SSAssignmentsFromDocument(@"# 作业四\n截止：本周日", @"t/r", @"a.md", @"v", now, cal);
    Check(noTime.count == 1 && [noTime[0][@"needsTime"] boolValue], @"relative date without time requires both date and time");
    Check(SSAssignmentsFromDocument(@"# 作业四\n发布：本周日 21:00\n```\n截止：星期天 21:00\n```", @"t/r", @"a.md", @"v", now, cal).count == 0, @"relative publication dates and fenced examples remain ignored");
    NSArray *renamed = SSAssignmentsFromDocument([rules stringByReplacingOccurrencesOfString:@"本周日" withString:@"下周日"], @"teacher/course", @"assignment-04.md", @"v2", now, cal);
    Check([weekly[0][@"id"] isEqual:renamed[0][@"id"]], @"relative deadline edits retain assignment identity");
}
static void SecurityTests(void) {
    Check([SSCanonicalRepository(@"git@github.com:Student/Course.git") isEqual:@"student/course"], @"canonical SSH URL");
    Check(!SSCanonicalRepository(@"https://github.com.evil.invalid/student/course") && !SSCanonicalRepository([@"https://token@" stringByAppendingString:@"github.com/student/course.git"]) && !SSCanonicalRepository(@"ext::cmd"), @"reject credentials and unsupported transports");
    Check(SSValidBranch(@"main") && SSValidBranch(@"course/main") && !SSValidBranch(@"--all") && !SSValidBranch(@"../main"), @"safe branches");
    Check(SSSensitivePath(@".env.local") && SSSensitivePath(@".aws/credentials") && SSSensitivePath(@"answer.zip") && !SSSensitivePath(@"answer.md"), @"sensitive files and archives blocked");
    NSString *fake = [[@"gh" stringByAppendingString:@"p_"] stringByAppendingString:[@"A" stringByPaddingToLength:40 withString:@"A" startingAtIndex:0]];
    Check(SSContainsSecret([fake dataUsingEncoding:NSUTF8StringEncoding]), @"detect token");
    NSMutableData *binary = [NSMutableData dataWithBytes:"\xff\x00" length:2]; [binary appendData:[fake dataUsingEncoding:NSUTF8StringEncoding]];
    Check(SSContainsSecret(binary), @"binary prefix cannot hide ASCII token");
    Check(![SSRedactedText(fake) containsString:fake], @"token redaction");
    Check(![SSRedactedText([@"https://private-user:" stringByAppendingString:[@"private-pass@" stringByAppendingString:@"github.com/a/b"]]) containsString:@"private-pass"], @"URL credentials redacted");
}
static void APITests(void) {
    FixtureAPI *api = FixtureAPI.new; NSError *error = nil;
    NSDictionary *challenge = [api beginDeviceLogin:&error]; Check(challenge != nil, @"begin device flow");
    Check([api completeDeviceLogin:challenge error:&error], @"device polling completes");
    Check(api.intervals.count == 3 && [api.intervals[2] integerValue] >= 10, @"slow_down polling interval respected");
    Check([api.credentials[@"refresh_token"] isEqual:@"test-refresh"], @"refresh token persisted via secret store");
    api.credentials = @{@"access_token":@"expired", @"refresh_token":@"refresh", @"client_id":api.clientID, @"expires_at":[NSDate dateWithTimeIntervalSinceNow:-60]};
    Check([[api accessToken:&error] isEqual:@"new-access"], @"expired access token refreshed");
    api.responses = @{@"/user":@{@"login":@"student", @"id":@42}, @"/repos/student/course":@{@"fork":@YES, @"id":@12, @"full_name":@"student/course", @"owner":@{@"id":@42}, @"parent":@{@"id":@11, @"full_name":@"teacher/course"}}};
    NSDictionary *course = @{@"fork":@"student/course", @"upstream":@"teacher/course", @"forkID":@12, @"upstreamID":@11, @"ownerID":@42};
    Check([api verifyCourse:course error:&error] != nil, @"verify fork owner and parent IDs");
    NSMutableDictionary *wrong = course.mutableCopy; wrong[@"ownerID"] = @99;
    Check([api verifyCourse:wrong error:&error] == nil, @"wrong account rejected");
    wrong = course.mutableCopy; wrong[@"upstreamID"] = @999;
    Check([api verifyCourse:wrong error:&error] == nil, @"wrong parent rejected");
    [api beginDeviceLogin:&error]; [api cancelDeviceLogin]; Check(![api completeDeviceLogin:challenge error:&error], @"device login cancellable");
}
static void GitTests(void) {
    NSError *error = nil;
    NSMutableDictionary *f = Fixture(); FixtureGit *service = Service(f); NSString *path = f[@"path"];
    NSString *teacherBefore = Git(f[@"teacherBare"], @[@"rev-parse", @"main"]);
    Check([service validateCourse:f error:&error], @"validate course remotes");
    Check([service linkCourse:f error:&error], @"link verifies teacher access");
    NSMutableDictionary *cache = NSMutableDictionary.dictionary;
    NSString *oldKey = [NSString stringWithFormat:@"v2|teacher/course|README.md|%@|Asia/Shanghai", Git(f[@"seed"], @[@"rev-parse", @"HEAD:README.md"])];
    cache[oldKey] = @[];
    NSDictionary *scan = [service scanCourse:f cache:cache error:&error]; Check([scan[@"candidates"] count] == 1, @"scan teacher main");
    NSString *newKey = [@"v3" stringByAppendingString:[oldKey substringFromIndex:2]];
    Check([cache[newKey] count] == 1 && [cache[oldKey] count] == 0, @"new parser does not reuse empty results cached by older parser");
    NSUInteger cacheCount = cache.count;
    Check([[service scanCourse:f cache:cache error:&error][@"candidates"] firstObject] != nil && cache.count == cacheCount, @"scan cache reuse");
    service.denyTeacher = YES; Check(![service scanCourse:f cache:cache error:&error], @"private upstream denied fails safely"); service.denyTeacher = NO;
    Write([path stringByAppendingPathComponent:@"answer one.txt"], @"my homework\n"); Write([path stringByAppendingPathComponent:@"unrelated.txt"], @"keep local\n");
    Check(![service syncCourse:f token:@"test" error:&error], @"dirty worktree blocks sync");
    Git(path, @[@"remote", @"set-url", @"--push", @"origin", @"https://github.com/teacher/course.git"]);
    Check([service commitCourse:f paths:@[@"answer one.txt"] message:@"complete assignment" login:@"student" userID:@42 token:@"test" error:&error], @"selected-file commit and explicit fork push");
    Check([[Git(f[@"forkBare"], @[@"show", @"main:answer one.txt"]) lowercaseString] containsString:@"homework"], @"selected file reached own fork");
    Check([Git(f[@"forkBare"], @[@"ls-tree", @"--name-only", @"main"]) rangeOfString:@"unrelated.txt"].location == NSNotFound, @"unselected file excluded");
    Check([Git(path, @[@"log", @"-1", @"--format=%ae"]) isEqual:@"42+student@users.noreply.github.com"], @"private email not used for new commit");
    Check([Git(path, @[@"config", @"user.email"]) isEqual:@"private@example.invalid"], @"repository email setting preserved");
    Check([Git(f[@"teacherBare"], @[@"rev-parse", @"main"]) isEqual:teacherBefore], @"teacher branch never changed");
    Git(path, @[@"add", @"unrelated.txt"]); NSString *before = Git(path, @[@"rev-parse", @"HEAD"]);
    Check(![service commitCourse:f paths:@[@"unrelated.txt"] message:@"should block" login:@"student" userID:@42 token:@"test" error:&error], @"existing staged content blocked");
    Check([Git(path, @[@"rev-parse", @"HEAD"]) isEqual:before], @"blocked commit preserves HEAD"); Git(path, @[@"reset", @"--quiet", @"HEAD", @"--", @"unrelated.txt"]);
    NSString *fake = [[@"gh" stringByAppendingString:@"p_"] stringByAppendingString:[@"B" stringByPaddingToLength:40 withString:@"B" startingAtIndex:0]];
    Write([path stringByAppendingPathComponent:@"answer.txt"], fake);
    Check(![service commitCourse:f paths:@[@"answer.txt"] message:@"secret should block" login:@"student" userID:@42 token:@"test" error:&error], @"secret in selected blob blocks commit");
    Check(Git(path, @[@"diff", @"--cached", @"--name-only"]).length == 0, @"failed secret check leaves original index intact");
    Git(path, @[@"add", @"answer.txt"]); Git(path, @[@"commit", @"-m", @"unsafe old commit"]); Git(path, @[@"rm", @"answer.txt"]); Git(path, @[@"commit", @"-m", @"removed afterwards"]);
    Check(![service pushCourse:f token:@"test" error:&error], @"removed secret in outgoing history still blocks push");
    Git(path, @[@"config", @"url.https://github.com/teacher/course.git.pushInsteadOf", @"https://github.com/student/course.git"]);
    Check(![service validateCourse:f error:&error], @"local URL rewrite rejected");
    Git(path, @[@"config", @"--unset", @"url.https://github.com/teacher/course.git.pushInsteadOf"]);
    service.wrongAccount = YES; Check(![service pushCourse:f token:@"test" error:&error], @"account switch blocks pushing old account fork"); service.wrongAccount = NO;
    Git(path, @[@"remote", @"set-url", @"origin", @"https://github.com/teacher/course.git"]); Check(![service validateCourse:f error:&error], @"wrong origin blocks operation");
    Cleanup(f);

    f = Fixture(); service = Service(f); path = f[@"path"];
    Write([path stringByAppendingPathComponent:@"answer.txt"], @"keep local commit when network fails\n"); service.rejectPush = YES;
    Check(![service commitCourse:f paths:@[@"answer.txt"] message:@"answer" login:@"student" userID:@42 token:@"test" error:&error], @"push rejection reported");
    Check([Git(path, @[@"show", @"HEAD:answer.txt"]) containsString:@"keep local"], @"failed push preserves local commit");
    service.rejectPush = NO; Check([service pushCourse:f token:@"test" error:&error], @"retry own fork push works"); Cleanup(f);

    f = Fixture(); service = Service(f); path = f[@"path"];
    Write([path stringByAppendingPathComponent:@"shared.txt"], @"student edit\n");
    Check([service commitCourse:f paths:@[@"shared.txt"] message:@"student work" login:@"student" userID:@42 token:@"test" error:&error], @"student change pushed");
    NSString *seed = f[@"seed"];
    Write([seed stringByAppendingPathComponent:@"shared.txt"], @"teacher edit\n"); Git(seed, @[@"add", @"shared.txt"]); Git(seed, @[@"commit", @"-m", @"new homework"]); Git(seed, @[@"push", f[@"teacherBare"], @"main"]);
    teacherBefore = Git(f[@"teacherBare"], @[@"rev-parse", @"main"]);
    NSDictionary *conflict = [service syncCourse:f token:@"test" error:&error];
    Check([conflict[@"conflicts"] count] == 1, @"conflict is returned for guided handling");
    f[@"pendingMergeTip"] = conflict[@"mergeHead"]; f[@"pendingConflicts"] = conflict[@"conflicts"];
    Check(![service continueMergeForCourse:f token:@"test" error:&error], @"unresolved conflict blocks continuation");
    Check(![service stageResolvedFiles:f paths:@[@"shared.txt"] error:&error], @"conflict markers block marking solved");
    Write([path stringByAppendingPathComponent:@"shared.txt"], @"student and teacher resolved\n");
    Check([service stageResolvedFiles:f paths:@[@"shared.txt"] error:&error], @"resolved file staged");
    Check([service continueMergeForCourse:f token:@"test" error:&error], @"guided merge completes and pushes fork");
    Check([Git(f[@"teacherBare"], @[@"rev-parse", @"main"]) isEqual:teacherBefore], @"teacher remains unchanged after merge continuation");
    Check([Git(f[@"forkBare"], @[@"show", @"main:shared.txt"]) containsString:@"resolved"], @"resolved version only reaches fork"); Cleanup(f);
    f = Fixture(); service = Service(f); path = f[@"path"]; seed = f[@"seed"];
    Git(seed, @[@"checkout", @"-b", @"lesson"]);
    Write([seed stringByAppendingPathComponent:@"README.md"], @"# Homework 2\nDue: 2026-10-12 21:00\n");
    Write([seed stringByAppendingPathComponent:@"duplicate.md"], @"# Homework 2\nDue: 2026-10-12 21:00\n");
    Write([seed stringByAppendingPathComponent:@"assignment-04.md"], @"# 规则\n- 截止时间：本周日 21:00\n- 提交单个 Markdown 文件。\n# 任务\n完成附件作业：运动学基础和牛顿定律。\n");
    Write([seed stringByAppendingPathComponent:@"large.md"], [@"x" stringByPaddingToLength:1024 * 1024 + 1 withString:@"x" startingAtIndex:0]);
    Check([NSFileManager.defaultManager createSymbolicLinkAtPath:[seed stringByAppendingPathComponent:@"external.md"] withDestinationPath:@"/private/not-a-document" error:NULL], @"fixture document symlink");
    Git(seed, @[@"add", @"."]); Git(seed, @[@"commit", @"-m", @"teacher changes default branch"]); Git(seed, @[@"push", f[@"teacherBare"], @"lesson"]);
    Git(f[@"teacherBare"], @[@"symbolic-ref", @"HEAD", @"refs/heads/lesson"]);
    NSMutableDictionary *oldCache = NSMutableDictionary.dictionary;
    oldCache[[NSString stringWithFormat:@"v2|teacher/course|assignment-04.md|%@|Asia/Shanghai", Git(seed, @[@"rev-parse", @"HEAD:assignment-04.md"])]] = @[];
    scan = [service scanCourse:f cache:oldCache error:&error];
    Check([scan[@"branch"] isEqual:@"lesson"] && [scan[@"candidates"] count] == 2, @"current teacher default branch scanned and duplicates collapsed");
    NSDictionary *weeklyCandidate = nil;
    for (NSDictionary *item in scan[@"candidates"]) if ([item[@"path"] isEqual:@"assignment-04.md"]) weeklyCandidate = item;
    Check([weeklyCandidate[@"deadlineText"] isEqual:@"本周日 21:00"] && [weeklyCandidate[@"needsDate"] boolValue] && [weeklyCandidate[@"snippet"] containsString:@"牛顿定律"], @"Git blob scan discovers screenshot-style assignment despite old empty cache");
    Check([scan[@"skipped"] count] == 2, @"large document and symlink reported");
    Check([service syncCourse:f token:@"test" error:&error] != nil, @"clean sync succeeds after teacher default branch changes");
    Check([Git(f[@"forkBare"], @[@"show", @"main:README.md"]) containsString:@"Homework 2"], @"teacher default merged into explicit own main");
    Git(path, @[@"checkout", @"-b", @"answer-branch"]);
    Check([service scanCourse:f cache:NSMutableDictionary.dictionary error:&error] != nil, @"read scan works on other local branch");
    Check(![service pushCourse:f token:@"test" error:&error], @"wrong submission branch blocks push"); Cleanup(f);

    f = Fixture(); service = Service(f); path = f[@"path"]; seed = f[@"seed"];
    Write([seed stringByAppendingPathComponent:@"remote.txt"], @"remote fork change"); Git(seed, @[@"add", @"remote.txt"]); Git(seed, @[@"commit", @"-m", @"remote fork"]); Git(seed, @[@"push", f[@"forkBare"], @"main"]);
    Write([path stringByAppendingPathComponent:@"local.txt"], @"different local change"); Git(path, @[@"add", @"local.txt"]); Git(path, @[@"commit", @"-m", @"local change"]);
    before = Git(path, @[@"rev-parse", @"HEAD"]);
    Check(![service syncCourse:f token:@"test" error:&error] && service.pushTargets.count == 0, @"fork branch divergence blocks sync without any push");
    Check([Git(path, @[@"rev-parse", @"HEAD"]) isEqual:before], @"divergence preserves local commit"); Cleanup(f);

}
int main(void) { @autoreleasepool { ParserTests(); SecurityTests(); APITests(); GitTests(); printf("PASS: %lu homework/API/Git/security assertions\n", (unsigned long)assertions); } return 0; }
