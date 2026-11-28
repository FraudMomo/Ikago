# Security, privacy and storage

## How it's built

- **Where data lives.** `ProtectedStorage` puts everything in the team-prefixed app group container, which other
  teams' apps can't read. WebKit's per-app folders are symlinks into it. Ad hoc builds use
  `Application Support/Ikago`.
- **Encryption at rest.** History, sessions, downloads, favicons, notes and autofill go through `SealedStorage`
  (AES-GCM, key in the login Keychain). A locked Keychain stops at launch with Try Again instead of starting empty.
- **Website data** is one store per Space (`WebProfiles`). The Default Space uses an identifier store
  (`ProtectedStorage.defaultStoreID`), never WebKit's `.default()`. Chromium keeps its own cookie store.
  `EngineCookieSync` copies sign-ins between the engines.
- **Permissions.** Every kind is in one catalog (`PermissionKinds.swift`). Requests go through `PermissionRequest`,
  which denies itself if dropped. The window asks with its own prompt (`PermissionPrompt`); answers are stored in
  `SitePermissions`.
- **Network.** HTTPS policies, tracker and cookie rules are WebKit content rule lists, plus CEF request handlers on
  Chromium. Third-party cookies are blocked on both. Phishing lists (`SiteSafety`, `ThreatHosts`) download and match
  on this Mac; no address is sent anywhere.
- **Passwords.** Two sources (`PasswordSource`): Apple Passwords on WebKit, or Ikago's own `PasswordVault`, where each
  password is sealed to a Secure Enclave key that needs Touch ID per fill. `PasswordKeyScript` and `FormFillScript`
  run in isolated worlds and get values as call arguments. Saving and strong passwords are `PasswordSaving` and
  `PasswordGenerator`. Cards are sealed to the vault's key too.
- **Extensions.** Web Store packages are verified by `CRXVerifier` before unpacking. `ExtensionAccess` decides
  per-site access on both engines, and `ExtensionSync` keeps Web Store extensions in step between them. Safari
  extensions are found (`SafariExtensionScanner`), never added by themselves.
- **Import** reads other browsers' files read-only (`Import/`, `ImportFileParser`). macOS hides their folders until the
  person allows each one, so discovery shows a "needs access" entry and opens the folder picker, after a card that says
  what comes (`ImportAccessPrompt`; Full Disk Access for Safari gets one too, before System Settings opens).
- **Agents.** `AgentServer` listens on loopback only, refuses requests with an `Origin`, and needs the sealed token.
  An agent's name only labels it and grants nothing.

## Traps

- **Never fall back to plain text** when sealing fails, and never touch `HTTPCookieStorage.shared` (configuring it
  loads WebKit's shared cookie file and writes it back at quit).
- **Flush cookies before quitting** (`WebProfiles.flushCookies`). WebKit's network process otherwise dies mid-write and
  loses the newest logins.
- **Camera and microphone:** `WebTab.tearDown` ends capture before detaching, or anything holding the view keeps the
  device on.
- **Private windows write nothing to disk:** no favicons, downloads history, passwords or permissions.
- **Outside files are hostile.** Clamp or check every number before converting or using it in a range;
  `parserfuzzchecks` fuzzes each parser. A history JSON holding `1e300` once ended Ikago.
- **Imports:** read sources through read-only SQLite handles, never log or keep decryption keys, and never mark a
  partial import complete. Test with an `open` launch: a terminal with Full Disk Access sees folders a normal launch
  can't.
- **App links** (`ExternalLinkOpener`): cancel the navigation before asking, keep the whole callback URL, and never log
  it.
- **Never bypass TLS errors,** never claim live Safe Browsing, never borrow an API key.
- **Checks use disposable stores** and a fixed test key, never the real Keychain or the person's stores
  (`usesRealStores`).
