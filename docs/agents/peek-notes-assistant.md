# Peek, notes, page assistance and page menus

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
- When a clicked link opens in Peek is a setting (Settings ▸ Tabs ▸ Peek, `LinkPeek`): Off (Shift-click opens a new tab),
  Shift-click (default), or Automatically, which also peeks links to other sites from pinned tabs and from search results,
  and optionally every link that would open a new tab. Both engines ask `WebTabDelegate.webTab(_:peeks:trigger:)` →
  `BrowserState.peeks` (WebKit's navigation and popup policies; Chromium's `IKCEFPage.peekHandler` from `OnBeforePopup`
  and `OnBeforeBrowse`); a page shown in Peek never peeks its own links (`selectionpeekchecks`).
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
