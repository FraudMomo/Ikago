# AGENTS.md — Architecture rules for Ikago

Ikago is a lightweight native macOS browser: a SwiftUI sidebar, Spaces, split view, a floating command bar, Chrome Web
Store extensions, and first-class access for AI agents. It is written in **Swift 6 with AppKit and SwiftUI**, and the
page engine is the user's choice: **Apple's WebKit** (`WKWebView`) or **Chromium** through a prebuilt CEF framework.
Read these rules before changing code, and the topic file for the area you touch (§4) before working there.

## 1. Golden rules

1. **Two engines, public API first.** Pages are `WKWebView`s or embedded CEF pages behind the
   `WebTab` protocol. Use Objective-C++ only at the Swift/CEF boundary in `CEF/Bridge/`. No custom
   CEF build, no Chromium fork, and never compile Chromium. Use private WebKit SPI only when
   there is no public way and the payoff is large; mark each use with a `// SPI:` comment and
   list it in `docs/agents/private-spi.md`.
1a. **No Chromium windows, ever.** Ikago draws all the UI. Chrome-style browsers exist only because
   some Chromium services need one; they stay hidden (`IKCEFNativeTools`, `HiddenChromiumPage`). Pages
   Chromium opens by itself become Ikago tabs, DevTools docks beside the page (`DevToolsDock`), and
   `ChromiumWindowGuard` hides anything titled that slips through. Tests stay hidden too, and
   `CEFHiddenServiceChecks.noVisibleChromiumWindows` fails the suite otherwise.
1b. **Never change a user's engine silently.** A new profile starts on `BrowserState.newProfileEngine` (Chromium) and the
   welcome page (`ikago://welcome`) asks before any site loads; after that the engine changes only by the person's choice,
   on relaunch. Sites can have their own engine (per-site engines, `docs/agents/chromium.md`), but only by the person's choice: lists are
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

## 2. Layout

```text
Ikago/
├── App/         main.swift, AppDelegate, MainMenu (all shortcuts + ShortcutRouter), AppIdentity, ProtectedStorage
├── Browser/     No views. State/ (BrowserState and its extensions by topic), Model/ (Storage/, Tabs/, Preferences/),
│                Address/ (omnibox engine, input, suggestions), Downloads/, Favicons/, Passwords/, Notifications/,
│                Reader/, Translation/, WebApps/, Continuity/
├── Engine/      Shared/ (BrowserEngine; Page/, Media/, Passwords/, Safety/), WebKit/ (WebTab, profiles, security;
│                Passwords/, Monitors/), Chromium/ (Tab/, Passwords/, Video/, DevTools/, Cookies/, Runtime/,
│                MediaTranslation/)
├── Extensions/  WebKit/ (WKWebExtension manager, tab bridge, Web Store), Chromium/ (hidden manager, popups)
├── Import/      Browser data import
├── UI/          Window/ (Controller/ holds BrowserWindowController and its extensions), Content/ (tab panes, Reader/),
│                Shell/ (root view), Toolbar/ (customizable controls), Tabs/ (Top Tabs row),
│                Sidebar/ (TabList/, Groups/, Bookmarks/, Media/, Spaces/), Address/,
│                Overlays/ (Site/, Passwords/, Performance/, Assistant/, Peek/), Pages/ (ikago:// pages; Welcome/,
│                History/, Bookmarks/), Settings/ (Core/, General/, Appearance/, Privacy/, Extensions/), Downloads/,
│                Design/ (Palette, glass buttons, logos)
├── Checks/      Chromium/ (runtime checks, IKAGO_CHECKS builds; Runner/ and one folder per area), Debug/ (WebKit test
│                driver in Driver/ and one folder per area, DEBUG builds)
└── Resources/   Info.plist, entitlements, Assets.xcassets

CEF/             Objective-C++ bridge, CMake build, pinned SDK (cef-lock.json)
scripts/         build.py, package_app.py, install.sh, install_test.sh, release.py, release_chromium.py,
                 chromium_lock.py, fetch_cef.py, fetch_sparkle.py, check_cef_update.py, run_chromium_checks.py
```

