// Local-only runner: DDL_TESTING keeps app credentials/data out of production storage.
#import <Foundation/Foundation.h>
#import "../Sources/SSGitHub.m"
int main(void){@autoreleasepool{
    SSGitHub *api=SSGitHub.new;SSGitHubCLILogin *guard=SSGitHubCLILogin.new;NSError *error=nil;
    NSDictionary *before=[guard snapshot:&error];if(!before){fprintf(stderr,"Existing login protection unavailable: %s\n",error.localizedDescription.UTF8String);fprintf(stderr,"Keychain status %ld\n",(long)error.code);return 1;}
    if(![api.authType isEqual:@"githubCLI"]){fprintf(stderr,"Bundled provider unavailable\n");return 1;}
    NSDictionary *challenge=[api beginDeviceLogin:&error];if(!challenge){fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);return 1;}
    printf("DEVICE_CODE=%s\n",[challenge[@"user_code"] UTF8String]);fflush(stdout);
    BOOL ok=[api completeDeviceLogin:challenge error:&error];
    NSDictionary *after=[guard snapshot:&error];BOOL preserved=YES;
    NSMutableSet *accounts=[NSMutableSet setWithArray:before.allKeys];[accounts addObjectsFromArray:after.allKeys];
    for(NSString *account in accounts)if(![before[account][(__bridge id)kSecValueData] isEqual:after[account][(__bridge id)kSecValueData]])preserved=NO;
    if(!ok){fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);[api signOut];return 1;}
    NSArray *courses=SSReadPlist(@"test-courses.plist");NSUInteger accessible=0;
    for(NSDictionary *course in courses)if([api readableTeacher:course error:&error])accessible++;
    NSDictionary *me=[api user:&error];
    NSDictionary *report=@{@"login":@(ok),@"sharedLoginPreserved":@(preserved),@"privateCourses":@(accessible),@"expectedCourses":@(courses.count),@"accountVerified":@([me[@"id"] isKindOfClass:NSNumber.class]),@"provider":api.authType};
    [api signOut];SSWritePlist(@"result.plist",report,NULL);
    printf("Login %s; shared official login %s; private course reads %lu/%lu; test app credential removed\n",ok ? "PASS":"FAIL",preserved ? "PASS":"FAIL",(unsigned long)accessible,(unsigned long)courses.count);
    return ok && preserved && accessible==courses.count ? 0:1;
}}
