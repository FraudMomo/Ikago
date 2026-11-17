# Builds

What changed in each release of Ikago, newest first. Add changes under **Unreleased** as they land;
`scripts/release.py` publishes that section as the release notes and moves it under the new version.

## Unreleased

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
