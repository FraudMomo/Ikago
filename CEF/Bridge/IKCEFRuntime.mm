#import "IKCEFRuntimeInternal.h"
#import "IKCEFPageInternal.h"
#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_command_line.h"
#include "include/wrapper/cef_library_loader.h"
#include <memory>
CefRefPtr<CefClient> IKCEFMakeToolClient();

namespace {
bool running = false, ready = false, started = false;
NSUInteger browsers = 0;
NSURL *storageRoot;
std::unique_ptr<CefScopedLibraryLoader> loader;
class Application final : public CefApp, public CefBrowserProcessHandler {
 public:
  Application(void (^callback)(void), bool fixture) : callback_([callback copy]), fixture_(fixture) {}
  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }
  void OnRegisterCustomPreferences(cef_preferences_type_t, CefRawPtr<CefPreferenceRegistrar> registrar) override {
    auto value = CefValue::Create();
    value->SetBool(false);
    registrar->AddPreference("ikago.security_initialized", value);
  }
  void OnBeforeCommandLineProcessing(const CefString&, CefRefPtr<CefCommandLine> command) override {
    // Autofill's server lookups send Google a signature of the forms on visited pages, and the
    // omnibox asks Google about AI Mode eligibility. Ikago uses its own omnibox.
    // Memory: Chromium keeps a spare renderer warm for the next site (one idle process), and the
    // optimization guide and page annotations load hints and models into the browser process for
    // Chrome UI Ikago doesn't have. Chromium's omnibox models go unused for the same reason.
    command->AppendSwitchWithValue("disable-features",
        "AutofillServerCommunication,AimServerEligibilityEnabled,AimEnabled,"
        "SpareRendererForSitePerProcess,OptimizationHints,OptimizationHintsFetching,PageContentAnnotations,"
        "OmniboxOnDeviceHeadProviderNonIncognito,OmniboxOnDeviceHeadProviderIncognito,OmniboxOnDeviceTailModel");
    // Fixtures contain no credentials and never read a saved profile. Production
    // retains Chromium's real Keychain-backed encryption and security defaults.
    if (fixture_) {
      command->AppendSwitch("use-mock-keychain");
      command->AppendSwitch("use-fake-device-for-media-stream");
    }
  }
  CefRefPtr<CefClient> GetDefaultClient() override { return IKCEFMakeToolClient(); }
  void OnContextInitialized() override {
    ready = true;
    auto callback = callback_;
    callback_ = nil;
    dispatch_async(dispatch_get_main_queue(), ^{ if (running && callback) callback(); });
  }
 private:
  void (^callback_)(void);
  bool fixture_;
  IMPLEMENT_REFCOUNTING(Application);
};
CefRefPtr<Application> application;
}

@interface IKCEFApplication () <CefAppProtocol>
@property(nonatomic) BOOL handlingSendEvent;
@end
@implementation IKCEFApplication
- (id)targetForAction:(SEL)action to:(id)target from:(id)sender {
  id resolved = [super targetForAction:action to:target from:sender];
  if (target || resolved) return resolved;
  NSResponder *fallback = self.browserCommandTarget;
  if (fallback && [fallback respondsToSelector:action] && self.keyWindow &&
      self.browserCommandWindowMatcher && self.browserCommandWindowMatcher(self.keyWindow)) return fallback;
  return nil;
}
- (BOOL)isHandlingSendEvent { return self.handlingSendEvent; }
- (void)sendEvent:(NSEvent *)event {
  CefScopedSendingEvent sending;
  [super sendEvent:event];
}
- (void)terminate:(id)sender {
  if (!running) { [super terminate:sender]; return; }
  id delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(cefApplicationRequestsQuit)])
    [(id<IKCEFApplicationDelegate>)delegate cefApplicationRequestsQuit];
}
@end

BOOL IKCEFCanCreateContext(NSURL *root) {
  return running && ready && [root.URLByStandardizingPath isEqual:storageRoot];
}
void IKCEFTrackBrowser(int delta) {
  NSCAssert(NSThread.isMainThread, @"CEF lifetime requires main thread");
  if (delta > 0) browsers += delta;
  else { NSCAssert(browsers >= NSUInteger(-delta), @"Unbalanced CEF browser lifetime"); browsers -= -delta; }
}
@implementation IKCEFRuntime
+ (BOOL)ready { return running && ready; }
+ (BOOL)canShutdown { return !running || (ready && !browsers); }
+ (void)runMessageLoop { CefRunMessageLoop(); }
+ (void)quitMessageLoop { if (running) CefQuitMessageLoop(); }
+ (BOOL)startWithArgc:(int)argc argv:(char **)argv root:(NSURL *)root helper:(NSURL *)helper
               ready:(void (^)(void))callback error:(NSError **)error {
  NSParameterAssert(NSThread.isMainThread);
  if (started || ![NSApp isKindOfClass:IKCEFApplication.class] || !root.isFileURL ||
      !root.path.isAbsolutePath || !helper.isFileURL ||
      ![NSFileManager.defaultManager isExecutableFileAtPath:helper.path]) {
    if (error) *error = IKCEFError(@"CEF requires its application class, bundled helper and a fresh lifecycle.");
    return NO;
  }
  if (![NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES
      attributes:@{NSFilePosixPermissions: @0700} error:error]) return NO;
  started = true;
  loader = std::make_unique<CefScopedLibraryLoader>();
  if (!loader->LoadInMain()) {
    if (error) *error = IKCEFError(@"The bundled CEF framework could not be loaded.");
    loader.reset(); return NO;
  }
  const bool fixture = [root.lastPathComponent hasPrefix:@"ikago-cef-smoke-"];
  CefSettings settings;
  if (fixture) CefString(&settings.locale) = "en-US";
  settings.no_sandbox = false;
  settings.remote_debugging_port = 0;
  settings.persist_session_cookies = false;
  settings.command_line_args_disabled = true;
  CefString(&settings.root_cache_path) = root.URLByStandardizingPath.path.UTF8String;
  CefString(&settings.browser_subprocess_path) = helper.path.UTF8String;
  CefString(&settings.log_file) = [root URLByAppendingPathComponent:@"cef.log"].path.UTF8String;
  settings.log_severity = fixture ? LOGSEVERITY_WARNING : LOGSEVERITY_DISABLE;
  application = new Application(callback, fixture);
  storageRoot = root.URLByStandardizingPath;
  running = true;
  if (!CefInitialize(CefMainArgs(argc, argv), settings, application, nullptr)) {
    running = ready = false;
    application = nullptr;
    loader.reset();
    if (error) *error = IKCEFError(@"CEF initialization failed. No browser was opened.");
    return NO;
  }
  return YES;
}
+ (BOOL)shutdownWithError:(NSError **)error {
  NSParameterAssert(NSThread.isMainThread);
  if (!running) return YES;
  if (!ready || browsers) {
    if (error) *error = IKCEFError(@"Wait for every CEF browser to finish closing before shutdown.");
    return NO;
  }
  running = ready = false;
  IKCEFClearContexts();
  CefShutdown();
  application = nullptr;
  storageRoot = nil;
  loader.reset();
  return YES;
}
@end
