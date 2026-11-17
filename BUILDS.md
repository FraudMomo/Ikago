# Builds

What changed in each release of Ikago, newest first. Add changes under **Unreleased** as they land;
`scripts/release.py` publishes that section as the release notes and moves it under the new version.

## Unreleased

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
