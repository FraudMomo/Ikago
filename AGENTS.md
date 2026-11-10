# AGENTS.md — Architecture rules for Ikago

Ikago is a lightweight native macOS browser: a SwiftUI
sidebar, Spaces, split view, a floating command bar, Chrome Web Store extensions, and
first-class access for AI agents. It is written in **Swift 6 with AppKit and SwiftUI**, and
the page engine is the user's choice: **Apple's WebKit** (`WKWebView`) or **Chromium** through
a prebuilt CEF framework. Read these rules before changing code.

---

## 1. Golden rules

1. **Two engines, public API first.** Pages are `WKWebView`s or embedded CEF pages behind the
   `WebTab` protocol. Use Objective-C++ only at the Swift/CEF boundary in `CEF/Bridge/`. No custom
   CEF build, no Chromium fork, and never compile Chromium. Use private WebKit SPI only when
   there is no public way and the payoff is large; mark each use with a `// SPI:` comment and
   list it in §7.
1a. **No Chromium windows, ever.** Ikago draws all the UI. Chrome-style browsers exist only because
   some Chromium services need one; they stay hidden (`IKCEFNativeTools`, `HiddenChromiumPage`). Pages
   Chromium opens by itself become Ikago tabs, DevTools docks beside the page (`DevToolsDock`), and
   `ChromiumWindowGuard` hides anything titled that slips through. Tests stay hidden too, and
   `CEFHiddenServiceChecks.noVisibleChromiumWindows` fails the suite otherwise.
1b. **Never change a user's engine silently.** WebKit is the default; a change applies on relaunch. Sites can have their
   own engine (§8, per-site engines), but only by the person's choice: lists are suggestions they assign, never defaults.
2. **One owner per web view.** Only `Engine/WebKit/WebTab.swift` creates and configures `WKWebView`
   (it is the navigation and UI delegate). Everything else talks to the `WebTab` protocol.
3. **Storage per Space.** `Engine/WebKit/WebProfiles.swift` maps a Space's profile ID to its
   `WKWebsiteDataStore`: `"Default"` → `.default()`, an isolated Space → a persistent store
   keyed by the Space's UUID. Never create a data store anywhere else.
4. **Fail closed.** Permission requests are denied unless the user allows them
   (`PermissionRequest` denies itself if dropped). WebKit's popup blocker stays on
   (`javaScriptCanOpenWindowsAutomatically = false`).
5. **Agents are a feature, not a hack.** Agent control (planned, see ROADMAP.md) goes through Ikago's
   own MCP server and public WebKit calls (`evaluateJavaScript` in an isolated content
   world, `takeSnapshot`). It is off by default, local only, token-protected, and the UI
   always shows when an agent is driving a tab.

---

## 2. Layout

```text
Ikago/
├── App/         main.swift, AppDelegate, MainMenu (all shortcuts + ShortcutRouter), AppIdentity, ProtectedStorage
├── Browser/     No views. State/ (BrowserState and its extensions), Model/ (tabs, Spaces, preferences, sessions),
│                Address/ (omnibox engine, input, suggestions), Downloads/, Favicons/
├── Engine/      Shared/ (WebTab protocol, BrowserEngine, permissions), WebKit/ (WebTab, profiles, security,
│                Apple Passwords), Chromium/ (CEFWebTab, sessions, hidden services, DevTools dock, window guard)
├── Extensions/  WebKit/ (WKWebExtension manager, tab bridge, Web Store), Chromium/ (hidden manager, popups)
├── Import/      Browser data import
├── UI/          Window/ (controllers), Content/ (tab panes), Shell/ (root view), Toolbar/, Tabs/, Sidebar/, Address/,
│                Overlays/, Pages/ (ikago:// pages), Settings/, Downloads/, Design/ (Palette, glass buttons, logos)
├── Checks/      Chromium/ (runtime checks, IKAGO_CHECKS builds), Debug/ (WebKit test driver, DEBUG builds)
└── Resources/   Info.plist, entitlements, Assets.xcassets

CEF/             Objective-C++ bridge, CMake build, pinned SDK (cef-lock.json)
scripts/         build.py, package_app.py, install.sh, fetch_cef.py, check_cef_update.py, run_chromium_checks.py
```

Build with `python3 scripts/build.py` (`--flavor release|checks|debug`). `Checks/` is left out of release
builds. Generated: `.cef/` (the SDK), `build/`, `out/`. Minimum macOS 26 (Liquid Glass; `WKWebExtension`
itself needs 15.4). Bundle ID `app.ikago.browser`; data lives in the protected app group container
`<team>.app.ikago.browser` (`ProtectedStorage`), or `Application Support/Ikago` in ad hoc builds.

---

## 3. WebKit traps

1. **Popups must use WebKit's configuration.** In `createWebViewWith`, return a web view
   built from the configuration WebKit passes in, synchronously, or `window.opener` (OAuth)
   breaks. `WebContentViewController.adoptPopup` does this and turns the popup into a tab.
2. **Decision handlers run exactly once.** WebKit raises if a decision/completion handler
   is dropped. Permission handlers go through `PermissionRequest` (one-shot, denies on deinit).
