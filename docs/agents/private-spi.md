# Private SPI in use

Each use is guarded (`responds(to:)`, `dlsym` or a check before calling), so a WebKit or macOS change turns the
feature off instead of crashing. Mark new uses `// SPI:` and add them here.

| SPI | Where | Why |
|---|---|---|
| `WKPreferences` `developerExtrasEnabled` | `WebTab` | Inspect Element in the page menu |
| `WKWebView._inspector` (`show`, `close`, `isVisible`) | `WebTab` | the docked Web Inspector (⌥⌘I) |
| `WKHTTPCookieStore._flushCookiesToDiskWithCompletionHandler:` | `WebProfiles.flushCookies` | write cookies before quit; no public flush |
| `WKUIDelegatePrivate` `_webView:saveDataToFile:…` | `WebTab+Delegates` | the PDF viewer's download button |
| Edit ▸ AutoFill ▸ Passwords… (`_handleInsertFromPasswordsCommand:`) | `PasswordAutoFill.swift` | Apple Passwords' panel |
| `responsibility_get_pid_responsible_for_pid` | `PerformanceSampler` | find WebKit processes that belong to Ikago |
| `WKWebView._isPlayingAudio` | `PlayingAudioObserver` | the tab's speaker for every kind of audio |
| `WKWebView._webProcessIdentifier` | `PagePerformance` | map a tab to its process |
| `_updateMediaPlaybackControlsManager`, `_canTogglePictureInPicture`, `_togglePictureInPicture` | `MediaPictureInPicture` | Picture in Picture for Media Source video |
| `WKPreferences` `_setAllowsPictureInPictureMediaPlayback:` | `MediaPictureInPicture.allow` | WebKit turns PiP off for embedding apps |
