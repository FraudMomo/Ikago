#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
NS_SWIFT_UI_ACTOR
@interface IKCEFContexts : NSObject
/// Persistent paths are SHA256(profile ID) directly under root. Private contexts
/// have no cache path. root must equal CEF's configured root_cache_path.
+ (BOOL)prepareProfile:(NSString *)profile root:(NSURL *)root ephemeral:(BOOL)ephemeral
                 error:(NSError **)error;
+ (void)flushProfile:(NSString *)profile completion:(void (^)(BOOL))completion;
+ (BOOL)forgetEphemeralProfile:(NSString *)profile;
+ (void)setCookie:(NSHTTPCookie *)cookie sameSite:(NSInteger)sameSite profile:(NSString *)profile
       completion:(void (^)(NSError *_Nullable))completion;
/// Every cookie in the Space, HttpOnly included, delivered on the main thread. Each dictionary has
/// name, value, domain, path, secure, httpOnly, sameSite (-1 unset, 0 none, 1 lax, 2 strict) and,
/// unless it's a session cookie, expires (seconds since 1970). nil means Chromium refused the read.
+ (void)cookiesForProfile:(NSString *)profile
               completion:(void (^)(NSArray<NSDictionary<NSString *, id> *> *_Nullable))completion;
/// Deletes cookies called `name` that apply to `url`, then calls back on the main thread.
+ (void)deleteCookieNamed:(NSString *)name url:(NSString *)url profile:(NSString *)profile
               completion:(void (^)(BOOL))completion;
@end
NS_ASSUME_NONNULL_END
