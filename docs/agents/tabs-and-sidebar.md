- The sidebar's list is AppKit's outline view (`SidebarOutlineList`, `NSOutlineView` in a plain `NSScrollView`): only
  the rows on screen exist, and moving rows is the outline's own drag and drop, nothing drawn of our own: AppKit's gap
  (`.gap`, `rowHeight` a row's so the gap is one) and its highlight of a group under the pointer. The list only says which
  drops are allowed (`validateDrop`: between rows, into a group; never onto the list itself, never inside a row that
  isn't a group) and turns a drop into a model move (`acceptDrop`, at the place AppKit offered, found in the model by
  the row it goes before, never by an index: the icon sidebar leaves rows out, and tabs travelling with the dragged one
  shift every index). AppKit offers a group's header as "into the group" over its whole height, so nothing could go
  above the first group: `validateDrop` retargets the header's upper part (a third for tabs, a half for groups) to the
  place before the group (`setDropItem`); `outlinedropchecks`/`raildropchecks` check it with the real proposals (the
  outline's own drag path, a pointer over the rows), never with a hand-picked index. The dragged row's picture
  is drawn with `ImageRenderer`, never `cacheDisplay` (which leaves SwiftUI text out); AppKit overlays skip themselves
  under `drawsPicture`. When the model changes, rows still there move with the outline's own `moveItem` and keep their
  views (`apply`/`update`); removing and inserting them, or reloading, gave new views that drew empty for a moment
  (`outlinedragchecks` checks the views are kept). A drop shows at once, with no animation (`droppedAt`: the update of
  the next half second runs in a zero-length animation group): the gap already showed the place, and the moved row
  slid there from its old place when dragged up. Other changes (new tab, close, open or shut a group) keep theirs.
  `update` is a plan that can't contradict itself: each list shown after, from the top, gets its rows put in order
  (moved from where they are, or inserted), rows no longer shown end up at the tail of their lists and are removed
  last, and what it can't express (a row coming out of a closed group, a row twice) reloads. Removing first, in
  dictionary order, took rows out of a parent that had gone already. `outlinestresschecks`/`railstresschecks` run
  hundreds of seeded drops, at given places and through the outline's own drag path to a random pointer, mixed with
  groups opening, tabs coming and going and groups ungrouped, and compare the outline's rows, depths and parents with
  the model after each. A row whose height changes (a group nested or not, a split row's tiles, the New Tab row) is
  told to the outline (`noteChangedHeights`): stale cached heights crashed inside AppKit when a drag opened its gap. Slots, hidden source rows and highlights of our own flickered and crashed: don't add them back.
  What the rows are and what a move does is `SidebarOutline` (`sidebarOutline`, `moveSidebarRow`: a row becomes what
  the place it lands in holds: pinned rows above the New Tab row, loose tabs below it, members inside a group), checked
  in `outlinechecks`; the drag itself in `outlinedragchecks`/`raildragchecks` with a pretend `NSDraggingInfo`, each step
  run from the main queue (AppKit's drag handling inside a Swift task's job corrupted the executor record and crashed).
  Rows are SwiftUI views in reusable cells (`OutlineHostingCell`, the window's environment and the sidebar's appearance
  passed in). The cell lets the outline have presses on a row's body (click = `SidebarOutlineTable.onClick` after the
  outline's own tracking returns without a drag; drag), and the row its trailing controls, right clicks (menus) and
  middle clicks. Drags carry the same `TabDrag`/`GroupDrag` pasteboard types and start
  `chrome.beginTabDrag`/`beginFolderDrag`, so split targets, other windows, essentials, Space dots and tear-off work as
  before. Group cards are drawn by the rows (`OutlineRowView`, top/middle/bottom pieces). `draggingEnded` is optional:
  call the outline's only if it has one. Views in cells never use `isolated deinit` (freed from AppKit's autorelease
  pool, it crashed in the runtime). The SwiftUI `TabListView` stays only for "Keep pinned tabs and groups in view".
- The icon sidebar uses the same list (`OutlineRailCells`): the rail's tiles as cells in one 36 pt column, the group
  tint behind that column only, pins left out while Essentials or the tab row show them. Each tile measures itself for
  the hover effects in its own cell's `RailSpace`; the rail's list space (`RailSurface.list`) is the outline view,
  so clipping, `tilesRect` and scroll mirroring keep working. Essentials and pinned group tiles stay outside the list.
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
- A row's drop delegates treat a drag as a group drag only while a group is dragged (`chrome.draggingFolderID`): a tab
  drag can also report the group type, and treating it as a group refused every tab dropped on loose and pinned rows.
  (Dropping a tab on another to group or split was tried and taken out for now.)
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
- Ikago Home (`ikago://home`, `HomePage`, `NewTabMode.home`, the default for new profiles; saved profiles keep their
  choice) is the new-tab page after Safari's Start Page: a field that opens the address bar, bookmarks as tiles with
  folders opened in place, then the most visited pages; Customize picks the sections (`homeShowsFavorites`,
  `homeShowsFrequent`) and what new tabs open. Every new tab gets its own (`newTab` makes the tab directly; `openPage`
  would reuse one), its tab reads "New Tab", and closed untouched it isn't recorded (`isUntouchedNewTab`). A click
  opens the page in that tab, ⌘-click in a new one. Checks: `startpagechecks`.
  Its background (`HomeBackground`, `HomeBackdrop`): the page colour, a picked colour (`homeBackgroundColor`), or
  the person's image copied beside the session as `home-background.jpg` (≤2560 px, `homeBackgroundImage`), with an
  optional blur (`homeBackgroundBlur`) and a light veil for legibility. `homebg:` in the driver sets it.
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

- **Model.** `TabItem`s live in `BrowserState.tabs` (every Space). `pinnedTabs`, `regularTabs` and `sidebarOrder` are
  the active Space's. Groups are `TabFolder`s: they nest (`parentID`), can sit among loose tabs (`afterTabID`), be
  hidden (`isClosed`) or pinned (`isPinned`). Lists of groups read `listedFolders`; tab order for ⌃Tab is
  `orderedSidebarTabs` (the pin grid, then the sidebar's rows). Moves go through the model (`move`,
  `moveSidebarRows`, `placeFolder`), never by editing arrays in views.
- **Sidebar rows.** `SidebarOutline` (`state.sidebarOutline`) is every row the sidebar can list, as a tree: the block
  (pinned rows, and groups with the pins placed after them), the divider (the New Tab line), then loose tabs with groups
  among them. A group's rows are its groups, then its tabs; split tabs are one row. Views leave rows out (the divider
  when New Tab is off, loose tabs under Top Tabs, the rail's pins), never the model. ⌃Tab order is its tab order.
- **One drop rule.** A drop's target is `.before(row)`, `.into(group)` or `.end`. `SidebarOutline.place(for:at:)` turns
  it into a place, or nil (a group into itself). Into an open group is first, into a shut one last; inside a group a row
  lands among its own kind. `moving(_:to:)` is the outline with the rows there, and `BrowserState.apply(_:)` writes an
  outline back: above the divider tabs are pinned rows, below it loose tabs, in a group members; groups get their
  parent and `afterTabID` from their place. `moveSidebarRows` is the three in a row. `outlinechecks` tests each case
  and thousands of seeded moves read back.
- **Sidebar list.** `SidebarOutlineList` shows the rows in AppKit's `NSOutlineView`, and reordering is the outline's own
  drag and drop. The view only turns the pointer into a target and shows the place the model gives: over a row's upper
  half, before it; over a group header's lower half, into it; over a tab's lower half or in a gap, before the row below.
  It asks on every drag move (`SidebarOutlineTable.draggingUpdated`) and sets the place every time; the drop lands where
  its gap showed (`shownDrop`), and the gap closes before the rows move. Rows are SwiftUI views in reusable cells
  (`OutlineHostingCell`, in `SidebarOutlineRows`); a row's place (indent, card piece) is the cell's insets and the row
  view, set again after every change, never baked into its content. The icon rail uses the same list with tiles as cells
  (`OutlineRailCells`). The SwiftUI `TabListView` remains only for "Keep pinned tabs and groups in view".
- **Three sidebar states:** full, icon rail (`SidebarRail`), hidden. A hidden sidebar can peek in at the window edge.
- **Rail hover effects** (Magnify, Expand) are one state machine (`RailHoverModel.phase`) drawn in a click-through
  child window (`RailOverlay`). The window server sends pointer moves only where a child window draws, so pages under
  it don't see hovers. Look at the graph in its doc comment before changing it.
- **Top Tabs** (`SidebarTopTabs`, `TabsToolbar`): the Space's tabs above the page, groups as chips, an optional rail
  of pins and groups. `LayoutSwitch.set` changes layouts in one frame with a cross-fade.
- **Drags** carry `TabDrag` (`app.ikago.tab`) or `GroupDrag` (`app.ikago.group`) on the pasteboard, so the same drag
  works across the sidebar, rail, Top Tabs, Space dots, split targets and other windows. Selected tabs travel with the
  dragged one (`TabDrag.companions`).
- **Split view** is `splits: [[String]]` (groups of 2 to 4 tabs). Helpers are in `BrowserState+Layout`;
  `WebTabContainerView` arranges panes in nested `NSSplitView`s; drops onto the page use an AppKit `SplitDropTarget`.
- **Window dragging.** A `WindowDragArea` sits behind the sidebar, tab row and page card, so empty chrome moves the
  window. The page's top edge can too (`PageWindowGrab`).
- **Closing** the active tab goes to its opener, then its split partner, then right, then left. ⌘⇧T reopens the last
  closed tab or window in its place.

- Modals share `ModalDesign`: with glass off, solid neutral sheets (`ModalMetrics.card`, 16 pt corners, hairline rim, a contact
  and an ambient `CardShadow`); 15 pt semibold headings, 32 pt fields, an accent default button beside bordered secondary ones,
  and a full-width hairline above the footer.
  Cast shadows from `CardShadow`, never the changing card contents. Settings appearance choices show light/dark/system previews.
- Group appearance uses a bounded integrated editor with a local icon/color draft. The default icon stays a folder, even with several tabs.
  Use Emoji opens the public macOS character picker through a native text input client. Done saves both choices;
  Cancel, Esc and outside clicks discard the draft. Keep the preview and selected states visible in both color modes.

- **Never use AppKit's proposed drop level.** In gap mode AppKit offers each gap at the deepest level it could belong to
  (it tells levels apart by the pointer's x, and the rows have no indentation), so the gap above a group came as "end of
  the open group above". The pointer and the rows on screen decide (`target`), and one gap has one meaning.
- **Set the drop place every time AppKit asks.** It puts its own guess in place before `validateDrop`; returning early
  for an unchanged target let its guess show. It also asks only when its guess changes: hence the `draggingUpdated`
  hook.
- **A drop lands where its gap showed.** When AppKit hands the drop over, the gap may be closing and the rows under the
  pointer moving back; reading the pointer again there landed elsewhere.
- **Find a drop's place in the model by the row it goes before, never by index.** The rail leaves rows out and tabs
  travelling with the dragged one shift every index.
- **The outline holds only rows on screen:** a shut group has no children for AppKit. Its rows come and go with
  `insertItems`/`removeItems` as it opens and shuts; the data source says the new rows before the outline is told
  (`update`). A row moved out of a shut group the outline still held was shown twice.
- **Rows that stay keep their views:** move them with the outline's `moveItem`. Reloading or remove-and-insert made
  new views that drew empty for a moment.
- **A drop closes AppKit's gap at once, then moves the rows** (`takeDrop`). Moving rows while the gap was open left
  AppKit's gap row pointing at rows that had moved, and a later drag crashed in `NSTableRowHeightData setGapRow:`. The
  gap's motion still on the rows goes with it, or a moved row slid on from its old place.
- **Rows move only when AppKit is done with the drag** (`dropFinished`): after `concludeDragOperation` for a drag from
  elsewhere, after `draggingSession(_:endedAt:operation:)` for a drag from the list itself. As the source, AppKit takes
  the dragged row's space out during the drag and gives it back at the end by its old row; rows moved before that
  crashed it (`_doDraggingEndedForGapStyle`, `setGapRow:`). Pretend drags have no source, so only a hand drag covers it.
- **AppKit's `performDragOperation` runs first,** then the list takes a drop it refused (`takeDrop`): its check reads
  its last `validateDrop`, skipped when only the pointer moved. Skipping AppKit's perform left its drop state behind,
  and the next `moveItem` raised.
- **A row's look follows its place:** indent and card come from where it is now (`place(rebuilding:)`), so a row moved
  out of a group stops looking like a member.
- **Tell the outline when a row's height changes** (`noteChangedHeights`). Stale cached heights crashed inside AppKit
  when a drag opened its gap.
- **Don't draw your own drop slots, hidden source rows or highlights** over the outline. They flickered and crashed;
  the outline's own gap (and its highlight for a drop into a shut group) is the indicator.
- **Run AppKit drag handling on the main queue,** not inside a Swift task's job: that corrupted the executor and
  crashed.
- **Views in cells never use `isolated deinit`:** freed from AppKit's autorelease pool, it crashed in the runtime.
- **Draw drag images with `ImageRenderer`,** never `cacheDisplay`, which leaves SwiftUI text out.
- **Rail hover state changes only through `RailHoverModel`'s graph.** AppKit doesn't send exit events when a window
  covers the rail or the rail slides away, so a second path left the wide rail stuck open.
- **Never swap Spaces while a list is on screen** during the Space swipe; that was the visible pop.
- **Split panes:** never `removeArrangedSubview`, and a parked view goes back to autoresizing (Auto Layout sized it
  0×0). Corner flipping follows the view's own `isFlipped`, not the layer's.
- **Tab drags never use plain text** on the pasteboard: web views would take it.
- Checks: `outlinechecks` tests the rule without the list. `outlinebugchecks`, `outlinedropchecks`,
  `outlinedragchecks`, `outlinestresschecks` and the `rail…` variants drive the real outline with a pretend drag;
  `IKAGO_SHOTS=<folder>` saves window shots of the bug cases. The stress run checks every drop against the rule and
  the outline against the model. A pretend drag goes through `draggingEntered` to `performDragOperation` and
  `concludeDragOperation` (or `draggingExited`), as AppKit's do: `validateDrop` and `acceptDrop` alone leave AppKit's
  gap state behind and crash a later drag. Give each run its own `IKAGO_TEST_PROFILE`: the default one is shared and
  keeps groups from earlier runs. Crash walks drag in the list too (`sidebardrag`). `railhoverchecks` drives the hover
  machine with a pretend pointer.
