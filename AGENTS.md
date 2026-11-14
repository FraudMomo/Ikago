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
1b. **Never change a user's engine silently.** A new profile starts on `BrowserState.newProfileEngine` (Chromium) and the
   welcome page (`ikago://welcome`) asks before any site loads; after that the engine changes only by the person's choice,
   on relaunch. Sites can have their own engine (§8, per-site engines), but only by the person's choice: lists are
   suggestions they assign, never defaults. New profiles take their look from `applyNewProfileDefaults`; saved profiles
   keep their own values, so optional preferences keep their old meaning when unset.
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
├── UI/          Window/ (controllers), Content/ (tab panes), Shell/ (root view), Toolbar/ (customizable controls),
│                Tabs/ (Sidebar + Tabs row), Sidebar/, Address/,
│                Overlays/, Pages/ (ikago:// pages), Settings/, Downloads/, Design/ (Palette, glass buttons, logos)
├── Checks/      Chromium/ (runtime checks, IKAGO_CHECKS builds), Debug/ (WebKit test driver, DEBUG builds)
└── Resources/   Info.plist, entitlements, Assets.xcassets

CEF/             Objective-C++ bridge, CMake build, pinned SDK (cef-lock.json)
scripts/         build.py, package_app.py, install.sh, fetch_cef.py, check_cef_update.py, run_chromium_checks.py
```

Build with `python3 scripts/build.py` (`--flavor release|checks|debug`). `Checks/` is left out of release
builds. Release packaging keeps the matching unstripped app binary in `out/symbols/` and removes local symbols from
the distributed executable before signing. Generated: `.cef/` (the SDK), `build/`, `out/`. Minimum macOS 26 (Liquid Glass; `WKWebExtension`
itself needs 15.4). Bundle ID `app.ikago.browser`; data lives in the protected app group container
`<team>.app.ikago.browser` (`ProtectedStorage`), or `Application Support/Ikago` in ad hoc builds.

Packaging retains only English CEF UI locale packs (including English variants), matching Ikago's UI; the SDK stays intact.
Keep `en.lproj` as the fallback and keep ICU, shared `.pak` files, snapshots and graphics libraries. Multilingual webpage
text and international formatting remain available; `CEFLocaleChecks` verifies missing-locale fallback and native controls.

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
   The sidebar and the Sidebar + Tabs row run in their own `NSHostingView`s (`IsolatedHost`) so their updates don't walk the
   whole window's graph; anchors can't cross hosts, so the Downloads button's frame reaches the shell through
   `ChromeModel.downloadsButtonFrame`, published after layout (never during it).
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
    The opt-in `focusAddressBarOnNewTab` setting focuses the address after opening the chosen
    homepage/extension provider, using current-tab navigation and an empty query. Use the floating
    field if the integrated field is hidden. BrowserWindow rejects page focus before resigning
    the address editor; explicit browser commands reset editing intentionally. Page reconciliation
    must not steal the keyboard, and outgoing field transitions must not leave it unfocused.
    BrowserWindow dismisses address editing on outside mouse-downs across the whole window,
    preserving the original click. Address fields and results mark their bounds with
    AddressInteractionRegion so cursor placement, popup actions and clear buttons keep working.
    Typing straight after ⌘L/⌘T never loses letters: keys that arrive before the field has the keyboard go to its text
    (`BrowserWindow.typeAhead`), and the field selects all only while nothing has been typed (`palette.edited`,
    `selectsAllOnFocus`), or a late re-focus selects the first letters and the next keystroke replaces them (`typefast`).
13. **Toolbar controls come from `state.chromeLayout`** (`ChromeLayout`: the sidebar's top row and bottom bar, lists of
    `ChromeItem`), drawn by `ChromeItemView`. New controls get a `ChromeItem` case so users can place them. "Chrome" in
    these names means the browser's own UI, not Google Chrome.

---

## 4. Design

1. **Clean first.** No decorative icons or labels; secondary actions appear on hover or in
   context menus. Ikago's own pages (Settings, History, Downloads, Bookmarks) are `ikago://` tabs
   (`InternalPage`), never separate windows or panels.
2. **Corners come from `Radius`** (6 inner, 8 control, 10 row, 12 card, 16 sheet, 26 bar for the Spotlight-style command bar): pick by the surface's size, never a
   one-off literal (small Settings mockups excepted).
2a. **Floating surfaces use `.surface(shape, palette)`**: Liquid Glass, or a flat panel when the
   user turns glass off (Settings ▸ Appearance). With the frosted sidebar (`frostedChrome`) the window itself is the one frosted
   layer (`WindowBackgroundView`: vibrant `.sidebar` blur under a light Space wash), and docked sidebars, the rail and
   the tab row draw no material of their own (`sidebarJoinsWindow`), since stacked blurs read flat and grey; floating
   sidebars (the peek) use `surface(..., translucentSidebar:)`. Honor Reduce Transparency and preserve readable Space tint. Never call `glassEffect` directly. Glass can't
   render offscreen, so drag previews use plain fills. Related icon controls share one reactive capsule (`GlassControlGroup`); a lone control uses
   `glassControl`, which adds nothing inside a group. Don't merge separate glass circles in a container: they melt together with visible necks.
   Don't switch styles with an `if` around large subtrees: `glassButtons` is one style that decides inside, because
   an `if` at the root rebuilds the window on change and overflowed the stack when a page inserted a button.
3. **Space colors tint the full chrome**, including flat sidebars and the Sidebar + Tabs row. Use
   `state.palette` and `.surface`; glass surfaces retain the Space tint. Keep page contents
   neutral, provide readable ink for arbitrary custom colors, and let website theme colors
   blend subtly rather than replace the Space's identity. Margins follow `state.frameInset`.
4. **The tab row moves; everything else stays immediate.** `TabMotion` (`TabSlotMotion.swift`, a 200 ms ease-out)
   animates the Sidebar + Tabs row's *structure*: an opened tab's slot grows in while neighbours and the + button slide;
   a closed tab (closed at once, no delay) shrinks out; reorders reflow. A settled slot isn't clipped, so an attached
   tab's flares reach into the page. The row animates only on `TabMotionKey` (item ids) through `tabStripMotion`, which
   blocks callers' transactions. Selection, address editing, window resizes and Space switches stay immediate, and so does
   suggestion selection. Titles crossfade over 100 ms, hover fills fade (~0.1s in, 0.2s out), and the address
   field eases its focus fill/ring. Respect Reduce Motion. Other changes animate quickly: `Animation.ikago`
   (0.2s) or `.ikagoQuick` (0.12s). Sidebar selection highlights follow the configured `TabSelectionHighlight` style.
5. **One layout, the sidebar, with an optional tab row.** Settings ▸ Appearance ▸ Layout (`LayoutChoice`) picks Sidebar or
   Sidebar + Tabs (`browserPreferences.sidebarTopTabs`, `state.usesTabsLayout`, `state.showsSidebarTopTabs`): `SidebarTopTabs` (its own
   `IsolatedHost`) shows the Space's ungrouped tabs above the page as arched, attached tabs (`AttachedTabShape`), and
   `TabsToolbar` (its own host) is the top of the page card: navigation left, the centred address field, other controls right;
   the page's top corners are square under it (`WebTabContainerView.squareTop`). The address bar is 36 pt with no rule under it; the active tab and the bar share `tabSheetColor` (the page color, see-through when frosted), so tab and bar read as one lighter sheet that settles into the solid page. There is no full sidebar in this layout:
   the sidebar is a rail of pins and groups below the tab row, or hidden (its peek is the rail). New tabs open on the right
   (`effectiveNewTabPosition`); the address frame reaches the shell through `ChromeModel.addressFieldFrame`. There is one `ContentHost`, so turning the row on or off never moves the page.
   Switching layouts goes through `LayoutSwitch.set`: the new layout is built in one frame with animations disabled and
   the window cross-fades (a `CATransition` on its layer); never animate the switch's geometry, which resized every page
   and rebuilt the sidebar list each frame (measure with `layoutprobe`). The Top Bar
   layout was removed; sessions saved with it (or the older Chrome layout) open as Sidebar + Tabs, and their saved Top Bar
   fields are ignored. Sidebar groups are tinted cards or an indented folder list (`SidebarGroupStyle`); group
   headers line up with tab rows (icon where favicons sit), with semibold names and the chevron right after the name (a pill keeps
   it at the far end). Groups nest (`TabFolder.parentID`, optional; `BrowserState+NestedGroups`, `GroupEntry.tree`): nested
   groups sit inside the top-level group's card as plain, indented headers, listed before the group's own tabs; counts, sleep
   and the active tab cover the subtree; deleting a group moves its tabs and groups up a level; moves into a group's own
   subtree are refused (`nestedgroupchecks`). The rail shows top-level groups only, and the Color pill label fills the header like a book's bookmark: a light wash of the group's color, a solid 3 pt spine on the leading edge, `Radius.control` corners; a group whose tabs are all closed or asleep fades to half until hovered (rail tiles too); closed groups stack 4 pt apart, and a hairline separates pinned rows from groups. With glass off the
   docked sidebar joins the window (`sidebarJoinsWindow`): it draws no card, so sidebar and tab row are one surface and only the
   page is rounded. The traffic lights, the sidebar's top row and the tab row share one centre (`sidebarRowCenter`);
   `positionTrafficLights` sets both axes in every layout. Top-row controls that don't fit beside the lights move to a second
   row (`SidebarView.topRowCapacity`), never under them. An optional Space header and shortcut rows (`SidebarShortcuts`,
   `sidebarShortcuts`) sit under the top row.
6. **Extensions live in the site-and-extensions popover** in the address field. It is Ikago's own card over the window
   (`SiteInfoOverlay`, `ChromeModel.showSiteInfo`, centred under its button, from the address bar's frame in Sidebar + Tabs; a click outside or Esc closes
   it; the button sits beside the address button, never inside its label or overlay, which took the first click), never an NSPopover: one hung from the hover button closed the moment it opened, and its see-through material made
   the text unreadable. The card is a `modalSurface` on the chrome palette (Liquid Glass with little Space tint when on,
   the frosted window's material with the translucent sidebar, solid otherwise) that grows out of its button on a short
   spring. Rows have white symbols on colored circles (`SiteSettingRow`, `SettingTile`); choices are `CompactMenu`s, a
   white pill opening a real `NSMenu` (SwiftUI's `Menu` drops a custom label's background on macOS); controls answer a
   press (`SiteCardPressStyle`). Zoom moves in 10 % steps (`PageZoom`, also ⌘+/⌘−) with Reset away from 100 %. Its card
   holds the site's settings (`SiteSettingsCard`): camera and microphone Ask/Allow/Block (`SitePermissions`, applied by
   `rememberedDecision` before any prompt; private windows always ask), engine, tracker blocking, keep awake, zoom, and
   Clear Site Data (that site only, both engines). An extension's page (Momentum's new tab) shows its extension's icon
   (`ExtensionPageIcon`): its own icon can't be fetched outside the page. On WebKit use native
   `performAction` and popup anchors; on Chromium popups open in `ChromiumExtensionPopup`.
