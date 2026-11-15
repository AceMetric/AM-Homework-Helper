#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
NSDictionary *AMChatGPTStatus(void);
NSDictionary *AMChatGPTProfile(NSString *purpose);
NSArray *AMChatGPTModels(NSError **error);
BOOL AMChatGPTSavePreferences(NSDictionary *preferences,NSError **error);
void AMChatGPTSignIn(NSString * _Nullable registration,void (^completion)(NSError * _Nullable));
void AMChatGPTCancelSignIn(void);
BOOL AMChatGPTSelectAccount(NSString *registration,NSError **error);
BOOL AMChatGPTSignOut(NSError **error);
NSDictionary * _Nullable AMChatGPTGenerate(NSDictionary *input,NSString *instruction,NSArray *images,NSString *purpose,BOOL (^cancelled)(void),NSError **error);
#ifdef DDL_TESTING
void AMChatGPTSetCredentialStore(NSDictionary * _Nullable (^ _Nullable read)(NSString *),BOOL (^ _Nullable write)(NSString *,NSDictionary *));
void AMChatGPTSetBrowserOpener(void (^ _Nullable opener)(NSURL *));
void AMChatGPTSetTransport(NSData * _Nullable (^ _Nullable transport)(NSURLRequest *,NSInteger *,NSError **));
NSDictionary * _Nullable AMChatGPTValidateIdentity(NSDictionary *tokens,NSDictionary *jwks,NSString *client,NSString * _Nullable nonce,NSError **error);
BOOL AMChatGPTReserveRequest(NSDate *date,NSError **error);
#endif
NS_ASSUME_NONNULL_END
