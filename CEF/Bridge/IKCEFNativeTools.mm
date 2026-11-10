#import "IKCEFNativeTools.h"
#import "IKCEFPageInternal.h"
#import "IKCEFRuntimeInternal.h"
#include <map>
#include "include/cef_dialog_handler.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_request_handler.h"
#include "IKCEFSecurityInternal.h"

// Ikago never shows a Chromium window. Chrome-style browsers exist only because some Chromium
// services need one (the extension manager, for example), and they stay hidden. A browser that
// Chromium creates on its own, such as an extension's tabs.create, is handed over to Ikago as a tab.

namespace {
std::map<int, CefRefPtr<CefBrowser>> windows;
int nextToken = 0;
bool closingAll = false;
NSMutableDictionary<NSNumber *, IKCEFPage *> *proxies;
NSString *nextFolder;
void (^foreignPageHandler)(NSURL *);
bool OpensInIkago(NSString *url) {
  NSString *scheme = [NSURL URLWithString:url].scheme.lowercaseString;
  return [@[@"http", @"https", @"chrome-extension"] containsObject:scheme ?: @""];
}
void HandOver(const CefString& url) {
  NSString *value = IKCEFString(url);
  if (foreignPageHandler && OpensInIkago(value)) foreignPageHandler([NSURL URLWithString:value]);
}
NSWindow *NativeWindow(CefRefPtr<CefBrowser> browser) {
  return [(__bridge NSView *)browser->GetHost()->GetWindowHandle() window];
}
NSDictionary *Snapshot(CefRefPtr<CefBrowser> browser) {
  NSWindow *window = NativeWindow(browser);
  return @{@"id": @(browser->GetIdentifier()), @"url": IKCEFString(browser->GetMainFrame()->GetURL()),
    @"loading": @(browser->IsLoading()), @"title": IKCEFString(browser->GetMainFrame()->GetURL()),
    @"window": @(window.windowNumber)};
}
bool FixtureContext(CefRefPtr<CefRequestContext> context) {
  NSString *cache = IKCEFString(context->GetCachePath());
  return [cache.stringByDeletingLastPathComponent.lastPathComponent hasPrefix:@"ikago-cef-smoke-"];
}
bool Fixture(CefRefPtr<CefBrowser> browser) { return FixtureContext(browser->GetHost()->GetRequestContext()); }
class Observer final : public CefDevToolsMessageObserver {
 public:
  explicit Observer(IKCEFPage *page) : page_(page) {}
  void OnDevToolsMethodResult(CefRefPtr<CefBrowser>, int id, bool success, const void *data, size_t size) override {
    [page_ methodResult:id success:success data:[NSData dataWithBytes:data length:size]];
  }
  void OnDevToolsEvent(CefRefPtr<CefBrowser>, const CefString& method, const void *, size_t) override {
    if (method == "Page.interstitialShown") [page_ emit:@"interstitial" payload:@{}];
  }
 private:
  __weak IKCEFPage *page_;
  IMPLEMENT_REFCOUNTING(Observer);
};
class FolderDialog final : public CefDialogHandler {
 public:
  bool OnFileDialog(CefRefPtr<CefBrowser> browser, FileDialogMode mode, const CefString&,
      const CefString&, const std::vector<CefString>& filters, const std::vector<CefString>&,
      const std::vector<CefString>&, CefRefPtr<CefFileDialogCallback> callback) override {
    const auto url = browser->GetMainFrame()->GetURL().ToString();
    if (!url.starts_with("chrome://extensions") ||
        (mode != FILE_DIALOG_OPEN_FOLDER && !(mode == FILE_DIALOG_OPEN && filters.empty()))) return false;
    // Ikago picks the folder in its own panel first; the hidden page never shows one.
    NSString *folder = nextFolder;
    nextFolder = nil;
    if (!folder && Fixture(browser)) {
      NSString *cache = IKCEFString(browser->GetHost()->GetRequestContext()->GetCachePath());
      folder = [cache.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"FixtureExtension"];
    }
    if (folder && [NSFileManager.defaultManager fileExistsAtPath:folder]) callback->Continue({folder.UTF8String});
    else callback->Cancel();
    return true;
  }
 private:
  IMPLEMENT_REFCOUNTING(FolderDialog);
};
class ToolClient final : public CefClient, public CefLifeSpanHandler, public CefPermissionHandler, public CefRequestHandler {
 public:
  explicit ToolClient(bool owned) : owned_(owned) { IKCEFTrackBrowser(1); }
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  bool OnBeforePopup(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, int, const CefString& url, const CefString&,
      WindowOpenDisposition, bool, const CefPopupFeatures&, CefWindowInfo&, CefRefPtr<CefClient>&,
      CefBrowserSettings&, CefRefPtr<CefDictionaryValue>&, bool*) override {
    HandOver(url);
    return true;
  }
  bool OnBeforeBrowse(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefRefPtr<CefRequest> request,
      bool, bool) override {
    if (owned_ || !frame->IsMain()) return false;
    const CefString url = request->GetURL();
    if (!OpensInIkago(IKCEFString(url))) return false;
    HandOver(url);
    browser->GetHost()->CloseBrowser(true);
    return true;
  }
  CefRefPtr<CefDialogHandler> GetDialogHandler() override { return new FolderDialog(); }
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    if (!pending_) IKCEFTrackBrowser(1);
    pending_ = false;
    windows[browser->GetIdentifier()] = browser;
    bool known = false;
    for (auto context : IKCEFContextsSnapshot())
      if (context->IsSharingWith(browser->GetHost()->GetRequestContext())) { known = true; break; }
    if (!known) { browser->GetHost()->CloseBrowser(true); return; }
    if (closingAll) { browser->GetHost()->CloseBrowser(true); return; }
    Ready(browser, 0);
  }
  void Ready(CefRefPtr<CefBrowser> browser, int attempt) {
    if (!windows.contains(browser->GetIdentifier())) return;
    NSWindow *window = NativeWindow(browser);
    if (!window) {
      if (attempt >= 200 || closingAll) { browser->GetHost()->CloseBrowser(true); return; }
      CefRefPtr<ToolClient> keepAlive = this;
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        keepAlive->Ready(browser, attempt + 1);
      });
      return;
    }
    // Never visible, even if Chromium later shows or activates it: transparent, click-through, far off
    // screen, and left out of the Window menu, ⌘` and Mission Control.
    window.alphaValue = 0;
    window.ignoresMouseEvents = YES;
    window.excludedFromWindowsMenu = YES;
    window.collectionBehavior = NSWindowCollectionBehaviorTransient | NSWindowCollectionBehaviorIgnoresCycle;
    [window setFrameOrigin:NSMakePoint(-100000, -100000)];
    [window orderOut:nil];
    if (!proxies) proxies = [NSMutableDictionary dictionary];
    IKCEFPage *proxy = [[IKCEFPage alloc] initContainer];
    proxy->_browser = browser;
    proxy->_registration = browser->GetHost()->AddDevToolsMessageObserver(new Observer(proxy));
    proxies[@(browser->GetIdentifier())] = proxy;
    if (closingAll) browser->GetHost()->CloseBrowser(true);
  }
  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    IKCEFPage *proxy = proxies[@(browser->GetIdentifier())];
    if (proxy) {
      [proxy invalidateRequests:@"The native tool closed."];
      proxy->_registration = nullptr; proxy->_browser = nullptr; proxy->_closing = YES;
      [proxies removeObjectForKey:@(browser->GetIdentifier())];
    }
    windows.erase(browser->GetIdentifier()); IKCEFTrackBrowser(-1);
  }
  bool OnRequestMediaAccessPermission(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>,
      const CefString&, uint32_t, CefRefPtr<CefMediaAccessCallback> callback) override {
    callback->Cancel(); return true;
  }
 private:
  ~ToolClient() override {
    if (pending_) {
      if (NSThread.isMainThread) IKCEFTrackBrowser(-1);
      else dispatch_async(dispatch_get_main_queue(), ^{ IKCEFTrackBrowser(-1); });
    }
  }
  bool pending_ = true;
  bool owned_;
  IMPLEMENT_REFCOUNTING(ToolClient);
};
NSNumber *Open(NSString *profile, const char *url, NSError **error) {
  closingAll = false;
  auto context = IKCEFContext(profile);
  if (!context || context->GetCachePath().empty()) {
    if (error) *error = IKCEFError(@"Native extension/security tools require a prepared non-private Space.");
    return nil;
  }
  CefWindowInfo window;
  window.runtime_style = CEF_RUNTIME_STYLE_CHROME;
  window.bounds = CefRect(120, 120, 1000, 760);
  window.hidden = true;
  CefBrowserSettings settings;
  const int token = ++nextToken;
  if (!CefBrowserHost::CreateBrowser(window, new ToolClient(true), url, settings, nullptr, context)) {
    if (error) *error = IKCEFError(@"CEF could not open its native management window.");
    return nil;
  }
  return @(token);
}
}
CefRefPtr<CefClient> IKCEFMakeToolClient() { return new ToolClient(false); }
@implementation IKCEFNativeTools
+ (NSWindow *)windowForBrowser:(NSInteger)identifier {
  auto found = windows.find(int(identifier)); return found == windows.end() ? nil : NativeWindow(found->second);
}
+ (void)setForeignPageHandler:(void (^)(NSURL *))handler { foreignPageHandler = [handler copy]; }
+ (void)setNextFolderSelection:(NSString *)path { nextFolder = [path copy]; }
+ (void)closeBrowser:(NSInteger)identifier {
  auto found = windows.find(int(identifier));
  if (found != windows.end()) found->second->GetHost()->CloseBrowser(true);
}
+ (NSNumber *)openExtensionsForProfile:(NSString *)profile error:(NSError **)error { return Open(profile, "chrome://extensions/", error); }
+ (NSNumber *)openSecurityForProfile:(NSString *)profile error:(NSError **)error { return Open(profile, "chrome://settings/security", error); }
+ (NSNumber *)openExtensionResource:(NSString *)identifier path:(NSString *)path profile:(NSString *)profile error:(NSError **)error {
  NSString *url = [NSString stringWithFormat:@"chrome-extension://%@/%@", identifier, path];
  return Open(profile, url.UTF8String, error);
}
+ (NSNumber *)openPage:(NSURL *)url profile:(NSString *)profile error:(NSError **)error {
  if (![@[@"http", @"https"] containsObject:url.scheme.lowercaseString] || url.user || url.password) {
    if (error) *error = IKCEFError(@"Only normal web pages can open in the native extension window.");
    return nil;
  }
  return Open(profile, url.absoluteString.UTF8String, error);
}
+ (NSArray<NSDictionary *> *)windows {
  NSMutableArray *result = [NSMutableArray array];
  for (auto [id, browser] : windows) [result addObject:Snapshot(browser)];
  return result;
}
+ (IKCEFPage *)hiddenPageForWindow:(NSInteger)identifier { return proxies[@(identifier)]; }
+ (void)closeAll {
  closingAll = true;
  auto snapshot = windows;
  for (auto [_, browser] : snapshot) browser->GetHost()->CloseBrowser(true);
}
@end
