# Tabs, sidebar, pins, groups, split view and window dragging

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
- Newly opened background tabs load by default (configurable in Tabs & Memory), without selecting
  them. Restored session tabs and unloaded pins remain lazy; never preload a restored session.
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


- Modals share `ModalDesign`: with glass off, solid neutral sheets (`ModalMetrics.card`, 16 pt corners, hairline rim, a contact
  and an ambient `CardShadow`); 15 pt semibold headings, 32 pt fields, an accent default button beside bordered secondary ones,
  and a full-width hairline above the footer.
  Cast shadows from `CardShadow`, never the changing card contents. Settings appearance choices show light/dark/system previews.
- Group appearance uses a bounded integrated editor with a local icon/color draft. The default icon stays a folder, even with several tabs.
  Use Emoji opens the public macOS character picker through a native text input client. Done saves both choices;
  Cancel, Esc and outside clicks discard the draft. Keep the preview and selected states visible in both color modes.

- The sidebar can sit on either side; window controls optionally follow it. Page bounds must never overlap the docked bars.
- Tabs select like Finder's (`TabClick`): Shift-click a range in sidebar order, ⌘-click one more, ⌥-click to peek, a plain
  click opens a tab and ends the selection (`ChromeModel.selectedTabIDs`, tinted with `tabSelectionTint`). Their menu
  moves, groups or closes them all, and dragging one carries the rest (`TabDrag.companions`, taken by every drop through
  `TabDrag.travelling`, group headers included), including out to a new window; the drag shows a stack with a count badge
  and the others fade while they travel (`travellingWithDrag`). A drop's payload arrives after the drag-out check
  (`tabDraggedOut`, 250 ms after release), so that check takes the companions only when the pointer left every window;
  several tabs placed after one row go in last-first to keep their order. Measure with `dragprobe` and a real posted drag.
- Sidebar animated rows must render their live model immediately, including initially empty lists; retained closing rows contain only metadata. Never wait for an empty ForEach to appear before seeding rows.
- Tab previews replace native title tooltips on rows, tiles and top tabs. Button accessibility labels remain available.