3. **KVO on `WKWebView` fires on the main thread.** `WebTab` uses `MainActor.assumeIsolated`
   in its observers; keep it that way.
4. **App shortcuts beat the page.** `AppDelegate` installs a key-down monitor that sends
   Cmd/Ctrl shortcuts to the main menu first (`ShortcutRouter`); Cmd+C/V/X/A/Z stay with
   the page.
5. **Overlays live in the window's SwiftUI tree** (`BrowserRootView`), not child windows, so
   Liquid Glass samples the page behind them. Show/hide them through `ChromeModel`.
   The sidebar and the top bars run in their own `NSHostingView`s (`IsolatedHost`) so their updates don't walk the whole
   window's graph; anchors can't cross hosts, so the Downloads button's and address field's frames reach the shell through
   `ChromeModel.downloadsButtonFrame`/`addressFieldFrame`, published after layout (never during it).
   Sidebar lists scroll in AppKit's `NSScrollView` (`SidebarScrollView`), never SwiftUI's `ScrollView`.
   The list's document follows the row height SwiftUI measures (`ScrollRoot`), not the host's intrinsic size.
   While a trackpad scroll is live the rows' host skips its layout passes (`ListScrollView.pausesRowUpdates`): the rows
   are already drawn, and SwiftUI would otherwise re-render the whole list on every scroll step. A host's `updateNSView`
   sets `rootView` inside `withTransaction(context.transaction)`, or animations stop at the host boundary.
   A group opens and closes with `Animation.groupDisclosure`, started inside the list's own graph (`SidebarFolderSection.open`
   follows the model): measured, a `withAnimation` around the model change does not animate rows in another host. Only
   the rows' frame height animates (measured once, rows mounted shut first), and a shut group is the same height with its
   rows mounted or not. The document grows at once; it gives up a closed group's space after it, while a list scrolled
   past its new end follows the closing rows on the same spring (`ListScrollView.follow`). The list's root keeps
   `minHeight: 0`, or the host centres rows taller than the document for a frame. Measure with `groupseed`/`groupprobe`.
   AppKit views in SwiftUI that fill their space conform to `FillingViewRepresentable`; a plain `NSViewRepresentable`
   makes SwiftUI solve Auto Layout for its `fittingSize` on every layout (measured: the top main-thread cost on tab switches).
6. **Scripts the browser runs use `WKContentWorld.defaultClient`,** never the page world, so
   pages can't see or tamper with them. The one exception is Chromium's `MediaTranslationShim` (X only), which must
   wrap the page's own Media Source; it only rewires that page's media.
7. **Extensions must be loaded before tabs exist.** `WKWebViewConfiguration.webExtensionController`
   is read when the web view is created; `AppDelegate` awaits `ExtensionManager.loadInstalled()`
   before opening the window. Tell the controllers about tab/window events
   (`ExtensionManager.tabOpened/Closed/Activated/Changed`) whenever the model changes.
8. **Extension pages need their extension's configuration.** A tab showing a
   `webkit-extension://` or `chrome-extension://` URL (options pages, `tabs.create`) is created from
   `WKWebExtensionContext.webViewConfiguration` (`TabController.startIfNeeded`).
9. **The sidebar shows one Space.** `pinnedTabs`, `regularTabs`, `sidebarOrder` are the
   active Space's; `tabs` holds every Space. Reorder with `move(_:before:pinned:folderID:)`,
   which keeps other Spaces' tabs in place. Visits are recorded on commit, not on URL change.
10. **Tab drags use the `app.ikago.tab` type (`TabDrag`),** never plain text: web views
    ignore it, so `WebTabContainerView` can take a dropped tab for split view.
11. **Split view is `splits: [[String]]`** (groups of 2–4, a tab in at most one). Use the
    helpers in `BrowserState+Split` (`splitGroup(of:)`, `separate`, `removeFromSplits`) and
    `listItems` to show a group as one item. `state.splitLayout` (`SplitLayout`: columns, rows,
    grid) arranges them; a grid nests `NSSplitView`s in `WebTabContainerView`. Drops use
    `SplitDropOverlay` (four edge triangles with a preview).
12. **Address editing takes the keyboard from the page.** The field is `AddressTextField`
    (AppKit). While `chrome.inlineAddress`/`showPalette` is set the page must not be focused
    (`shouldFocusPage`); views show the field only for `chrome.isEditingAddress(of:)` the edited
    tab, and a tab switch ends editing. `state.addressStyle` picks Integrated or Floating.
    Top layouts always create a real tab and edit inline, append ordinary new tabs, and place
    links after their opener. Sidebar alone honors placement/address-style/focus preferences.
    The opt-in `focusAddressBarOnNewTab` setting focuses the address after opening the chosen
    homepage/extension provider, using current-tab navigation and an empty query. Use the floating
    field if the integrated field is hidden. BrowserWindow rejects page focus before resigning
    the address editor; explicit browser commands reset editing intentionally. Page reconciliation
    must not steal the keyboard, and outgoing field transitions must not leave it unfocused.
    BrowserWindow dismisses address editing on outside mouse-downs across the whole window,
    preserving the original click. Address fields and results mark their bounds with
    AddressInteractionRegion so cursor placement, popup actions and clear buttons keep working.
