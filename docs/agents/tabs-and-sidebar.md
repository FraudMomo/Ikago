# Tabs, sidebar, pins, groups, split view and window dragging

- Sidebar essentials contain pinned tabs in both docked and peeked sidebars. Settings ▸ Show essentials
  (`showPinnedGrid`) is one switch for every layout: off, no sidebar shows essentials (no grid, no essential tiles in the
  rail), and pinned tabs stay ordinary pinned tabs: rows in the list, plain tiles in the rail's list, or icon tabs at
  the start of the Top Tabs row (`pinsInTabRow`). In Top Tabs with essentials on, the pins live in the
  icon sidebar, also while it is hidden and slides in at the edge; only a hidden sidebar with edge peek off sends them to
  the tab row. They never show in both places (`pinsInRail`).
- The icon sidebar's hover effect (`RailHoverEffect`, Settings ▸ Appearance ▸ Layout ▸ Window and Sidebar, shown only
  where there is an icon sidebar; off by default and under Reduce Motion): `UI/Sidebar/RailHoverModel.swift` (the state
  machine), `RailHover.swift` (constants, Magnify's icons, tracking), `RailHoverLayers.swift` (what draws over the page)
  and `RailOverlay.swift` (its window). The rail itself never changes size or place, so nothing the pointer measures
  shifts under it.
- **When the effects open and close is one state machine and nothing else** (`RailHoverModel.phase`, its graph is in the
  doc comment): `idle → arming → open → leaving → closing → idle`, and any state straight to `idle` when the effect
  changes, the rail goes away or moves under it. A rail's tracking view only starts it; from then a 60 Hz timer reads
  the real pointer (and whether this window is the one under it) and takes at most one step per tick; it stops at
  `idle`. Everything drawn is derived from the phase (`shown`, `expanded`, `covered`, `rowOnScreen`). Exit events
  decided closing before and AppKit doesn't send them when a window covers the rail, a rail slides away under a still
  pointer, or the style changes: the wider rail stayed out for good (2026-11-21). Don't add another path that changes
  what shows; add an edge to the graph.
- It opens only on a rail that is still (two ticks at the same frame) and sits on that frame (`anchor`) while shown;
  if the rail moves (a rail slid in from the edge sliding away, a window resize) it resets at once. Following a moving
  rail stranded the wider rail half off the window under Top Tabs.
- Magnify is a carousel, stepped by tile, never by the pointer's distance (a smooth curve felt restless, 2026-11-21):
  the tile nearest the pointer (`hovered`) grows most (`largest`) with a full row over the page with its name, the
  tiles just above and below (`neighbours`) grow a little (`neighbour`) with shorter, fainter rows; the hovered
  row's name is semibold. Moving within a tile
  changes nothing. Like the Dock, nothing slides: each row stays on its own tile and only its shown width animates
  (laid out at full length, revealed to `width`, the name fading where cut), on the same spring as the icons (`glide`);
  rows that slid between tiles parted from their icons and their names cross-faded into each other. Everything fades
  and grows in and out with `strength`; the tiles are kept through `closing` so the rows fade with it. While it shows,
  a copy of the rail's icons only (`SidebarRail(magnified:)`) lies in the overlay over the rail, whose tiles stay and
  whose own icons step aside (`railCopy`), and the rows lie between the two: one icon per item, never a bigger
  duplicate over it. The two lists scroll together (`listScrolled`). Items register their frames with the model
  (`register`, by owning view: a rebuilt tile registers before the old one goes); a shut group's tiles are left out
  (`railItemsHidden`). The newest rail to appear is the one followed (style switches mount it before the last goes).
  Rows work like their tiles. Tab rows have the full sidebar's controls (`TabMediaIndicators`, `RailTabCloseButton`):
  Magnify's hovered row always, Expand's rows with close on hover (`RailTabControls`), beside the row's button, never
  inside it.
- The icon rail keeps the full sidebar's order (Sidebar layout): essentials, pinned tiles, groups, a line, New Tab
  (when the sidebar shows it, `sidebarShowsNewTab`), then tabs. Under Top Tabs it keeps pins and groups only.
- Expand: resting `expandDelay` on the rail opens the full sidebar over the rail and the page (`RailExpandPanel` draws
  `SidebarView` at `state.sidebarWidth`, `RailHoverModel.expandWidth`), laid out exactly as when it is docked: top row,
  address field, essentials, groups, bottom bar, and the same drags (reorder, into groups, out to split the page). Its
  edge grows from the rail's while it fades in. The drawn traffic lights glide from the rail's column to its top row
  while it is out (`FullScreenWindowControls.placeRail`: one host covering both places, each light offset by `progress`
  on `RailHover.reveal`/`conceal`; `LightsHost` takes clicks only on the lights) and stay uncovered: the panel has a
  round hole over each light that moves with it (`lightFrames`, re-read on `lightsMoves`), and while the pointer is over them the overlay ignores the
  mouse (`onPassThrough`). Its sidebar button keeps the full sidebar docked (`sidebarOverRail`, `showFullSidebar`);
  `WindowDragArea` in the overlay moves the browser window (its parent). Inactive drawn lights are solid grey, as
  macOS's are, since see-through ones showed what was behind them.
- Drag state is read only in leaf views: rows, tiles and drop targets never read `draggingTabID`/`selectedTabIDs` while
  building (`DragSourceDim`, `DragInsertionLine`, `TravellingWithDrag`), and delegates ask for the dragged tab through a
  closure and write their preview only when it changes. Measured with `renders:<n>` (`RenderProbe`): a drag's start and
  end re-ran every row builder and target (31 each with 30 tabs); now only the 31 small dims.
- In the full sidebar's rows (and Expand's), a tab dropped on another tab's middle half combines them (`combines:`; tiles,
  the essentials grid and the tab row only reorder) (`TabReorderDropDelegate.combine`, `TabCombine`): across
  the row, the first half groups the two (`drop(_:onto:makeGroup:)`: a new group where the target was, or the target's
  group) and the second half splits them (`splitTabs`); left/right in lists and tiles, top/bottom in the tab row, whose
  ends are for reordering. The quarters at either end only reorder. `CombineHint` tints the half and names it (just
  the symbol on small tiles); nothing changes until the drop. Pinned targets and split members only offer what applies.
  `hintshot:<png>` draws the hints offscreen.
