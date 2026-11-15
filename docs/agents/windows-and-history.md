# Windows, history, import and Settings layout

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
