# Interaction refinements

- Unpinned tab menus offer **Pin as Sidebar Row** directly; existing pins can switch between row and tile.
- Group menus open one integrated icon/color grid. Rename fields use the current name as a placeholder;
  Return or outside-click commits. New Space uses the same in-window presentation and focuses its name field.
- Hover cards prepare available thumbnails before appearing, fade in as one surface, and omit the current tab’s thumbnail.
- Space swipes crossfade the sidebar list; inserted and retiring rows animate inside the native list host.
- Shift-click links opens a live, dismissible Peek over the existing page. It does not navigate the underlying tab.
  Shift-click another tab previews its live page. Open Tab promotes navigation; a transient preview is closed on dismissal.
- The media island puts PiP after the source control, with Close appearing beside it on hover. WebKit’s guarded native PiP
  selector handles page-managed streams; the direct-media fallback remains for other engines.
- WebKit avoids automatically running its bundled blocker alongside an existing ad blocker, without changing Chromium’s
  separately running extension. Explicit extension choices and independent blockers remain manageable in Settings.
- Downloads closes before its temporary control is dismissed, preserving history and active-download visibility.
- Top tabs use readable 160–180 pt slots and overflow by scrolling. Compact navigation animates between expanded and
  reading states; bottom navigation floats, reserves reachable page space, and does not reserve room for traffic lights.
- Standalone traffic lights sit over system material, with page space reserved underneath.
- Notes opens in a dismissible overlay. Page assistance is available directly from the sidebar and toolbar and opens as
  a full-height side panel; on-device processing remains opt-in with an enable switch in the panel itself.
- Unstarted pages and hibernated pages share the dimmed/sleep presentation; live parked pages remain distinct.

The WebKit native PiP selector is private SPI, checked at runtime and documented in docs/agents/private-spi.md. Chromium cannot natively
reopen every page-managed or protected stream without an engine-owned window, which Ikago deliberately forbids.