13. **Top bars use their layout's palette.** `TabItem.themeColor` (from `WKWebView.themeColor`)
    blends subtly into the Space through `BrowserState.barTint`/`barPalette`. The Top Bar's neutral
    surface opts into webpage tint. Never draw bar controls with the sidebar palette.
    Tab widths come from `TabStripLayout`; the island is centred, outside-island buttons are zones.
    Bound the viewport to the parent GeometryReader, budget actual control widths and gaps, and
    scroll the active tab/group into view on appearance and resize. Overflow customized controls
    before squeezing tabs; fold outside controls into the island when their zones cannot fit.
    Regular tabs share a dynamic width (Compact up to 280 pt; Separate fills its tab row) down to
    a readable 120 pt. Past that, the active tab keeps 120 pt while inactive tabs compact
    toward favicons (34 pt Compact, 40 pt Separate; icon-only below `TabStripLayout.iconOnlyWidth`, with
    × on hover), and the strip scrolls only once every tab is at its minimum.
    Use actual scroll geometry for edge fades: only fade a side with hidden content beyond it.
14. **Toolbar controls come from `state.chromeLayout`** (`ChromeLayout`, zones of `ChromeItem`),
    drawn by `ChromeItemView`. New controls get a `ChromeItem` case so users can place them. "Chrome" in
    these names means the browser's own UI, not Google Chrome.

---

## 4. Design

1. **Clean first.** No decorative icons or labels; secondary actions appear on hover or in
   context menus. Ikago's own pages (Settings, History, Downloads, Bookmarks) are `ikago://` tabs
   (`InternalPage`), never separate windows or panels.
2. **Floating surfaces use `.surface(shape, palette)`**: Liquid Glass, or a flat panel when the
   user turns glass off (Settings ▸ Appearance). Sidebars may independently use the native
   frosted material via `surface(..., translucentSidebar:)`; honor Reduce Transparency and
   preserve readable Space tint. Never call `glassEffect` directly. Glass can't
   render offscreen, so drag previews use plain fills. Related icon controls share one reactive capsule (`GlassControlGroup`); a lone control uses
   `glassControl`, which adds nothing inside a group. Don't merge separate glass circles in a container: they melt together with visible necks.
   Don't switch styles with an `if` around large subtrees: `glassButtons` is one style that decides inside, because
   an `if` at the root rebuilds the window on change and overflowed the stack when a page inserted a button.
3. **Space colors tint the full chrome**, including flat sidebars and top bars. Use
   `state.palette` and `.surface`; glass surfaces retain the Space tint. Keep page contents
   neutral, provide readable ink for arbitrary custom colors, and let website theme colors
   blend subtly rather than replace the Space's identity. Margins follow `state.frameInset`.
4. **Top tabs move; everything else stays immediate.** `TabMotion` (`TabSlotMotion.swift`, a 200 ms ease-out)
   animates top-strip *structure*: an opened tab's slot grows in while neighbours, the viewport and the + button
   slide; a closed tab (closed at once, no delay) shrinks out; reorders and group collapse/expand reflow.
   Strips animate only on `TabMotionKey` (item ids) through `tabStripMotion`, which blocks callers'
   transactions. Selection, address editing, window resizes and Space switches stay immediate, and so does
   suggestion selection. Titles crossfade over 100 ms, hover fills fade (~0.1s in, 0.2s out), and the address
   field eases its focus fill/ring. Respect Reduce Motion. Other changes animate quickly: `Animation.ikago`
   (0.2s) or `.ikagoQuick` (0.12s). Sidebar selection highlights follow the configured `TabSelectionHighlight` style.
5. **Two layouts:** `TabLayout.vertical` (Sidebar) and `.horizontal` (Top Bar). The Top Bar offers
   Separate and Compact tabs. Features must work in both. Layout switches keep the page in the window
   even mid-animation (`ContentHost`).
6. **Extensions live in the site-and-extensions popover** in the address field. On WebKit use native
   `performAction` and popup anchors; on Chromium popups open in `ChromiumExtensionPopup`.
7. **Settings is quiet and typographic.** A 220 pt navigation column on the page's own background: a "Settings" heading,
   a search field (`SettingsSearch`: add every new setting to its index, with the `PageSection` title it lives under),
   monochrome outline symbols, a neutral fill for the selected row (no colored tiles, no accent fill). Pages use
   `PageScaffold` (26 pt title; Settings pages have no subtitle), `PageSection` (12 pt secondary heading over a soft
   borderless panel, 12 pt corners) and `PageRow` (44 pt rows, 13 pt titles, 12 pt subtitles, no decorative per-row icons; an engine
   logo beside an engine choice shows its value). Controls are
   standard macOS ones (`.buttonStyle(.automatic)`, `.borderedProminent`, small switches), not the browser's glass buttons.
   Titles and subtitles describe; they never sell ("Import", not "Bring Your Browser to Ikago"). Subtitles are a few words and
   footers one short sentence, or none. No ambient glows, tinted
   cards or rounded display fonts. `.ikago` animations never overshoot.

---

## 5. Style

