#import "IKCEFContexts.h"
#import "IKCEFPageInternal.h"
#import "IKCEFRuntimeInternal.h"
#import <CommonCrypto/CommonDigest.h>
#include "include/cef_cookie.h"
#include "include/cef_request_context_handler.h"
#include <map>
#include "IKCEFSecurityInternal.h"

namespace {
struct Context {
  CefRefPtr<CefRequestContext> value;
  bool ephemeral;
  std::string root;
};
std::map<std::string, Context> contexts;
class SetCookie final : public CefSetCookieCallback {
 public:
  explicit SetCookie(void (^completion)(NSError *)) : completion_([completion copy]) {}
  void OnComplete(bool success) override {
    completion_(success ? nil : IKCEFError(@"Chromium rejected an imported cookie."));
  }
 private:
  void (^completion_)(NSError *);
  IMPLEMENT_REFCOUNTING(SetCookie);
};
class Flush final : public CefCompletionCallback {
 public:
  explicit Flush(void (^completion)(BOOL)) : completion_([completion copy]) {}
  void OnComplete() override {
    auto done = completion_;
    dispatch_async(dispatch_get_main_queue(), ^{ done(YES); });
  }
 private:
  void (^completion_)(BOOL);
  IMPLEMENT_REFCOUNTING(Flush);
};
/// Answers from its destructor: CEF never calls Visit for an empty store, it only releases the visitor.
class CollectCookies final : public CefCookieVisitor {
 public:
  explicit CollectCookies(void (^completion)(NSArray *)) : completion_([completion copy]), cookies_([NSMutableArray new]) {}
  ~CollectCookies() override {
    auto done = completion_;
    NSArray *result = [cookies_ copy];
    dispatch_async(dispatch_get_main_queue(), ^{ done(result); });
  }
  bool Visit(const CefCookie& cookie, int, int, bool&) override {
    NSInteger sameSite = cookie.same_site == CEF_COOKIE_SAME_SITE_LAX_MODE ? 1 :
        cookie.same_site == CEF_COOKIE_SAME_SITE_STRICT_MODE ? 2 :
        cookie.same_site == CEF_COOKIE_SAME_SITE_NO_RESTRICTION ? 0 : -1;
    NSMutableDictionary *item = [@{
      @"name": @(CefString(&cookie.name).ToString().c_str()),
      @"value": @(CefString(&cookie.value).ToString().c_str()),
      @"domain": @(CefString(&cookie.domain).ToString().c_str()),
      @"path": @(CefString(&cookie.path).ToString().c_str()),
      @"secure": @(bool(cookie.secure)),
      @"httpOnly": @(bool(cookie.httponly)),
      @"sameSite": @(sameSite),
    } mutableCopy];
    cef_time_t expires;
    double seconds = 0;
    if (cookie.has_expires && cef_time_from_basetime(cookie.expires, &expires) && cef_time_to_doublet(&expires, &seconds))
      item[@"expires"] = @(seconds);
    [cookies_ addObject:item];
    return true;
  }
 private:
  void (^completion_)(NSArray *);
  NSMutableArray *cookies_;
  IMPLEMENT_REFCOUNTING(CollectCookies);
};
class DeleteCookies final : public CefDeleteCookiesCallback {
 public:
  explicit DeleteCookies(void (^completion)(BOOL)) : completion_([completion copy]) {}
  void OnComplete(int) override {
    auto done = completion_;
    dispatch_async(dispatch_get_main_queue(), ^{ done(YES); });
  }
 private:
  void (^completion_)(BOOL);
  IMPLEMENT_REFCOUNTING(DeleteCookies);
};
}

CefRefPtr<CefRequestContext> IKCEFContext(NSString *profile) {
  NSCAssert(NSThread.isMainThread, @"CEF contexts require the main thread");
  auto entry = contexts.find(profile.UTF8String);
  return entry == contexts.end() ? nullptr : entry->second.value;
}
std::vector<CefRefPtr<CefRequestContext>> IKCEFContextsSnapshot() {
  std::vector<CefRefPtr<CefRequestContext>> result;
  for (const auto& [_, context] : contexts) result.push_back(context.value);
  return result;
}
void IKCEFClearContexts(void) { IKCEFSecurityReset(); contexts.clear(); }

