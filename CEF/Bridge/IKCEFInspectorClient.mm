#import "IKCEFPageInternal.h"
#import "IKCEFRuntimeInternal.h"

namespace {
/// DevTools has its own client. Reusing a page client would overwrite the tab's
/// browser handle and emit inspector navigation as ordinary tab events.
class InspectorClient final : public CefClient, public CefLifeSpanHandler {
 public:
  explicit InspectorClient(IKCEFPage *page) : page_(page) { IKCEFTrackBrowser(1); }
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    IKCEFPage *page = page_;
    if (!page || page.isClosed || !page->_developerTools) { browser->GetHost()->CloseBrowser(true); return; }
    announceWindow(browser, 0);
  }
  void OnBeforeClose(CefRefPtr<CefBrowser>) override {
    IKCEFPage *page = page_;
    if (page.devToolsWindowHandler) page.devToolsWindowHandler(nil);
    releaseLifetime();
  }
 private:
  ~InspectorClient() override { releaseLifetime(); }
  // Chromium creates the native window slightly after the browser.
  void announceWindow(CefRefPtr<CefBrowser> browser, int attempt) {
    NSWindow *window = [(__bridge NSView *)browser->GetHost()->GetWindowHandle() window];
    IKCEFPage *page = page_;
    if (!page) return;
    if (window) {
      // Chromium ignores the hidden flag for DevTools, so take it off screen before anything draws.
      [window orderOut:nil];
      if (page.devToolsWindowHandler) page.devToolsWindowHandler(window);
      return;
    }
    if (attempt >= 200) return;
    CefRefPtr<InspectorClient> keepAlive = this;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
      keepAlive->announceWindow(browser, attempt + 1);
    });
  }
  void releaseLifetime() {
    if (!tracked_) return;
    tracked_ = false;
    if (NSThread.isMainThread) IKCEFTrackBrowser(-1);
    else dispatch_async(dispatch_get_main_queue(), ^{ IKCEFTrackBrowser(-1); });
  }
  __weak IKCEFPage *page_;
  bool tracked_ = true;
  IMPLEMENT_REFCOUNTING(InspectorClient);
};
}
CefRefPtr<CefClient> IKCEFMakeInspectorClient(IKCEFPage *page) { return new InspectorClient(page); }