1. Files under 300 lines; small single-purpose SwiftUI views and AppKit controllers.
2. State: `@MainActor @Observable` classes (`BrowserState`), no Combine where `@Observable` works.
3. Keep feature parity: atomic session save/restore with backup, fail-closed permissions,
   per-Space colors, shortcuts Cmd+T, Cmd+W, Cmd+Shift+T, Cmd+L, Cmd+F, Cmd+P.
4. Verify with the Debug test driver (`IKAGO_TEST_MODE=1 IKAGO_TEST_ACTIONS=…`, see
   `App/TestDriver.swift`); it uses in-memory website data and a temporary session folder.

---

## 6. Browser features

- Desktop app links use `ExternalLinkOpener` and public `NSWorkspace` APIs. Handle clicked links,
  top-level OAuth redirects, scripted handoffs and new-window links for any registered app scheme.
  Cancel WebKit navigation before prompting, preserve the complete callback URL, and launch the
  application the user approved. Never log callback URLs or authentication codes. Scripted subframe
  launches stay blocked; app links must not create blank popup tabs or replace the browser page.
- Sidebar essentials contain pinned tabs in both docked and peeked sidebars. Hidden pin
  grids fall back to tab-list rows so pinned tabs stay reachable. The grid uses at most three
  columns, adapting down with the sidebar's available width, with bounded scrolling and an
  empty drop target during tab drags. Split drops accept live tabs only. Tab rows use SwiftUI's
  drag/drop lifecycle with before/after insertion markers, without native overlays intercepting
  row input or mutating order during hover. Read the payload asynchronously before committing
  a move so the source view is not rearranged inside a native drop callback.
  Move split groups together, keep sidebar reflow to 0.12 s, and respect Reduce Motion.
  Group headers accept membership drops explicitly; only web-page split targets intercept input
  through a native overlay.
  Closing a pin unloads its page and retains its identity; only unpinning/removal deletes it.
  Persist favicon URLs on tabs/bookmarks and retain disk icons without age expiry.
  Favicon views synchronously seed from disk/memory; never clear a working same-site image
  on view task restarts or failed fetches. Page/site aliases retain the last valid image across
  changing icon URLs. Validate fetched replacements before updating tab/bookmark metadata,
  and reject late results from a different page or document.
  Address-bar searches/URLs from a pinned tab open a new regular tab instead of replacing it.
  This guard lives in the window's shared address-open path for both integrated and floating
  fields, including suggestions. Page links and redirects stay native. Bookmarks are shared
  saved pages independent of live tabs; opening can reuse matching tabs in the current Space.
- The status bar is `LinkStatusView`: the hovered link's address in a pill at the page's bottom-left, plain AppKit on the
  tab's host view (never the SwiftUI shell), shown undecoded. WebKit reports hovers from `LinkHoverMonitor` (isolated
  world, every frame); Chromium from `OnStatusMessage`. Both reach `WebTabDelegate.webTab(_:didHoverLink:)`.
- View ▸ Performance Stats (`PerformanceOverlay`, saved in UserDefaults, never shown in check runs): frames per second and the
  slowest frame of the last second from a main-thread display link, plus CPU and memory footprint summed over the app, its
  Chromium helpers and its WebKit processes (`PerformanceSampler`, once a second off the main thread). Plain AppKit on the
  window's content view, so it adds nothing to the SwiftUI graphs. Check it with the `perfstats` test action.
- The sidebar's media island (`SidebarMediaPlayer`) is a compact black island: black glass (solid black with
  glass off), Media Session title, artist and artwork (`MediaArtwork`: cookie-free, raster only, memory only), a wave in
  the artwork's color (`MediaWaveform`): fine bars for five voice-and-music bands (120 Hz–4 kHz, scaled to the track's
  recent loudness), only from real levels (Chromium with the live wave on); otherwise no wave rather than a fake one. Closing it hides it until
  something new plays. Opening, closing and appearing run in the island's own `withAnimation` (`Animation.island`), so
  the sidebar list gives way smoothly (measured with `islandprobe`); never an implicit `.animation` here.
- Completed download rows open files on a single click via a dedicated button; cancel and
  Show in Finder are separate hit targets. Keep popup styling on the current chrome palette
  and shared surface; a missing file or failed open reports an error without removing history.
- Downloads use a toolbar-anchored dropdown in all layouts, plus `ikago://downloads` for
  full history. `DownloadCenter` owns byte progress and cancellation; `DownloadHistoryStore` saves
  owner-only atomic history with backup (up to 1,000 entries). Keep completed/failed/cancelled
  entries across relaunches, restore unfinished entries as interrupted, and never delete files
  when clearing history. The automatic toolbar control stays for active/recent (24-hour) downloads;
  the dropdown’s × dismisses it without clearing history (active work stays visible until finished,
  and a new download brings it back). A user-placed Downloads control is permanent. Download flight
  and completion feedback is visual only, passes through input and respects Reduce Motion.
  Page progress and Stop belong in every address presentation; a finished load runs the progress line to the end, then fades it.
