# Distribution: Developer ID, notarization and updates

Public releases are made by `scripts/release.py` and published as GitHub Releases. Builds made on a developer's Mac
(`scripts/install.sh`) are unchanged: they keep the local Chromium rebuilder (`scripts/auto_update.py`, `ChromiumUpdates`).

## One-time setup on the releasing Mac
- A **Developer ID Application** certificate in the login keychain (developer.apple.com ▸ Certificates). Same team as
  local builds, so the protected app-group container (`<TEAM>.app.ikago.browser`) and everyone's data carry over.
- Notarization credentials: `xcrun notarytool store-credentials ikago-notary --apple-id … --team-id …` with an
  app-specific password. Saved in the login keychain.
- The update signing key (EdDSA) in the login keychain, under the account in `scripts/release.json`. The login keychain
  doesn't sync through iCloud: back the key up with `release.py --export-update-key FILE` and add it on another Mac with
  `--import-update-key FILE`. Losing it means installed copies can't verify new updates; anyone holding it can sign them.
- `python3 scripts/release.py --check` lists whatever is missing.

## What a release does
1. Bumps `scripts/release.json` (version, build + 1; Sparkle compares the build number, which must only go up).
2. Builds with `IKAGO_DISTRIBUTION=1`: `package_app.py` signs every piece with Developer ID, the hardened runtime and
   Apple's secure timestamp, and adds the feed (`SUFeedURL`) and public key (`SUPublicEDKey`) to Info.plist.
3. Notarizes the app (zip), staples it, builds the DMG (app + Applications link), signs, notarizes and staples the DMG,
   and checks it with `spctl` the way Gatekeeper will.
4. Signs the DMG for Sparkle (`sign_update`) and writes `appcast.xml` with just this release.
5. Release notes: `--notes FILE`, or else the `## Unreleased` section of `BUILDS.md` plus a short install line
   (`out/release/notes.md`); the release refuses to start when that section is empty. Add each user-facing change
   there as it lands.
6. With `--publish`: moves Unreleased under `## X.Y.Z — date` in `BUILDS.md`, commits it with the version, tags `vX.Y.Z`, pushes, and creates the GitHub release with the DMG and
   `appcast.xml`. The feed URL is `releases/latest/download/appcast.xml`, so a release must be marked latest (never a
   pre-release) for installed copies to see it.

## Updates in the app
- `AppUpdates` runs Sparkle's `SPUUpdater` only when Info.plist has a feed and key, and never in test mode. It checks
  daily, verifies the EdDSA signature and Apple's signature, and installs on restart; Settings ▸ About and
  Ikago ▸ Check for Updates… control it. System profiling stays off.
- Release builds set `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction`: the feed itself is signed with the
  update key (`sign_update` on appcast.xml), so a tampered feed or an unsigned download is refused. Release notes
  travel inside the signed feed (`<description sparkle:format="markdown">`), never as a link to a web page.
- Ikago draws its own update UI (`AppUpdateDriver`, an `SPUUserDriver`): `UpdateCard` at the top right of the active
  window says what the update is (`UpdateSummary.kind`: a security update with its Chromium from `<ikago:chromium>`,
  new features from BUILDS.md, or both), then Update and Relaunch or Later; security updates
  (`<sparkle:criticalUpdate>`) have no Skip. The same card shows the download, the install and manual checks.
  `updatecard:security|features` (test action) shows a sample.
- Sparkle is pinned in `CEF/sparkle-lock.json` and fetched by `scripts/fetch_sparkle.py` into `.sparkle/`. Its XPC
  services are removed (Ikago isn't sandboxed); `Autoupdate` and `Updater.app` are signed before the framework.
- Chromium security updates ship as ordinary Ikago releases: update `CEF/cef-lock.json`, run the checks, release.

## Automatic Chromium releases (GitHub Actions)
- `.github/workflows/chromium-release.yml` runs daily. A cheap Linux job (`release_chromium.py --check`) compares the
  last release tag's `cef-lock.json` with the CEF index; only when it is behind does the release job run, on GitHub's `xcode-27` image with Xcode 27.2 selected (the
  same build as local releases; Xcode 26.6's Swift 6.3 crashes compiling Ikago). Move both together when upgrading Xcode.
- `release_chromium.py` starts from the last release's tag in `out/chromium-release` (a worktree), never from main, so
  unfinished work can't ship. It copies the current release tooling from main (`TOOLING`) over the tag's, pins the latest
  stable CEF (`chromium_lock.py`: size and SHA-1 from the index, SHA-256 recorded), builds and runs the Chromium checks
  (one retry), then calls `release.py --security --tag-only` with the next patch version and a build number above both
  the tag's and main's. Publishing pushes only the tag; then main gets the same Chromium (unless it has a newer one),
  `release.json` and a BUILDS.md entry under Unreleased, committed by github-actions[bot].
- Secrets live only in the `release` environment, which only `main` may deploy from: `DEVELOPER_ID_P12` (base64) and
  `DEVELOPER_ID_P12_PASSWORD`, `NOTARY_API_KEY` (the .p8 text), `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER`, and
  `SPARKLE_UPDATE_KEY` (the exported key). The job imports the certificate into a throwaway keychain and writes the keys
  to the runner's temp folder, removing all of them at the end; `release.py` checks that the update key matches
  `updatePublicKey` before signing (`update_public_key.swift`). Workflow permissions default to none; the only action is
  `actions/checkout`, pinned to a commit.
- A failed release opens one issue ("Automatic Chromium release failed"). `workflow_dispatch` with `trial` builds,
  tests, notarizes and signs but publishes nothing.
- Feature releases from a Mac refuse to publish while a newer stable Chromium is out (`--allow-older-chromium` skips
  it), so a feature release never takes users back to an older Chromium.

## Testing beside a downloaded copy
- `scripts/install_test.sh` installs `/Applications/Ikago Test.app` (`IKAGO_TEST_BUILD=1`: name "Ikago Test",
  `IkagoTestBuild` in Info.plist, `AppIdentity.isTestBuild`) and never touches `/Applications/Ikago.app`. It keeps the
  app ID and Developer ID signature, so it opens the same protected data and Keychain items without prompts; it
  refuses to install with any other signature. Build 0 keeps Launch Services choosing the real Ikago for links.
- The two share data, so only one may run: `ensureOnlyCopy` (main.swift) stops a second copy before it opens anything.
  Ikago Test never updates itself (no feed, no Chromium rebuilds); run the script again.
- `install.sh` refuses to replace a downloaded release (Info.plist has `SUFeedURL`) unless `IKAGO_REPLACE_RELEASE=1`,
  and the Chromium rebuild job (`auto_update.py`) does nothing while one is installed; `--remove-agent` turns it off.

## Credits
`package_app.py` copies the required notices into `Contents/Resources/Acknowledgements` (Ikago's license, the
third-party notices, Chromium's generated credits, CEF's license, SVT-AV1's license and patent license, Sparkle's
license); Settings ▸ About ▸ Acknowledgements opens each in a tab. A missing notice stops the build.
