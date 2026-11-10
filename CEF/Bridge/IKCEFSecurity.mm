#import "IKCEFSecurity.h"
#import "IKCEFPageInternal.h"
#include "IKCEFSecurityInternal.h"
#include "IKCEFMediaBridgeInternal.h"
#include "include/cef_parser.h"
#include "include/cef_resource_request_handler.h"
#include <atomic>
#include <arpa/inet.h>
#include <memory>
#include <algorithm>
#include <vector>

namespace {
struct Policy {
  bool trackers = true, cookies = true, safeBrowsing = true, forceHTTPS = false, allowLocal = true;
  std::vector<std::string> domains, exceptions;
};
std::shared_ptr<const Policy> policy = std::make_shared<Policy>();
void (^changeHandler)(NSString *);
struct ObservedContext {
  CefRefPtr<CefRequestContext> context;
  std::vector<CefRefPtr<CefRegistration>> registrations;
};
std::vector<ObservedContext> initialized;
bool IsInitialized(CefRefPtr<CefRequestContext> context) {
  for (const auto& item : initialized) if (item.context->IsSame(context)) return true;
  return false;
}
NSMutableDictionary<NSString *, NSString *> *issues;
std::string Host(const CefString& url) {
  CefURLParts parts;
  return CefParseURL(url, parts) ? CefString(&parts.host).ToString() : "";
}
bool Domain(const std::string& host, const std::string& domain) {
  return host == domain || (host.size() > domain.size() && host.ends_with("." + domain));
}
bool HasUserPreference(CefRefPtr<CefRequestContext> context, const std::string& name) {
  auto dictionary = context->GetAllPreferences(false);
  if (!dictionary) return false;
  if (dictionary->HasKey(name)) return true;
  size_t start = 0;
  while (true) {
    auto dot = name.find('.', start);
    if (dot == std::string::npos) return dictionary->HasKey(name.substr(start));
    dictionary = dictionary->GetDictionary(name.substr(start, dot - start));
    if (!dictionary) return false;
    start = dot + 1;
  }
}
void Apply(CefRefPtr<CefRequestContext> context) {
  auto current = std::atomic_load(&policy);
  auto initializedPreference = context->GetPreference("ikago.security_initialized");
  const bool hasInitialized = initializedPreference && initializedPreference->GetBool();
  if (!issues) issues = [NSMutableDictionary dictionary];
  for (auto name : {"profile.cookie_controls_mode", "safebrowsing.enabled", "credentials_enable_service"}) {
    // Native per-Space user/managed settings persist in Chromium. App defaults
    // initialize unset values only; unrelated SwiftUI changes must not reset them.
    if (std::string(name) != "credentials_enable_service" &&
        (hasInitialized || HasUserPreference(context, name))) continue;
    auto value = CefValue::Create();
    if (std::string(name) == "profile.cookie_controls_mode") value->SetInt(current->cookies ? 1 : 0);
    else if (std::string(name) == "safebrowsing.enabled") value->SetBool(current->safeBrowsing);
    else value->SetBool(false); // Ikago's own vault fills passwords; Chromium's password manager stays off.
    CefString error;
    NSString *key = [NSString stringWithUTF8String:name];
    if (!context->SetPreference(name, value, error)) issues[key] = IKCEFString(error);
    else [issues removeObjectForKey:key];
  }
  auto marker = CefValue::Create(); marker->SetBool(true);
  CefString error;
  if (!context->SetPreference("ikago.security_initialized", marker, error))
    issues[@"ikago.security_initialized"] = IKCEFString(error);
}
class PreferenceObserver final : public CefPreferenceObserver {
 public:
  explicit PreferenceObserver(NSString *profile) : profile_([profile copy]) {}
  void OnPreferenceChanged(const CefString&) override { if (changeHandler) changeHandler(profile_); }
 private:
  NSString *profile_;
  IMPLEMENT_REFCOUNTING(PreferenceObserver);
};
bool Loopback(const std::string& host) {
  in_addr address;
  return host == "localhost" || host.ends_with(".localhost") || host == "[::1]" || host == "::1" ||
      (inet_pton(AF_INET, host.c_str(), &address) == 1 && (ntohl(address.s_addr) >> 24) == 127);
}
// The HTTPS-only upgrade of a top-level navigation, or an empty string to leave it alone.
std::string Upgrade(const Policy& current, CefRefPtr<CefRequest> request) {
  CefURLParts parts;
  if (!current.forceHTTPS || !CefParseURL(request->GetURL(), parts) || CefString(&parts.scheme).ToString() != "http") return "";
  const auto host = CefString(&parts.host).ToString();
  bool allowed = current.allowLocal && Loopback(host);
  for (const auto& exception : current.exceptions) if (Domain(host, exception)) allowed = true;
  if (allowed) return "";
  CefString(&parts.scheme) = "https";
  if (CefString(&parts.port).ToString() == "80") CefString(&parts.port).clear();
  CefString secure;
  return CefCreateURL(parts, secure) ? secure.ToString() : "-";
}
bool Tracker(const Policy& current, CefRefPtr<CefRequest> request, const CefString& initiator) {
  if (!current.trackers) return false;
  const auto host = Host(request->GetURL());
  auto first = Host(request->GetFirstPartyForCookies());
  if (first.empty()) first = Host(initiator);
  for (const auto& domain : current.domains)
    if (Domain(host, domain) && !Domain(first, domain)) return true;
  return false;
}
// Only requests Ikago cancels or upgrades get a handler. CEF loads and saves cookies itself for
// requests with a handler, without Chromium's third-party cookie setting, so every other request
// stays with Chromium.
class Resource final : public CefResourceRequestHandler {
 public:
  Resource(const CefString& initiator, bool top) : initiator_(initiator), top_(top) {}
  cef_return_value_t OnBeforeResourceLoad(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>,
      CefRefPtr<CefRequest> request, CefRefPtr<CefCallback>) override {
    auto current = std::atomic_load(&policy);
    if (top_) {
      const auto secure = Upgrade(*current, request);
      if (secure == "-" || (!secure.empty() && request->GetMethod() != "GET")) return RV_CANCEL;
      if (!secure.empty()) request->SetURL(secure);
      return RV_CONTINUE;
    }
    return Tracker(*current, request, initiator_) ? RV_CANCEL : RV_CONTINUE;
  }
  // Never let a handled request carry or store cookies on CEF's own path.
  CefRefPtr<CefCookieAccessFilter> GetCookieAccessFilter(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, CefRefPtr<CefRequest>) override {
    return top_ ? nullptr : new NoCookies();
  }
 private:
  class NoCookies final : public CefCookieAccessFilter {
    bool CanSendCookie(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, CefRefPtr<CefRequest>, const CefCookie&) override { return false; }
    bool CanSaveCookie(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, CefRefPtr<CefRequest>, CefRefPtr<CefResponse>, const CefCookie&) override { return false; }
    IMPLEMENT_REFCOUNTING(NoCookies);
  };
  CefString initiator_;
  bool top_;
  IMPLEMENT_REFCOUNTING(Resource);
};
class Handler final : public CefRequestContextHandler {
 public:
  explicit Handler(NSString *profile) : profile_([profile copy]) {}
  void OnRequestContextInitialized(CefRefPtr<CefRequestContext> context) override {
    Apply(context);
    if (!IsInitialized(context)) {
      ObservedContext item{context, {}};
      auto observer = new PreferenceObserver(profile_);
      for (auto name : {"profile.cookie_controls_mode", "safebrowsing.enabled", "safebrowsing.enhanced"})
        item.registrations.push_back(context->AddPreferenceObserver(name, observer));
      initialized.push_back(std::move(item));
    }
    if (changeHandler) changeHandler(profile_);
  }
  CefRefPtr<CefResourceRequestHandler> GetResourceRequestHandler(CefRefPtr<CefBrowser>,
      CefRefPtr<CefFrame> frame, CefRefPtr<CefRequest> request, bool navigation, bool,
      const CefString& initiator, bool&) override {
    if (auto media = IKCEFMediaRoute(request, initiator)) return media;
    CefURLParts parts;
    if (!CefParseURL(request->GetURL(), parts)) return nullptr;
    const auto scheme = CefString(&parts.scheme).ToString();
    if (scheme != "http" && scheme != "https") return nullptr;
    const bool top = navigation && (!frame || frame->IsMain());
    auto current = std::atomic_load(&policy);
    if (top ? Upgrade(*current, request).empty() : !Tracker(*current, request, initiator)) return nullptr;
    return new Resource(initiator, top);
  }
 private:
  NSString *profile_;
  IMPLEMENT_REFCOUNTING(Handler);
};
}
CefRefPtr<CefRequestContextHandler> IKCEFMakeSecurityHandler(NSString *profile) { return new Handler(profile); }
void IKCEFSecurityForget(CefRequestContext *context) {
  std::erase_if(initialized, [context](const auto& item) { return item.context->IsSame(context); });
}
void IKCEFSecurityReset() { initialized.clear(); issues = nil; changeHandler = nil; }
@implementation IKCEFSecurity
+ (void)setChangeHandler:(void (^)(NSString *))handler { changeHandler = [handler copy]; }
+ (BOOL)setPreference:(NSString *)name value:(id)value profile:(NSString *)profile error:(NSError **)error {
  NSParameterAssert(NSThread.isMainThread);
  auto context = IKCEFContext(profile);
  auto converted = CefValue::Create();
  if ([name isEqual:@"profile.cookie_controls_mode"] && [value isKindOfClass:NSNumber.class] &&
      [value intValue] >= 0 && [value intValue] <= 2) converted->SetInt([value intValue]);
  else if ([name isEqual:@"safebrowsing.enabled"] && [value isKindOfClass:NSNumber.class]) converted->SetBool([value boolValue]);
  else { if (error) *error = IKCEFError(@"Unsupported security preference."); return NO; }
  CefString reason;
  if (!context || !IsInitialized(context) || !context->SetPreference(name.UTF8String, converted, reason)) {
    if (error) *error = IKCEFError(reason.empty() ? @"The Space’s security settings are not ready." : IKCEFString(reason));
    return NO;
  }
  return YES;
}
+ (void)configure:(NSDictionary *)options {
  NSParameterAssert(NSThread.isMainThread);
  auto next = std::make_shared<Policy>();
  next->trackers = [options[@"trackers"] boolValue];
  next->cookies = [options[@"cookies"] boolValue];
  next->safeBrowsing = [options[@"safeBrowsing"] boolValue];
  next->forceHTTPS = [options[@"forceHTTPS"] boolValue];
  next->allowLocal = options[@"allowLocal"] ? [options[@"allowLocal"] boolValue] : true;
  for (NSString *domain in options[@"exceptions"]) if (domain.length) next->exceptions.emplace_back(domain.lowercaseString.UTF8String);
  for (NSString *domain in options[@"domains"]) next->domains.emplace_back(domain.lowercaseString.UTF8String);
  std::atomic_store(&policy, std::shared_ptr<const Policy>(next));
  for (auto context : IKCEFContextsSnapshot()) if (IsInitialized(context)) Apply(context);
}
+ (NSDictionary *)snapshotForProfile:(NSString *)profile {
  auto context = IKCEFContext(profile);
  if (!context || !IsInitialized(context)) return @{@"ready": @NO};
  auto safe = context->GetPreference("safebrowsing.enabled");
  auto cookies = context->GetPreference("profile.cookie_controls_mode");
  auto enhanced = context->GetPreference("safebrowsing.enhanced");
  return @{@"ready": @YES, @"safeBrowsingAvailable": @(safe && safe->GetType() == VTYPE_BOOL),
    @"safeBrowsingEnabled": @(safe && safe->GetBool()),
    @"safeBrowsingEnhanced": @(enhanced && enhanced->GetBool()),
    @"cookieControlsMode": @(cookies ? cookies->GetInt() : -1),
    @"thirdPartyCookiesBlocked": @(cookies && cookies->GetInt() == 1),
    @"issues": issues.allValues ?: @[]};
}
@end
