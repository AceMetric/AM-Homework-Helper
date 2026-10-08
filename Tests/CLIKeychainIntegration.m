// Disposable system-keychain integration, never included in production.
#import <Foundation/Foundation.h>
#import "../Sources/SSGitHub.m"
@interface QAKeychain:SSGitHubCLILogin
@property NSString *service;
@end
@implementation QAKeychain
- (NSString *)keychainService {return self.service;}
@end
static NSUInteger step;
static void Check(BOOL value){step++;if(!value){fprintf(stderr,"FAIL: disposable keychain integration step %lu\n",(unsigned long)step);@throw [NSException exceptionWithName:@"QAFailure" reason:@"Synthetic keychain check failed" userInfo:nil];}}
static BOOL Set(QAKeychain *fixture,NSString *account,NSString *value){NSDictionary *item=@{(__bridge id)kSecValueData:[value dataUsingEncoding:NSUTF8StringEncoding]};return [fixture replaceAccount:account previous:item]==errSecSuccess;}
int main(void){@autoreleasepool{
    QAKeychain *fixture=QAKeychain.new;fixture.service=[@"io.github.acemetric.sshomeworkmanager.qa.cli." stringByAppendingString:NSUUID.UUID.UUIDString];
    @try {
        Check(Set(fixture,@"fixture",@"original-fixture"));Check(Set(fixture,@"",@"original-active"));
        fixture.before=[fixture snapshot:NULL];Check(fixture.before.count==2);
        Check(Set(fixture,@"fixture",@"helper-fixture"));Check(Set(fixture,@"",@"helper-active"));fixture.owned=[fixture snapshot:NULL];
        Check([fixture restore:NULL]);NSDictionary *restored=[fixture snapshot:NULL];Check([SSCLIDecode(restored[@"fixture"][(__bridge id)kSecValueData]) isEqual:@"original-fixture"] && [SSCLIDecode(restored[@""][(__bridge id)kSecValueData]) isEqual:@"original-active"]);
        fixture.before=restored;Check(Set(fixture,@"fixture",@"helper-second"));fixture.owned=[fixture snapshot:NULL];Check(Set(fixture,@"fixture",@"external-change"));
        Check([fixture restore:NULL]);restored=[fixture snapshot:NULL];Check([SSCLIDecode(restored[@"fixture"][(__bridge id)kSecValueData]) isEqual:@"external-change"]);
        puts("PASS: real disposable keychain snapshots, shared-item restoration and later modification protection");
    } @catch(NSException *exception){return 1;} @finally {[fixture replaceAccount:@"fixture" previous:nil];[fixture replaceAccount:@"" previous:nil];}
}return 0;}
