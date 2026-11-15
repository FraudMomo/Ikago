# Shell and WebKit traps

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
