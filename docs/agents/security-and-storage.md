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
  `PasswordKeyScript` shows the key in password and username fields (by name, autocomplete, placeholder or label) in an
  isolated world, including fields in open shadow roots, a field focused before the script ran (autofocus; also picked up
  on the next click), and fields in a modal dialog or popover (the key joins the top layer as a manual popover). A field
  too small for the key (a dialog still growing in) keeps it hidden and is measured again as it settles, never dropped; only a trusted click asks native code, which
  picks a login (`PasswordChooser`) and passes it to the script's `fill` as call arguments, never script text. WebKit:
  `.defaultClient` world and message handler; main frame, same-origin frames, and HTTPS frames on the same registrable domain (a
  sign-in iframe such as idmsa.apple.com in appstoreconnect.apple.com); `fill` gets the frame's own origin. Chromium: the
  "ikago-passwords" world of the top document and its same-site HTTPS frames (`scanPasswordFrames`, re-run after loads and
  clicks since sign-in iframes arrive late), on sites with a saved login or, while saving is on, any HTTPS site; the key shows
  only with a saved login (`setKeyAllowed`). The page never messages Ikago: passive monitors see real clicks and keys, then ask
  the script (`hit(x, y)` on the top document, `poll`/`focusRect`/`saveState` in frames). Never enable DevTools' Runtime domain
  on pages (pages can detect it and it streams every console message). The logins list is Ikago's own card in the window's
  SwiftUI tree (`PasswordSuggestions`, shown through `ChromeModel`), the same on both engines: it opens under the field after
  the person's own click or Tab (`passwordSuggestOnFocus`, unset: on; a page focusing a field by itself opens nothing) or from
  the key, and a local monitor reads arrows, Return and Escape while the page keeps the keyboard. Logins with the same
  username on several sites of the domain are one row (the vault's best match first; its chevron, or →, lists the others, so
  none is hidden). The username the form holds (`typed`, read again with the script's `typed()` as the person types) narrows
  the rows to usernames containing it, but only when one does (a prefilled address that isn't saved shows them all; typing
  one that isn't closes the list). More than three usernames add a search field (usernames, sites, titles). The click that
  closes the list (on the key or the field) doesn't reopen it (`closedByClick`), and the header has a close button. Choosing
  a login still asks Touch ID. Fields in child frames without a known offset list at the pointer. Debug tests pick the first login instead of a list.
- Saving logins (`PasswordSaving`, `passwordOfferSave`, unset: on; Ikago Passwords only; never in private windows, asked of the
  window): the script captures a filled password on submit, Return or a button, and confirms the sign-in only when the password
  field goes away or the page moves on to one without a password field, so a rejected password is never offered. The card
  (`PasswordSaveCard`) offers Save, Not Now or Never for This Site (`passwordNeverSave`, registrable domains). A login's
  `fingerprint` (HMAC under a key derived from the local data key, inside the sealed vault) recognizes a resubmitted password
  without Touch ID; older logins learn it on their first fill. Export to Apple Passwords: Apple has no API for adding passwords,
  so `PasswordExportSection` writes the Passwords app's CSV (one Touch ID for all), the person imports it (File ▸ Import
  Passwords…), and Ikago erases the file; only logins saved here (`savedHere`) and not yet exported (`exported`, cleared when the
  password changes) are included. Checks: `passwordsavechecks` (WebKit) and `CEFPasswordChecks` (Chromium).
- Strong passwords (`PasswordGenerator`, `passwordSuggestStrong`, unset: on; HTTPS or local pages, never private windows,
  whichever source fills logins): the key script marks new-password fields (`autocomplete="new-password"`, the new and confirm
  fields of a two- or three-password form, or a password field on a sign-up page) and reports their `passwordrules`,
  `minlength`, `maxlength` and `pattern`. The suggestions card puts "Use Strong Password" first (`PasswordSuggestions.generated`);
  the script's `fillNew` fills the field and its confirmation (never a current-password field). Nothing is saved then: the
  person confirms the save card once the form goes through, with its username (`rememberStrong` only marks the password, in
  memory, so the card says "Save strong password?" and doesn't time out). So a change-password form never replaces the saved
  login before the change succeeds, and no login is ever saved without the person seeing its username; an empty one says so
  and the button reads Save Anyway. Default format: three groups of six letters and digits with one
  uppercase and one digit, no look-alike characters; every pick is `SecRandomCopyBytes` with rejection sampling. On Chromium
  the script learns `setGenerateAllowed` and the field's report travels with its rect. Checks: `passwordstrongchecks`.
- Addresses and cards (Settings ▸ Autofill; `autofillAddresses`, `autofillCards`, `autofillOfferSave`, unset: on): stored in
  `autofill.sealed` (`AutofillStore`, `SealedStorage`, with a backup); a card's number is sealed again to the password vault's
  Secure Enclave key (`PasswordVault.seal(secret:label:)`, bound to `secretSite` and the card's id, so it can never read as a
  password) and opens with Touch ID for each fill (`open(secret:)`); only its last four digits, brand, name and expiry are
  readable, and the security code is never saved or filled. `deleteAll` keeps the vault's key while cards need it.
  `FormFillScript` (isolated world; on Chromium it shares the password world, `pageScripts`) recognizes fields by
  `autocomplete` tokens, then name, id, label and placeholder (an expiry needs "exp", "cc" or "card", so a birthday never
  reads as one); an address field needs a second address field beside it. After the person's own click or Tab it reports the
  field (`focus` on WebKit, `focusInfo` on Chromium); `AutofillFlow.choose` lists saved ones (`AutofillSuggestions`, the same
  card style as passwords) and the script's `fill` takes the values as call arguments for its origin only, filling the whole
  form's fields the person can see (selects by value or text, expiry in the field's shape). Seeing means at least 4×4
  points, `checkVisibility` with opacity and visibility, no transparent ancestor, not clipped away (`clip-path`, `clip`, an
  `overflow: hidden` box it sits outside of), not moved off the page and, when in view, not covered by another element: a
  page that shows a name and hides a street or phone gets only the name. Saving reads the same visible fields. Submits are captured (`submitted` / `takeSubmitted`) and
  `AutofillSaveCard` offers the new card, then the new address. Secure pages only, main frame or same-site frames, never
  private windows for saving. Checks: `autofillchecks`.
- Safari bundle native messages use WebKit's default delivery; do not override the messaging
  delegate with a blanket unsupported response. Chrome native messaging is still unavailable.
- Extension website access (`ExtensionAccess`, one store for both engines, keyed by Web Store ID when there is one): an
  extension runs on every website, or asks on each, where the choice is Always Allow, Allow for One Day or Don't Allow
  (registrable domain, subdomains included; `ExtensionAccess.pattern(for:)` keeps IPs and one-word hosts exact). Ones
  installed before this keep running everywhere; new installs ask (`startAsking`). WebKit applies it with
  `setPermissionStatus` (one day uses WebKit's expiry; every grant is reset first so "Ask Next Time" takes effect);
  Chromium with `developerPrivate` site access (ON_ALL_SITES / ON_SPECIFIC_SITES + host grants), lined up after every read
  of a Space's extensions. The first visit to a matching website shows `ExtensionAccessCard`; the site card and Settings
  change it. Checks: `extensionaccesschecks` (WebKit), `CEF_EXTENSION_ACCESS_OK` (Chromium).
- Safari extensions are found, never added on their own: `SafariExtensionScanner` watches /Applications and ~/Applications
  (and rescans one folder down, and when Ikago becomes active); Settings ▸ Extensions ▸ Safari Extensions lists each with a
  switch, and the first switch-on asks for its permissions and adds it. They run on WebKit pages whichever engine is the
  default (`WebProfiles` always attaches the controller). Detection never depends on Safari having it turned on. Safari
  app extensions (`com.apple.Safari.extension`, native code Safari hosts) and content blockers are listed as "Safari only":
  WebKit can't run them. Check: `safariscanchecks`.
- Preserve WebKit’s native extension resource origins. Use `resourceURL`/`canonicalURL` to
  resolve Chrome-style navigation and persist stable package IDs; extension-tab APIs must
  expose resource URLs consistent with `runtime.getURL`.
- Agents name themselves in the MCP handshake (`clientInfo`); `AgentIdentity` turns that into "Claude Code" or "Codex"
  and a mark (`Resources/agent-logos`, Simple Icons). The name only labels tabs, the bar and the log, and grants nothing:
  the token is the only credential. `AgentServer` keeps session → agent so each request is logged under its agent
  (`AgentActivity.current`). Setup snippets (`AgentSetup`) all carry the token, so they leave Ikago only on Copy; Reset
  token stops every agent.
