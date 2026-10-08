#import <Foundation/Foundation.h>
#import "../Sources/SSGitHub.m"
static NSUInteger checks;
static void Check(BOOL value,NSString *message){checks++;if(!value){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
@interface CLIMemoryFixture:SSGitHubCLILogin
@property NSMutableDictionary *items;
@property NSMutableArray *changedAccounts;
@end
@implementation CLIMemoryFixture
- (NSDictionary *)snapshot:(NSError **)error {return self.items.copy;}
- (OSStatus)replaceAccount:(NSString *)account previous:(NSDictionary *)previous {if(previous)self.items[account]=previous;else [self.items removeObjectForKey:account];[self.changedAccounts addObject:account];return errSecSuccess;}
@end
static NSDictionary *Item(NSString *value,NSInteger time){return @{(__bridge id)kSecValueData:[value dataUsingEncoding:NSUTF8StringEncoding],(__bridge id)kSecAttrModificationDate:[NSDate dateWithTimeIntervalSince1970:time]};}
@interface CLIResultFixture:SSGitHubCLILogin
@property NSDictionary *result;
@end
@implementation CLIResultFixture
- (NSDictionary *)finish:(NSDictionary *)challenge error:(NSError **)error {return self.result;}
@end
@interface CLIAPIFixture:SSGitHub
@property NSDictionary *stored;
@property BOOL wrongUser;
@property BOOL missingScope;
@property BOOL saveFails;
@end
@implementation CLIAPIFixture
- (id)requestURL:(NSURL *)url form:(NSDictionary *)form token:(NSString *)token error:(NSError **)error {self.responseScopes=self.missingScope ? @"read:org,gist":@"repo, read:org, gist";return @{@"id":@42,@"login":self.wrongUser ? @"other":@"student"};}
- (BOOL)storeCredentials:(NSDictionary *)credentials {if(self.saveFails)return NO;self.stored=credentials;return YES;}
@end
static CLIAPIFixture *API(void){CLIAPIFixture *api=CLIAPIFixture.new;api.authType=@"githubCLI";api.clientID=@"github-cli";CLIResultFixture *login=CLIResultFixture.new;login.result=@{@"access_token":@"synthetic",@"login":@"student"};api.cliLogin=login;return api;}
int main(void){@autoreleasepool{
    Check([SSCLIDecode([@"go-keyring-base64:c3ludGhldGlj" dataUsingEncoding:NSUTF8StringEncoding]) isEqual:@"synthetic"],@"official keyring base64 decoding");
    Check([SSCLIDecode([@"go-keyring-encoded:6162" dataUsingEncoding:NSUTF8StringEncoding]) isEqual:@"ab"],@"legacy hex decoding");
    Check(!SSCLIDecode([@"go-keyring-encoded:fg" dataUsingEncoding:NSUTF8StringEncoding]),@"malformed hex rejected");
    NSDictionary *environment=SSCLIEnvironment(@"/tmp/synthetic-cli");Check(!environment[@"GH_TOKEN"] && !environment[@"GITHUB_TOKEN"] && !environment[@"GH_DEBUG"] && !environment[@"GIT_CONFIG_GLOBAL"],@"allow-listed environment excludes secrets and debug");
    Check([environment[@"GH_TELEMETRY"] isEqual:@"false"] && [environment[@"GH_NO_UPDATE_NOTIFIER"] isEqual:@"1"],@"telemetry and updates disabled");
    Check([SSCLIProfile() containsString:@"(deny file-write*)"] && [SSCLIProfile() containsString:@"Library/Keychains"] && ![SSCLIProfile() containsString:@"GH_CONFIG_DIR"],@"all credential file writes denied without writable directory exemption");
    CLIMemoryFixture *login=CLIMemoryFixture.new;login.before=@{@"":Item(@"old-active",1),@"student":Item(@"old-user",1)};login.owned=@{@"":Item(@"helper",2),@"student":Item(@"helper",2)};login.items=login.owned.mutableCopy;login.changedAccounts=NSMutableArray.array;
    Check([login restore:NULL] && [login.items[@""] isEqual:Item(@"old-active",1)] && [login.items[@"student"] isEqual:Item(@"old-user",1)],@"restore both original active and account values");
    login.before=@{};login.owned=@{@"student":Item(@"helper",2)};login.items=login.owned.mutableCopy;
    Check([login restore:NULL] && login.items.count==0,@"remove only newly created helper-owned account");
    login.before=@{@"":Item(@"old",1)};login.owned=@{@"":Item(@"helper",2)};login.items=[@{@"":Item(@"concurrent",3),@"other":Item(@"external",4)} mutableCopy];[login.changedAccounts removeAllObjects];
    Check([login restore:NULL] && login.changedAccounts.count==0 && [login.items[@""] isEqual:Item(@"concurrent",3)] && login.items[@"other"],@"concurrent CLI state left untouched");
    login.before=@{@"":Item(@"old",1)};login.owned=@{@"":Item(@"helper",2)};login.items=[@{@"":Item(@"helper",3)} mutableCopy];
    Check([login restore:NULL] && [login.items[@""] isEqual:Item(@"helper",3)],@"same token changed again by another process is not restored");
    CLIAPIFixture *api=API();Check([api completeDeviceLogin:@{} error:NULL] && [api.stored[@"authType"] isEqual:@"githubCLI"] && [api credentialAccount]!=nil,@"verified CLI token stored under independent provider");
    api=API();api.wrongUser=YES;Check(![api completeDeviceLogin:@{} error:NULL] && !api.stored,@"account mismatch rejected before storage");
    api=API();api.missingScope=YES;Check(![api completeDeviceLogin:@{} error:NULL] && !api.stored,@"missing private repo scope rejected");
    api=API();api.saveFails=YES;Check(![api completeDeviceLogin:@{} error:NULL] && !api.stored,@"own keychain failure never marked successful");
    api=API();api.loginCancelled=YES;Check(![api completeDeviceLogin:@{} error:NULL] && !api.stored,@"cancelled login cannot store a credential");
    printf("PASS: %lu official CLI credential protection assertions\n",(unsigned long)checks);
}return 0;}