- Security uses public WebKit HTTPS policies and native WKContentRuleLists. Strict mode
  never sends top-level HTTP requests; do not replay insecure POST bodies or silently fall
  back after a failed upgrade. Tracker/cookie rules are on by default, compiled before tabs,
  and updated on existing pages without removing extension-owned rules. Report compilation
  failures and describe the curated tracker list honestly; never bypass TLS certificate errors.
  Third-party cookies are blocked, not partitioned, on both engines; both partition third-party storage per top-level site
  (`CookieIsolationChecks`, `CEFCookieIsolationChecks`). On Chromium only requests Ikago cancels or upgrades get a
  `CefResourceRequestHandler`: CEF loads and saves cookies itself for those, ignoring the third-party setting.
  WebKit's blob files and media cache live in the user's temporary folder; `ProtectedStorage.removeTemporaryFiles` clears them at launch and quit.
- Private windows leave no trace on disk: favicons stay in memory (`persist: false`, `\.privateBrowsing`) and downloads stay out of
  the saved history (`WebProfiles.isPrivateStore`). Deleting history or clearing data also discards the session and download
  backups. Favicons only decode formats sites use (`isFaviconFormat`), because decoding happens in the unsandboxed main process.
- Chromium's background traffic is checked with a temporary `log-net-log` switch. Autofill's server lookups and AI Mode eligibility
  checks stay off. Component updates remain on because they deliver certificate revocation lists.
- History, sessions, download history and favicons are encrypted at rest (`SealedStorage`, AES-GCM, key in the login Keychain). Never
  fall back to plain text. A locked Keychain stops at launch with Try Again, so it can't look like lost data. Unattended checks use a
  fixed test key and must never touch the real Keychain.
- Everything else lives in protected storage (`ProtectedStorage`): the team-prefixed app group container, which macOS denies to apps of
  other teams (only Full Disk Access gets in). `package_app.py` adds the group to the app and every helper for team signatures. WebKit's
  per-app folders (`~/Library/WebKit|Caches|HTTPStorages/<bundle>`) are symlinks into it; macOS checks real paths, so links don't open a
  way around it. WebKit's built-in `.default()` store is never used, because its cookie file sits directly in the shared HTTPStorages
  folder: the Default Space is the identifier store `ProtectedStorage.defaultStoreID`, adopted from the old files at launch. Never touch
  `HTTPCookieStorage.shared` (configuring it loads that file and writes it back at quit); Ikago's own requests use ephemeral sessions.
  The updater's `Updates` folder stays in Application Support because it runs outside the app. Data moved in that a build can't open
  stops at launch instead of starting empty. Chromium's cookies are additionally encrypted with its Keychain key.
- Always require HTTPS is on by default, applied once to older sessions (`httpsDefaultApplied`). A site unavailable over HTTPS offers
  a remembered per-site exception on its error page. Sites ask before saving files (`DownloadPermissions`); with no window to ask in,
  the download doesn't happen.
- Phishing warnings (`SiteSafety`) cover look-alike addresses and public lists on both engines (`ThreatHosts`: phishunt.io
  CC0, PhishDestroy's main list MIT, never its aggregated community list); WebKit adds Apple's own fraud warnings. Lists download to this Mac and are matched locally; no address
  is ever sent anywhere. Warnings can always be overridden, and a list can't flag a site in `SiteSafetyRules.protected`. Describe this
  honestly: it isn't a live verdict service, and brand-new sites can slip through.
- Chromium updates run outside the app (`scripts/auto_update.py`, LaunchAgent `app.ikago.updater`) in a separate source copy: download
  and verify, build, run the full check suite, require a real signature, stage, then install only while Ikago is closed. Any failure leaves
  the installed app alone and reports in Settings ▸ About & Updates. The renderer, GPU, plugin and alert helpers have no camera or
  microphone entitlement; only the app and the base helper, which hosts the capture service, do.
- Switching engines keeps people signed in (`EngineCookieSync`). History, bookmarks and tabs live in the shared session. Cookies
  are copied only in Chromium runs, which can reach both stores: WebKit → Chromium on the launch after a switch, Chromium → WebKit
  on the quit before one (WebKit is only touched then, so ordinary quits stay fast). After a clean switch the last engine is
  authoritative, so logouts carry over; otherwise the copy only merges. Never write cookies anywhere else or log their values.
  localStorage and IndexedDB don't transfer. Clearing website data or deleting a Space applies to both engines. Checks use
  disposable stores and must never reach the real ones (`usesRealStores`).
- Website data persists per Space store. Quitting replies `.terminateLater` and flushes every
  persistent store's cookies (`WebProfiles.flushCookies`, bounded timeout) before exiting; WebKit's
  networking process otherwise dies mid-write and loses the newest cookies (logins, rotated device
  tokens). Keep that work callback/run-loop based: `terminate` from inside a main-actor Task blocks
  Swift tasks, so the Debug `quit` action terminates from the run loop like a menu. Session cookies
  ending at quit is WebKit behaviour. Verify with `datapersistencechecks:write|<base>` then
  `datapersistencechecks:read|<base>` in two launches sharing `IKAGO_TEST_STORAGE_UUID`.
- Window dragging works like the sidebar in every layout: a `WindowDragArea` sits *behind* each bar's
  content (Top Bar toolbar and tab row, Compact island), so any empty bar space moves the window,
  and behind the page card, so the window margins do too. A floating Top Bar card's surrounding margin
  drags as well. Never cover bars with a drag overlay plus exclusion rects.
- In every layout a still press-and-hold (0.12 s) within 10 pt of the page's top edge (web pages and
  `pageSurface`-marked internal, error and empty pages) becomes a
  window drag (`PageWindowGrab`, a passive local event monitor; no view, inset or overlay). The page
  receives every press immediately; moving first, double-clicks, modified clicks, split headers and
  overlays stay with the page. A grab ends the page's press away from it and drops the later mouse-up.
