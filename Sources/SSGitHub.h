#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface SSGitHub : NSObject
@property(atomic) BOOL requestsCancelled;
@property (copy) NSString *clientID;
@property (copy) NSString *authType; // githubCLI, oauth or githubApp; never inferred from a token
@property (readonly) BOOL hasCredentials;
@property (readonly) NSDictionary *authenticationIdentity;
// 只读批次可绑定启动时的账户；切换账户后停止旧请求链，不借用新账户的凭据继续读取。
@property(copy,nullable) NSDictionary *expectedReadIdentity;
@property(strong,nullable) NSMutableDictionary *peerImmutableCache;
- (BOOL)selectAuthentication:(NSString *)type error:(NSError **)error;
- (NSDictionary * _Nullable)readableTeacher:(NSDictionary *)course error:(NSError **)error;
@property (copy) NSString *installationURL;
- (NSDictionary * _Nullable)beginDeviceLogin:(NSError **)error;
- (BOOL)completeDeviceLogin:(NSDictionary *)challenge error:(NSError **)error;
- (NSDictionary * _Nullable)user:(NSError **)error;
- (NSArray<NSDictionary *> * _Nullable)accessibleForks:(NSError **)error;
- (NSDictionary * _Nullable)repository:(NSString *)fullName error:(NSError **)error;
- (id _Nullable)readRepository:(NSString *)repository resource:(NSString *)resource error:(NSError **)error;
- (NSDictionary * _Nullable)peerForks:(NSDictionary *)course page:(NSUInteger)page error:(NSError **)error;
- (NSDictionary * _Nullable)peerSnapshot:(NSDictionary *)peer teacher:(NSDictionary *)teacher scope:(NSString *)scope error:(NSError **)error;
- (NSData * _Nullable)peerBlob:(NSString *)sha repository:(NSString *)repository error:(NSError **)error;
- (NSDictionary * _Nullable)peerTree:(NSString *)commit repository:(NSString *)repository error:(NSError **)error;
- (NSString * _Nullable)accessToken:(NSError **)error;
- (NSDictionary * _Nullable)verifyCourse:(NSDictionary *)course error:(NSError **)error;
- (void)cancelDeviceLogin;
- (void)signOut;
@end
NS_ASSUME_NONNULL_END
