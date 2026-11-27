# Tabs, sidebar, groups and split view

## How it's built

- **Model.** `TabItem`s live in `BrowserState.tabs` (every Space). `pinnedTabs`, `regularTabs` and `sidebarOrder` are
  the active Space's. Groups are `TabFolder`s: they nest (`parentID`), can sit among loose tabs (`afterTabID`), be
  hidden (`isClosed`) or pinned (`isPinned`). Lists of groups read `listedFolders`; tab order for ⌃Tab is
  `orderedSidebarTabs`. Moves go through the model (`move`, `moveSidebarRow`, `placeFolder`), never by editing arrays
  in views.
- **Sidebar rows.** `SidebarOutline` says what the rows are and what a move does; `outlinechecks` tests it.
- **Sidebar list.** `SidebarOutlineList` shows those rows in AppKit's `NSOutlineView`, and reordering is the outline's
  own drag and drop. Rows are SwiftUI views in reusable cells (`OutlineHostingCell`). The icon rail uses the same list
  with tiles as cells (`OutlineRailCells`). The SwiftUI `TabListView` remains only for "Keep pinned tabs and groups in
  view".
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

## Traps

- **Find a drop's place in the model by the row it goes before, never by index.** The rail leaves rows out and tabs
  travelling with the dragged one shift every index.
- **Rows that stay keep their views:** move them with the outline's `moveItem`. Reloading or remove-and-insert made
  new views that drew empty for a moment.
- **Tell the outline when a row's height changes** (`noteChangedHeights`). Stale cached heights crashed inside AppKit
  when a drag opened its gap.
- **Don't draw your own drop slots, hidden source rows or highlights** over the outline. They flickered and crashed;
  the outline's own gap is the indicator.
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
- Checks: `outlinedropchecks`, `outlinedragchecks`, `outlinestresschecks` and the `rail…` variants drive the real
  outline. `railhoverchecks` drives the hover machine with a pretend pointer.
