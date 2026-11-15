# Security, privacy, storage, passwords and extensions

- Desktop app links use `ExternalLinkOpener` and public `NSWorkspace` APIs. Handle clicked links,
  top-level OAuth redirects, scripted handoffs and new-window links for any registered app scheme.
  Cancel WebKit navigation before prompting, preserve the complete callback URL, and launch the
  application the user approved. Never log callback URLs or authentication codes. Scripted subframe
  launches stay blocked; app links must not create blank popup tabs or replace the browser page.
- Security uses public WebKit HTTPS policies and native WKContentRuleLists. Strict mode
  never sends top-level HTTP requests; do not replay insecure POST bodies or silently fall
  back after a failed upgrade. Tracker/cookie rules are on by default, compiled before tabs,
  and updated on existing pages without removing extension-owned rules. Report compilation
  failures and describe the curated tracker list honestly; never bypass TLS certificate errors.
  Third-party cookies are blocked, not partitioned, on both engines; both partition third-party storage per top-level site
  (`CookieIsolationChecks`, `CEFCookieIsolationChecks`). On Chromium only requests Ikago cancels or upgrades get a
  `CefResourceRequestHandler`: CEF loads and saves cookies itself for those, ignoring the third-party setting.
  WebKit's blob files and media cache live in the user's temporary folder; `ProtectedStorage.removeTemporaryFiles` clears them at launch and quit.
- Private windows leave no trace on disk: favicons stay in memory (`persist: false`, `\.privateBrowsing`) and downloads stay out of
  the saved history (`WebProfiles.isPrivateStore`). Deleting history or clearing data also discards the session and download
  backups. Favicons only decode formats sites use (`isFaviconFormat`), because decoding happens in the unsandboxed main process.
- Chromium's background traffic is checked with a temporary `log-net-log` switch. Autofill's server lookups and AI Mode eligibility
  checks stay off. Component updates remain on because they deliver certificate revocation lists.
- History, sessions, download history and favicons are encrypted at rest (`SealedStorage`, AES-GCM, key in the login Keychain). Never
  fall back to plain text. A locked Keychain stops at launch with Try Again, so it can't look like lost data. Unattended checks use a
  fixed test key and must never touch the real Keychain.
- Everything else lives in protected storage (`ProtectedStorage`): the team-prefixed app group container, which macOS denies to apps of
  other teams (only Full Disk Access gets in). `package_app.py` adds the group to the app and every helper for team signatures. WebKit's
  per-app folders (`~/Library/WebKit|Caches|HTTPStorages/<bundle>`) are symlinks into it; macOS checks real paths, so links don't open a
  way around it. WebKit's built-in `.default()` store is never used, because its cookie file sits directly in the shared HTTPStorages
  folder: the Default Space is the identifier store `ProtectedStorage.defaultStoreID`, adopted from the old files at launch. Never touch
  `HTTPCookieStorage.shared` (configuring it loads that file and writes it back at quit); Ikago's own requests use ephemeral sessions.
  The updater's `Updates` folder stays in Application Support because it runs outside the app. Data moved in that a build can't open
  stops at launch instead of starting empty. Chromium's cookies are additionally encrypted with its Keychain key.
- Always require HTTPS is on by default, applied once to older sessions (`httpsDefaultApplied`). A site unavailable over HTTPS offers
  a remembered per-site exception on its error page. Sites ask before saving files (`DownloadPermissions`); with no window to ask in,
  the download doesn't happen.
