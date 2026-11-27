#import "IKCEFPageInternal.h"
#import "IKCEFRuntimeInternal.h"
#include "include/cef_parser.h"
#include <os/log.h>

namespace {
class PDFCallback : public CefPdfPrintCallback {
 public:
  explicit PDFCallback(void (^completion)(BOOL)) : completion_([completion copy]) {}
  void OnPdfPrintFinished(const CefString&, bool ok) override {
    void (^completion)(BOOL) = completion_;
    dispatch_async(dispatch_get_main_queue(), ^{ completion(ok); });
  }
 private:
  void (^completion_)(BOOL);
  IMPLEMENT_REFCOUNTING(PDFCallback);
};
}

namespace {
// CreateBrowser hands Chromium this view as the parent of the browser's own view, unretained, and builds that view
// later, after a queue of other tabs when many open at once. A tab closed in that gap must not free the parent under
// Chromium (0.7.x crash: open 30 background tabs, show one and close it at once). Pages stay here from creation until
// Chromium attaches the browser, or, when the tab already closed, until the browser is gone. Main thread only.
NSMutableSet<IKCEFPage *> *IKCEFUnsettledPages() {
  static NSMutableSet<IKCEFPage *> *pages = [NSMutableSet set];
  return pages;
}
}

@implementation IKCEFPage
@synthesize topInset = _topInset;
- (void)setTopInset:(CGFloat)inset {
  _topInset = MAX(0, inset);
  self.needsLayout = YES;
}
- (void)layout {
  [super layout];
  if (!self.ready) return;
  NSView *child = (__bridge NSView *)_browser->GetHost()->GetWindowHandle();
  child.frame = NSMakeRect(0, 0, self.bounds.size.width, MAX(0, self.bounds.size.height - _topInset));
}
- (instancetype)initContainer {
  if ((self = [super initWithFrame:NSMakeRect(0, 0, 800, 600)])) {
    _pending = [NSMutableDictionary dictionary];
    _pendingPopups = [NSMutableDictionary dictionary];
    _mediaRequests = [NSMutableArray array];
    _permissionPrompts = [NSMutableArray array];
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  }
  return self;
}
+ (instancetype)pageWithProfile:(NSString *)profile error:(NSError **)error {
  NSParameterAssert(NSThread.isMainThread);
  auto context = IKCEFContext(profile);
  if (!context) {
    if (error) *error = IKCEFError(@"Prepare the Space's CEF context before creating its pages.");
    return nil;
  }
  IKCEFPage *page = [[self alloc] initContainer];
  CefWindowInfo window;
  window.SetAsChild((__bridge CefWindowHandle)page, CefRect(0, 0, 800, 600));
  window.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
  CefBrowserSettings settings;
  settings.javascript_close_windows = STATE_DISABLED;
  settings.javascript_access_clipboard = STATE_DISABLED;
  settings.javascript_dom_paste = STATE_DISABLED;
  auto client = IKCEFMakeClient(page);
  page->_client = client;
  IKCEFTrackBrowser(1);
  if (!CefBrowserHost::CreateBrowser(window, client, "about:blank", settings, nullptr, context)) {
    IKCEFTrackBrowser(-1);
    if (error) *error = IKCEFError(@"CEF rejected browser creation.");
    return nil;
  }
  [IKCEFUnsettledPages() addObject:page];
  return page;
}
- (void)attached:(CefRefPtr<CefBrowser>)browser {
  _browser = browser;
  if (_closing) { browser->GetHost()->CloseBrowser(true); return; }  // kept until browserClosed
  [IKCEFUnsettledPages() removeObject:self];
  NSView *child = (__bridge NSView *)browser->GetHost()->GetWindowHandle();
  child.frame = self.bounds;
  child.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.needsLayout = YES;
  [self emit:@"ready" payload:@{}];
  if (self.documentStartScript.length) {
    // Registered before the first real navigation and only then navigating, so the registration is part of the
    // tab's DevTools state when Chromium swaps processes, and runs before the page's own scripts. Page domain only.
    NSString *script = self.documentStartScript;
    __weak IKCEFPage *weakSelf = self;
    _registeringScript = YES;
    [self devToolsMethod:@"Page.enable" parameters:@{} completion:^(NSDictionary *, NSError *) {}];
    // A navigation event (the blank start page's own) must not cancel this, or the page would load before it.
    [self devToolsMethod:@"Page.addScriptToEvaluateOnNewDocument" parameters:@{@"source": script} survivingNavigation:YES
              completion:^(NSDictionary *, NSError *error) {
      static os_log_t log = os_log_create("app.ikago.browser", "media-translation");
      if (error) os_log_error(log, "document-start script not registered: %{public}@", error.localizedDescription);
      else os_log_info(log, "document-start script registered");
      IKCEFPage *page = weakSelf;
      if (!page) return;
      page->_registeringScript = NO;
      [page loadQueuedURL];
    }];
    // Never keep a tab blank for long: without an answer, load anyway (the page then plays video natively).
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
      IKCEFPage *page = weakSelf;
      if (!page || !page->_registeringScript) return;
      page->_registeringScript = NO;
      [page loadQueuedURL];
    });
    return;
  }
  [self loadQueuedURL];
}
- (void)browserClosed { [IKCEFUnsettledPages() removeObject:self]; }
- (void)holdUntilSettled { [IKCEFUnsettledPages() addObject:self]; }
- (void)loadQueuedURL {
  if (_queuedURL) { NSString *url = _queuedURL; _queuedURL = nil; [self loadURL:url]; }
}
- (BOOL)ready { return _browser && !_closing; }
- (BOOL)isClosed { return _closing; }
- (BOOL)canGoBack { return self.ready && _browser->CanGoBack(); }
- (BOOL)canGoForward { return self.ready && _browser->CanGoForward(); }
- (BOOL)loading { return self.ready && _browser->IsLoading(); }
- (BOOL)audioMuted { return self.ready && _browser->GetHost()->IsAudioMuted(); }
- (void)setAudioMuted:(BOOL)value {
  if (!self.ready) return;
  _browser->GetHost()->SetAudioMuted(value);
}
- (double)zoomLevel { return self.ready ? _browser->GetHost()->GetZoomLevel() : 0; }
- (void)setZoomLevel:(double)value { if (self.ready) _browser->GetHost()->SetZoomLevel(value); }
- (void)loadURL:(NSString *)url {
  if (_closing) return;
  _captureBlocked = NO;
  if (!self.ready || _registeringScript) { _queuedURL = [url copy]; return; }
  NSURL *target = [NSURL URLWithString:url];
  _approvedFilePath = target.isFileURL && !target.user && !target.password && !target.port &&
      (!target.host.length || [target.host.lowercaseString isEqual:@"localhost"]) ?
      target.URLByStandardizingPath.path : nil;
  [self invalidateRequests:@"The page navigated."];
  _browser->GetMainFrame()->LoadURL(url.UTF8String);
}
- (void)goBack { if (self.canGoBack) _browser->GoBack(); }
- (void)goForward { if (self.canGoForward) _browser->GoForward(); }
- (void)reloadIgnoringCache:(BOOL)ignore {
  if (!self.ready) return;
  _captureBlocked = NO;
  if (ignore) _browser->ReloadIgnoreCache(); else _browser->Reload();
}
- (void)stopLoading { if (self.ready) _browser->StopLoad(); }
- (void)focusPage { if (self.ready) _browser->GetHost()->SetFocus(true); }
- (void)findText:(NSString *)text forward:(BOOL)forward matchCase:(BOOL)matchCase {
  if (!self.ready) return;
  // The same text and options steps to the next match; anything else starts a new search.
  BOOL next = [_lastFind isEqualToString:text] && _lastFindMatchCase == matchCase;
  _lastFind = [text copy];
  _lastFindMatchCase = matchCase;
  _browser->GetHost()->Find(text.UTF8String, forward, matchCase, next);
}
- (void)clearFind {
  _lastFind = nil;
  if (self.ready) _browser->GetHost()->StopFinding(true);
}
- (void)printPage { if (self.ready) _browser->GetHost()->Print(); }
- (void)savePDFToPath:(NSString *)path completion:(void (^)(BOOL))completion {
  if (!self.ready) return completion(NO);
  CefPdfPrintSettings settings;
  settings.print_background = true;
  settings.generate_tagged_pdf = true;
  _browser->GetHost()->PrintToPDF(path.UTF8String, settings, new PDFCallback(completion));
}
- (void)saveLongPDFToPath:(NSString *)path inches:(CGSize)inches completion:(void (^)(BOOL))completion {
  if (!self.ready || inches.width <= 0 || inches.height <= 0) return completion(NO);
  CefPdfPrintSettings settings;
  settings.print_background = true;
  settings.paper_width = inches.width;
  settings.paper_height = inches.height;
  settings.margin_type = PDF_PRINT_MARGIN_NONE;
  settings.prefer_css_page_size = false;
  _browser->GetHost()->PrintToPDF(path.UTF8String, settings, new PDFCallback(completion));
}
- (void)exitFullscreen { if (self.ready) _browser->GetHost()->ExitFullscreen(true); }
- (void)refitPage {
  if (!self.ready) return;
  NSView *child = (__bridge NSView *)_browser->GetHost()->GetWindowHandle();
  NSRect frame = NSMakeRect(0, 0, self.bounds.size.width, MAX(0, self.bounds.size.height - _topInset));
  // One point shorter, then the real size: Chromium sees a fresh resize and lays out and paints for it.
  child.frame = NSMakeRect(0, 0, frame.size.width, MAX(0, frame.size.height - 1));
  child.frame = frame;
  _browser->GetHost()->NotifyScreenInfoChanged();
}
- (void)stopCaptureAndReload {
  if (!self.ready) return;
  _captureBlocked = YES;
  [self invalidateRequests:@"Capture was stopped."];
  _browser->Reload();
}
- (void)emit:(NSString *)name payload:(NSDictionary *)payload {
  if (self.eventHandler) self.eventHandler(name, payload);
}
- (void)closePage {
  if (_closing) return;
  _closing = YES;
  _queuedURL = nil;
  [self invalidateRequests:@"The page has closed."];
  if (_browser) {
    _browser->GetHost()->CloseDevTools();
    _browser->GetHost()->CloseBrowser(true);
  }
}
- (void)dealloc {
  // Browser close is asynchronous; the client uses a weak page reference.
  if (_browser && !_closing) _browser->GetHost()->CloseBrowser(true);
}
@end
