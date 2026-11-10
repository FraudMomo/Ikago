#import "IKCEFPage.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_request_context.h"
#include "include/cef_download_handler.h"
#include "include/cef_context_menu_handler.h"

CefRefPtr<CefRequestContext> IKCEFContext(NSString *profile);
NSString *IKCEFString(const CefString& value);
NSError *IKCEFError(NSString *message);

@interface IKCEFPage () {
 @public
  CefRefPtr<CefBrowser> _browser;
  CefRefPtr<CefClient> _client;
  CefRefPtr<CefRegistration> _registration;
  NSMutableDictionary<NSNumber *, id> *_pending;
  /// Requests a navigation doesn't cancel (the document-start script registration).
  NSMutableSet<NSNumber *> *_survivors;
  int _nextMessage;
  BOOL _closing;
  BOOL _developerTools;
  NSString *_queuedURL;
  BOOL _registeringScript;
  NSString *_lastFind;
  NSString *_approvedFilePath;
  CGFloat _topInset;
  NSMutableDictionary<NSNumber *, IKCEFPage *> *_pendingPopups;
  NSMutableArray<IKCEFMediaRequest *> *_mediaRequests;
  BOOL _captureBlocked;
}
- (instancetype)initContainer;
- (void)emit:(NSString *)name payload:(NSDictionary *)payload;
- (void)attached:(CefRefPtr<CefBrowser>)browser;
@end
@interface IKCEFMediaRequest (Internal)
- (instancetype)initWithOrigin:(NSString *)origin permissions:(uint32_t)permissions callback:(CefRefPtr<CefMediaAccessCallback>)callback;
- (void)cancel;
@end
@interface IKCEFPage (DevToolsInternal)
- (void)devToolsMethod:(NSString *)method parameters:(NSDictionary *)parameters survivingNavigation:(BOOL)survives
            completion:(void (^)(NSDictionary *, NSError *))completion;
- (void)invalidateRequests:(NSString *)reason;
- (void)methodResult:(int)identifier success:(BOOL)success data:(NSData *)data;
@end

CefRefPtr<CefClient> IKCEFMakeClient(IKCEFPage *page);
CefRefPtr<CefClient> IKCEFMakeInspectorClient(IKCEFPage *page);

/// `gate` may be nil: the download then proceeds without asking.
bool IKCEFBeforeDownload(CefRefPtr<CefBrowser>, CefRefPtr<CefDownloadItem>, const CefString&, CefRefPtr<CefBeforeDownloadCallback>,
    void (^gate)(NSString *, NSString *, void (^)(BOOL)));
void IKCEFDownloadUpdated(CefRefPtr<CefBrowser>, CefRefPtr<CefDownloadItem>, CefRefPtr<CefDownloadItemCallback>);

CefRefPtr<CefContextMenuHandler> IKCEFMakeContextMenu(IKCEFPage *page);
