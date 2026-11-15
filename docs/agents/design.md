# Design

1. **Clean first.** No decorative icons or labels; secondary actions appear on hover or in
   context menus. Ikago's own pages (Settings, History, Downloads, Bookmarks) are `ikago://` tabs
   (`InternalPage`), never separate windows or panels.
2. **Corners come from `Radius`** (6 inner, 8 control, 10 row, 12 card, 16 sheet, 26 bar for the Spotlight-style command bar): pick by the surface's size, never a
   one-off literal (small Settings mockups excepted).
2a. **Floating surfaces use `.surface(shape, palette)`**: Liquid Glass, or a flat panel when the
   user turns glass off (Settings ▸ Appearance). With the frosted sidebar (`frostedChrome`) the window itself is the one frosted
   layer (`WindowBackgroundView`: vibrant `.sidebar` blur under a light Space wash), and docked sidebars, the rail and
   the tab row draw no material of their own (`sidebarJoinsWindow`), since stacked blurs read flat and grey; floating
   sidebars (the peek) use `surface(..., translucentSidebar:)`. Honor Reduce Transparency and preserve readable Space tint. Never call `glassEffect` directly. Glass can't
   render offscreen, so drag previews use plain fills. Related icon controls share one reactive capsule (`GlassControlGroup`); a lone control uses
   `glassControl`, which adds nothing inside a group. Don't merge separate glass circles in a container: they melt together with visible necks.
   Don't switch styles with an `if` around large subtrees: `glassButtons` is one style that decides inside, because
   an `if` at the root rebuilds the window on change and overflowed the stack when a page inserted a button.
3. **Space colors tint the full chrome**, including flat sidebars and the Sidebar + Tabs row. Use
   `state.palette` and `.surface`; glass surfaces retain the Space tint. Keep page contents
   neutral, provide readable ink for arbitrary custom colors, and let website theme colors
   blend subtly rather than replace the Space's identity. Margins follow `state.frameInset`.
4. **The tab row moves; everything else stays immediate.** `TabMotion` (`TabSlotMotion.swift`, a 200 ms ease-out)
   animates the Sidebar + Tabs row's *structure*: an opened tab's slot grows in while neighbours and the + button slide;
   a closed tab (closed at once, no delay) shrinks out; reorders reflow. A settled slot isn't clipped, so an attached
   tab's flares reach into the page. The row animates only on `TabMotionKey` (item ids) through `tabStripMotion`, which
   blocks callers' transactions. Selection, address editing, window resizes and Space switches stay immediate, and so does
   suggestion selection. Titles crossfade over 100 ms, hover fills fade (~0.1s in, 0.2s out), and the address
   field eases its focus fill/ring. Respect Reduce Motion. Other changes animate quickly: `Animation.ikago`
   (0.2s) or `.ikagoQuick` (0.12s). Sidebar selection highlights follow the configured `TabSelectionHighlight` style.
5. **One layout, the sidebar, with an optional tab row.** Settings ▸ Appearance ▸ Layout (`LayoutChoice`) picks Sidebar or
   Sidebar + Tabs (`browserPreferences.sidebarTopTabs`, `state.usesTabsLayout`, `state.showsSidebarTopTabs`): `SidebarTopTabs` (its own
   `IsolatedHost`) shows the Space's ungrouped tabs above the page as arched, attached tabs (`AttachedTabShape`), and
   `TabsToolbar` (its own host) is the top of the page card: navigation left, the centred address field, other controls right;
   the page's top corners are square under it (`WebTabContainerView.squareTop`). The address bar is 36 pt with no rule under it; the active tab and the bar share `tabSheetColor` (the page color, see-through when frosted), so tab and bar read as one lighter sheet that settles into the solid page. There is no full sidebar in this layout:
   the sidebar is a rail of pins and groups below the tab row, or hidden (its peek is the rail). New tabs open on the right
   (`effectiveNewTabPosition`); the address frame reaches the shell through `ChromeModel.addressFieldFrame`. There is one `ContentHost`, so turning the row on or off never moves the page.
   Switching layouts goes through `LayoutSwitch.set`: the new layout is built in one frame with animations disabled and
   the window cross-fades (a `CATransition` on its layer); never animate the switch's geometry, which resized every page
   and rebuilt the sidebar list each frame (measure with `layoutprobe`). The Top Bar
   layout was removed; sessions saved with it (or the older Chrome layout) open as Sidebar + Tabs, and their saved Top Bar
   fields are ignored. Sidebar groups are tinted cards or an indented folder list (`SidebarGroupStyle`); group
   headers line up with tab rows (icon where favicons sit), with semibold names and the chevron right after the name (a pill keeps
   it at the far end). Groups nest (`TabFolder.parentID`, optional; `BrowserState+NestedGroups`, `GroupEntry.tree`): nested
   groups sit inside the top-level group's card as plain, indented headers, listed before the group's own tabs; counts, sleep
   and the active tab cover the subtree; deleting a group moves its tabs and groups up a level; moves into a group's own
   subtree are refused (`nestedgroupchecks`). The rail shows top-level groups only, and the Color pill label fills the header like a book's bookmark: a light wash of the group's color, a solid 3 pt spine on the leading edge, `Radius.control` corners; a group whose tabs are all closed or asleep fades to half until hovered (rail tiles too); closed groups stack 4 pt apart, and a hairline separates pinned rows from groups. With glass off the
   docked sidebar joins the window (`sidebarJoinsWindow`): it draws no card, so sidebar and tab row are one surface and only the
   page is rounded. The traffic lights, the sidebar's top row and the tab row share one centre (`sidebarRowCenter`);
   `positionTrafficLights` sets both axes in every layout. Top-row controls that don't fit beside the lights move to a second
   row (`SidebarView.topRowCapacity`), never under them. An optional Space header and shortcut rows (`SidebarShortcuts`,
   `sidebarShortcuts`) sit under the top row.
