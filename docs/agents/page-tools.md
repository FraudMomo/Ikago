# Page tools: notifications, Reader, translation, Save Page, web apps

Phase 7's everyday features. Each works the same on WebKit and Chromium, and all of them start from the site card
(`SitePageActions`), the View and File menus and the address field's actions.

## Website notifications
- A page-world shim (`NotificationShim`) stands in for `Notification` on both engines (Chromium shows nothing for a page's
  notification and WebKit has no public hook). It only asks; the site's saved choice decides (`WebNotifications`,
  `BrowserState+Privacy`: the same prompt and durations as camera and microphone, in the site card and Settings ▸
  Security ▸ Permissions; the prompt records the choice, `WebNotifications` then asks macOS the first time). A page can
  fake the answer it reads, never a delivery. Top documents on https or loopback only; private windows never.
- WebKit: a `.page`-world message handler (`WebNotificationBridge`). Chromium: the shim raises a DOM event that the
  page-state script (isolated world) relays through its DevTools binding, and Ikago answers with `Runtime.evaluate`.
- Chromium injects the shim after commit, from `observePageState`, **not** as a document-start script: registering any
  document-start script (`documentStartScript`) makes Back through a restored tab's history stall (`CEFHistoryChecks`).
- Delivery is `UNUserNotificationCenter`, titled with the page's title and the host as subtitle; clicking one selects the
  tab. Test mode never posts (`WebNotifications.testDelivered`).

## Reader
- `ReaderScript` runs in the isolated world: scores paragraph containers, drops furniture, and rebuilds the article from
  an allow-list of tags (only `href`, `src`, `alt`, `colspan` survive), so the result can't run anything.
- `ReaderOverlay` is a nonpersistent WKWebView over the page's host view with a CSP that allows no scripts; its look
  (font, size, theme) is `ReaderStyle` in the preferences and changes in place. Links open in a new tab.
- Its control pill is an `NSHostingView` near the window's top: keep `safeAreaRegions = []`, or the title bar's safe
  area draws the pill ~32 pt below its frame and clicks on ✕ and Aa fall through to the article.

## Translation
- On-device with Apple's Translation framework. The framework only runs from a view, so `TranslationHost` (zero size,
  in the shell) owns `.translationTask`; `TranslationJob` carries the page's texts and shows `TranslationCard`.
- The card opens in `.choosing`: From (detected, or any language) → To (any language from `LanguageAvailability`, the
  last choice remembered in `translationLanguage`). The run starts only on Translate; closing the card cancels it.
- `TranslationScript` collects text nodes (not code, editable or `translate=no`), writes translations back by node,
  and restores the originals. The page's language is detected with `NLLanguageRecognizer`; the target is Settings ▸ General.
- Import `Translation` with `@preconcurrency`: its session isn't `Sendable`.

## Save Page
- ⌘S, the site card's Save Page tile, the page menu and the command bar open `SavePageSheet` over the window (never a
  save panel's format menu): Document (web archive, HTML, text), PDF (printable pages, one long page), Image (the full
  page or the visible area, PNG or JPEG). Save asks where (`PageSaver.save`, the name filled in); Copy puts images, HTML
  and text on the clipboard. Each engine makes every format in `WebTab.exportPage(_:)`; `savePage(as:to:)` writes it.
- WebKit: `createWebArchiveData`; paged PDF from `createPDF` slices joined with PDFKit (a print operation hangs without
  its sheet); Long PDF is `createPDF` with no rect (the whole content as one page); the full-page image draws that PDF
  (`PageExport.rasterize`, 2x, smaller past `longestImage`), the visible area is `takeSnapshot`. Chromium: MHTML from
  `Page.captureSnapshot`; both PDFs from CEF's `PrintToPDF` (`savePDF`, `saveLongPDF` sized to `cssContentSize` with no
  margins), since headful DevTools can't print; the full page from `Page.captureScreenshot` with
  `captureBeyondViewport`. HTML and text come from the page in the isolated world (`PageExport.htmlScript`, `textScript`).

## Web apps
- `WebApp` (preferences) + a launcher bundle in ~/Applications (`WebAppLauncher`) whose script opens
  `ikago-app://<id>`. The app runs in Ikago: `BrowserWindows.open(webApp:)` is a regular-window state with `webApp` set,
  no sidebar (`webAppLayout`, `WebAppBar`), on the Space it was installed from. Never part of the saved session; never
  the frontmost regular window for links from other apps; target=_blank links off its site open in the main window.
- The launcher can't give the app a Dock icon of its own while it runs (it is Ikago's process); pinned, it stays in the
  Dock as a shortcut and shows in Launchpad and Spotlight.

Checks: `PageToolChecks` (WebKit, `pagetoolchecks`), `CEFPageToolChecks` (Chromium smoke).
- Find in page (`FindBarView`, `FindBarModel`, `BrowserWindowController` find handlers): results arrive as `FindResult`
  (found, total, active). Chromium reports them itself (`OnFindResult`; the selected match often comes in an interim
  update and the count in the final one, so both are passed on), and a new search that selects nothing gets one step so
  it reads "1 of N". WebKit's find says only whether it found one: `FindHighlights.detailsBody` counts the matches, finds
  the selected one from the DOM selection, marks them (Highlight All) and returns tick positions for `FindTicksView` on
  the tab's host view. Match Case works on both engines (Chromium starts a new search when the text or Match Case
  changes). Find belongs to each tab: its own text (`findTexts`) and whether its bar is open
  (`findOpenTabs`). A tab never starts from another tab's search (no shared find pasteboard); switching tabs hides the
  bar or brings back that tab's own, and ⌘G with the bar closed opens the tab's find. WebKit repaints only what a new
  highlight covers, so the old Highlight All marks are deleted before new ones are set, or earlier letters' marks stay.
  A search issued twice counts as Find Next on both engines. `findchecks` covers both engines.

