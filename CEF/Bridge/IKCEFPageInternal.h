#import "IKCEFPage.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_request_context.h"
#include "include/cef_download_handler.h"
#include "include/cef_context_menu_handler.h"
#include "include/cef_jsdialog_handler.h"

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
  BOOL _lastFindMatchCase;
  NSString *_approvedFilePath;
  CGFloat _topInset;
  NSMutableDictionary<NSNumber *, IKCEFPage *> *_pendingPopups;
  NSMutableArray<IKCEFMediaRequest *> *_mediaRequests;
  NSMutableArray<IKCEFPermissionPrompt *> *_permissionPrompts;
  BOOL _captureBlocked;
  /// A download the person asked for from the page menu, which needs no site permission.
  NSString *_requestedDownload;
}
- (instancetype)initContainer;
- (void)emit:(NSString *)name payload:(NSDictionary *)payload;
- (void)attached:(CefRefPtr<CefBrowser>)browser;
/// Chromium has destroyed the browser; the bridge stops keeping the page alive for it.
- (void)browserClosed;
/// Keeps a page Chromium will parent a browser to alive until `attached:` or `browserClosed` (popups use it too: their
/// opener may close, and its `_pendingPopups` with it, before Chromium builds the popup's view).
- (void)holdUntilSettled;
@end
@interface IKCEFPermissionPrompt (Internal)
- (instancetype)initWithOrigin:(NSString *)origin promptID:(uint64_t)promptID permissions:(uint32_t)permissions
                      callback:(CefRefPtr<CefPermissionPromptCallback>)callback;
@property(nonatomic, readonly) uint64_t promptID;
/// Denies (if still open) and tells the handler it is gone.
- (void)cancel;
/// Chromium dismissed it: its callback is no longer used.
- (void)abandon;
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

CefRefPtr<CefJSDialogHandler> IKCEFMakeDialogs(IKCEFPage *page);
