// Fixed test helper owns one dummy Keychain item across fixture app replacement.
// Never compiled or embedded in production; cannot query production service names.
#import <Foundation/Foundation.h>
#import <Security/Security.h>
int main(int argc,const char *argv[]){@autoreleasepool{
    if(argc!=3)return 2;NSString *command=@(argv[1]),*service=@(argv[2]);
    if(![service hasPrefix:@"io.github.ddl-manager.update-test."] || ![service hasSuffix:@".github"])return 2;
    NSMutableDictionary *query=[@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:service,(__bridge id)kSecAttrAccount:@"qa-preservation"} mutableCopy];
    NSData *fixture=[@"synthetic-auth-placeholder" dataUsingEncoding:NSUTF8StringEncoding];
    if([command isEqual:@"write"]){SecItemDelete((__bridge CFDictionaryRef)query);query[(__bridge id)kSecValueData]=fixture;return SecItemAdd((__bridge CFDictionaryRef)query,NULL)==errSecSuccess ? 0 : 1;}
    if([command isEqual:@"read"]){query[(__bridge id)kSecReturnData]=@YES;query[(__bridge id)kSecMatchLimit]=(__bridge id)kSecMatchLimitOne;CFTypeRef value=NULL;OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)query,&value);NSData *data=CFBridgingRelease(value);return status==errSecSuccess && [data isEqual:fixture] ? 0 : 1;}
    if([command isEqual:@"delete"]){OSStatus status=SecItemDelete((__bridge CFDictionaryRef)query);return status==errSecSuccess || status==errSecItemNotFound ? 0 : 1;}
    return 2;
}return 0;}