6. **Extensions live in the site-and-extensions popover** in the address field. It is Ikago's own card over the window
   (`SiteInfoOverlay`, `ChromeModel.showSiteInfo`, centred under its button, from the address bar's frame in Sidebar + Tabs; a click outside or Esc closes
   it; the button sits beside the address button, never inside its label or overlay, which took the first click), never an NSPopover: one hung from the hover button closed the moment it opened, and its see-through material made
   the text unreadable. The card is a `modalSurface` on the chrome palette (Liquid Glass with little Space tint when on,
   the frosted window's material with the translucent sidebar, solid otherwise) that grows out of its button on a short
   spring. Rows have white symbols on colored circles (`SiteSettingRow`, `SettingTile`); choices are `CompactMenu`s, a
   white pill opening a real `NSMenu` (SwiftUI's `Menu` drops a custom label's background on macOS); controls answer a
   press (`SiteCardPressStyle`). Zoom moves in 10 % steps (`PageZoom`, also ⌘+/⌘−) with Reset away from 100 %. Its card
   holds the site's settings (`SiteSettingsCard`): camera and microphone Ask/Allow/Block (`SitePermissions`, applied by
   `rememberedDecision` before any prompt; private windows always ask), engine, tracker blocking, keep awake, zoom, and
   Clear Site Data (that site only, both engines). An extension's page (Momentum's new tab) shows its extension's icon
   (`ExtensionPageIcon`): its own icon can't be fetched outside the page. On WebKit use native
   `performAction` and popup anchors; on Chromium popups open in `ChromiumExtensionPopup`.
7. **Settings is quiet and ordered: one sub-page at a time.** A 220 pt navigation column on a slightly quieter background: a small
   "Settings" heading, a search field (`SettingsSearch`: add every new setting to its index, with the `PageSection` title it lives
   under), categories under small group headings (Personalize, Your Browsing), monochrome outline symbols, a neutral fill for the
   selected row (no colored tiles, no accent fill, no chevron). Pages use `PageScaffold` on `SettingsColors.page`; Settings pages open
   with a 24 pt title and one short descriptive line, no artwork, then a segmented bar of the category's sub-pages (`SettingsSubpage`,
   `SettingsSubnav`; the chosen one rides a sliding pill). A sub-page lists the `PageSection` titles it shows
   (`settingsVisibleSections`): a new section must be added to one, or it never appears. Search results open the sub-page holding
   their section. Inside Settings (`settingsSurface`), `PageSection` is a card (`SettingsColors.card`, 14 pt corners, hairline rim,
   soft shadow) with its 13 pt semibold heading inside and rows divided by hairlines; its footer sits under the card. Elsewhere
   `PageSection` keeps its soft 12 pt panel. Keep visual previews where a choice is about looks (layout cards, color mode, group
   label style, the sidebar and toolbar editor's figure). `PageRow`:
   56 pt rows with 13 pt medium titles and 12 pt subtitles in Settings (44 pt elsewhere), no decorative per-row icons; an engine logo
   beside an engine choice shows its value. Controls come from `SettingsControls`: `SettingsMenu` (a white pill opening a native
   menu, never a stock pop-up button), `SettingsSegmented` (sliding pill), `SettingsButtonStyle` (white pill, or `prominent` in the
   accent; never blue text), native switches and sliders, all in `SettingsColors.accent` (a soft iris, `Color.settingsAccent` where
   the palette isn't at hand), never the system blue. Narrow windows show `SettingsCategoryMenu` instead of the column. Titles and subtitles describe; they never sell ("Import", not "Bring Your
   Browser to Ikago"). Search engines show their favicons (`SearchEngineIcons`). Subtitles are a few words and footers one short sentence, or none. No ambient glows, tinted cards or rounded
   display fonts. `.ikago` animations never overshoot.
