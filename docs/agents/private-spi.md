# Private SPI in use

The inspector entries are guarded with `responds(to:)`, so a WebKit change disables the feature
instead of crashing. They live in `WebTab.swift` and are toggled by Settings ▸ Developer tools.

- `WKPreferences` key `developerExtrasEnabled`: adds Inspect Element to the page's context menu.
- `WKWebView._inspector` (`show`, `close`, `isVisible`): opens Ikago's own docked Web
  Inspector (⌥⌘I). The only public alternative is Safari's Develop menu.
- `WKHTTPCookieStore._flushCookiesToDiskWithCompletionHandler:` (`WebProfiles.flushCookies`): writes
  cookies to disk before quitting; guarded by `responds(to:)` and a timeout. No public flush exists.
- `WKUIDelegatePrivate` `_webView:saveDataToFile:suggestedFilename:mimeType:originatingURL:` (`WebTab+Delegates`):
  WebKit's PDF viewer download button delivers the file here, not as a `WKDownload`; saved via `DownloadCenter.save`.
- AppKit's Edit ▸ AutoFill ▸ Passwords… item, found by its private identifier/action
  `_handleInsertFromPasswordsCommand:` (`SystemPasswordPanel` in `PasswordAutoFill.swift`). Opening it
  posts the Edit menu's begin/end tracking notifications, because AppKit refreshes the item only then.
  If the item is missing, the sign-in key stays hidden. Toggled by Settings ▸ Security ▸ Passwords.

- `responsibility_get_pid_responsible_for_pid` (`PerformanceSampler`, looked up with `dlsym`): finds the WebKit processes that
  belong to Ikago, which launchd starts. Without it the performance overlay counts the app and its child processes only.

- `WKWebView._isPlayingAudio` (`PlayingAudioObserver`, KVO, guarded by `responds(to:)`): WebKit's own audible flag, so
  Web Audio, detached `Audio` elements and closed shadow roots still show the tab's speaker. The media script stays the
  source for playback controls. When the flag is available it alone decides the tab's speaker; the script's reports are keyed per document (a random
  `documentID`, cleared on pagehide), never by frame address, which pushState changes and left stale "playing" reports.

- `_webProcessIdentifier` (`PagePerformance`, checked before calling): maps a WebKit tab to its renderer for the visible
  Performance page and demand-driven tab preview. There is no public mapping; absence returns unavailable. It never changes page behavior.
- SPI: guarded WKWebView `_updateMediaPlaybackControlsManager`, `_canTogglePictureInPicture`, `_togglePictureInPicture` allow native macOS PiP for MSE media; DOM presentation-mode APIs remain the fallback.
- SPI: guarded WKPreferences `_setAllowsPictureInPictureMediaPlayback:` (`MediaPictureInPicture.allow`): without it WebKit
  reports no PiP support to pages and the toggle above does nothing. No public switch exists on macOS.
