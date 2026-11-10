#import "IKCEFDownloads.h"
#import "IKCEFPageInternal.h"
#include "include/cef_download_handler.h"
#include "include/cef_download_item.h"

@implementation IKCEFDownloads
+ (instancetype)shared {
  static IKCEFDownloads *instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ instance = [IKCEFDownloads new]; });
  return instance;
}
@end
namespace {
NSString *Identifier(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item) {
  return [NSString stringWithFormat:@"%d:%u", browser->GetIdentifier(), item->GetId()];
}
}
bool IKCEFBeforeDownload(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item,
    const CefString& suggested, CefRefPtr<CefBeforeDownloadCallback> callback,
    void (^gate)(NSString *, NSString *, void (^)(BOOL))) {
  auto handler = IKCEFDownloads.shared.destinationHandler;
  if (!handler) return true;
  // The item is only valid during this call, and the gate may answer much later.
  NSString *identifier = Identifier(browser, item), *name = IKCEFString(suggested), *url = IKCEFString(item->GetOriginalUrl());
  BOOL ephemeral = browser->GetHost()->GetRequestContext()->GetCachePath().empty();
  void (^proceed)(void) = ^{
    NSString *path = handler(identifier, name, url, ephemeral);
    if (path.length && path.isAbsolutePath) callback->Continue(path.UTF8String, false);
  };
  if (!gate) { proceed(); return true; }
  // A callback released without Continue cancels the download, so denying needs nothing more.
  gate(IKCEFString(browser->GetMainFrame()->GetURL()), url, ^(BOOL allowed) { if (allowed) proceed(); });
  return true;
}
void IKCEFDownloadUpdated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item,
    CefRefPtr<CefDownloadItemCallback> callback) {
  auto handler = IKCEFDownloads.shared.eventHandler;
  if (!handler || !item->IsValid()) return;
  NSDictionary *snapshot = @{@"id": Identifier(browser, item), @"url": IKCEFString(item->GetOriginalUrl()),
    @"path": IKCEFString(item->GetFullPath()), @"received": @(item->GetReceivedBytes()),
    @"total": @(item->GetTotalBytes()), @"complete": @(item->IsComplete()),
    @"cancelled": @(item->IsCanceled()), @"interrupted": @(item->IsInterrupted()),
    @"reason": @(item->GetInterruptReason())};
  handler(snapshot, ^{ callback->Cancel(); });
}
