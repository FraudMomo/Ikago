# Builds

What changed in each release of Ikago, newest first. Add changes under **Unreleased** as they land;
`scripts/release.py` publishes that section as the release notes and moves it under the new version.

## Unreleased

- **Fewer, simpler settings:** some options that only changed where or how the same things show are gone, and what
  they held moved somewhere you'll find it:
  - The sidebar is always on the left. A sidebar set to the right opens on the left.
  - "Keep pinned tabs and groups in view" is gone: pinned tabs and groups scroll with the rest of the list.
  - Tab Animations are gone: the highlight fades quickly to the tab you pick, and the page changes at once.
  - The Space header and shortcut rows at the top of the sidebar are gone. Shortcuts you used are now pinned tabs
    (Bookmarks, History, Downloads, Performance, Settings), and Assistant and Notes are buttons in the sidebar's top
    row. Pinned tabs can now sit above Essentials as well as below: drag them there.
  - Buttons have six places instead of thirteen: the sidebar's top and bottom rows, the left and right of the Top Tabs
    toolbar, the icons-only sidebar, and inside the address field, where any button can now go (Reload and Site &
    Extensions live there). Buttons you had placed elsewhere moved to the nearest place.
  - The window has a thin, fixed border, and the sidebar meets the page: the Window border and Sidebar gap sliders
    are gone.
  - The sidebar is Full, Icons or Hidden, and with Top Tabs also Off. Hidden slides in when the pointer reaches the
    window's edge, Off doesn't; this replaces "Reveal at the window edge".
  - The address bar is Full Width or Page Title; Centered is gone, and the Top Tabs bar has one height.
  - The top of the page always moves the window: press and hold, then drag, and double-click there to zoom. Its
    settings and the drop-down header are gone.
  - Tab groups have one switch, Color pill: colored names in tinted cards, or a simple folder list when it's off. Tab
    counts are gone, and Top Tabs shows groups in the tab row or the icon sidebar.
  - Essentials have three or four columns, and stay at the top of the sidebar while the tabs scroll, in both the full
    and the icons-only sidebar.
  - Pin Group is gone: anything above the New Tab line is pinned, groups too. Tabs in a group there stay when you
    close them, like pinned tabs, and groups you had pinned are back in the list. With no Essentials yet, a box at the
    top shows where to drag tabs to add them.
- **Icon sidebar Expand:** it opens from anywhere on the icon sidebar, and the full sidebar slides out at its full
  width instead of growing out of the icons.
- **Dragging in the sidebar:** a tab or group dropped just above a group could end up inside a group, and among the
  groups at the top a row dropped between two groups went into one of them. Rows now land exactly where the gap
  shows. Dropping onto a group's name puts the row in that group. A tab dragged out of a group no longer looks like
  part of it, and dragging tabs into and out of groups no longer closes Ikago.
- **Tab order:** in a group that holds other groups, Control-Tab now goes through the tabs in the order the sidebar
  shows them.
- **Location on WebKit:** sites asking for your location got no prompt and were always refused. They now ask
  like every other permission.
- **Quitting after a link preview:** with Chromium, quitting Ikago while a link preview was open, or after one,
  could leave it stuck and never quit. It now quits normally.
- **Importing a damaged file no longer closes Ikago:** some unusual history exports made Ikago close while importing.
  Now it imports what it can read.
- **Damaged videos no longer close Ikago:** with Chromium, a damaged or unusual video on X could close Ikago.
  Now it plays another way.
- **Crash reports you can pass on:** if Ikago closes unexpectedly, the next launch asks whether to save a crash
  report. Save Report puts it in your Downloads folder, without your name or home folder, ready to send to the
  developer in a GitHub issue or another way. Nothing is saved unless you say so, and nothing is sent by itself. Help ▸ Save Crash
  Report saves one on request, with reports from the past week.
- **Many tabs with Chromium:** with lots of tabs open, closing a tab right after switching to it could close
  Ikago. That no longer happens.
- **Google sign-in no longer crashes with Chromium:** entering your email and pressing Next could close Ikago,
  because macOS ended it when Chromium checked for a phone to sign in with. Ikago now asks for Bluetooth
  access like other browsers do.
- **Importing from other browsers:** on recent macOS, Chrome, Safari and other browsers showed an empty "Default
  profile" or imported nothing, because macOS keeps their data private until you allow it. Import now asks you once
  to allow each browser, then finds your real profiles and imports the one you use. Safari's saved logins and open
  tabs need Full Disk Access, and Import now says so with a button that opens the right setting.

## 0.7.1 — 2026-11-21

- **Chromium 158:** the Chromium engine is updated to Chromium 158 with its latest security fixes. Picture in
  Picture works again with it.
