# Ikago to-do

Working list for the next builds. Tick items off as they land; move finished themes into ROADMAP.md.

> Checked 2026-11-17: the bookmarks bar exists only as the sidebar's drawer (Shift+Cmd+B); there is none under the
> Top Bar. The macOS Bookmarks menu has Show Bookmarks Bar / Bookmark This Page / Show Bookmarks but doesn't list
> bookmarks. Imports bring bookmarks in flat (no folders), and there is no export yet.
>
> Ticked items are fixed in the working tree and tested in Ikago Test, not yet committed.

## Top Bar layout (make it as usable as the sidebar)

- [x] **Bookmarks bar** under the Top Bar.
- [x] **Bookmarks in the macOS menu bar**: a Bookmarks menu with folders as submenus.
- [ ] **Tab groups in the Top Bar**: Chrome-style group chips that collapse and expand.
  - [ ] Setting for where groups show: **both (default)**, sidebar/icon sidebar only, or Top Bar only.
- [ ] **Hide (close) a tab group**: it stays saved but is hidden. This is separate from collapse.
  - [ ] Bring it back from the icon sidebar, or a clean "Show tab groups" button/menu.
- [ ] **Toolbar placement in four zones**: far left, left of the URL bar, right of the URL bar, far right.
- [x] **Bug: closing a tab animates over the tab before it** Fixed: the closing tab fades out under its neighbours. (the transition overlaps).
- [ ] **Bug: a new tab opened from the command bar sometimes disappears**, or opens but isn't shown as selected
  in the Top Bar. It may be a state bug and not only a UI bug.

## Sidebar + Tabs layout

- [x] **URL bar height**: a custom slider in place of the three fixed heights.
- [x] **Bug: no scroll wheel/scrolling in the sidebar** Fixed: a slim scroll bar in its own gutter beside the rows.
  - [x] Setting "Keep pinned tabs and groups in view": only the tabs under them scroll. when many tabs are open.
- [x] **Bug: toolbar icons are positioned wrongly in the sidebar.** The Reload button drops onto its own row
  under Back/Forward, alone at the right, instead of staying in the row by the traffic lights. Check how the
  row wraps or overflows when it's narrow or has several buttons (a phone/device button, the sidebar toggle,
  Back, Forward, Reload). Fixed: icons shrink first, then plain buttons move into a "»" More menu; Downloads,
  Devices, Spaces, Share and Site Info always stay in the row.
- [ ] **Customizable Space header and shortcuts**, like the toolbar: remove the assistant button, add your own
  buttons, move the grid above or below, and so on.

## Bookmarks

- [x] **Folders** fully supported, including in imports.
- [x] **Large bookmark lists stay fast**: the page filters once and shows 200 rows at a time; the bar shows 40 chips.

## Import and export

- [ ] **Robust import for every browser** (Chrome, Safari, Firefox and the others). Checked with real profiles:
  - [x] Safari open tabs (Tab Groups → groups) and website logins (cookies) are read; Full Disk Access is explained.
  - [x] Chrome: a profile without bookmarks no longer reports an error.
  - [ ] Chrome cookies depend on the Keychain prompt ("Chrome Safe Storage"); confirm in a real import.
  - [ ] Passwords: Chrome's Login Data (Keychain), Firefox (key4.db), Safari (needs its CSV export).
  - [ ] Cookies for an engine not running this launch are lost; keep them until that engine starts.
  - [x] Read databases from a snapshot copy so an open browser never blocks or hides recent data.
  - [ ] History: Ikago keeps 1,000 entries in total (`Session.maxHistory`), so imports can't add more. Decide on a
    larger history store before raising it.
  - [x] Importing again moves earlier flat bookmarks into their folders, without duplicates ("Import Again").
  - [ ] One clear report per item (found, imported, skipped and why) instead of one summary line.
- [x] **Import keeps bookmark folders.**
- [ ] **Export**: bookmarks, history and passwords in formats Chrome, Safari and others can import, so people can
  leave Ikago.

## Tabs

- [x] **Bug: Cmd+Shift+T (reopen closed tab) doesn't behave like Chromium.** Match Chrome: reopen in the original
  order, at the same position in the same Space, group and window, with back/forward history kept. Reopening a
  closed window brings back all its tabs. Repeated presses go further back through the list. Fixed: a run of
  closed tabs comes back in its order and place (pins after groups too).
  - [ ] Still open: reopening a closed window with all its tabs.

## Extensions

- [ ] **Bug: extension errors that look like update or service worker problems.** Momentum shows
  "Message to service worker timed out. Reason: Worker version not verified" from its `getVersion` handler.
  Check whether the update check or reinstall leaves the service worker on an old or unverified version.
  Check which engine it happens on and whether a relaunch fixes it. Also check whether the error text shown in
  Settings is useful or just noise.

- [x] **Extension site requests use Ikago's access card**, not the system alert, over the pane that asked in
  split view.
- [x] **Bug: wrong favicons in the command bar** (a tab kept the last site's icon after moving to another site).

## Privacy

- [ ] **Investigate iCloud Private Relay, or something like it.** Private Relay itself is meant for Safari, so
  find out whether a third-party browser on WebKit or Chromium can use it at all. If it can't, look at
  alternatives: per-Space proxy or SOCKS settings, Oblivious DoH / encrypted DNS, or working with a relay or VPN
  provider. Check what each engine supports.

## Passwords

- [ ] **Regular reminder when new passwords are saved** suggesting an export to iCloud Keychain. Offer
  "Ignore" and "Don't show again".

## Settings

- [ ] **Visual settings**: an image, figure or looping clip beside each option showing what it changes
  (e.g. what the grid looks like). Clear for first-time users and people new to sidebars.
  - [ ] Window-moving settings show the drag edge height visually.
- [ ] **Hide or gray out settings that no longer apply**, e.g. after changing the layout.

## Find in page (Cmd+F)

- [x] **Bug: Esc doesn't close the find bar** Fixed, plus Cmd+F always focuses the field., and the matches stay highlighted after closing. Closing should
  clear all highlights on both engines.
- [x] **Find bar redesign** in Ikago's style, with a labeled **Highlight All** toggle (WebKit) and match count.
- [ ] **Better Cmd+F**: current match position ("3 of 12"), next/previous (Cmd+G / Shift+Cmd+G, Return /
  Shift+Return), and the last search remembered per tab.
- [ ] **Advanced options**: match case, whole words, maybe regex. Show where matches are along the scroll bar,
  and search across all open tabs.

## Pages and polish

- [x] **Bug: dropping a file onto a page opens the file** instead of handing it to the page's upload area
  (e.g. a drop zone on Gmail or Drive). Drops on the page should go to the page first. Only open the file
  when the page doesn't take the drop, or when it's dropped on the tab strip or sidebar. Check both engines.
  Fixed for WebKit (Chromium already gave drops to the page).
- [ ] **Bug: DuckDuckGo sometimes shows as a plain page** (not loading properly or not styled).
- [x] **Empty state when all tabs are closed**: a nice Ikago screen, not a blank page with the Space name.
- [x] **Extension popup "Allow on every website"** should look like a button, not a label.

## Engines, first run and downloads

- [ ] **WebKit-only option at download or first start**: Chromium isn't downloaded unless it's needed later.

## Performance

- [ ] **Animations and transitions on weaker Macs**: high CPU seen on an M1 MacBook Air. Measure, then optimize
  or reduce effects there.
- [ ] **Tab memory for WebKit and Chromium**: study how Chrome discards/sleeps tabs. Make Conservative vs
  Responsive modes clearly different in memory use.