- Rail tiles drag like the full sidebar's rows (`onDrag` with `TabDrag`, `tabDropTarget` on each tile, `tabListEndDrop`
  under the last one): reorder, onto a group tile to join it, onto the page to split it, out to a new window. Group
  tiles drag and take drops like group headers (`RailGroupDrag`, `FolderHeaderDropDelegate`).
- The rail's sidebar button sits where the full sidebar has it: at the top under the lights when the sidebar's top row
  holds it (`SidebarRail.togglesAtTop`), else at the foot. A click opens the full sidebar (`showFullSidebar`); its menu hides the
  sidebar. Under Top Tabs it hides the rail.
- Both draw in a window of their own (`RailOverlay`): borderless, transparent, a child of the browser window and exactly
  its size. It is put in place invisible and click-through ahead of use (`onPrepare`, when a rail appears and on
  `arming`) and showing is only its alpha: ordered in as it showed, its first frames were lost and Magnify popped. Measured: AppKit sends pointer moves to every tracking area under the pointer
  whatever is drawn over it, so pages hovered under in-window overlays; the window server gives a child window the
  pointer only where it draws and lets it through elsewhere. The one exception to overlays living in the window's tree
  (`shell-and-webkit.md`).
- The overlay window covers the whole browser window and its host is a drop destination wherever it is, so during a tab
  or group drag (`isDragging`) it lets the pointer through outside the effect's zone: split view's targets on the page
  and every other drop reach the browser window. Back at `idle` `anchor` is cleared, so the hidden overlay holds no
  sidebar or rail copy (and no drop targets); `arming` mounts it again. Magnify's carousel holds still during drags.
- Every rail on screen is its own `RailSurface` (docked, slid in from the edge); the model follows the one the pointer
  came onto and resets when it goes. A rail slid in from the edge stays while the machine isn't idle (`holdsSidebar` in
  `holdsPeek`) and may slide away once it is (`onRelease`).