Build with `python3 scripts/build.py` (`--flavor release|checks|debug`). `Checks/` is left out of release
builds. Release packaging keeps the matching unstripped app binary in `out/symbols/` and removes local symbols from
the distributed executable before signing. Generated: `.cef/` (the SDK), `build/`, `out/`. Minimum macOS 26 (Liquid Glass; `WKWebExtension`
itself needs 15.4). Bundle ID `app.ikago.browser`; data lives in the protected app group container
`<team>.app.ikago.browser` (`ProtectedStorage`), or `Application Support/Ikago` in ad hoc builds.

Packaging retains only English CEF UI locale packs (including English variants), matching Ikago's UI; the SDK stays intact.
Keep `en.lproj` as the fallback and keep ICU, shared `.pak` files, snapshots and graphics libraries. Multilingual webpage
text and international formatting remain available; `CEFLocaleChecks` verifies missing-locale fallback and native controls.

## 3. Style

1. One feature, one place: related files share a nested folder, and small related pieces share a file instead of
   one tiny file each. Aim for files under about 300 lines; up to about 450 is fine when splitting would scatter one
   feature. Small single-purpose SwiftUI views and AppKit controllers.
2. State: `@MainActor @Observable` classes (`BrowserState`), no Combine where `@Observable` works.
3. Keep feature parity: atomic session save/restore with backup, fail-closed permissions,
   per-Space colors, shortcuts Cmd+T, Cmd+W, Cmd+Shift+T, Cmd+L, Cmd+F, Cmd+P.
4. Verify with the Debug test driver (`IKAGO_TEST_MODE=1 IKAGO_TEST_ACTIONS=…`, see
   `Checks/Debug/Driver/TestDriver.swift`); it uses in-memory website data and a temporary session folder.

## 4. Topic rules (read the one you need)

Each file holds the measured decisions and traps for its area. Read it before changing that area, and update it (not
this file) when a rule there changes.

| Area | File |
|---|---|
| SwiftUI/AppKit shell, overlays, isolated hosts, popups, address focus, split view, toolbar controls | `docs/agents/shell-and-webkit.md` |
| Design: corners, glass, Space colors, motion, layouts, site card, Settings look | `docs/agents/design.md` |
| Tabs, sidebar, pins, groups, split drops, window dragging, full screen, the rail | `docs/agents/tabs-and-sidebar.md` |
| Address bar, suggestions ranking, command palette actions | `docs/agents/address-bar.md` |
| Security, privacy, encrypted and protected storage, cookies, passwords, extensions | `docs/agents/security-and-storage.md` |
| Media island, memory management, performance tools, downloads, Picture in Picture | `docs/agents/media-performance-downloads.md` |
| Several windows, history, back history, import, Settings page structure | `docs/agents/windows-and-history.md` |
| Peek, multi-tab selection, notes, page assistance, page menus | `docs/agents/peek-notes-assistant.md` |
| Chromium/CEF: media translation, per-site engines, appearance, DevTools, extensions | `docs/agents/chromium.md` |
| Notifications, Reader, translation, Save Page, web apps | `docs/agents/page-tools.md` |
| Releases: Developer ID, notarization, DMG, Sparkle updates, credits | `docs/agents/distribution.md` |
| Private WebKit SPI in use (list every new use here) | `docs/agents/private-spi.md` |

Rules that bite everywhere:

- Never take a Chromium page out of the window or resize it frame by frame in an animation: its layers drift and it
  draws shifted (move views straight between parents; size once).
- AppKit views in SwiftUI that fill their space conform to `FillingViewRepresentable`; sidebar lists scroll in AppKit.
- Overlays live in the window's SwiftUI tree and show through `ChromeModel`; floating surfaces use `.surface`.
- Scripts the browser runs use isolated worlds, never the page world; permissions fail closed.
- Measure before claiming a fix: the Debug test driver (`IKAGO_TEST_ACTIONS`) and the Chromium checks
  (`python3 scripts/build.py --flavor checks` first, then `scripts/run_chromium_checks.py`).
