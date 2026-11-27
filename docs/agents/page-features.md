# Page features

A map of the features around the page. Each one works on both engines unless it says otherwise.

## How it's built

- **Address bar and command bar.** `CommandPaletteModel` drives every address style. `OmniboxEngine` ranks
  suggestions on Chromium's relevance scale. The field is AppKit (`AddressTextField`). Commands and settings are
  results too (`PaletteActionCatalog`). Remote suggestions are opt-in and use cookie-free sessions.
- **Peek** (`LivePeekPanel`): a link in a floating card over the window. Keeping it moves the same live page into a
  tab without reloading. `LinkPeek` decides which clicks peek.
- **Find** (`FindBarModel`): per tab. Chromium counts matches itself; on WebKit `FindHighlights` counts and marks them.
- **Reader** (`ReaderScript`, `ReaderOverlay`): rebuilds the article from an allow-list of tags into a web view that runs
  no scripts.
- **Translation:** Apple's Translation framework, on device. It runs only from a view, so `TranslationHost` owns the
  task.
- **Save Page** (`SavePageSheet`, `WebTab.exportPage`): document, PDF or image, from each engine's own export.
- **Notifications:** a page-world shim stands in for `Notification`; the site's saved permission decides, and
  `UNUserNotificationCenter` delivers.
- **Web apps** (`WebApp`, `WebAppLauncher`): a launcher in ~/Applications that opens a sidebar-less Ikago window.
- **Downloads.** `DownloadCenter` owns progress and cancellation; `DownloadHistoryStore` saves history with a backup.
- **Media island** (`SidebarMediaPlayer`): the playing tab's controls in the sidebar.
- **Memory.** `TabMemoryManagement` unloads background tabs after a time (Conservative, Balanced or Responsive), never
  by RAM quota.
- **Performance tools:** View ▸ Performance Stats (`PerformanceOverlay`) and `ikago://performance`.
- **Notes** (`ikago://notes`) and **page assistance** (`PageAssistantView`, Apple Foundation Models, off by default).
- **Home** (`ikago://home`, `HomePage`): the new-tab page.

## Traps

- **Typing right after ⌘L or ⌘T never loses letters:** early keys go to the field (`BrowserWindow.typeAhead`), and it
  selects all only while nothing is typed.
- **While the address is being edited, the page must not take focus** (`shouldFocusPage`).
- **A pinned tab never navigates away from the address bar:** searches from it open a new tab.
- **Peek on Chromium:** while the card grows the page keeps its final size and only its origin moves, and it moves
  straight into the tab's view. Otherwise Chromium's layers drift.
- **Reader's and other pills near the title bar** need `safeAreaRegions = []`.
- **Import `Translation` with `@preconcurrency`;** its session isn't `Sendable`.
- **Save Page on WebKit:** a print operation hangs without its sheet, so paged PDF is built from `createPDF` slices.
- **Clearing download history never deletes files.**
- **Delayed previews and Peek never wake unloaded tabs.**
- **Page assistance** reads the page only on an explicit request. Page content is untrusted data, and it has no
  browser tools.
