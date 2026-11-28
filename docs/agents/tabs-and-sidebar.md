# Tabs, sidebar, groups and split view

## How it's built

- **Model.** `TabItem`s live in `BrowserState.tabs` (every Space). `pinnedTabs`, `regularTabs` and `sidebarOrder` are
  the active Space's. Groups are `TabFolder`s: they nest (`parentID`), can sit among loose tabs (`afterTabID`), be
  hidden (`isClosed`). In the Sidebar layout everything above the New Tab line is pinned: a group there keeps its tabs,
  unloaded, when they close (`isInPinnedFolder`). Lists of groups read `listedFolders`; tab order for ⌃Tab is
  `orderedSidebarTabs` (the pin grid, then the sidebar's rows). Moves go through the model (`move`,
  `moveSidebarRows`, `placeFolder`), never by editing arrays in views.
- **Sidebar rows.** `SidebarOutline` (`state.sidebarOutline`) is every row the sidebar can list, as a tree: the pinned
  rows above the essentials (`TabItem.pinAboveGrid`), the essentials' own row (`.essentials`: the grid, never moved), the block (pinned rows, and groups with the pins placed after them), the divider (the New Tab
  line), then loose tabs with groups among them. A group's rows are its groups, then its tabs; split tabs are one row.
  Views leave rows out (the divider when New Tab is off, loose tabs under Top Tabs, the rail's pins and essentials),
  never the model. ⌃Tab order is its tab order.
- **One drop rule.** A drop's target is `.before(row)`, `.into(group)`, `.end`, `.essential(before: tile)`. `acceptsSidebarRows` says whether it goes anywhere and `moveSidebarRows` moves it: into the
  essentials a single tab becomes one, before the tile named. For rows of the list,
  `SidebarOutline.place(for:at:)` gives the place, or nil (a group into itself, or above the essentials). Into an open
  group is first, into a shut one last; inside a group a row lands among its own kind. `moving(_:to:)` is the outline
  with the rows there, and `BrowserState.apply(_:)` writes an outline back: above the essentials tabs are pins above
  them, above the divider pinned rows, below it loose tabs, in a group members; groups get their parent and `afterTabID`
  from their place. `outlinechecks` tests each case and thousands of seeded moves read back.
- **Sidebar list.** `SidebarOutlineList` shows the rows in AppKit's `NSOutlineView`, one list for the whole sidebar, and
  reordering is the outline's own drag and drop. The view only turns the pointer into a target and shows the place the
  model gives: over a row's upper half, before it; over a group header's lower half, into it; over a tab's lower half or
  in a gap, before the row below. Over the essentials' row, `SidebarEssentials.spot` says what is under the pointer: its
  band (the top 16 pt) is before it, a tile is the essentials before that tile. The list
  takes every drop on that row: views inside a row never see drops. So the row's height and the grid's columns come from
  the state (`SidebarEssentials.height`), and the grid never scrolls by itself. Scrolled past, the row floats at the top: it is AppKit's floating group row (`isGroupItem`), the rows passing
  under it are masked (`maskUnderEssentials`), drags over it aim at it (`floatingEssentials`), and since AppKit hosts it
  outside the outline, the list's scroll view takes drops there and hands them to the outline (`OutlineScrollView`). The list spans the sidebar's margins with its rows inset inside them (`insets(for:)`), never content insets: AppKit placed the floating row partway along those while a drag moved the gap. It asks on every drag move
  (`SidebarOutlineTable.draggingUpdated`) and sets the place every time; the drop lands where its gap showed
  (`shownDrop`), and the gap closes before the rows move. Rows are SwiftUI views in reusable cells
  (`OutlineHostingCell`, in `SidebarOutlineRows`); a row's place (indent, card piece) is the cell's insets and the row
  view, set again after every change, never baked into its content. The icon rail uses the same list with tiles as cells
  (`OutlineRailCells`).
- **Selection.** The active row's highlight fades from the old tab to the new one (`TabSelectionHighlight`) in the
  sidebar, rail and tab row: rows live in separate hosts, so it can't slide between them. The page switches at once
  (`WebTabContainerView.show`).
- **Fixed design.** Most of the look is fixed, not a setting: the sidebar is on the left, the window border 1 pt
  (`frameInset`), no gap between sidebar and page (`sidebarGap`), the Top Tabs bar 34 pt (`tabsToolbarHeight`), the
  address Full Width or Page Title. Groups have one switch, Color pill (`groupsAsPills`): pills in tinted cards, or a
  small marker in a folder list; no tab counts. Essentials have three or four columns. A setting that is removed keeps
  its saved field ignored, or reads an old value as the nearest one (`TabsAddressStyle`, `GroupPlacement` decode an
  unknown value as the default).
- **Sidebar modes** (`sidebarMode`): Full, Icons (`SidebarRail`), Hidden (slides in at the window's edge) or Off. Top
  Tabs has no Full.
- **Rail hover effects** (Magnify, Expand) are one state machine (`RailHoverModel.phase`) drawn in a click-through child
  window (`RailOverlay`). The window server sends pointer moves only where a child window draws, so pages under it don't
  see hovers. Expand opens from anywhere on the rail and its full sidebar slides in whole; Magnify lets clicks through
  to the rail's own buttons. Look at the graph in its doc comment before changing it.
- **Top Tabs** (`SidebarTopTabs`, `TabsToolbar`): the Space's tabs above the page, groups as chips, an optional rail
  of pins and groups. `LayoutSwitch.set` changes layouts in one frame with a cross-fade.
- **Drags** carry `TabDrag` (`app.ikago.tab`) or `GroupDrag` (`app.ikago.group`) on the pasteboard, so the same drag
  works across the sidebar, rail, Top Tabs, Space dots, split targets and other windows. Selected tabs travel with the
  dragged one (`TabDrag.companions`).
- **Split view** is `splits: [[String]]` (groups of 2 to 4 tabs). Helpers are in `BrowserState+Layout`;
  `WebTabContainerView` arranges panes in nested `NSSplitView`s; drops onto the page use an AppKit `SplitDropTarget`.
- **Window dragging.** A `WindowDragArea` sits behind the sidebar, tab row and page card, so empty chrome moves the
  window. In the Sidebar layout the page's top 20 pt do too, after a brief press and hold, and a double-click there
  zooms (`PageWindowGrab`, fixed).
- **Closing** the active tab goes to its opener, then its split partner, then right, then left. ⌘⇧T reopens the last
  closed tab or window in its place.

## Traps

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
- **A list's rows never change while a drag from it is under way** (`isDragSource`, from AppKit's start of the session
  to its end). As the source, AppKit takes the dragged row's space out during the drag and gives it back at the end by
  its old row; rows changed before that crashed it (`_doDraggingEndedForGapStyle`, `setGapRow:`), with no crash
  report. A drop anywhere can change them: on this list, the list above the essentials, the grid, the page. So the
  list holds its rows (`show`) and catches up when the session ends (`dropFinished`); a drop on the list itself moves
  rows then too, and a drag from elsewhere after `concludeDragOperation`. Pretend drags have no source, so only a hand
  drag covers this.
- **AppKit's `performDragOperation` runs first,** then the list takes a drop it refused (`takeDrop`): its check reads
  its last `validateDrop`, skipped when only the pointer moved. Skipping AppKit's perform left its drop state behind,
  and the next `moveItem` raised.
- **A row's look follows its place:** indent and card come from where it is now (`place(rebuilding:)`), so a row moved
  out of a group stops looking like a member.
- **Tell the outline when a row's height changes** (`noteChangedHeights`). Stale cached heights crashed inside AppKit
  when a drag opened its gap.
- **One list, never two.** A second list above the essentials crashed AppKit three ways: rows changed in the list a drag
  came from, a list emptied by its only row being dragged out (AppKit divided by its height), and a list resized while
  it was a drag's source. Everything the sidebar lists is a row of the one outline.
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
