# Chromium engine

- Prebuilt CEF only (`CEF/cef-lock.json`); check for newer releases with `scripts/check_cef_update.py`. DRM stays
  on WebKit, so Chromium itself can't decode H.264, AAC or protected video. `NativeVideoOverlay` plays such videos with
  AVFoundation over the page: the "ikago-media" isolated world reports X player boxes (or HTTPS sources Chromium
  rejected; known videos are skipped, because X's DOM changes constantly while scrolling and measuring forces layout),
  X streams come from the public syndication endpoint (ephemeral, no cookies, `video.twimg.com` only), and
  the overlay is clipped to the visible area, autoplays muted at ≥ 50 % visible and forwards scrolling to the page.
  Inspect real pages with the checks build: `--cef-smoke <url> --cef-smoke-dump --cef-smoke-root <ikago-cef-smoke-…>`
  (add `--cef-smoke-translate` to play X through the translation layer and print the player's state).
- Media translation (on by default, Settings ▸ Engine): `MediaTranslationShim` runs in X's main world before its scripts
  (`IKCEFPage.documentStartScript`: `Page.enable` + `Page.addScriptToEvaluateOnNewDocument` before the first navigation,
  which waits up to 2 s; the registration survives navigation events). It reports H.264/AAC MP4 as supported, including
  the combined `avc1…,mp4a…` question, and backs those SourceBuffers with AV1/FLAC ones. Each append travels as base64url
  parts in GET requests to `/__ikago_media__` on the page's own origin, because X's service worker drops POST bodies;
  `IKCEFMediaBridge` answers them natively (Chromium's request initiator must be the site itself, no cookies, 48 MB cap,
  parts reassembled when the request opens) with `MediaTranslator`: VideoToolbox decodes H.264, SVT-AV1 (static, pinned
  in `CEF/svtav1-lock.json`, fetched by `scripts/fetch_svtav1.py`, checked by `scripts/check_svtav1_update.py`; low-delay
  mode yields one packet per frame, so take it after each send) encodes each segment from a key frame, AudioToolbox
  decodes AAC into verbatim FLAC. Keep it cheap: the shim marks each append `urgent` (seeking, nothing buffered, or
  playing with < 5 s ahead: user-initiated, every core) or not (background QoS and SVT's fewest threads, which macOS keeps
  on the efficiency cores: ~3.5× less energy), and sends `fit`, the video's shorter on-screen side in device pixels, so a
  source above 720p shown at 720p or less is scaled to 720p by VideoToolbox while decoding. Preset 12 / qp 35 were
  measured against X's own H.264 (SSIM 0.98); measure energy (`proc_pid_rusage` `ri_energy_nj`), not just CPU time,
  before changing them. Chromium decodes the AV1 in hardware on M3 and later (`powerEfficient` in the dump).
  `NativeVideoOverlay` takes over (and only then pauses the page's video) when a translation fails, the video errors or vanishes, or it never starts. Logs (sizes and outcomes only) use the
  `media-translation` category. The translator still parses page bytes in the main process (Swift, bounds-checked);
  move it into a sandboxed helper before widening it beyond X.
- Per-site engines (`SiteEngines`, Settings ▸ General ▸ Engine by Site, the site popover's "Opens in"): ready-made
  `SiteEngineList`s and the person's own sites map hosts (with subdomains; the most specific rule wins, own sites over
  lists) to an engine. `BrowserRuntime.engine` is the default; `BrowserRuntime.running` is what this launch runs (always
  WebKit; Chromium when the default or a rule needs it, since it starts only at launch). After a rule change the
  affected sites' sign-ins move first, then open tabs follow (`BrowserState.siteEnginesChanged`); switching to a tab on
  the other engine shows the badge too. Ask `runs(_:)` for runtime matters and the page's or
  tab's `engine` (`WebTab.engine`, `TabItem.engine`) for per-page ones; never assume one engine per launch.
  `TabController.targetEngine` picks the engine when a page starts; main-frame GET navigations to another engine's site
  hand off (`webTab(_:handsOff:method:)`), parking the old page for Back/Forward (`EngineHandoff`, at most 4 switches in
  10 s) and showing a fading `EngineBadge`. Popups keep their engine (window.opener); clicked target=_blank links on
  WebKit open as plain new tabs in the right engine. Private windows use the default engine. Logins: a site whose engine
  changes has its cookies copied once to the new engine (`EngineCookieSync.rulesChanged`/`moveSiteLogins`, queued until
  a launch where Chromium runs); the whole-store copy on a default switch skips sites ruled to the destination, which
  holds their newest logins. Clearing data clears both engines. Check runs (`CEFSessions.overrideRoot`) get disposable
  WebKit stores; `CEFSiteEngineChecks` covers the rules and a real handoff.
- Chromium pages follow Ikago's light/dark mode, not macOS's (`ChromiumAppearance`, from `applyChrome`): Chromium themes
  page content from the app's appearance, so `NSApp.appearance` is Ikago's mode (nil in System mode; set by
  regular windows only, never private ones). `systemIsDark` therefore comes from macOS's own setting (`SystemAppearance`:
  `AppleInterfaceStyle` and its change notification), never `NSApp.effectiveAppearance`, which reports Ikago's choice back; CEF's `SetChromeColorScheme` (`IKCEFContexts.setColorScheme`) covers Chromium's own UI.
  `CEFColorSchemeChecks` checks both directions, so the Mac's own appearance can't make it pass. Never emulate it per tab.
- Known limitation (ROADMAP.md ▸ Known limitations): Chromium's speaker indicator misses cross-origin embedded players,
  Web Audio and detached `Audio` objects; WebKit's covers everything (`PlayingAudioObserver`). Don't fix it with a main-world
  script, a `CefAudioHandler` or disabled site isolation.
- Both engines play their own page audio. Chromium uses CEF's native output and `SetAudioMuted`; Ikago does not install
  a `CefAudioHandler` or reroute sound for visualization. Never route WebKit media through Web Audio to read it
  (cross-origin, redirected and HLS media go silent). `CEFAudioChecks` verifies native mute/unmute without stopping playback.
- Chromium media/theme state uses per-document isolated contexts with `Runtime.addBinding` and CEF DevTools events,
  never `Runtime.enable` or periodic state polling. Only registered context IDs may report, and native payloads are bounded.
  `CEFPageStateChecks` verifies zero idle state reads and page-world isolation. The native-video geometry observer starts
  only on X or after a page reports unsupported video, and stops while parked. Stopping inactive capture never reloads a page.
- DevTools docks left, right, top or bottom (`DevToolsDock`, saved side and share) under a native bar with dock and
  close buttons; the divider has its own gap. `ChromiumWindowGuard` hides every Chromium window (including Chrome's
  `BrowserNativeWidgetWindow` frame) except the one marked `dockedDevTools`; service windows are transparent and off screen.
- Chrome Web Store extensions sync between engines through `ExtensionSync` (sealed ledger; each change wins over older
  ones; the running engine catches up at launch and when Chromium's Extensions settings open). Unsupported installs are
  remembered per engine. Local folders and Safari extensions don't sync, nor does extension data.
- Pages are embedded Alloy-style browsers. Extension APIs that need a Chrome window don't see them, and their tab IDs
  (large, unrelated to CEF browser IDs) can't be found without a debugger-permission bridge, which Ikago doesn't install.
  Popups get `ChromiumPopupLayer` through `IKCEFPage.documentStartScript` (popup page only): a stand-in active tab
  (`ChromiumPopupLayer.tabID`) with the real address and title; reloading it goes to Ikago via `__ikagoRequests`, other
  calls aimed at it fail cleanly. The Web Store's button is "Add to Ikago" (`ChromiumStoreBridge`: isolated world, real
  click seen natively, verified CRX, the shared install prompt). uBlock Origin Lite is a default (`ExtensionSync.defaults`).
  Element fullscreen (`ChromiumFullscreen`) lifts the page above Ikago's UI (below the camera band) and takes the window full screen.
- Preserve fail-closed permissions, isolated script worlds, popup/opener identity, per-Space storage and native
  certificate verification. Never claim live Safe Browsing protection without a verified verdict, and never borrow an
  API key. No Quad9 or OpenPhish.
- Runtime checks use disposable profiles, a mock keychain and fake devices. Never enter credentials, weaken production
  encryption or raise a system permission prompt to make a check pass. They must not show a Chromium window.