@implementation IKCEFContexts
+ (BOOL)prepareProfile:(NSString *)profile root:(NSURL *)root ephemeral:(BOOL)ephemeral
                 error:(NSError **)error {
  NSParameterAssert(NSThread.isMainThread);
  if (!profile.length || !IKCEFCanCreateContext(root)) {
    if (error) *error = IKCEFError(@"Invalid CEF profile identity or storage root.");
    return NO;
  }
  std::string key = profile.UTF8String;
  std::string rootPath = root.URLByStandardizingPath.path.UTF8String;
  auto existing = contexts.find(key);
  if (existing != contexts.end()) {
    BOOL matches = existing->second.ephemeral == bool(ephemeral) && existing->second.root == rootPath;
    if (!matches && error) *error = IKCEFError(@"An open Space cannot change its CEF storage identity.");
    return matches;
  }
  CefRequestContextSettings settings;
  settings.persist_session_cookies = false;
  if (!ephemeral) {
    NSData *identity = [profile dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(identity.bytes, (CC_LONG)identity.length, digest);
    NSMutableString *name = [NSMutableString string];
    for (auto byte : digest) [name appendFormat:@"%02x", byte];
    NSURL *path = [root URLByAppendingPathComponent:name isDirectory:YES];
    if (![NSFileManager.defaultManager createDirectoryAtURL:path withIntermediateDirectories:YES
        attributes:@{NSFilePosixPermissions: @0700} error:error]) return NO;
    CefString(&settings.cache_path) = path.path.UTF8String;
  }
  auto context = CefRequestContext::CreateContext(settings, IKCEFMakeSecurityHandler(profile));
  if (!context) {
    if (error) *error = IKCEFError(@"CEF could not create this Space's request context.");
    return NO;
  }
  contexts.emplace(key, Context{context, bool(ephemeral), rootPath});
  return YES;
}
+ (void)flushProfile:(NSString *)profile completion:(void (^)(BOOL))completion {
  auto context = IKCEFContext(profile);
  auto cookies = context ? context->GetCookieManager(nullptr) : nullptr;
  if (!cookies || !cookies->FlushStore(new Flush(completion))) completion(NO);
}
+ (void)setCookie:(NSHTTPCookie *)cookie sameSite:(NSInteger)sameSite profile:(NSString *)profile
       completion:(void (^)(NSError *))completion {
  auto context = IKCEFContext(profile);
  auto manager = context ? context->GetCookieManager(nullptr) : nullptr;
  if (!manager) { completion(IKCEFError(@"The destination Space is not prepared.")); return; }
  CefCookie value;
  CefString(&value.name) = cookie.name.UTF8String;
  CefString(&value.value) = cookie.value.UTF8String;
  if ([cookie.domain hasPrefix:@"."]) CefString(&value.domain) = cookie.domain.UTF8String;
  CefString(&value.path) = cookie.path.UTF8String;
  value.secure = cookie.secure;
  value.httponly = cookie.HTTPOnly;
  value.same_site = sameSite == 1 ? CEF_COOKIE_SAME_SITE_LAX_MODE : sameSite == 2 ?
      CEF_COOKIE_SAME_SITE_STRICT_MODE : sameSite == 0 ? CEF_COOKIE_SAME_SITE_NO_RESTRICTION : CEF_COOKIE_SAME_SITE_UNSPECIFIED;
  if (cookie.expiresDate) {
    cef_time_t expires;
    value.has_expires = cef_time_from_doublet(cookie.expiresDate.timeIntervalSince1970, &expires) &&
        cef_time_to_basetime(&expires, &value.expires);
  }
  NSURLComponents *url = [NSURLComponents new];
  url.scheme = cookie.secure ? @"https" : @"http";
  url.host = [cookie.domain hasPrefix:@"."] ? [cookie.domain substringFromIndex:1] : cookie.domain;
  url.path = cookie.path;
  if (!url.URL || !manager->SetCookie(url.URL.absoluteString.UTF8String, value, new SetCookie(completion)))
    completion(IKCEFError(@"Chromium could not import this cookie."));
}
+ (void)cookiesForProfile:(NSString *)profile completion:(void (^)(NSArray<NSDictionary<NSString *, id> *> *))completion {
  auto context = IKCEFContext(profile);
  auto manager = context ? context->GetCookieManager(nullptr) : nullptr;
  if (!manager || !manager->VisitAllCookies(new CollectCookies(completion))) completion(nil);
}
+ (void)deleteCookieNamed:(NSString *)name url:(NSString *)url profile:(NSString *)profile completion:(void (^)(BOOL))completion {
  auto context = IKCEFContext(profile);
  auto manager = context ? context->GetCookieManager(nullptr) : nullptr;
  if (!manager || !manager->DeleteCookies(url.UTF8String, name.UTF8String, new DeleteCookies(completion))) completion(NO);
}
+ (BOOL)forgetEphemeralProfile:(NSString *)profile {
  NSParameterAssert(NSThread.isMainThread);
  auto entry = contexts.find(profile.UTF8String);
  if (entry == contexts.end() || !entry->second.ephemeral) return NO;
  IKCEFSecurityForget(entry->second.value.get());
  contexts.erase(entry);
  return YES;
}
@end
