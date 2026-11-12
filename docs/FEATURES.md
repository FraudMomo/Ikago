# Browser controls

## Tabs and navigation

- **Peek:** Shift-click a tab to preview it without selecting or loading it. Hover for
  ¾ second for a passive card with its engine, an available thumbnail, and renderer RAM.
  Shared renderer memory is labelled; unloaded tabs stay unloaded.
- **Unload:** right-click a tab → Unload Tab, or a group → Unload Group. This releases
  its page while keeping the tab. Selecting it reloads the page; unsaved page contents
  and native navigation history are not retained by a manual unload.
- **Pins:** right-click a pin → Show as Sidebar Row / Show as Pinned Tile.
  Settings → Sidebar & Toolbar → Grid columns chooses 2–8 columns, as space permits.
  Unloaded tabs are dimmer, and default group icons show a favicon mosaic.
- **Closing:** a child tab returns to the previously selected surviving tab.
- **Private opening:** link, tab and bookmark menus can open a private window.
- **Search:** native selection search stays in Ikago. Search settings also offer
  Brave Search, Ecosia and Yahoo alongside DuckDuckGo, Google and Bing.

## Layout and Spaces

- Settings → Appearance → Sidebar side moves the sidebar left or right. Window
  controls can follow it or stay in their own island. Horizontal trackpad swipes over
  the sidebar or icon rail switch Spaces.
- A Space’s context menu chooses shared or separate cookie storage. Shared Spaces use
  the same logins. Changing this reloads pages with the chosen store; cookies are not
  copied or deleted.
- Settings → Appearance → Color & Theme edits any Space. Presets and custom light/dark
  colors use the same Space selection; custom swatches have an in-app palette and hex entry.
- Top navigation can sit at the bottom. Optional **Compact on scroll** reduces it to
  a page-title ribbon; scroll up or click the title to expand. Bottom address suggestions
  open upward. Compact address editing uses a stable shared field outside the tab strip.
- Regular top tabs retain readable widths and scroll. Unconfigured top-bar pins start
  hidden and remain accessible through the tab sidebar.
- Fullscreen uses a shorter AppKit resize and refits pages during transitions. Sidebar
  rubber-banding no longer competes with an automatic bottom clamp.

## Page tools

- **Notes:** View → Notes (⌥⌘J), `ikago://notes`, or a customized Notes toolbar button.
  One shared scratchpad saves encrypted edits and flushes on quit. Private-window notes
  remain in memory and disappear when that window closes.
- **Apple Intelligence:** Settings → General → Page assistance, then View → Ask This Page.
  Summaries and questions use a bounded page excerpt on this Mac, only when requested.
  The system model must be available. Answers can be inaccurate; long pages are truncated.
- **Translate:** right-click → Translate Page with Google. This opens Google Translate
  with the page address; it is separate from on-device assistance.
- **Floating video:** the media island has a PiP button, independent of page menus.
  WebKit uses its native video presentation mode. On Chromium, directly playable video URLs can open in a native floating AVKit
  player. Protected and page-managed streams cannot universally be reopened this way;
  WebKit’s own video/Picture in Picture menu remains available where supported.
- Page dialogs use site-labelled native sheets. WebKit extension loading is deduplicated.
- For a stalled video, the site menu offers a reversible **Built-in tracker blocking**
  switch and reload. Extension ad blockers retain their own controls. This is a recovery
  option, not a verified fix for every YouTube delay.

## Small controls

- Closing Downloads dismisses its automatic button without clearing history. Active
  downloads and new downloads show it again; explicitly customized buttons stay visible.
- The media island fades away after 30 seconds without hover, keyboard focus or an
  explicitly expanded player. New or resumed playback can bring it back.
