#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
NS_SWIFT_UI_ACTOR
@interface IKCEFMediaRequest : NSObject
@property(nonatomic, readonly) NSString *origin;
@property(nonatomic, readonly) BOOL camera;
@property(nonatomic, readonly) BOOL microphone;
@property(nonatomic, readonly) BOOL resolved;
@property(nonatomic, copy, nullable) void (^cancellationHandler)(void);
- (void)resolve:(BOOL)allow;
@end
/// Embedded, native-view CEF page. All methods and callbacks use the main thread.
NS_SWIFT_UI_ACTOR
@interface IKCEFPage : NSView
@property(nonatomic, copy, nullable) void (^eventHandler)(NSString *, NSDictionary *);
@property(nonatomic, copy, nullable) void (^externalLinkHandler)(NSURL *, NSString *);
@property(nonatomic, copy, nullable) BOOL (^popupHandler)(IKCEFPage *, NSString *, BOOL);
@property(nonatomic, copy, nullable) BOOL (^navigationHandler)(NSURL *, NSString *method);
/// A link the person asked to open in a new tab (⌘-click, middle-click): the URL and whether it stays in the background.
@property(nonatomic, copy, nullable) void (^newTabHandler)(NSURL *, BOOL background);
@property(nonatomic, copy, nullable) void (^mediaPermissionHandler)(IKCEFMediaRequest *);
/// Asked before a download starts: page URL, file URL, and a reply. No reply means no download.
@property(nonatomic, copy, nullable) void (^downloadGateHandler)(NSString *, NSString *, void (^)(BOOL));
/// Receives the hidden DevTools window once it exists, and nil when it closes.
@property(nonatomic, copy, nullable) void (^devToolsWindowHandler)(NSWindow *_Nullable);
@property(nonatomic, readonly) BOOL ready;
@property(nonatomic, readonly, getter=isClosed) BOOL closed;
@property(nonatomic, readonly) BOOL canGoBack;
@property(nonatomic, readonly) BOOL canGoForward;
@property(nonatomic, readonly) BOOL loading;
@property(nonatomic) BOOL audioMuted;
/// CEF's identifier for this page's browser (IKCEFAudio levels); 0 before it attaches.
@property(nonatomic, readonly) int browserIdentifier;
@property(nonatomic) double zoomLevel;
@property(nonatomic) CGFloat topInset;
/// Runs in the main world of every new document before the page's own scripts. Set before the page attaches.
@property(nonatomic, copy, nullable) NSString *documentStartScript;
- (instancetype)initWithFrame:(NSRect)frame NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
/// Fails unless the named context is already prepared. Never falls back to default.
+ (nullable instancetype)pageWithProfile:(NSString *)profile error:(NSError **)error NS_SWIFT_NAME(make(profile:));
- (void)loadURL:(NSString *)url;
- (void)goBack;
- (void)goForward;
- (void)reloadIgnoringCache:(BOOL)ignoreCache;
- (void)stopLoading;
- (void)focusPage;
- (void)findText:(NSString *)text forward:(BOOL)forward matchCase:(BOOL)matchCase;
- (void)clearFind;
- (void)printPage NS_SWIFT_NAME(printPage());
/// Leaves element fullscreen, as if the page had asked (Escape, or the window left full screen).
- (void)exitFullscreen;
/// Fits the page to its view again after a big, animated size change (full screen): Chromium can keep drawing the
/// size it saw mid-change, cutting off the top, until its view's size changes once more.
- (void)refitPage;
/// Ends all streams by reloading, blocking further capture until explicit navigation/reload.
- (void)stopCaptureAndReload;
/// Cancels all requests on navigation, process death and close.
- (void)closePage;
@end
@interface IKCEFPage (DeveloperTools)
@property(nonatomic, readonly) BOOL devToolsVisible;
- (void)setDeveloperToolsEnabled:(BOOL)enabled;
- (void)toggleDevTools;
- (void)inspectAtPoint:(NSPoint)point;
@end
@interface IKCEFPage (DevTools)
/// Raw CDP stays at the browser boundary; Swift builds isolated-world operations.
- (void)devToolsMethod:(NSString *)method parameters:(NSDictionary *)parameters
           completion:(void (^)(NSDictionary *_Nullable, NSError *_Nullable))completion;
@end
NS_ASSUME_NONNULL_END