- Hover reveals start only from the person's own pointer movement: `RailTrackingView` holds still (`stillAt`) when the
  app or window comes forward or a rail/edge appears under the pointer (⌘Tab back, a click on the sidebar button), so
  neither Expand nor the hidden sidebar opens by itself. Expand opens only from the rail's tiles, and over the rail's own
  buttons it lets the click through at once and closes.
- `railhoverchecks` is a quick local check (a pretend pointer, `pretendPointer`, drives the machine; the real one is
  never moved): every run ends at `idle` in each sidebar style, hiding the sidebar while Expand is out, and Top Tabs with
  the rail slid in from the edge. `railpoint:<y>,<png prefix>` holds the pretend pointer on the rail and saves the window
  and the effects' window, for looking at it. Look and feel are checked by hand.
- The pinned grid uses a saved two-to-eight column preference (three by default),
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
  Placement is drag-driven, and the tab menu offers it too while the Sidebar layout shows essentials (`TabContextMenu.pinItems`):
  Pin Tab (a row) and Add to Essentials for open tabs, Add to Essentials/Unpin for rows, Move to Pinned Tabs/Remove from
  Essentials for tiles. Elsewhere there is one Pin/Unpin action; split tabs pin as rows only.
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
- In the Sidebar layout the page's top edge (web pages and `pageSurface`-marked internal, error and empty pages) can move
  the window; Top Tabs never uses it (its tab row moves the window, and Settings shows the switch off and disabled) (`PageWindowGrab`, Settings ▸ Appearance ▸ Layout ▸ Moving the Window, `PageGrabMode`): Off, Press and Hold
  (unset), or Drop-Down Header. The edge reaches `pageGrabHeight` points down (unset: 10, 4–32). Press and Hold: a still
  press (0.12 s) becomes a window drag through a passive local event monitor (no view, inset or overlay); the page
  receives every press immediately; moving first, modified clicks, split headers and overlays stay with the page, and a
  grab ends the page's press away from it and drops the later mouse-up. Drop-Down Header: resting the pointer on the
  edge (0.18 s, from the same monitor's mouse moves) drops `PageGrabHeader`, an AppKit view added above every page in the
  pages' container (pages never move or resize), under the pointer and clear of the page's corners; it drags the window
  and leaves 0.45 s after the pointer does. In both styles a double-click on the edge zooms the window
  (`pageGrabZoom`, unset: on) and the page never sees that second click. Checks: `pagegrabchecks`, `CEFPageGrabChecks`.
- Split drops use a permanently mounted AppKit SplitDropTarget above WKWebView, with
  preview and acceptance driven by native dragging callbacks. Transparent SwiftUI-only drop
  surfaces can fall through to embedded pages. Decode TabDrag from the live pasteboard
  rather than transient chrome drag state. In Top Tabs only panes along the top have square tops
  (`TabHostView.touchesTop`); which corners are the bottom follows the pane view's own `isFlipped`
  (a backing layer uses its view's coordinates; the layer's `isGeometryFlipped` follows the flipped NSSplitView around it
  and must not be used), re-applied whenever it moves; check with the `corners:<png>` test action. In the tab row a split pair shows, on hover, a close button per tab and a
  centred Separate button (`SplitTabButton`, `unsplitGroup`). Pane headers (`PaneHeaderView`) are a small frosted pill centred at the pane's
  top that fades in only while the pointer is near that edge (`TabHostView.onMove`) and fades out otherwise, so they never
  cover the page at rest; they use native independent drag handles/buttons; page focus must not interrupt header controls.
  Switching tabs moves page views straight between panes and the hidden parking view, never out of the window: a Chromium page taken out of the window is resized to 0×0, and ChatGPT lost its scroll position and blinked on return (`CEFTabSwitchChecks`). Never call `removeArrangedSubview` (it removes the view from the window; split views arrange all their subviews, so moving one is enough), and a parked view goes back to autoresizing (a split view put it on Auto Layout, which sized it 0×0 in parking). A Chromium page gets one fresh resize the first time it shows (`CEFWebTab.visibilityChanged`), since an adopted link tab could stay blank. Each split keeps its panes' shares across resizes (`PaneSplitView.layout`): Auto Layout alone gave a resize to one pane, and a layout switch collapsed a grid's column to 0 pt (measure with the `panes` test action). Dropping the active unsplit tab creates a `ikago://split-empty` slot. Filling the slot
  preserves its side/layout and removes the placeholder; sessions retain empty slots.
- Top Tabs in split view (`state.showsPaneBars`): the address bar above the page gives way to a bar on each visible pane
  (`PaneBar`, an `NSHostingView` with `safeAreaRegions = []`, or the title bar's safe area pushes it down): back, forward,
  reload for that pane's page, its "site / title" opening the command bar (which floats; `canUseInlineAddress` is off
  then), and close. `TabHostView.barHeight`/`pageFrame` keep every view that fills the pane's height below the bar; the
  hover pill, engine badge and header band measure from `pageFrame`. The page is resized once when bars come or go.
  `panebarchecks`.
- Page-switch fades and tab-highlight motion are independent Settings ▸ Appearance options.
  Instant mode removes in-flight layer fades; shared TabSelectionHighlight implements None,
  Slide, Fade, Scale and Spring for all layouts, pins and split groups. Respect Reduce Motion.
- Closing the active tab follows Chrome: back to its opener (`TabItem.openerID`, set for link tabs and forgotten once
  another tab is chosen), then its split partner, then the tab to the right, then the left. ⌘⇧T reopens a tab in its
  Space, group and place (`SavedTab.after`) and selects it. Like Chrome, a tab still on its new-tab page (an extension's
  new-tab page or the homepage, nowhere to go back to) is not recorded when closed (`isUntouchedNewTab`); blank tabs
  never are. A closed window is remembered whole (`closedWindows` on the first window's state, at most
  `WindowSession.maxClosedWindows`, saved in `Session.closedWindows`); ⌘⇧T reopens whatever closed last, tab or window
  (`SavedTab.closedAt`, `WindowSession.closedAt`, `reopensWindowNext`). Closing the first window records it the same
  way before it takes over another. Windows closing while the app quits are never recorded (the state is frozen).
- Ikago never opens a fixed site by itself: the first tab of a launch and Split View's new pane open `startPageURL`
  (the homepage when new tabs open it, else the chosen engine's `homeURL`); a new private window opens like ⌘N.
- If ⌘T's blank tab has no page view yet when Return is pressed, `open` sets the tab's address so the page starts there. Closing a top tab with the mouse keeps the others' width until
  the pointer leaves the row. In Top Tabs, tabs opened from a pin open on the right.
- The sidebar's top row and bottom bar each have a left, centre and right place (`ChromeZone`, `ChromeLayout.topLeading`,
  `topCenter`, `sidebarTop` = right; `bottomLeading`, `sidebarBottom` = centre, `bottomTrailing`), filled by dragging in
  Settings ▸ Sidebar & Toolbar ▸ Customize; the centre stays centred, and left/centre top groups start after the traffic
  lights. Too many for one row wrap to a second row on the right as before. Readers of a whole row use `topItems`/`bottomItems`. A two-finger swipe over the sidebar pages between Spaces live (`SpaceSwipe`):
  pins and tabs follow the fingers point for point and fade out by half the sidebar's width (`SpaceSwipe.fadeSpan`); on
  release past a third, or after a flick that way (over 300 pt/s, measured over the last 80 ms), the list carries on at the
  fingers' speed to that invisible point, the Spaces swap there, and the next list springs in from the mirrored point
  with the same speed. A flick back, or a short drag, springs home from the fingers' speed. Gestures that start while
  it animates are left to the list. Never swap Spaces while a list is visible: that was the pop. With Liquid Glass on, every chrome control is glass: toolbar groups, the Top Tabs controls and
  address field, the tab row's +, rail tiles and pinned tiles.
- New-tab placement is configurable (top/bottom); links can open before/after their opener or
  follow the new-tab setting. Preserve manual order and other Spaces; adjacent links inherit the
  opener's group, while normal new tabs remain loose and unpinned. All link paths, including
  WebKit popups, use `newTabFromLink`. `WKNavigationAction.buttonNumber` is a mask (middle = 4),
  unlike AppKit's index (middle = 2); middle-click opens in the background, Shift selects it.
- Newly opened background tabs load by default (configurable in Tabs & Memory), without selecting
  them. Restored session tabs and unloaded pins remain lazy; never preload a restored session.
- Hidden tab groups (`TabFolder.isClosed`, Hide Group, `hideFolder`, `BrowserState+Groups`) stay saved with their
  nested groups; their pages unload and they leave every list: the full sidebar, the rail and the tab row
  (`listedFolders`, `GroupEntry.tree` and `orderedSidebarTabs` skip them, so ⌃Tab never lands there). They come back
  from the Tab Groups control (`ChromeItem.tabGroups`, `TabGroupsButton`/`TabGroupsMenu`: hidden groups to show, then the
  others to go to; placeable in Customize, and added by itself to the sidebar's bottom bar and the rail's foot while
  groups are hidden and it isn't placed, `addsTabGroupsButton`), the tab row's `HiddenGroupsButton` (same menu), the
  group's menu, Tab ▸ Show Hidden Group, or selecting one of their tabs.
- Groups can sit among the tabs, as in Chrome and Firefox (`TabFolder.afterTabID`: nil keeps a group in the block above
  the New Tab line, as older sessions restore; "" is first among the loose tabs; a tab's id is right after that loose
  tab). `blockFolders` and `looseEntries` order the sidebar (`LooseSegment`), the rail and the tab row
  (`TopRowEntry.row`), and `orderedSidebarTabs` follows them. `keepGroupsInPlace` re-anchors groups when the tab before
  them closes or moves; a tab dropped after that tab goes above the groups (`reorderTab`). A group made from a loose tab
  takes its place (`createFolder(with:)`). Drags: a group dropped before/after a loose row (`TabReorderDropDelegate.group`)
  or at the list's end goes among the tabs; on the New Tab row it goes back to the block (`placeFolderInBlock`); beside
  another group it joins that group's place (`placeFolder` copies `afterTabID`). Space moves and nesting clear it.
- Pinned groups (`TabFolder.isPinned`, Pin Group in a top-level group's menu, `setFolderPinned`, `pinnedFolders`) are pins,
  not groups: a button each with a menu of the group's tabs, like a bookmarks folder (`PinnedGroups.swift`): rows under
  the essentials in the full sidebar, tiles with the pins in the rail. Lists of groups read `listedFolders` (sidebar,
  rail, tab row). Their tabs stay when closed, unloaded, like pinned tabs (`isInPinnedFolder` in `closeTab`); a pinned
  group can't be hidden; Delete Group unpins first so its tabs really close. Tabs dropped on one join the group, and its
  menu adds the current tab. Checks: `nestedgroupchecks`.
- Tabs and groups move between Spaces from their menus (Move to Space, also for several selected tabs) or by dropping
  tabs on a Space's dot in the Space bar (`moveTab`, `moveTabs`, `moveFolder(_:toSpace:)`). A group takes the groups
  inside it and their tabs, arrives at the top level after the target's groups, and its tabs keep their groups. Between
  Spaces with different storage the pages reopen there (no closed-tab entry). The view stays in the current Space.
- Groups drag by their header (`GroupDrag`, type `app.ikago.group`, declared in Info.plist) and move like tabs, with the
  tabs' blue line (`GroupInsertionLine` is `TabInsertionIndicator`): on another header the first half drops before it
  and the second half of a shut group after it, beside it at its level (`placeFolder`, `canPlaceFolder` refuses its own
  subtree); putting a group inside another is the menu's Move Into; the list's end takes it to the top level, last; a Space's dot
  moves it there with its groups and tabs. Header drops for tabs and groups share one delegate
  (`FolderHeaderDropDelegate`). A new drag type only reaches drop targets once Launch Services knows the app: a debug
  binary run directly needs `lsregister -f build/debug/Ikago.app` first. Measure with `groupdragprobe` and a posted drag.
- The Bookmarks page selects like Finder (Shift-click a range, ⌘-click one more, or Select mode); the bar moves or deletes
  the selection in one change (`moveBookmarks`, `removeBookmarks`), deleting only after a confirmation. Imported bookmarks
  are copies (imports read private snapshots, read only), so edits never reach Safari or another browser.
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
  sidebar peeks from the left edge (always, even with Settings ▸ Reveal at the window edge off, which stops the
  hidden sidebar's edge peek elsewhere: `sidebarEdgePeek`), staying while `chrome.holdsPeek`,
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
