# Engines: WebKit and Chromium

## How it's built

- **`WebTab`** (`Engine/Shared/`) is the one protocol both engines implement. Everything outside `Engine/` talks to it.
  `TabController` starts, unloads and wakes a tab's page (`startIfNeeded`).
- **WebKit.** `Engine/WebKit/WebTab.swift` creates every `WKWebView` and is its navigation and UI delegate.
  `WebProfiles` maps a Space to its website data store.
- **Chromium.** `CEFWebTab` (`Engine/Chromium/`) wraps an `IKCEFPage` from the Objective-C++ bridge (`CEF/Bridge/`).
  Pages are embedded Alloy-style browsers. Chromium starts only at launch, and only when the default engine or a
  site rule needs it.
- **Which engine.** `BrowserRuntime.engine` is the default. `BrowserRuntime.running` is what this launch runs (WebKit
  always, Chromium when needed). Ask a page or tab its `engine`; never assume one engine per launch.
- **Per-site engines** (`SiteEngines`): the person's own rules and lists they chose map hosts to an engine.
  Main-frame navigations to another engine's site hand off (`EngineHandoff`), parking the old page for Back. Sign-ins
  follow: `EngineCookieSync` copies a site's cookies to its new engine.
- **Appearance.** Chromium pages follow Ikago's light/dark mode through `NSApp.appearance` (`ChromiumAppearance`).
  macOS's own mode comes from `SystemAppearance`.
- **Media.** Chromium here can't decode H.264, AAC or DRM video. On X, `MediaTranslationShim` (X's page world) reroutes
  Media Source appends to `IKCEFMediaBridge`, and `MediaTranslator` turns them into AV1 and FLAC (VideoToolbox,
  SVT-AV1, AudioToolbox). `NativeVideoOverlay` plays with AVFoundation when that fails. DRM sites belong on WebKit.
- **Page state on Chromium** (media, theme, passwords) reports through per-document isolated worlds and
  `Runtime.addBinding`, never polling.
- **Picture in Picture.** On WebKit it's macOS's own, turned on by SPI. On Chromium, `ChromiumPictureInPicture` moves
  the page into Ikago's floating panel.
- **DevTools** dock inside the window (`DevToolsDock`).
- **Removing Chromium** (`ChromiumRemoval`) deletes its data folders, and leaves the framework in the bundle (deleting
  it breaks the signature).
- **Updates.** CEF is pinned in `CEF/cef-lock.json`; `scripts/check_cef_update.py` and `chromium_lock.py` move it.

## Traps

- **Page lifetime.** `CreateBrowser` keeps an unretained pointer to its parent view and builds the browser later.
  `IKCEFUnsettledPages` holds each page until it attaches or closes, and popups get the same hold
  (`holdUntilSettled`). Dropping either brings back a use-after-free crash.
- **Quitting** waits until every Chromium browser has closed (`IKCEFRuntime.canShutdown`). A page no window's content
  owns (the link preview's) must close in `closeAllPages()`, or ⌘Q hangs.
- **Never take a Chromium page out of the window, and never resize it frame by frame.** Its layers drift and it draws
  shifted or blank. Move views straight between parents, size once, never `removeArrangedSubview`.
- **Privacy keys.** Chromium calls protected macOS services on its own (Bluetooth on Google sign-in, local network,
  speech). A missing `NS…UsageDescription` makes macOS kill the app. Keep `Info.plist`'s keys a superset of Chrome's;
  `check_crash_risks.py` (run by packaging) checks them.
- **WebKit popups** must return a web view built from the configuration WebKit passes in, synchronously, or
  `window.opener` (OAuth) breaks.
- **Decision handlers run exactly once,** or WebKit raises. Permission handlers go through `PermissionRequest`.
- **Extensions load before tabs exist.** `webExtensionController` is read when a web view is created.
- **KVO on `WKWebView`** fires on the main thread; observers use `MainActor.assumeIsolated`.
- **No document-start scripts on Chromium** unless needed (X's media shim): registering one stalls Back through a
  restored tab's history.
- **Never enable DevTools' `Runtime` domain** on pages: pages can detect it.
- **Media bytes are hostile.** `MP4Reader` checks every number before use; run `mediaparserchecks` after changing it.
- **Audio.** Both engines play their own audio. Never route WebKit media through Web Audio (cross-origin media goes
  silent), and don't install a `CefAudioHandler`.
- **`buttonNumber`** in `WKNavigationAction` is a mask (middle = 4), unlike AppKit (middle = 2).
- Runtime checks use disposable profiles, a mock keychain and fake devices. They never show a Chromium window
  (`CEFHiddenServiceChecks`).