- Split drops use a permanently mounted AppKit SplitDropTarget above WKWebView, with
  preview and acceptance driven by native dragging callbacks. Transparent SwiftUI-only drop
  surfaces can fall through to embedded pages. Decode TabDrag from the live pasteboard
  rather than transient chrome drag state. Pane headers
  use native independent drag handles/buttons; page focus must not interrupt header controls.
  Dropping the active unsplit tab creates a `ikago://split-empty` slot. Filling the slot
  preserves its side/layout and removes the placeholder; sessions retain empty slots.
- Page-switch fades and tab-highlight motion are independent Settings ▸ Appearance options.
  Instant mode removes in-flight layer fades; shared TabSelectionHighlight implements None,
  Slide, Fade, Scale and Spring for all layouts, pins and split groups. Respect Reduce Motion.
- URL suggestions share CommandPaletteModel in both address styles
  (`OmniboxEngine`, `OmniboxInput`). Input is classified as URL, query or unknown. Matches carry
  Chromium-scale relevance: inline-autocompleted navigation 1410+, search-what-you-typed 1300
  (1150 for URL input, whose what-you-typed navigation is 1200), earlier searches from history
  1240–1279 (up to three), remote predictions 1230 and below (up to five, requested from the first
  letter after a short debounce), and history/bookmark/open-tab pages ≤ 1199 from
  topicality × frecency (Visit `visits`/`typed`, Chromium recency buckets). One row per page,
  at most `OmniboxEngine.maxResults`. Only pages that were typed, visited ≥ 3 times or bookmarked
  inline-autocomplete, completing to the host root within the host. Inline completion follows
  forward typing only (`userEdited`), never deletion or programmatic text. ↑/↓ preview a row's
  `fill` as `temporaryText` without replacing the typed query and never wrap; hover only highlights.
  Esc restores the typed text before closing. Tab focuses a row's "Switch to this tab" button,
  then the next row. Shift+Delete or × forgets a history row. Search result pages appear as earlier
  searches, never as navigation rows. Focusing the field (empty, or ⌘L on the untouched page address)
  lists up to five recent searches, then most visited pages (never the current page), with no row
  highlighted: ↓ previews the first, Return on the untouched address keeps the page. Address-field navigations mark the tab in `typedNavigations` so
  its next committed visit increments `typed`. Switch-to-tab buttons
  are independently configurable; remote search autocomplete is opt-in. Debounce requests,
  exclude addresses, use cookie-free ephemeral sessions, cancel on dismiss/changes and ignore
  late responses. Provider failures must preserve direct search and local suggestions.
- New-tab placement is configurable (top/bottom); links can open before/after their opener or
  follow the new-tab setting. Preserve manual order and other Spaces; adjacent links inherit the
  opener's group, while normal new tabs remain loose and unpinned. All link paths, including
  WebKit popups, use `newTabFromLink`. `WKNavigationAction.buttonNumber` is a mask (middle = 4),
  unlike AppKit's index (middle = 2); middle-click opens in the background, Shift selects it.
- Browser preferences and bookmarks persist with the session; keep new session fields optional
  so existing profiles restore. Hibernation remains opt-in and protects every visible split pane,
  loading/media tabs, protected pins and domain exceptions. Wake through `startIfNeeded()`.
- Extension resource origins are persisted per installation, alongside stable package IDs.
  Keep WebKit's native scheme and restore the saved origin before loading the context; localStorage
  and IndexedDB must survive reloads, enable/disable and relaunches. Ordinary Debug tests remain
  nonpersistent; explicit restart fixtures may use a fresh disposable store/controller UUID.
- Newly opened background tabs load by default (configurable in Tabs & Memory), without selecting
  them. Restored session tabs and unloaded pins remain lazy; never preload a restored session.
- Web Store packages are verified before unpacking (`CRXVerifier`): CRX3 only, every signature valid, signed by the
  key the extension ID comes from and by the Web Store's publisher key, no ZIP tokens in the header. Local packages are the person's choice.
- Extension compatibility checks must run on every install path. Passing a manifest check is
  not proof of runtime support. Show reasons in the store page and Settings. Automatic updates
  must retain the previous working copy on failure and ask before expanding capabilities.
- Camera/microphone: `WebTab.tearDown` ends capture (`setCamera/MicrophoneCaptureState(.none)`) and pauses
  media before detaching, because anything still holding a detached web view keeps the device open. A muted
  capture still counts as in use (`TabItem.…Muted`). Tab indicators are `CaptureMenu`s: mute/resume, stop, and
  for the microphone the input device. WebKit can't route a page to a chosen mic, so the menu switches the
  system default input through CoreAudio (`AudioInputDevices`), labelled as affecting all apps; no page-world script.