- Phishing warnings (`SiteSafety`) cover look-alike addresses and public lists on both engines (`ThreatHosts`: phishunt.io
  CC0, PhishDestroy's main list MIT, never its aggregated community list); WebKit adds Apple's own fraud warnings. Lists download to this Mac and are matched locally; no address
  is ever sent anywhere. Warnings can always be overridden, and a list can't flag a site in `SiteSafetyRules.protected`. Describe this
  honestly: it isn't a live verdict service, and brand-new sites can slip through.
- Chromium updates run outside the app (`scripts/auto_update.py`, LaunchAgent `app.ikago.updater`) in a separate source copy: download
  and verify, build, run the full check suite, require a real signature, stage, then install only while Ikago is closed. Any failure leaves
  the installed app alone and reports in Settings ▸ About & Updates. The renderer, GPU, plugin and alert helpers have no camera or
  microphone entitlement; only the app and the base helper, which hosts the capture service, do.
- Switching engines keeps people signed in (`EngineCookieSync`). History, bookmarks and tabs live in the shared session. Cookies
  are copied only in Chromium runs, which can reach both stores: WebKit → Chromium on the launch after a switch, Chromium → WebKit
  on the quit before one (WebKit is only touched then, so ordinary quits stay fast). After a clean switch the last engine is
  authoritative, so logouts carry over; otherwise the copy only merges. Never write cookies anywhere else or log their values.
  localStorage and IndexedDB don't transfer. Clearing website data or deleting a Space applies to both engines. Checks use
  disposable stores and must never reach the real ones (`usesRealStores`).
- Website data persists per Space store. Quitting replies `.terminateLater` and flushes every
  persistent store's cookies (`WebProfiles.flushCookies`, bounded timeout) before exiting; WebKit's
  networking process otherwise dies mid-write and loses the newest cookies (logins, rotated device
  tokens). Keep that work callback/run-loop based: `terminate` from inside a main-actor Task blocks
  Swift tasks, so the Debug `quit` action terminates from the run loop like a menu. Session cookies
  ending at quit is WebKit behaviour. Verify with `datapersistencechecks:write|<base>` then
  `datapersistencechecks:read|<base>` in two launches sharing `IKAGO_TEST_STORAGE_UUID`.
- Extension resource origins are persisted per installation, alongside stable package IDs.
  Keep WebKit's native scheme and restore the saved origin before loading the context; localStorage
  and IndexedDB must survive reloads, enable/disable and relaunches. Ordinary Debug tests remain
  nonpersistent; explicit restart fixtures may use a fresh disposable store/controller UUID.
- Web Store packages are verified before unpacking (`CRXVerifier`): CRX3 only, every signature valid, signed by the
  key the extension ID comes from and by the Web Store's publisher key, no ZIP tokens in the header. Local packages are the person's choice.
- Extension compatibility checks must run on every install path. Passing a manifest check is
  not proof of runtime support. Show reasons in the store page and Settings. Automatic updates
  must retain the previous working copy on failure and ask before expanding capabilities.
- Camera/microphone: `WebTab.tearDown` ends capture (`setCamera/MicrophoneCaptureState(.none)`) and pauses
  media before detaching, because anything still holding a detached web view keeps the device open. A muted
  capture still counts as in use (`TabItem.…Muted`). Tab indicators are `CaptureMenu`s: mute/resume, stop, and
  for the microphone the input device. WebKit can't route a page to a chosen mic, so the menu switches the
  system default input through CoreAudio (`AudioInputDevices`), labelled as affecting all apps; no page-world script.
- Passwords fill from one of two sources (`PasswordSource`, Settings ▸ Passwords). Apple Passwords (WebKit only): Apple's own
  AutoFill panel types the login, and Ikago never sees it. Ikago Passwords (both engines, Chromium's only source): `PasswordVault`,
  imported from a Passwords app or Chrome CSV export that is then overwritten and deleted (`PasswordImport`). Each password is encrypted
  (ECIES, AES-GCM bound to site and username) to a Secure Enclave key that needs Touch ID or the Mac password for every single fill;
  sites and usernames are sealed. Matching is the registrable domain from the bundled Public Suffix List (`PublicSuffix`, `public_suffix_list.dat`): exact host first, then parents/children, then other subdomains; subdomains of a public suffix (github.io) are separate sites. The menu lists every match.
  `PasswordKeyScript` shows the key in password and username fields in an isolated world; only a trusted click asks native code, which
  picks a login in a native menu (`PasswordChooser`) and passes it to the script's `fill` as call arguments, never script text. WebKit:
  `.defaultClient` world and message handler, main frame or same-origin frames. Chromium: the "ikago-passwords" world of the top
  document only, injected per document and only on sites with a saved login. The page never messages Ikago: a passive mouse-down
  monitor sees the real click and asks the script's `hit(x, y)`. Never enable DevTools' Runtime domain on pages (pages can detect
  it and it streams every console message). Saving new passwords isn't built yet. Debug tests count panel
  requests and pick the first login instead of showing a menu.
- Safari bundle native messages use WebKit's default delivery; do not override the messaging
  delegate with a blanket unsupported response. Chrome native messaging is still unavailable.
- Preserve WebKit’s native extension resource origins. Use `resourceURL`/`canonicalURL` to
  resolve Chrome-style navigation and persist stable package IDs; extension-tab APIs must
  expose resource URLs consistent with `runtime.getURL`.
