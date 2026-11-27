# Ikago

Ikago is a native macOS browser in Swift 6, AppKit and SwiftUI: a sidebar or Top Tabs, Spaces, split view, a command
bar, Chrome Web Store extensions and an MCP server for AI agents. Each page runs on Apple's WebKit (`WKWebView`) or on
Chromium through a prebuilt CEF framework, the person's choice, behind one `WebTab` protocol. macOS 26 and later.

## Layout

```text
Ikago/
├── App/         launch, AppDelegate, MainMenu (every shortcut, ShortcutRouter), ProtectedStorage, CrashReports
├── Browser/     state and model, no views: State/ (BrowserState by topic), Model/, Address/, Downloads/, Passwords/…
├── Engine/      Shared/ (the WebTab protocol), WebKit/ (WebTab, WebProfiles), Chromium/ (CEFWebTab and its parts)
├── Agent/       the MCP server agents use to drive tabs
├── Extensions/  WebKit/ (WKWebExtension), Chromium/ (hidden extension manager, popups)
├── Import/      other browsers' data
├── UI/          Window/, Shell/, Sidebar/, Tabs/, Content/, Address/, Overlays/, Pages/ (ikago://), Settings/, Design/
├── Checks/      Debug/ (the test driver, DEBUG builds), Chromium/ (runtime checks, checks builds)
└── Resources/
CEF/             the Objective-C++ bridge to CEF, CMake build, pinned SDK (cef-lock.json)
scripts/         build, package, install, release, Chromium updates, crash tools, demo
```

## Build and verify

- `python3 scripts/build.py --flavor debug|checks|release|asan`. `asan` works on WebKit only.
- Test driver: launch a debug build with `open -n -W -g --env IKAGO_TEST_MODE=1 --env "IKAGO_TEST_ACTIONS=a;b;quit"`
  (steps in `Checks/Debug/Driver/`). It uses in-memory website data and a temporary session, and can save window
  screenshots: look at the UI you changed before handing it over. Never move the person's mouse.
- Chromium checks: build `--flavor checks`, then `python3 scripts/run_chromium_checks.py`.
- Crashes: `scripts/crash_explore.py` walks random, replayable driver sequences. `parserfuzzchecks` and
  `mediaparserchecks` fuzz the parsers of outside data.
- Launch with `open -n`, never from a shell: a shell launch takes the terminal's macOS permissions and hides crashes.
- Another session may be running Ikago or its checks at the same time. Use your own profile and don't kill other
  copies.
- Measure before claiming a fix.

## Hard rules

These protect people's data, their trust, and the app's stability. Everything else is your judgment.

1. **Prebuilt CEF only.** Never fork or compile Chromium. Objective-C++ lives only in `CEF/Bridge/`.
2. **No Chromium windows on screen, ever, in tests too.** Ikago draws all UI. Chromium's service windows stay hidden,
   pages it opens become Ikago tabs, and DevTools docks in the window (`ChromiumWindowGuard`, `DevToolsDock`).
3. **Never change a person's engine for them.** A new profile asks on the welcome page. After that, the default
   engine and per-site engines change only by the person's choice.
4. **One owner per web view.** Only `Engine/WebKit/WebTab.swift` creates and configures a `WKWebView`. Only
   `WebProfiles` creates website data stores, one per Space.
5. **Fail closed.** Permissions are denied unless the person allows them. The popup blocker stays on.
6. **Browser scripts run in isolated worlds,** never the page's world (the media translation and notification shims
   are the listed exceptions). Values go to scripts as arguments, never pasted into script text.
7. **Private WebKit SPI only when there is no public way and it pays off:** mark it `// SPI:` and list it in
   `docs/agents/private-spi.md`.
8. **Agent control is off by default,** local only, token-protected, and the UI always shows when an agent drives a
   tab.
9. **Data at rest stays encrypted** (`SealedStorage`, `ProtectedStorage`). Never fall back to plain text, never log
   cookies, passwords or callback URLs, and never enter real credentials in tests.
10. **Saved sessions keep working.** New saved fields are optional, and an existing profile keeps its old behavior
    when a new preference is unset.
11. **Outside data never traps.** Numbers from files, pages and other browsers are checked before integer
    conversion, arithmetic or ranges. Add a fuzz seed when you add a parser.
12. **Commits:** one per feature or fix, only when asked. `BUILDS.md` ▸ Unreleased is public text: plain words, what
    people notice.

## Code

Keep code simple, clean and readable, for a person and for an agent. A file holds one idea: split by idea, never to
meet a line count, and don't scatter one feature across tiny files. Prefer the platform's own behavior (AppKit,
SwiftUI, WebKit, Chromium) to rebuilding it. Fix causes, not symptoms: a delay, an extra flag or a guard that hides an
ordering bug is not a fix. Delete code that a change makes unnecessary. State is `@MainActor @Observable`.

## Design

Clean and native: secondary actions on hover or in menus, Ikago's own pages are `ikago://` tabs. Space colors tint the
chrome. Motion is quick and never makes the person wait, and respects Reduce Motion. Use the shared pieces in
`UI/Design/` (`Radius`, `Palette`, `.surface`, the glass buttons) rather than one-off values.

## Topic docs

Read the one for the area you change. Each says how that area is built now, and the traps that crash or lose data.
Update it when you change how something works.

| Area | File |
|---|---|
| Windows, state, shell, overlays, hosts, shortcuts, Settings | `docs/agents/architecture.md` |
| WebKit, Chromium, page lifetime, per-site engines, media | `docs/agents/engines.md` |
| Sidebar, rail, Top Tabs, groups, pins, split view, dragging | `docs/agents/tabs-and-sidebar.md` |
| Storage, privacy, permissions, passwords, extensions, import | `docs/agents/security-and-storage.md` |
| Address bar, Peek, find, Reader, translation, downloads, other page tools | `docs/agents/page-features.md` |
| Releases, updates, test builds, crash reports | `docs/agents/release.md` |
| Private WebKit SPI in use | `docs/agents/private-spi.md` |
