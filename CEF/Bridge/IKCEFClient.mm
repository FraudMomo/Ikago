#import "IKCEFPageInternal.h"
#import "IKCEFRuntimeInternal.h"
#import "IKCEFAudioInternal.h"
#include "include/cef_parser.h"
#include "include/cef_navigation_entry.h"
#include "include/cef_ssl_status.h"
#include "include/cef_ssl_info.h"

NSString *IKCEFString(const CefString& value) {
  return [NSString stringWithUTF8String:value.ToString().c_str()] ?: @"";
}
NSError *IKCEFError(NSString *message) {
  return [NSError errorWithDomain:@"Ikago.CEF" code:1
      userInfo:@{NSLocalizedDescriptionKey: message}];
}

namespace {
class Client final : public CefClient, public CefLifeSpanHandler,
    public CefDisplayHandler, public CefLoadHandler, public CefRequestHandler,
    public CefPermissionHandler, public CefFindHandler, public CefDownloadHandler,
    public CefDevToolsMessageObserver {
 public:
  explicit Client(IKCEFPage *page) : page_(page) {}
  Client(IKCEFPage *page, IKCEFPage *opener, int popup) : page_(page), opener_(opener), popup_(popup) {}
  CefRefPtr<CefContextMenuHandler> GetContextMenuHandler() override { return IKCEFMakeContextMenu(page_); }
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }
  CefRefPtr<CefFindHandler> GetFindHandler() override { return this; }
  CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
  // Ikago plays the page's sound itself, so the media island can show its real wave (IKCEFAudio).
  CefRefPtr<CefAudioHandler> GetAudioHandler() override {
    static CefRefPtr<CefAudioHandler> audio = IKCEFMakeAudioHandler();
    return audio;
  }
  bool OnBeforeDownload(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item,
      const CefString& name, CefRefPtr<CefBeforeDownloadCallback> callback) override {
    IKCEFPage *page = page_;
    return IKCEFBeforeDownload(browser, item, name, callback, page.downloadGateHandler);
  }
  void OnDownloadUpdated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item,
      CefRefPtr<CefDownloadItemCallback> callback) override { IKCEFDownloadUpdated(browser, item, callback); }
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    IKCEFPage *page = page_;
    if (!page) { browser->GetHost()->CloseBrowser(true); return; }
    page->_client = this;
    page->_registration = browser->GetHost()->AddDevToolsMessageObserver(this);
    [page attached:browser];
    IKCEFPage *opener = opener_;
    if (opener) [opener->_pendingPopups removeObjectForKey:@(popup_)];
  }
  bool DoClose(CefRefPtr<CefBrowser> browser) override {
    // This browser is a tab, not the top-level SwiftUI window. Destroy its
    // native child view instead of forwarding performClose: to that window.
    NSView *child = (__bridge NSView *)browser->GetHost()->GetWindowHandle();
    [child removeFromSuperview];
    return true;
  }
  void OnBeforeClose(CefRefPtr<CefBrowser>) override {
    IKCEFTrackBrowser(-1);
    IKCEFPage *page = page_;
    if (!page) return;
    [page invalidateRequests:@"The page has closed."];
    page->_registration = nullptr;
    page->_browser = nullptr;
    page->_client = nullptr;
    page->_closing = YES;
    [page emit:@"closed" payload:@{}];
  }
  bool OnBeforePopup(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, int popup,
      const CefString& url, const CefString&, WindowOpenDisposition disposition, bool gesture,
      const CefPopupFeatures&, CefWindowInfo& window, CefRefPtr<CefClient>& client,
      CefBrowserSettings&, CefRefPtr<CefDictionaryValue>&, bool*) override {
    IKCEFPage *opener = page_;
    if (!gesture || !opener.popupHandler || opener.isClosed) return true;
    IKCEFPage *child = [[IKCEFPage alloc] initContainer];
    if (!opener.popupHandler(child, IKCEFString(url), disposition == CEF_WOD_NEW_BACKGROUND_TAB)) return true;
    client = new Client(child, opener, popup);
    child->_client = client;
    window.SetAsChild((__bridge CefWindowHandle)child, CefRect(0, 0, 800, 600));
    window.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
    opener->_pendingPopups[@(popup)] = child;
    IKCEFTrackBrowser(1);
    return false;
  }
  void OnBeforePopupAborted(CefRefPtr<CefBrowser>, int popup) override {
    IKCEFPage *opener = page_;
    IKCEFPage *child = opener ? opener->_pendingPopups[@(popup)] : nil;
    if (!child) return;
    [opener->_pendingPopups removeObjectForKey:@(popup)];
    IKCEFTrackBrowser(-1);
    [child closePage];
    [child emit:@"closed" payload:@{}];
  }
  // A page entered or left element fullscreen (a video's fullscreen button); Ikago gives it the screen.
  void OnFullscreenModeChange(CefRefPtr<CefBrowser>, bool fullscreen) override {
    [page_ emit:@"fullscreen" payload:@{@"value": @(fullscreen)}];
  }
  // The address of the link under the pointer (empty when it leaves), for the status bar.
  void OnStatusMessage(CefRefPtr<CefBrowser>, const CefString& value) override {
    [page_ emit:@"status" payload:@{@"value": IKCEFString(value)}];
  }
  void OnTitleChange(CefRefPtr<CefBrowser>, const CefString& title) override {
    [page_ emit:@"title" payload:@{@"value": IKCEFString(title)}];
  }
  void OnAddressChange(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame,
      const CefString& url) override {
    if (frame->IsMain()) [page_ emit:@"url" payload:@{@"value": IKCEFString(url)}];
  }
  void OnFaviconURLChange(CefRefPtr<CefBrowser>, const std::vector<CefString>& urls) override {
    if (!urls.empty()) [page_ emit:@"favicon" payload:@{@"value": IKCEFString(urls.front())}];
  }
  void OnLoadingProgressChange(CefRefPtr<CefBrowser>, double progress) override {
    [page_ emit:@"progress" payload:@{@"value": @(progress)}];
  }
  void OnLoadingStateChange(CefRefPtr<CefBrowser>, bool loading, bool back, bool forward) override {
    [page_ emit:@"loading" payload:@{@"value": @(loading), @"back": @(back), @"forward": @(forward)}];
  }
  void OnLoadStart(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, TransitionType) override {
    if (!frame->IsMain()) return;
    [page_ invalidateRequests:@"The page navigated."];
    [page_ emit:@"commit" payload:@{@"value": IKCEFString(frame->GetURL())}];
  }
  void OnLoadError(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, ErrorCode code,
      const CefString&, const CefString& url) override {
    if (frame->IsMain() && code != ERR_ABORTED)
      [page_ emit:@"failure" payload:@{@"code": @(code), @"url": IKCEFString(url)}];
  }
  void OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, int) override {
    if (!frame->IsMain()) return;
    auto entry = browser->GetHost()->GetVisibleNavigationEntry();
    auto ssl = entry ? entry->GetSSLStatus() : nullptr;
    bool secure = ssl && ssl->IsSecureConnection() && !CefIsCertStatusError(ssl->GetCertStatus()) &&
        ssl->GetContentStatus() == SSL_CONTENT_NORMAL_CONTENT;
    [page_ emit:@"security" payload:@{@"value": @(secure)}];
  }
  // ⌘-click and middle-click arrive here, not in OnBeforePopup. Unhandled, CEF would open the link in this tab.
  bool OnOpenURLFromTab(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, const CefString& target,
      WindowOpenDisposition disposition, bool gesture) override {
    bool newTab = disposition == CEF_WOD_NEW_BACKGROUND_TAB || disposition == CEF_WOD_NEW_FOREGROUND_TAB ||
        disposition == CEF_WOD_NEW_WINDOW;
    IKCEFPage *page = page_;
    NSURL *url = [NSURL URLWithString:IKCEFString(target)];
    NSString *scheme = url.scheme.lowercaseString;
    if (!newTab || !gesture || !page || page.isClosed || !page.newTabHandler ||
        !([scheme isEqual:@"http"] || [scheme isEqual:@"https"])) return false;
    BOOL background = disposition == CEF_WOD_NEW_BACKGROUND_TAB;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!page.isClosed && page.newTabHandler) page.newTabHandler(url, background);
    });
    return true;
  }
  bool OnBeforeBrowse(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame,
      CefRefPtr<CefRequest> request, bool, bool) override {
    if (frame->IsMain()) {
      [page_ invalidateRequests:@"The page is navigating."];
      [page_ emit:@"navigation" payload:@{}];
    }
    NSURL *url = [NSURL URLWithString:IKCEFString(request->GetURL())];
    NSString *scheme = url.scheme.lowercaseString;
    IKCEFPage *owner = page_;
    if (!owner || owner.isClosed) return true;
    if ([scheme isEqual:@"file"])
      return !frame->IsMain() || ![url.URLByStandardizingPath.path isEqual:owner->_approvedFilePath];
    if (frame->IsMain() && ![scheme isEqual:@"about"]) owner->_approvedFilePath = nil;
    if (frame->IsMain() && owner.navigationHandler && !owner.navigationHandler(url, IKCEFString(request->GetMethod()))) return true;
    if ([scheme isEqual:@"http"] || [scheme isEqual:@"https"] ||
        [scheme isEqual:@"about"] || [scheme isEqual:@"chrome-extension"]) return false;
    // Local files, javascript/data and browser privileged schemes are never
    // external app launches. Preserve the complete callback URL only in memory.
    NSSet *blocked = [NSSet setWithArray:@[@"file", @"javascript", @"data", @"chrome", @"devtools", @"ikago"]];
    IKCEFPage *page = page_;
    if (url && frame->IsMain() && ![blocked containsObject:scheme] && page.externalLinkHandler) {
      NSString *host = [NSURL URLWithString:IKCEFString(frame->GetURL())].host ?: @"";
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!page.isClosed && page.externalLinkHandler) page.externalLinkHandler(url, host);
      });
    }
    return true;
  }
  void OnRenderProcessTerminated(CefRefPtr<CefBrowser>, TerminationStatus, int,
      const CefString&) override {
    [page_ invalidateRequests:@"The renderer stopped."];
    [page_ emit:@"crash" payload:@{}];
  }
  bool OnRequestMediaAccessPermission(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame,
      const CefString& origin, uint32_t permissions, CefRefPtr<CefMediaAccessCallback> callback) override {
    IKCEFPage *page = page_;
    constexpr uint32_t devices = CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE | CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE;
    // Cross-origin subframes and screen capture remain denied. CEF still checks
    // secure contexts, Permissions Policy and macOS device authorization.
    NSURL *requestURL = [NSURL URLWithString:IKCEFString(origin)];
    NSURL *top = page && page->_browser ? [NSURL URLWithString:IKCEFString(page->_browser->GetMainFrame()->GetURL())] : nil;
    NSNumber *requestPort = requestURL.port ?: ([requestURL.scheme isEqual:@"https"] ? @443 : @80);
    NSNumber *topPort = top.port ?: ([top.scheme isEqual:@"https"] ? @443 : @80);
    BOOL sameOrigin = top && [requestURL.scheme isEqual:top.scheme] &&
        [requestURL.host isEqual:top.host] && [requestPort isEqual:topPort];
    if (!page || page.isClosed || page->_captureBlocked || !page.mediaPermissionHandler ||
        !frame || !sameOrigin || !permissions || (permissions & ~devices)) { callback->Cancel(); return true; }
    IKCEFMediaRequest *request = [[IKCEFMediaRequest alloc] initWithOrigin:IKCEFString(origin) permissions:permissions callback:callback];
    for (IKCEFMediaRequest *old in [page->_mediaRequests copy])
      if (old.resolved) [page->_mediaRequests removeObject:old];
    [page->_mediaRequests addObject:request];
    page.mediaPermissionHandler(request);
    return true;
  }
  void OnMediaAccessChange(CefRefPtr<CefBrowser>, bool video, bool audio) override {
    [page_ emit:@"capture" payload:@{@"camera": @(video), @"microphone": @(audio)}];
  }
  bool OnShowPermissionPrompt(CefRefPtr<CefBrowser>, uint64_t, const CefString&,
      uint32_t, CefRefPtr<CefPermissionPromptCallback> callback) override {
    callback->Continue(CEF_PERMISSION_RESULT_DENY);
    return true;
  }
  void OnFindResult(CefRefPtr<CefBrowser>, int, int count, const CefRect&, int, bool final) override {
    if (final) [page_ emit:@"find" payload:@{@"found": @(count > 0)}];
  }
  void OnDevToolsMethodResult(CefRefPtr<CefBrowser>, int identifier, bool success,
      const void *result, size_t size) override {
    [page_ methodResult:identifier success:success data:[NSData dataWithBytes:result length:size]];
  }
  void OnDevToolsAgentDetached(CefRefPtr<CefBrowser>) override {
    [page_ invalidateRequests:@"The renderer connection closed."];
  }
 private:
  __weak IKCEFPage *page_;
  __weak IKCEFPage *opener_;
  int popup_ = 0;
  IMPLEMENT_REFCOUNTING(Client);
};
}
CefRefPtr<CefClient> IKCEFMakeClient(IKCEFPage *page) { return new Client(page); }
