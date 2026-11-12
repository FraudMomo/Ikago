#import "IKCEFPageInternal.h"
#include "include/cef_jsdialog_handler.h"

namespace {
/// Browser-owned native sheets: CEF must never create a Chromium dialog window.
class Dialogs final : public CefJSDialogHandler {
 public:
  explicit Dialogs(IKCEFPage *page) : page_(page) {}
  bool OnJSDialog(CefRefPtr<CefBrowser>, const CefString& origin,
      JSDialogType type, const CefString& message, const CefString& input,
      CefRefPtr<CefJSDialogCallback> callback, bool& suppress) override {
    IKCEFPage *page = page_;
    if (!page || page.isClosed || !page.window || pending_ || ++count_ > 3 ||
        NSProcessInfo.processInfo.environment[@"IKAGO_TEST_MODE"]) {
      suppress = true;
      return false;
    }
    NSString *host = [NSURL URLWithString:IKCEFString(origin)].host ?: @"This page";
    NSAlert *alert = [NSAlert new];
    alert.messageText = host;
    alert.informativeText = [IKCEFString(message) substringToIndex:MIN((NSUInteger)4096, IKCEFString(message).length)];
    alert.icon = [NSImage imageWithSystemSymbolName:@"text.bubble" accessibilityDescription:nil];
    [alert addButtonWithTitle:@"OK"];
    if (type != JSDIALOGTYPE_ALERT) [alert addButtonWithTitle:@"Cancel"];
    NSTextField *field = nil;
    if (type == JSDIALOGTYPE_PROMPT) {
      field = [NSTextField textFieldWithString:IKCEFString(input)];
      field.frame = NSMakeRect(0, 0, 300, 24);
      alert.accessoryView = field;
    }
    pending_ = callback;
    sheet_ = alert.window;
    CefRefPtr<Dialogs> retained = this;
    [alert beginSheetModalForWindow:page.window completionHandler:^(NSModalResponse result) {
      if (!retained->pending_) return;
      auto reply = retained->pending_;
      retained->pending_ = nullptr;
      retained->sheet_ = nil;
      reply->Continue(result == NSAlertFirstButtonReturn,
                      field ? CefString(field.stringValue.UTF8String) : CefString());
    }];
    return true;
  }
  bool OnBeforeUnloadDialog(CefRefPtr<CefBrowser> browser, const CefString& message, bool,
      CefRefPtr<CefJSDialogCallback> callback) override {
    bool suppress = false;
    const auto origin = browser->GetMainFrame()->GetURL();
    if (!OnJSDialog(browser, origin, JSDIALOGTYPE_CONFIRM, message, CefString(), callback, suppress))
      callback->Continue(false, CefString());
    return true;
  }
  void OnResetDialogState(CefRefPtr<CefBrowser>) override {
    count_ = 0;
    if (pending_) { auto reply = pending_; pending_ = nullptr; reply->Continue(false, CefString()); }
    if (sheet_.sheetParent) [sheet_.sheetParent endSheet:sheet_ returnCode:NSModalResponseCancel];
    sheet_ = nil;
  }
 private:
  __weak IKCEFPage *page_;
  __weak NSWindow *sheet_;
  int count_ = 0;
  CefRefPtr<CefJSDialogCallback> pending_;
  IMPLEMENT_REFCOUNTING(Dialogs);
};
}
CefRefPtr<CefJSDialogHandler> IKCEFMakeDialogs(IKCEFPage *page) { return new Dialogs(page); }
