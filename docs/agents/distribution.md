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
5. With `--publish`: commits the version, tags `vX.Y.Z`, pushes, and creates the GitHub release with the DMG and
   `appcast.xml`. The feed URL is `releases/latest/download/appcast.xml`, so a release must be marked latest (never a
   pre-release) for installed copies to see it.

## Updates in the app
- `AppUpdates` (Sparkle's standard updater) runs only when Info.plist has a feed and key, and never in test mode. It
  checks daily, verifies the EdDSA signature and Apple's signature, and installs on restart; Settings ▸ About and
  Ikago ▸ Check for Updates… control it. System profiling stays off.
- Sparkle is pinned in `CEF/sparkle-lock.json` and fetched by `scripts/fetch_sparkle.py` into `.sparkle/`. Its XPC
  services are removed (Ikago isn't sandboxed); `Autoupdate` and `Updater.app` are signed before the framework.
- Chromium security updates ship as ordinary Ikago releases: update `CEF/cef-lock.json`, run the checks, release.

## Credits
`package_app.py` copies the required notices into `Contents/Resources/Acknowledgements` (Ikago's license, the
third-party notices, Chromium's generated credits, CEF's license, SVT-AV1's license and patent license, Sparkle's
license); Settings ▸ About ▸ Acknowledgements opens each in a tab. A missing notice stops the build.
