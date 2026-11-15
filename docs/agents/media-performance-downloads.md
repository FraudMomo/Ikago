# Media, memory, performance and downloads

- View ▸ Performance Stats (`PerformanceOverlay`, saved in UserDefaults, never shown in check runs): frames per second and the
  slowest frame of the last second from a main-thread display link, plus CPU and memory footprint summed over the app, its
  Chromium helpers and its WebKit processes (`PerformanceSampler`, once a second off the main thread). Plain AppKit on the
  window's content view, so it adds nothing to the SwiftUI graphs. Check it with the `perfstats` test action.
- View ▸ Performance opens `ikago://performance`: per-engine and shared process footprint/CPU, main renderer tab rows,
  GPU service CPU/RAM (never presented as GPU utilization), and a bounded RAM history. `PerformanceMonitor` shares one
  off-main sampler among visible diagnostics and stops when no consumers remain. Hidden Performance tabs unmount their
  dashboard. Renderer totals may be shared by tabs and exclude separate subframes; never add tab rows to browser totals.
  CEF's renderer helper reports its PID over native process messages, not page scripts. `PageLifetimeCanary` watches
  retired page owners/views weakly, checks every 30 seconds only while records remain (cap 200), and flags retention
  without claiming a proven leak. No page contents, URLs, dumps or canary data are written to disk.
- The sidebar's media island (`SidebarMediaPlayer`) is one clean row on the sidebar's own glass (`.surface` with the chrome
  palette; a flat panel with glass off): artwork, Media Session title and artist, and Play/Pause and Next always in reach.
  Clicking the title opens the card with mute, PiP and the source picker. Artwork comes from `MediaArtwork` (cookie-free, raster only, memory only).
  Artwork falls back to the playing media's poster and HTTPS page thumbnails when isolated-world metadata is absent;
  decode only a bounded 160 px thumbnail. Mute and Next have equal hit targets around the centred Play/Pause button;
  the source picker lives in the header so it cannot shift playback controls. Close stays inside the island.
  Playback indicators stay static; no waveform timer or audio analysis. Closing it hides it until
  something new plays. Opening, closing and appearing run in the island's own `withAnimation` (`Animation.island`), so
  the sidebar list gives way smoothly (measured with `islandprobe`); never an implicit `.animation` here.
- Completed download rows open files on a single click via a dedicated button; cancel and
  Show in Finder are separate hit targets. Keep popup styling on the current chrome palette
  and shared surface; a missing file or failed open reports an error without removing history.
- Downloads use a dropdown anchored to the sidebar's Downloads control, plus `ikago://downloads` for
  full history. `DownloadCenter` owns byte progress and cancellation; `DownloadHistoryStore` saves
  owner-only atomic history with backup (up to 1,000 entries). Keep completed/failed/cancelled
  entries across relaunches, restore unfinished entries as interrupted, and never delete files
  when clearing history. The automatic toolbar control stays for active/recent (24-hour) downloads started since launch (history restored at launch never brings it back);
  the dropdown’s × dismisses it without clearing history (active work stays visible until finished,
  and a new download brings it back). A user-placed Downloads control is permanent. Download flight
  and completion feedback is visual only, passes through input and respects Reduce Motion.
  Page progress and Stop belong in every address presentation; a finished load runs the progress line to the end, then fades it.
- The media script stays cheap on huge, changing pages (Pinterest): mutations are looked at once a quarter second (only
  the added elements themselves, never their subtrees; deeper shadow roots are found on load, clicks and keys), no
  layout-forcing reads (`getClientRects`) in reports, artwork only for playing media, and WebKit reports once per burst.
  Silent autoplay previews never report: only media that has been heard, errors and volume changes do.
- Browser preferences and bookmarks persist with the session; keep new session fields optional
  so existing profiles restore. `TabMemoryManagement` responds to macOS memory pressure, never an idle clock or a RAM
  quota. Conservative reclaims safe inactive pages on warnings; Responsive waits for critical pressure. Visible split
  panes, loading/playing/capturing pages, popups, protected pins/sites, drafts and native navigation history are protected.
  Failed inspection retains a page. Safe parked engine-history documents can release their views while retaining their
  Back/Forward destination and engine. Wake through `startIfNeeded()`. New profiles use Conservative; saved profiles
  map the former hibernation opt-in to Conservative and other profiles to Responsive unless a new choice was saved.
- Picture in Picture (the media island's button, the video's right-click item, a page's own PiP button). WebKit: macOS's own
  PiP, which WebKit turns off for embedding apps; `MediaPictureInPicture.allow` turns it on for every web view (measured:
  YouTube reported no PiP support, so every route silently did nothing). Chromium: its own PiP opens a borderless Chromium
  window, which `ChromiumWindowGuard` hides; instead `ChromiumPictureInPicture` puts the video in element fullscreen inside
  its frame (a user gesture through DevTools) and moves the page view into Ikago's floating panel, with Back to Tab and
  Play/Pause on hover, while the tab shows a note. A page's own request (`enterpictureinpicture`, reported by the
  page-state world) is taken out of Chromium's PiP into the panel. Videos Chromium can't play (H.264 files) fall back to
  AVKit for direct addresses. A tab moving windows ends the panel first (`WebTab.endPictureInPicture`). Check with
  `pipchecks` (WebKit) and `CEFPictureInPictureChecks`.