7. **Settings is quiet and ordered: one sub-page at a time.** A 220 pt navigation column on a slightly quieter background: a small
   "Settings" heading, a search field (`SettingsSearch`: add every new setting to its index, with the `PageSection` title it lives
   under), categories under small group headings (Personalize, Your Browsing), monochrome outline symbols, a neutral fill for the
   selected row (no colored tiles, no accent fill, no chevron). Pages use `PageScaffold` on `SettingsColors.page`; Settings pages open
   with a 24 pt title and one short descriptive line, no artwork, then a segmented bar of the category's sub-pages (`SettingsSubpage`,
   `SettingsSubnav`; the chosen one rides a sliding pill). A sub-page lists the `PageSection` titles it shows
   (`settingsVisibleSections`): a new section must be added to one, or it never appears. Search results open the sub-page holding
   their section. Inside Settings (`settingsSurface`), `PageSection` is a card (`SettingsColors.card`, 14 pt corners, hairline rim,
   soft shadow) with its 13 pt semibold heading inside and rows divided by hairlines; its footer sits under the card. Elsewhere
   `PageSection` keeps its soft 12 pt panel. Keep visual previews where a choice is about looks (layout cards, color mode, group
   label style, the sidebar and toolbar editor's figure). `PageRow`:
   56 pt rows with 13 pt medium titles and 12 pt subtitles in Settings (44 pt elsewhere), no decorative per-row icons; an engine logo
   beside an engine choice shows its value. Controls come from `SettingsControls`: `SettingsMenu` (a white pill opening a native
   menu, never a stock pop-up button), `SettingsSegmented` (sliding pill), `SettingsButtonStyle` (white pill, or `prominent` in the
   accent; never blue text), native switches and sliders, all in `SettingsColors.accent` (a soft iris, `Color.settingsAccent` where
   the palette isn't at hand), never the system blue. Narrow windows show `SettingsCategoryMenu` instead of the column. Titles and subtitles describe; they never sell ("Import", not "Bring Your
   Browser to Ikago"). Search engines show their favicons (`SearchEngineIcons`). Subtitles are a few words and footers one short sentence, or none. No ambient glows, tinted cards or rounded
   display fonts. `.ikago` animations never overshoot.

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
  grids fall back to tab-list rows so pinned tabs stay reachable. The grid uses a saved two-to-eight column preference (three by default),
  adapting down with the sidebar's available width, with bounded scrolling and an
  empty drop target during tab drags. Split drops accept live tabs only. Tab rows use SwiftUI's
  drag/drop lifecycle with before/after insertion markers, without native overlays intercepting
  row input or mutating order during hover. Read the payload asynchronously before committing
  a move so the source view is not rearranged inside a native drop callback.
  Move split groups together, keep sidebar reflow to 0.12 s, and respect Reduce Motion.
  Group headers accept membership drops explicitly; only web-page split targets intercept input
  through a native overlay.
  Pin Tab creates a standalone sidebar row. Dragging into the essentials grid makes it a tile;
  fixed section-boundary targets place standalone pins above or below groups (`pinAfterFolderID`, optional on saved tabs).
  Dropping on a regular row or at the normal list end unpins. Keep drop geometry mounted so starting a drag never shifts rows.
  Use one Pin/Unpin action; placement is drag-driven.
  Closing a pin unloads its page and retains its identity; only unpinning/removal deletes it.
  Persist favicon URLs on tabs/bookmarks and retain disk icons without age expiry.
  Favicon views synchronously seed from disk/memory; never clear a working same-site image
  on view task restarts or failed fetches. Page/site aliases retain the last valid image across
  changing icon URLs. Validate fetched replacements before updating tab/bookmark metadata,
  and reject late results from a different page or document.
  Icons follow Ikago's light/dark mode: `FaviconScript` picks the `<link rel=icon>` whose `media` matches Ikago's mode (both
  engines, isolated world; open pages pick again once on a mode switch), the page/site last-good entries are kept per mode
  (`FaviconCache.modeKey`, older unsuffixed entries are a fallback), and SVG icons have their `prefers-color-scheme` CSS
  resolved before decoding, because macOS's SVG renderer always draws the light style. Stored bytes are never duplicated
  per mode; only small decoded images are (`faviconappearancechecks`).
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
- View ▸ Performance opens `ikago://performance`: per-engine and shared process footprint/CPU, main renderer tab rows,
  GPU service CPU/RAM (never presented as GPU utilization), and a bounded RAM history. `PerformanceMonitor` shares one
  off-main sampler among visible diagnostics and stops when no consumers remain. Hidden Performance tabs unmount their
  dashboard. Renderer totals may be shared by tabs and exclude separate subframes; never add tab rows to browser totals.
  CEF's renderer helper reports its PID over native process messages, not page scripts. `PageLifetimeCanary` watches
  retired page owners/views weakly, checks every 30 seconds only while records remain (cap 200), and flags retention
  without claiming a proven leak. No page contents, URLs, dumps or canary data are written to disk.
- The sidebar's media island (`SidebarMediaPlayer`) is one clean row on the sidebar's own glass (`.surface` with the chrome
  palette; a flat panel with glass off): artwork, Media Session title and artist, and Play/Pause and Next always in reach.
  Clicking the title opens the card with mute, PiP and the source picker. Artwork comes from `MediaArtwork` (cookie-free, raster only, memory only).
  Artwork falls back to the playing media's poster and HTTPS page thumbnails when isolated-world metadata is absent;
  decode only a bounded 160 px thumbnail. Mute and Next have equal hit targets around the centred Play/Pause button;
  the source picker lives in the header so it cannot shift playback controls. Close stays inside the island.
  Playback indicators stay static; no waveform timer or audio analysis. Closing it hides it until
  something new plays. Opening, closing and appearing run in the island's own `withAnimation` (`Animation.island`), so
  the sidebar list gives way smoothly (measured with `islandprobe`); never an implicit `.animation` here.
- Completed download rows open files on a single click via a dedicated button; cancel and
  Show in Finder are separate hit targets. Keep popup styling on the current chrome palette
  and shared surface; a missing file or failed open reports an error without removing history.
- Downloads use a dropdown anchored to the sidebar's Downloads control, plus `ikago://downloads` for
  full history. `DownloadCenter` owns byte progress and cancellation; `DownloadHistoryStore` saves
  owner-only atomic history with backup (up to 1,000 entries). Keep completed/failed/cancelled
  entries across relaunches, restore unfinished entries as interrupted, and never delete files
  when clearing history. The automatic toolbar control stays for active/recent (24-hour) downloads started since launch (history restored at launch never brings it back);
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
- Window dragging: a `WindowDragArea` sits *behind* the sidebar's and the tab row's content, so any empty space there
  moves the window, and behind the page card and the whole layout, so the window margins do too (the hidden sidebar's
  hover edge is one). The tab row's scroll view is only as tall as the tabs, so the strip above them moves the window
  (`sidebarinteractionchecks` hit-tests it). Never cover bars with a drag overlay plus exclusion rects.
- In every layout a still press-and-hold (0.12 s) within 10 pt of the page's top edge (web pages and
  `pageSurface`-marked internal, error and empty pages) becomes a
  window drag (`PageWindowGrab`, a passive local event monitor; no view, inset or overlay). The page
  receives every press immediately; moving first, double-clicks, modified clicks, split headers and
  overlays stay with the page. A grab ends the page's press away from it and drops the later mouse-up.
- Split drops use a permanently mounted AppKit SplitDropTarget above WKWebView, with
  preview and acceptance driven by native dragging callbacks. Transparent SwiftUI-only drop
  surfaces can fall through to embedded pages. Decode TabDrag from the live pasteboard
  rather than transient chrome drag state. In Sidebar + Tabs only panes along the top have square tops
  (`TabHostView.touchesTop`); which corners are the bottom follows the pane view's own `isFlipped`
  (a backing layer uses its view's coordinates; the layer's `isGeometryFlipped` follows the flipped NSSplitView around it
  and must not be used), re-applied whenever it moves; check with the `corners:<png>` test action. In the tab row a split pair shows, on hover, a close button per tab and a
  centred Separate button (`SplitTabButton`, `unsplitGroup`). Pane headers (`PaneHeaderView`) are a small frosted pill centred at the pane's
  top that fades in only while the pointer is near that edge (`TabHostView.onMove`) and fades out otherwise, so they never
  cover the page at rest; they use native independent drag handles/buttons; page focus must not interrupt header controls.
  Switching tabs moves page views straight between panes and the hidden parking view, never out of the window: a Chromium page taken out of the window is resized to 0×0, and ChatGPT lost its scroll position and blinked on return (`CEFTabSwitchChecks`). Never call `removeArrangedSubview` (it removes the view from the window; split views arrange all their subviews, so moving one is enough), and a parked view goes back to autoresizing (a split view put it on Auto Layout, which sized it 0×0 in parking). A Chromium page gets one fresh resize the first time it shows (`CEFWebTab.visibilityChanged`), since an adopted link tab could stay blank. Each split keeps its panes' shares across resizes (`PaneSplitView.layout`): Auto Layout alone gave a resize to one pane, and a layout switch collapsed a grid's column to 0 pt (measure with the `panes` test action). Dropping the active unsplit tab creates a `ikago://split-empty` slot. Filling the slot
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
  at most `OmniboxEngine.maxResults`. Any page visited, open or bookmarked inline-autocompletes to
  its host root while the input is within the host (Safari's top hit); past the host only pages typed, visited ≥ 3
  times or bookmarked complete. Inline completion follows
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
- Swiping Back/Forward across an engine handoff (`HistorySwipe`): a passive scroll monitor follows a sideways
  two-finger swipe with an arrow at the page's edge, only where the page's own history ends and a parked page of the
  other engine waits, and navigates on release past 110 pt. It never swallows events. CEF reports no unconsumed scroll,
  so Chromium offers no swipe within its own history (a sideways pan in maps or carousels must not go Back).
- Several regular windows, as in Chrome (`BrowserWindows`, `BrowserState+Windows`): each window has its own `BrowserState`
  with its own tabs, groups, splits and recently closed; Spaces, settings, history and bookmarks are shared, copied between
  the windows' states when any changes them (`readShared`/`shareChanges`, each field only when it differs). The first
  window's state (`BrowserWindows.primary`) owns the session and saves the others in `Session.windows` (`WindowSession`:
  tabs, groups, splits, frame); the others' saves forward to it, and they reopen at launch. File ▸ New Window (⌘N), Tab ▸
  Move Tab to New Window (and the tab menu), a tab dragged out of every Ikago window (`ChromeModel.onTabDragEnded` →
  `tearOff`: a new window under the pointer; a window's only tab moves the window instead) and a tab dropped on another
  window's tabs (`TabDrag.load(_:into:)` → `bring`) all move the tab with its live page (`WebContentViewController.release`
  / `adopt`, `TabController.releasePage`): never reload it. A window after the first closes with its last tab, and its
  tabs join recently closed; closing the first window while others are open hands it another window's tabs and place
  (`handOver`) so the session keeps its owner. Private windows stay apart: no moves in or out. Check with `windowchecks`.
- History (`ikago://history` and Settings ▸ History share `HistoryBrowser`): newest first, grouped by day or by site
  (`HistoryGroup.build`, once per change of history, search or arrangement, never in `body`; search waits 150 ms), groups
  folded except the newest, an open group showing 25 rows with Show More. Clear Browsing Data (`ClearDataSheet` over the
  window, `ChromeModel.showClearData`, from the History page, Settings, the History menu ⇧⌘⌫ and the address bar's action)
  takes a period (last hour, today, since yesterday, all time, custom days) and what to remove: browsing history, search
  history (search result pages, `Visit.isSearch`), cookies and website data, caches, recently closed tabs, the downloads
  list, site icons (`BrowserState.clearData`, on the first window's state, then the session backup is discarded). WebKit
  clears website data by time; Chromium has no time filter, so a period clears the sites visited in it
  (`ChromiumWebsiteData.clear(onlyKnown:)`). Check with `historychecks`.
- Back history survives relaunch, unloading and ⌘⇧T (`TabHistory` on `TabItem`/`SavedTab`, recorded when a page finishes
  loading, `TabController+History`): WebKit restores its own `interactionState` (≤ 32 KB); every engine keeps up to 12 Back
  addresses, which Chromium (no API to restore entries) walks with `replace(with:)` so the page's own Back never points
  forward (`CEFHistoryChecks`). Private windows keep none.
- The media script stays cheap on huge, changing pages (Pinterest): mutations are looked at once a quarter second (only
  the added elements themselves, never their subtrees; deeper shadow roots are found on load, clicks and keys), no
  layout-forcing reads (`getClientRects`) in reports, artwork only for playing media, and WebKit reports once per burst.
  Silent autoplay previews never report: only media that has been heard, errors and volume changes do.
- Closing the active tab follows Chrome: back to its opener (`TabItem.openerID`, set for link tabs and forgotten once
  another tab is chosen), then its split partner, then the tab to the right, then the left. ⌘⇧T reopens a tab in its
  Space, group and place (`SavedTab.after`) and selects it. Closing a top tab with the mouse keeps the others' width until
  the pointer leaves the row, as Chrome does. In Sidebar + Tabs, tabs opened from a pin open on the right.
- The sidebar's top row and bottom bar each have a left, centre and right place (`ChromeZone`, `ChromeLayout.topLeading`,
  `topCenter`, `sidebarTop` = right; `bottomLeading`, `sidebarBottom` = centre, `bottomTrailing`), filled by dragging in
  Settings ▸ Sidebar & Toolbar ▸ Customize; the centre stays centred, and left/centre top groups start after the traffic
  lights. Too many for one row wrap to a second row on the right as before. Readers of a whole row use `topItems`/`bottomItems`. A two-finger swipe over the sidebar pages between Spaces live (`SpaceSwipe`):
  pins and tabs follow the fingers, and the next Space comes in on release past a third or after a flick; otherwise it
  springs back. With Liquid Glass on, every chrome control is glass: toolbar groups, the Sidebar + Tabs controls and
  address field, the tab row's +, rail tiles and pinned tiles.
- New-tab placement is configurable (top/bottom); links can open before/after their opener or
  follow the new-tab setting. Preserve manual order and other Spaces; adjacent links inherit the
  opener's group, while normal new tabs remain loose and unpinned. All link paths, including
  WebKit popups, use `newTabFromLink`. `WKNavigationAction.buttonNumber` is a mask (middle = 4),
  unlike AppKit's index (middle = 2); middle-click opens in the background, Shift selects it.
- Browser preferences and bookmarks persist with the session; keep new session fields optional
  so existing profiles restore. `TabMemoryManagement` responds to macOS memory pressure, never an idle clock or a RAM
  quota. Conservative reclaims safe inactive pages on warnings; Responsive waits for critical pressure. Visible split
  panes, loading/playing/capturing pages, popups, protected pins/sites, drafts and native navigation history are protected.
  Failed inspection retains a page. Safe parked engine-history documents can release their views while retaining their
  Back/Forward destination and engine. Wake through `startIfNeeded()`. New profiles use Conservative; saved profiles
  map the former hibernation opt-in to Conservative and other profiles to Responsive unless a new choice was saved.
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

- Closed tab groups (`TabFolder.isClosed`, `BrowserState+ClosedGroups`) came from the retired Top Bar's Close Group. Their
  pages stay unloaded until reopened from Tab ▸ Reopen Closed Group or by selecting one of their tabs; the sidebar lists
  them, and `navigationOrder` is the sidebar's order.
- Bookmarks show in an optional upward-expanding drawer at the bottom of the sidebar. ⇧⌘B and Settings ▸ Sidebar &
  Toolbar toggle the same saved preference. Bookmarks and
  nested `BookmarkFolder`s are shared across Spaces and independent of live tab groups; keep
  session additions optional, validate folder trees, and never delete saved pages when removing
  a folder. Bookmark drops save live tabs without closing them.
- The tab row has static selection; insertion follows `TabMotion`. ActiveTabScrollAnchor reports document-space geometry to
  one always-mounted native viewport owner: reveal clipped edges (including the active tab's flares), never recenter an
  already-visible active tab through a delayed SwiftUI scroll proxy.
- Integrated address editing uses opaque light/dark surfaces independent of glass. Every address presentation shares
  `OmniboxResults`/`OmniboxRow`, laid out like Spotlight: bare icons, 13–14 pt titles, a neutral rounded fill for the
  selection (text keeps its colors), the top hits without a heading and other sections headed over a hairline with
  "Show More" (opens the matching scope). The floating bar (`CommandPaletteView`, `Radius.bar`) is a capsule with a 22 pt
  field that opens into a card; the highlighted result's icon sits at its end and what Return does follows the text
  ("— Open", "— Search", "— Switch to Tab", "— Run"); with nothing typed it lists the scopes. The inline field leads with
  the highlighted result's icon.
  Browser commands and every setting are results too (`PaletteAction`, source `.action`, `ikago-action:` URLs, at most
  three, from 1215 down, only those that apply): commands in `PaletteActionCatalog` (tabs, windows, split view, appearance
  such as Light/Dark/System, layouts and sidebar styles, pages, places), settings registered from `SettingsSearch.index`
  (opens Settings at the section via `BrowserState.pendingSettingsSection`). Commands show their shortcut, settings where
  they live; each is aimed at its own window (`perform(in:)`, handlers in `BrowserWindowController+PaletteActions`),
  never sent to whichever window is key. Results are
  grouped under headings (`CommandPaletteModel.grouped`/`sections`: Top Hit, then Search, Open Tabs, Pages, Actions in
  ranked order). Scopes, after Spotlight's filters (`AddressScope`: Tabs ⌘1, History ⌘2, Bookmarks ⌘3, Actions ⌘4, which
  win over Select Tab while the field has the keyboard via `FocusingTextField.onCommandDigit`), list every match of one
  kind; a scope shows as a token, and Esc or ⌫ on an empty field leaves it. Address cards are solid
  (`AddressSurface`, `AddressAppearance`) and frosted only when `frostedChrome` is on, never Liquid Glass. Selection updates
  immediately without matched geometry or spring motion.
  Full screen is Ikago's own (`BrowserWindow.toggleFullScreen` → `BrowserWindowController+FullScreen`), because macOS's slides
  a titlebar strip over the bars whenever the menu bar shows: the window covers the display, Dock and menu bar auto-hide while
  it is key, the shell starts below a black camera band (`fullScreenTopBand`), the page goes edge to edge (`state.isImmersive`), the
  sidebar peeks from the left edge, staying while `chrome.holdsPeek`,
  and `FullScreenWindowControls` draws the traffic lights with the revealed chrome. Settings ▸ Appearance can drop the band
  (`fullScreenUnderNotch`). The sidebar has three states: full, a rail of icons (`SidebarRail`, `sidebarCompact`, ⌃⌘S),
  hidden (`sidebarVisible`, ⇧⌘S); the sidebar button cycles all three (`cycleSidebar`). The rail stacks Ikago-drawn traffic
  lights in a column (`FullScreenWindowControls`, kept directly above the shell view, never above the first subview: with the frosted window that is the material, and the shell covered the buttons; `railhit:click` checks) and shows groups as one tile each. Groups show `FolderIcon` (`TabFolder.icon`: an SF Symbol or an emoji,
  a folder in the group's color by default); an open group sits on a light fill of its color. In full screen, the revealed sidebar and lights start below the menu bar
  (`immersiveChromeTop`). Check full screen with `window.isInFullScreen`, never `styleMask.contains(.fullScreen)`. Native traffic-light origins convert through the content view on both axes; `sizingchecks` tests their actual
  frames against `sidebarRowCenter` at several window sizes, with and without the tab row.


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

- `WKWebView._isPlayingAudio` (`PlayingAudioObserver`, KVO, guarded by `responds(to:)`): WebKit's own audible flag, so
  Web Audio, detached `Audio` elements and closed shadow roots still show the tab's speaker. The media script stays the
  source for playback controls. When the flag is available it alone decides the tab's speaker; the script's reports are keyed per document (a random
  `documentID`, cleared on pagehide), never by frame address, which pushState changes and left stale "playing" reports.

- `_webProcessIdentifier` (`PagePerformance`, checked before calling): maps a WebKit tab to its renderer for the visible
  Performance page and demand-driven tab preview. There is no public mapping; absence returns unavailable. It never changes page behavior.

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


## 9. Optional browser tools and layout choices

- Modals share `ModalDesign`: with glass off, solid neutral sheets (`ModalMetrics.card`, 16 pt corners, hairline rim, a contact
  and an ambient `CardShadow`); 15 pt semibold headings, 32 pt fields, an accent default button beside bordered secondary ones,
  and a full-width hairline above the footer.
  Cast shadows from `CardShadow`, never the changing card contents. Settings appearance choices show light/dark/system previews.
- Group appearance uses a bounded integrated editor with a local icon/color draft. The default icon stays a folder, even with several tabs.
  Use Emoji opens the public macOS character picker through a native text input client. Done saves both choices;
  Cancel, Esc and outside clicks discard the draft. Keep the preview and selected states visible in both color modes.

- Notes (`ikago://notes`) shares an observable buffer, saves only dirty edits through `SealedStorage`, flushes on quit,
  and fails closed on read/decrypt errors. Private buffers are memory-only and discarded with their window. Checks use temporary storage.
- Page assistance is off by default. Its panel (`PageAssistantView`) is a page-colored card beside the page with the page card's
  margins: header, conversation, suggestions and a composer naming the page it reads. With the translucent sidebar it draws no
  card and sits on the frosted window. Enabling it seeds a customizable sidebar control; moves and explicit removal persist.
  Existing enabled profiles receive this placement once (`assistantToolbarInitialized`). Disabled assistance has no live control or open pane.
  Apple Foundation Models runs on-device only, checks model availability, and reads a bounded
  isolated-world page excerpt only on an explicit request. It has no browser tools; page content is untrusted data. Cancel on tab change or close.
- Native page menus keep WebKit editing and media actions. Search stays in Ikago; translation explicitly names Google.
  Direct media can open in a floating AVKit player; protected and page-managed streams retain engine-owned PiP controls.
- Shared Spaces use the Default cookie store. Switching sharing releases old pages and reopens with the selected store; it never copies cookies.
- The sidebar can sit on either side; window controls optionally follow it. Page bounds must never overlap the docked bars.
- When a clicked link opens in Peek is a setting (Settings ▸ Tabs ▸ Peek, `LinkPeek`): Off (Shift-click opens a new tab),
  Shift-click (default), or Automatically, which also peeks links to other sites from pinned tabs and from search results,
  and optionally every link that would open a new tab. Both engines ask `WebTabDelegate.webTab(_:peeks:trigger:)` →
  `BrowserState.peeks` (WebKit's navigation and popup policies; Chromium's `IKCEFPage.peekHandler` from `OnBeforePopup`
  and `OnBeforeBrowse`); a page shown in Peek never peeks its own links (`selectionpeekchecks`).
- Tabs select like Finder's (`TabClick`): Shift-click a range in sidebar order, ⌘-click one more, ⌥-click to peek, a plain
  click opens a tab and ends the selection (`ChromeModel.selectedTabIDs`, tinted with `tabSelectionTint`). Their menu
  moves, groups or closes them all, and dragging one carries the rest (`TabDrag.companions`, taken by every drop through
  `TabDrag.travelling`, group headers included), including out to a new window; the drag shows a stack with a count badge
  and the others fade while they travel (`travellingWithDrag`). A drop's payload arrives after the drag-out check
  (`tabDraggedOut`, 250 ms after release), so that check takes the companions only when the pointer left every window;
  several tabs placed after one row go in last-first to keep their order. Measure with `dragprobe` and a real posted drag.
- Shift-clicking a link (both engines) opens Peek (`peekLink`, `LivePeekPanel`): the page in a large floating card over
  the dimmed window, its site above it and a glass column beside it to close it or keep it as a tab; it is never in the tab
  list unless kept. Keeping it grows the card onto the page's place (`chrome.peekExpanding`, `peekTarget`), then the same live
  page becomes a tab placed like a link from the current tab (`newTabFromLink`, `content.adopt(_:fromPeek:)`), shown without the switch
  fade (`switchesInstantly`), on both engines with no reload. Two rules keep a Chromium page drawing in place: while the card grows the
  page takes its final size once and only its origin follows the card (`PeekAnchorView.fixedSize`), because a stream of animated
  resizes made Chromium's own layers drift taller than its view (36 pt, page shifted up) and no later resize undoes that; and the page
  moves straight into the tab's view, never out of the window (`releasePage(inWindow:)`). The preview's page
  sits in a plain AppKit view over the card (`PeekAnchorView`), never inside SwiftUI's host. `peekshot:<dir>` measures where
  a kept page really draws from the window's pixels; for Chromium run it with `IKAGO_CEF_SOFTWARE_COMPOSITING=1` (test mode only),
  since GPU-composited pages live in another process's layers. Delayed previews and Shift-click peeks never wake unloaded tabs. The hover card (`TabPeek`, 232 pt) shows title, site and
  memory, with an optional small thumbnail; Settings ▸ Tabs ▸ Tab Previews turns the card or its thumbnail off. Snapshots stay
  in memory at bounded thumbnail size; process metrics sample only while a preview is shown.

- Sidebar animated rows must render their live model immediately, including initially empty lists; retained closing rows contain only metadata. Never wait for an empty ForEach to appear before seeding rows.
- Tab previews replace native title tooltips on rows, tiles and top tabs. Button accessibility labels remain available.
- Picture in Picture (the media island's button, the video's right-click item, a page's own PiP button). WebKit: macOS's own
  PiP, which WebKit turns off for embedding apps; `MediaPictureInPicture.allow` turns it on for every web view (measured:
  YouTube reported no PiP support, so every route silently did nothing). Chromium: its own PiP opens a borderless Chromium
  window, which `ChromiumWindowGuard` hides; instead `ChromiumPictureInPicture` puts the video in element fullscreen inside
  its frame (a user gesture through DevTools) and moves the page view into Ikago's floating panel, with Back to Tab and
  Play/Pause on hover, while the tab shows a note. A page's own request (`enterpictureinpicture`, reported by the
  page-state world) is taken out of Chromium's PiP into the panel. Videos Chromium can't play (H.264 files) fall back to
  AVKit for direct addresses. A tab moving windows ends the panel first (`WebTab.endPictureInPicture`). Check with
  `pipchecks` (WebKit) and `CEFPictureInPictureChecks`.

- SPI: guarded WKWebView `_updateMediaPlaybackControlsManager`, `_canTogglePictureInPicture`, `_togglePictureInPicture` allow native macOS PiP for MSE media; DOM presentation-mode APIs remain the fallback.
- SPI: guarded WKPreferences `_setAllowsPictureInPictureMediaPlayback:` (`MediaPictureInPicture.allow`): without it WebKit
  reports no PiP support to pages and the toggle above does nothing. No public switch exists on macOS.