- **Icon sidebar on hover:** Magnify now shows the tab under the pointer as a row with its name, with the tabs
  around it smaller, like a carousel. Expand no longer gets stuck open or half open, keeps the window buttons
  usable, and stops the page underneath from reacting. Both now have close and mute buttons on their tab rows.
- **Icon sidebar:** tabs are in the same order as in the full sidebar, and the sidebar that slides in is easier to
  read over busy pages.
- **Reliability:** behind-the-scenes fixes so automatic Chromium updates reach you without failing.

## 0.7.0 — 2026-11-19

- **Top Tabs:** the Sidebar + Tabs layout is now called Top Tabs. Tab groups show as chips in the tab row, in their
  color, and can be hidden without deleting them (Hide Group in any group menu). Three address bar styles (Centered,
  Full Width, and Page Title, which shows the site and the page's title), pinned tabs can lead the tab row,
  and the hidden sidebar can slide in at the window's edge. In split view each pane has its own small bar with back,
  forward, reload, its address and close. The tab row no longer rubber-bands when its tabs fit, and the + sits closer
  to the tabs with a small divider.
- **Icon sidebar on hover** (Settings ▸ Appearance ▸ Layout): Magnify reaches the rows near the pointer out with
  their names, like the Dock, and a click on a group opens a card beside the sidebar with its tabs and nested groups.
  Expand widens the icon sidebar itself to show each row's name.
- **Essentials:** one Show essentials switch for every layout; the tab menu pins a tab as a row or adds it to
  essentials. Pinned tabs show in one place only.
- **Groups and Spaces:** drag a group's header to reorder it, nest it, take it out or move it to another Space. Move a
  group, or several selected tabs, to another Space from their menus. The Space swipe follows your fingers.
- **Permissions:** sites ask in Ikago's own prompt over the page, once even when they ask twice. Every permission a
  site can request (camera, microphone, location, notifications, clipboard, files, MIDI, the local network and more)
  can be allowed once, for a day or always, or blocked. The site card lists only what the site has asked for.
- **Save Page** (⌘S): save a page as a web archive, HTML, text, a PDF in pages or one long page, or an image of the
  whole page or what's on screen (PNG or JPEG), or copy it.
- **Find in page:** "N of M", Match Case, match marks on the scroll bar, and a separate search for each tab.
- **Tabs:** closing a window remembers it whole, so ⇧⌘T brings it back with all its tabs and groups. Untouched new
  tabs aren't reopened. Long titles fade out instead of ending in "…".
- **Import and export:** export bookmarks, history and passwords for other browsers, or all of them as one archive,
  and import those archives back.
- **Bookmarks:** select several bookmarks like in Finder, then move or delete them together.
- **Settings:** settings that don't apply to your layout are hidden instead of dimmed, and appearance options show a
  drawing of what they do. Remove Chromium (General ▸ Advanced) deletes its data and turns it off.
- **Performance:** showing, hiding or shrinking the sidebar resizes the page once instead of on every frame.
- **Fixes:** a new tab's address is kept when you press Return right after ⌘T. DuckDuckGo no longer opens unless it's
  your choice. Adding a login you already saved no longer duplicates it. Back through restored history no longer
  adds a duplicate entry.


## 0.6.1 — 2026-11-18

- **Chromium 156.0.8078.100:** the latest security and stability fixes from the Chromium project.

## 0.6.0 — 2026-11-17

- **Bookmarks:** the Bookmarks menu in the menu bar lists your bookmarks, with folders as submenus. Sidebar + Tabs
  has a bookmarks bar under the address (⇧⌘B), with folders as menus. Large collections stay fast.
- **Import:** bookmarks keep their folders, inside an "Imported from …" folder. Safari's open tabs and Tab Groups and
  its website logins come across too (Full Disk Access needed). Import works while the other browser is open, and
  Import Again moves bookmarks from earlier imports into their folders without making copies.
- **Find in page:** a new find bar with Highlight All and a match count. Esc closes it from anywhere and clears every
  highlight, and ⌘F always puts the cursor in it.
- **Extensions:** an extension asking to read a website shows Ikago's own card instead of a system alert, over the
  page that asked in split view. "Allow on Every Website" is a proper button. An error an extension reports while
  running (such as Momentum's "Message to service worker timed out") no longer looks like a failed install, and
  Restart in Settings ▸ Extensions starts it fresh.
- **Sidebar:** a slim scroll bar beside the tab list, and Keep pinned tabs and groups in view (Settings ▸ Sidebar).
  The Space header and shortcuts are customizable: show or hide the Space name, choose the rows (Assistant,
  Bookmarks, History, Downloads, Notes, Performance, Settings) and put the pinned-tab grid above or below them.
  Toolbar buttons that don't fit get smaller and then move into a More menu instead of dropping to a second row.
- **Tabs:** ⇧⌘T brings back several closed tabs in their order and places. A closing tab in the tab row fades out
  instead of sliding over its neighbour. A Space without tabs shows a start screen with recent sites.
- **Passwords:** Settings ▸ Passwords shows how many passwords are only in Ikago and not yet in Apple Passwords
  (iCloud Keychain), with a blue dot. Export all of them or choose which, and a weekly reminder offers it until you
  do (Not Now, or Don't Remind Me).
- **Performance:** a new Settings page for memory and the performance monitor. Three memory modes like Chrome's
  Memory Saver and Edge's sleeping tabs:
  Conservative puts unused background tabs to sleep after 30 minutes, Balanced after 2 hours (new profiles), and
  Responsive only when macOS runs short of memory. Playing, loading and visible tabs never sleep.
- **Updates:** an update you dismissed with Later stays in Settings ▸ About ("Ikago X is available"), with a blue
  dot, until you install it.
- **Toolbar:** in Sidebar + Tabs, controls can sit at the window's edges or right beside the address on either side
  (Settings ▸ Sidebar & Toolbar ▸ Toolbar). In the sidebar's top row, the center controls no longer overlap the
  others.
- **Fixes:** files dropped on a page reach its upload area instead of opening in a tab. Suggestions no longer show
  another website's icon; icons saved under the wrong site are cleared once and come back from their own sites. The address bar height in Sidebar + Tabs is a slider.

## 0.5.1 — 2026-11-17

- **Download needed:** copies before 0.5.1 can't install this update by themselves.
  [Download Ikago 0.5.1 from GitHub](https://github.com/FraudMomo/Ikago/releases/latest), open the DMG and drag
  Ikago to Applications to replace your copy. Your tabs and data stay, and later updates install by themselves.
- **Updates:** updates install again. macOS kept Sparkle's installer out of Ikago's protected storage, so updates
  downloaded and then stopped with "An error occurred while starting the installer".

## 0.5.0 — 2026-11-17

- **Downloads:** Download Image and Download Linked File in a page's menu work again with WebKit, and Chromium pages
  have them too.
- **Sidebar + Tabs:** the toolbar has its own controls, separate from the sidebar's: Settings ▸ Sidebar & Toolbar ▸
  Toolbar places them left or right of the address, and sets the bar's height (Compact, Standard or Large). Pinned
  tabs lead the tab row as icons when the icon sidebar is hidden, so the tabs no longer depend on it.
- **Icons-only sidebar:** choose the controls at its foot, such as Downloads in place of the sidebar button.
  Downloads appear there by themselves while there are any.
- **Address field:** Reload and the site and extensions button can leave the address field, and Site & Extensions is
  a control you can place in any toolbar.

## 0.4.1 — 2026-11-16

- **Updates:** updates now install after downloading; before, macOS stopped the installer and showed "Update Error!".
  Copies from before 0.4.1 can't update themselves: download 0.4.1 once from GitHub, and later updates install by
  themselves. Release notes in the update card keep each change on one line.

## 0.4.0 — 2026-11-16

- **Passwords:** the key and the login list now show reliably: in fields inside web components, in fields a page
  focuses as it loads, in sign-in dialogs, in fields found by their placeholder or label ("Email or phone"), and in
  fields that are still animating in. A click in a sign-in frame lists its logins too.
- **Moving the window:** Settings ▸ Appearance ▸ Layout ▸ Moving the Window. In the Sidebar layout, choose Press and
  Hold or a Drop-Down Header at the top of the page, how far down the edge reaches, and whether a double-click zooms
  the window, or turn it off. Sidebar + Tabs moves the window from its tab row.
- **Look:** the selected tab stands out in dark mode, the icon rail in Sidebar + Tabs is part of the window, and
  grouped toolbar buttons no longer turn into separate glass circles.

## 0.3.0 — 2026-11-16

The first public build: a native macOS browser with Spaces, split view, extensions and a choice of WebKit or
Chromium. Signed, notarized and updated over the air.

- **Browsing:** Spaces, tab groups, pinned tabs, bookmarks, Peek and split view with up to four pages
- **Your engine:** WebKit or Chromium as the default, with per-site rules
- **Reader, translation and saving:** Reader mode, whole-page translation on your Mac, and Save Page As (web archive
  or PDF)
- **Web apps:** add any site to Applications as its own window
- **Notifications:** websites can notify you through macOS, with Ask, Allow or Block per site
- **Extensions:** Chrome Web Store and Safari extensions, with a choice of which websites each one may read
- **Passwords:** a Touch ID–protected vault that offers to save and update logins, and exports to Apple Passwords
- **Continuity:** tabs from Safari on your other devices, and Handoff
- **Privacy:** isolated Space storage, tracker blocking, HTTPS by default and private windows
