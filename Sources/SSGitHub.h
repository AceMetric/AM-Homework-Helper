#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface SSGitHub : NSObject
@property (copy) NSString *clientID;
@property (copy) NSString *installationURL;
- (NSDictionary * _Nullable)beginDeviceLogin:(NSError **)error;
- (BOOL)completeDeviceLogin:(NSDictionary *)challenge error:(NSError **)error;
- (NSDictionary * _Nullable)user:(NSError **)error;
- (NSArray<NSDictionary *> * _Nullable)accessibleForks:(NSError **)error;
- (NSDictionary * _Nullable)repository:(NSString *)fullName error:(NSError **)error;
- (NSString * _Nullable)accessToken:(NSError **)error;
- (NSDictionary * _Nullable)verifyCourse:(NSDictionary *)course error:(NSError **)error;
- (void)cancelDeviceLogin;
- (void)signOut;
@end
NS_ASSUME_NONNULL_END