- Passwords fill from one of two sources (`PasswordSource`, Settings ▸ Passwords). Apple Passwords (WebKit only): Apple's own
  AutoFill panel types the login, and Ikago never sees it. Ikago Passwords (both engines, Chromium's only source): `PasswordVault`,
  imported from a Passwords app or Chrome CSV export that is then overwritten and deleted (`PasswordImport`). Each password is encrypted
  (ECIES, AES-GCM bound to site and username) to a Secure Enclave key that needs Touch ID or the Mac password for every single fill;
  sites and usernames are sealed. Matching is the registrable domain from the bundled Public Suffix List (`PublicSuffix`, `public_suffix_list.dat`): exact host first, then parents/children, then other subdomains; subdomains of a public suffix (github.io) are separate sites. The menu lists every match.
  `PasswordKeyScript` shows the key in password and username fields in an isolated world; only a trusted click asks native code, which
  picks a login in a native menu (`PasswordChooser`) and passes it to the script's `fill` as call arguments, never script text. WebKit:
  `.defaultClient` world and message handler, main frame or same-origin frames. Chromium: the "ikago-passwords" world of the top
  document only, injected per document and only on sites with a saved login. The page never messages Ikago: a passive mouse-down
  monitor sees the real click and asks the script's `hit(x, y)`. Never enable DevTools' Runtime domain on pages (pages can detect
  it and it streams every console message). Saving new passwords isn't built yet. Debug tests count panel
  requests and pick the first login instead of showing a menu.
- Safari bundle native messages use WebKit's default delivery; do not override the messaging
  delegate with a blanket unsupported response. Chrome native messaging is still unavailable.
- Preserve WebKit’s native extension resource origins. Use `resourceURL`/`canonicalURL` to
  resolve Chrome-style navigation and persist stable package IDs; extension-tab APIs must
  expose resource URLs consistent with `runtime.getURL`.
- Chrome open tab groups map to folders using source-profile/token identity scoped to the
  destination Space. Preserve names, colors, collapsed state and live membership; never combine
  groups by title. Reimport reuses folder IDs and preserves user edits. Report capacity limits;
  encrypted sessions and closed saved groups remain unsupported.
- Settings and internal-page content use explicit viewport/column widths; intrinsic content
  must never expand the shell or push Settings navigation outside the window.
- Settings categories render separate pages. Browser import discovers profiles and uses one
  explicit Import action for bookmarks, history, tabs and available website logins into the current
  Space, without replacing tabs or Spaces. Discovery uses metadata and installed-app fallback,
  so protected Chromium browsing records cannot hide the browser from the import list. The button includes compatible Keychain decryption;
  preserve required macOS authorization prompts. Preflight opens read-only handles only after
  Import; access denials use a native folder picker at the detected profile, with a retry action.
  Retain security-scoped access through the read, handle cancellation without importing, and
  never mark blocked/partial imports complete. SQLite failures must retain their actual cause. Read source profiles through SQLite read-only
  handles, never log or persist decryption keys, and read browsing records only after Import. Report unsupported/encrypted formats instead of silently claiming
  a complete import.

- Top layouts can close a tab group (folder context menu ▸ Close Group, `BrowserState+ClosedGroups`):
  `TabFolder.isClosed` (optional) removes it from the strip, its pages hibernate, and selection moves
  off it. Reopen from Tab ▸ Reopen Closed Group, the new-tab button's right-click menu, or the tab
  sidebar; selecting any of its tabs reopens it. Closing also cancels pending background loads of its tabs. Strips list `stripFolders`; next/previous tab and
  close-neighbour selection use `navigationOrder`, which skips closed groups in top layouts. The
  Sidebar layout still lists closed groups.
- Top layouts have independent saved visibility choices for pinned essentials. The optional
  bookmarks row starts hidden. Visible pins live in the tab strip. The temporary tab sidebar
  uses rows, never the vertical layout's tile grid. Hidden pins stay reachable in the tab sidebar,
  without falling back into the top tab strip; visible splits remain represented there.
  Enabled accessory rows touch the tab row on one shared surface, with no separate glass
  capsules or inter-row gaps. Accessory bars have bounded scroll viewports and contribute
  to the floating page's content inset so fixed page controls stay reachable.
- The optional bookmarks bar is a separate Top Bar row and an upward-expanding bottom drawer
  in the vertical sidebar. ⇧⌘B and Settings ▸ Toolbar & Sidebar toggle the same saved preference. Bookmarks and
  nested `BookmarkFolder`s are shared across Spaces and independent of live tab groups; keep
  session additions optional, validate folder trees, and never delete saved pages when removing
  a folder. Bookmark drops save live tabs without closing them.
- The Top Bar uses a native neutral surface with a restrained Space tint and correctly matched
  ink. Webpage tint is opt-in and subtle. Flat surfaces must use that same surface color without
  darkening it again. Separate tabs live below the toolbar; its centered address field stays
  available for pinned, split and collapsed-group tabs. Compact tabs edit in place. Both styles
  keep optional rows connected and support the floating toolbar setting. Heights are adjustable
  (`topToolbarHeight` 40–64 pt for the toolbar or Compact row, `topTabBarHeight` 28–48 pt for
  Separate tabs, both optional preferences); tabs and capsules derive from the row height and the
  address field stays 32 pt. Floating mode is a detached card: `topBarFloatingMargin` on every
  side, continuous 14 pt corners, its own shadow and no docked hairline. The address field
  centres the domain at rest, fades the page menu/reload in on hover, and left-aligns on an opaque
  field with the system focus ring while editing; its results use accent-filled rows (white text).
- Top layouts have static selection; insertion follows `TabMotion`. ActiveTabScrollAnchor is the
  only reveal owner: observe native clip/document frame changes and reveal clipped edges,
  never recenter an already-visible active tab through a delayed SwiftUI scroll proxy.
- Integrated address editing uses opaque light/dark surfaces independent of glass. Every address presentation shares
  `OmniboxResults`/`OmniboxRow`: 13 pt rows, favicons, accent-filled selection with white text like a menu item, and in
  dropdowns (`TopAddressSuggestionPopup`) the system material. Selection updates immediately without matched geometry or
  spring motion.
  Full screen is Ikago's own (`BrowserWindow.toggleFullScreen` → `BrowserWindowController+FullScreen`), because macOS's slides
  a titlebar strip over the bars whenever the menu bar shows: the window covers the display, Dock and menu bar auto-hide while
  it is key, the shell starts below a black camera band (`fullScreenTopBand`), the page goes edge to edge (`state.isImmersive`), the
  sidebar peeks from the left edge and the top bars drop in from the top (`TopBarReveal`), staying while `chrome.holdsPeek`,
  and `FullScreenWindowControls` draws the traffic lights with the revealed chrome. Settings ▸ Appearance can drop the band
  (`fullScreenUnderNotch`). The Sidebar layout has three states: full, a rail of icons (`SidebarRail`, `sidebarCompact`, ⌃⌘S),
  hidden (`sidebarVisible`, ⇧⌘S); the sidebar button cycles all three (`cycleSidebar`). The rail stacks Ikago-drawn traffic
  lights in a column and shows groups as one tile each. Groups show `FolderIcon` (`TabFolder.icon`: an SF Symbol or an emoji,
  a folder in the group's color by default); an open group sits on a light fill of its color. In full screen, revealed bars and lights start below the menu bar
  (`immersiveChromeTop`). Check full screen with `window.isInFullScreen`, never `styleMask.contains(.fullScreen)`. Native traffic-light origins convert through the content view on both axes; test their actual
  frames against the rendered toolbar at multiple window sizes and after layout changes.


## 7. Private SPI in use

The inspector entries are guarded with `responds(to:)`, so a WebKit change disables the feature
instead of crashing. They live in `WebTab.swift` and are toggled by Settings ▸ Developer tools.

- `WKPreferences` key `developerExtrasEnabled`: adds Inspect Element to the page's context menu.
- `WKWebView._inspector` (`show`, `close`, `isVisible`): opens Ikago's own docked Web
  Inspector (⌥⌘I). The only public alternative is Safari's Develop menu.
- `WKHTTPCookieStore._flushCookiesToDiskWithCompletionHandler:` (`WebProfiles.flushCookies`): writes
  cookies to disk before quitting; guarded by `responds(to:)` and a timeout. No public flush exists.
- `WKUIDelegatePrivate` `_webView:saveDataToFile:suggestedFilename:mimeType:originatingURL:` (`WebTab+Delegates`):
  WebKit's PDF viewer download button delivers the file here, not as a `WKDownload`; saved via `DownloadCenter.save`.
- AppKit's Edit ▸ AutoFill ▸ Passwords… item, found by its private identifier/action
  `_handleInsertFromPasswordsCommand:` (`SystemPasswordPanel` in `PasswordAutoFill.swift`). Opening it
  posts the Edit menu's begin/end tracking notifications, because AppKit refreshes the item only then.
  If the item is missing, the sign-in key stays hidden. Toggled by Settings ▸ Security ▸ Passwords.

- `responsibility_get_pid_responsible_for_pid` (`PerformanceSampler`, looked up with `dlsym`): finds the WebKit processes that
  belong to Ikago, which launchd starts. Without it the performance overlay counts the app and its child processes only.

## 8. Chromium engine

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
- Opt-in (Settings ▸ Engine ▸ Sound on Chromium, `chromiumLiveWave`, off by default and described with its delay):
  Chromium pages' sound is played by Ikago (`IKCEFAudio`): CEF's `CefAudioHandler` hands over each page's PCM and mutes
  the page's own output, and one `AVAudioEngine` plays it, so the media island's wave follows the real sound with no
  capture permission or recording indicator (Core Audio taps need both). Measured with `--cef-smoke-audio`: packets
  arrive ~21 ms after Chromium mixes them and wait 17–23 ms here (256-frame packets, one packet of slack, backlog
  trimmed), no underruns, so about 40 ms more audio delay. Off, `GetAudioParameters` declines and Chromium plays its own
  sound untouched (checked with `--cef-smoke-audio-off`); the setting applies when a page next starts playing. Ikago's mute applies to this playback (`IKCEFSetAudioMuted`, also before a stream starts).
  WebKit's sound never passes through Ikago; never route a page's media through Web Audio to read it (cross-origin,
  redirected and HLS media go silent).
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
