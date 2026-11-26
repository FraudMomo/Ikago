# Address bar, suggestions and command palette

- URL suggestions share CommandPaletteModel in both address styles
  (`OmniboxEngine`, `OmniboxInput`). Input is classified as URL, query or unknown. Matches carry
  Chromium-scale relevance: inline-autocompleted navigation 1410+, search-what-you-typed 1300
  (1150 for URL input, whose what-you-typed navigation is 1200), earlier searches from history
  1240–1279 (up to three), remote predictions 1230 and below (up to five, requested from the first
  letter after a short debounce), and history/bookmark/open-tab pages ≤ 1199 from
  topicality × frecency (Visit `visits`/`typed`, Chromium recency buckets). One row per page,
  at most `OmniboxEngine.maxResults`. Any page visited, open or bookmarked inline-autocompletes to
  its host root while the input is within the host; past the host only pages typed, visited ≥ 3
  times or bookmarked complete. Inline completion follows
  forward typing only (`userEdited`), never deletion or programmatic text. ↑/↓ preview a row's
  `fill` as `temporaryText` without replacing the typed query and never wrap; hover only highlights.
  Esc restores the typed text before closing. Tab focuses a row's "Switch to this tab" button,
  then the next row. Shift+Delete or × forgets a history row. Search result pages appear as earlier
  searches, never as navigation rows. Focusing the field (empty, or ⌘L on the untouched page address)
  lists up to five recent searches, then most visited pages (never the current page), with no row
  highlighted: ↓ previews the first, Return on the untouched address keeps the page. Address-field navigations mark the tab in `typedNavigations` so
  its next committed visit increments `typed`. Switch-to-tab buttons
  are independently configurable; remote search autocomplete is opt-in. Debounce requests,
  exclude addresses, use cookie-free ephemeral sessions, cancel on dismiss/changes and ignore
  late responses. Provider failures must preserve direct search and local suggestions.
- Integrated address editing uses opaque light/dark surfaces independent of glass. Every address presentation shares
  `OmniboxResults`/`OmniboxRow`, laid out like Spotlight: bare icons, 13–14 pt titles, a neutral rounded fill for the
  selection (text keeps its colors), the top hits without a heading and other sections headed over a hairline with
  "Show More" (opens the matching scope). The floating bar (`CommandPaletteView`, `Radius.bar`) is a capsule with a 22 pt
  field that opens into a card; the highlighted result's icon sits at its end and what Return does follows the text
  ("— Open", "— Search", "— Switch to Tab", "— Run"); with nothing typed it lists the scopes. The inline field leads with
  the highlighted result's icon.
  Browser commands and every setting are results too (`PaletteAction`, source `.action`, `ikago-action:` URLs, at most
  three, from 1215 down, only those that apply): commands in `PaletteActionCatalog` (tabs, windows, split view, appearance
  such as Light/Dark/System, layouts and sidebar styles, pages, places), settings registered from `SettingsSearch.index`
  (opens Settings at the section via `BrowserState.pendingSettingsSection`). Commands show their shortcut, settings where
  they live; each is aimed at its own window (`perform(in:)`, handlers in `BrowserWindowController+PaletteActions`),
  never sent to whichever window is key. Results are
  grouped under headings (`CommandPaletteModel.grouped`/`sections`: Top Hit, then Search, Open Tabs, Pages, Actions in
  ranked order). Scopes, after Spotlight's filters (`AddressScope`: Tabs ⌘1, History ⌘2, Bookmarks ⌘3, Actions ⌘4, which
  win over Select Tab while the field has the keyboard via `FocusingTextField.onCommandDigit`), list every match of one
  kind; a scope shows as a token, and Esc or ⌫ on an empty field leaves it. Address cards are solid
  (`AddressSurface`, `AddressAppearance`) and frosted only when `frostedChrome` is on, never Liquid Glass. Selection updates
  immediately without matched geometry or spring motion.
- ⇧⌘K (File ▸ Command Bar, `showCommandBar`, `prepareActions`) opens the floating command bar in any address style
  with nothing typed and the Actions scope on, so commands and settings come first; Esc or ⌫ widens it to everything.
  Not ⌘K, which many sites use. Like every menu shortcut it wins over the page, and it can be changed.
- Keyboard shortcuts are changeable (Settings ▸ General ▸ Shortcuts, `KeyboardShortcutsSection`): `KeyBindings` lists the
  menu's commands by a stable id (the action's selector, `#tag`, `@copy` for a command listed twice), remembers their
  built-in shortcuts right after `MainMenu.build`, and applies `BrowserPreferences.keyBindings` to the menu, which stays
  the one source of shortcuts (`ShortcutRouter`). A shortcut needs ⌘ or ⌃; one in use elsewhere is refused. While
  recording, the key monitor hands presses to the recorder (`KeyBindings.recorder`). Checks: `shortcutchecks`.
