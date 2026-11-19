# Windows, history, import and Settings layout

- Swiping Back/Forward across an engine handoff (`HistorySwipe`): a passive scroll monitor follows a sideways
  two-finger swipe with an arrow at the page's edge, only where the page's own history ends and a parked page of the
  other engine waits, and navigates on release past 110 pt. It never swallows events. CEF reports no unconsumed scroll,
  so Chromium offers no swipe within its own history (a sideways pan in maps or carousels must not go Back).
- Several regular windows (`BrowserWindows`, `BrowserState+Windows`): each window has its own `BrowserState`
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
- Export (Settings ▸ Import & Export, `BrowserExport`): bookmarks as Netscape HTML (marked `ikagoMarker`, top level as
  the toolbar folder), or Safari's export ZIP (`ZipArchive`, stored entries): `Bookmarks.html`, `History.json`
  (metadata first: Chrome's reader rejects it otherwise; `time_usec`, `visit_count`) and, after Touch ID, `Passwords.csv`
  in Apple Passwords' columns. Files are written 0600. Import reads the same archives (stored or deflated, by extension,
  unknown parts ignored), Safari and data-portability history JSON, and passwords CSV. Ikago's own export
  restores its layout (`fromIkago`: no "Imported" folder); bookmarks already on the Bookmarks Bar are never moved into an
  Imported folder. `applyImport` returns an `ImportReport`: per kind, found, imported and why the rest weren't. Imported
  cookies always go into WebKit's store too. `importexportchecks` covers every format both ways with `unzip -t`.
- Import sources: Chrome (Beta, Canary), Edge, Brave, Arc, Dia, Vivaldi, Chromium, Opera and Opera GX (profile in the data
  folder itself), Comet; Firefox, Zen, LibreWolf, Waterfox, Floorp; Safari and Safari Technology Preview. Add a browser in
  `BrowserProfileDiscovery` (path, cookie key, `bundleIDs`). Lists show the installed app's own icon (`BrowserLogo`),
  never bundled artwork. The welcome page has layout and optional import steps; About → Developer reopens the welcome page.
- Other Devices (Settings ▸ General, both off by default). Tabs: `SafariSyncedTabs` reads Safari's own synced copies
  (`CloudTabs.db` for each device's open tabs, `SafariTabs.db` for Tab Groups and profiles) read-only, shown in the Devices
  control's dropdown with Safari's last write time. Safari (and possibly its background agents; unconfirmed) writes those files,
  so the list re-reads only when a file's date changes, and a device's own date is a day (Safari stores no time). Nothing goes back to Safari, since iCloud Tabs has no API. Debug builds
  read `IKAGO_SAFARI_FOLDER` instead (the `devices` test action). Handoff: `HandoffAdvertiser` offers the key window's
  http(s) page as `NSUserActivityTypeBrowsingWeb` (never private windows) and opens continued pages in a new tab.
- Settings stay uncluttered: a setting that does nothing in the current layout is not shown at all (no dimmed rows or
  "applies to" notes), and Settings search leaves it out (`SettingsSearchEntry.layout`). A section with nothing left
  goes too; a renamed section must be listed in its sub-page (`SettingsSubpage.sections`) or it never shows. Options
  that change how the window looks get one small live drawing of the current choice, always in the same place: before
  the row's title (`PageRow.figure`, `FigureWindow`, 80×52 pt, `SettingFigures.swift`). Drawings of the whole window
  carry its traffic lights; drawings of one part (group headers, the tab highlight) don't. In a section that uses them,
  every row gets one, so titles line up. Covered: spacing, sidebar state and side, the edge reveal, the page edge
  (style, height to scale, zoom), full screen, pinned tabs, group style, placement and counts, and looping clips of
  the tab highlight and page switch (still with Reduce Motion). Address bar styles are picture cards.
