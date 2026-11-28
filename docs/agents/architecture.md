# Architecture: windows, state and the shell

## How it's built

- **State.** Each regular window has its own `BrowserState` (`Browser/State/`, split by topic into extensions): its
  tabs, groups, splits and recently closed. Spaces, settings, history and bookmarks are shared and copied between
  windows' states when one changes them (`readShared`/`shareChanges`). The first window's state
  (`BrowserWindows.primary`) owns the session file and saves the other windows in it. Private windows stay apart.
- **Session.** Saved atomically with a backup and encrypted (`SealedStorage`). Preferences live in
  `BrowserPreferences`; new fields are optional so old sessions restore. A removed option's field just goes (old
  sessions decode without it); one whose data must move somewhere else stays as a retired field, converted once at
  restore and cleared (`convertSidebarShortcuts`).
- **Window.** `BrowserWindowController` (`UI/Window/Controller/`, split by topic) owns the window, the content view
  controller and the commands. `BrowserRootView` (`UI/Shell/`) is the SwiftUI root: sidebar or rail, Top Tabs row,
  page card and overlays.
- **Hosts.** The sidebar, Top Tabs row and toolbar each run in their own `NSHostingView` (`IsolatedHost`), so their
  updates don't re-render the whole window. Anchors can't cross hosts: frames reach the shell through `ChromeModel`.
- **Pages.** `WebContentViewController` / `ContentHost` hold the page views in plain AppKit. Switching tabs moves page
  views between panes and a hidden parking view.
- **Overlays** (site card, prompts, password list, command bar, update card) live in the window's SwiftUI tree and
  show through `ChromeModel`, so Liquid Glass samples the page behind them. The only exception is the icon rail's hover
  effects (`RailOverlay`), a click-through child window (see `tabs-and-sidebar.md`).
- **Toolbar controls** come from `state.chromeLayout` (`ChromeLayout`, `ChromeItem`): the person places them in Settings
  ▸ Customize, in six places (`ChromeZone`): the sidebar's top and bottom rows, the Top Tabs toolbar's left and right,
  inside the address field in every layout (`AddressFieldControls`), and the icon rail's foot. A new control gets a
  `ChromeItem` case. Places that were retired are read once into the nearest one (`ChromeLayout.Retired`). "Chrome" in
  names means Ikago's own UI.
- **Shortcuts.** `MainMenu` holds every shortcut. `ShortcutRouter` sends ⌘/⌃ keys to the menu before the page (⌘C, V,
  X, A and Z stay with the page). Shortcuts are user-changeable (`KeyBindings`).
- **Settings** are `ikago://settings` pages: categories, sub-pages (`SettingsSubpage`) and sections (`PageSection`).
  A new section must be listed in its sub-page, and every setting goes into `SettingsSearch`'s index. A setting that
  does nothing in the current layout isn't shown.
- **Full screen** is Ikago's own (`BrowserWindowController+FullScreen`), not macOS's.
- **Several windows.** Tabs move between windows with their live page (`release`/`adopt`), never reloaded.

## Traps

- AppKit views in SwiftUI that fill their space conform to `FillingViewRepresentable`. A plain `NSViewRepresentable`
  makes SwiftUI solve Auto Layout on every layout, which is slow.
- A host's `updateNSView` sets `rootView` inside `withTransaction(context.transaction)`, or animations stop at the host
  boundary.
- An `NSHostingView` near the title bar needs `safeAreaRegions = []`, or it draws below its frame and clicks fall
  through.
- Don't switch between large subtrees with an `if` at the root of a view: it rebuilds the window and once overflowed
  the stack.
- Glass can't render offscreen, so drag images use plain fills. Never call `glassEffect` directly; use `.surface`.
- Check full screen with `window.isInFullScreen`, never `styleMask.contains(.fullScreen)`.
- Quitting answers `.terminateLater` and flushes cookies first. Terminate from the run loop, never from inside a
  main-actor `Task`, which blocks.
- Closing the first window while others are open hands it another window's tabs (`handOver`), so the session keeps
  its owner.
- A new drag type reaches drop targets only once Launch Services knows the app: a debug binary run directly needs
  `lsregister -f build/debug/Ikago.app`.
