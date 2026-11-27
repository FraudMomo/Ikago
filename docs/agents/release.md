# Releases, updates, test builds and crash reports

## How it's built

- **Feature releases** are made from the Mac by `scripts/release.py`:
  1. Bump `scripts/release.json`. The build number only goes up; Sparkle compares it, not the version.
  2. Build with Developer ID and the hardened runtime (`package_app.py`).
  3. Notarize and staple the app and the DMG.
  4. Sign the DMG and the appcast for Sparkle.
  5. With `--publish`: move `BUILDS.md` ▸ Unreleased under the version, commit, tag `vX.Y.Z`, push, and create the
     GitHub release.

  `--check` lists what the Mac is missing. Features bump the minor version, Chromium releases the patch.
- **Chromium security releases** are automatic (`.github/workflows/chromium-release.yml`, daily):
  - When the last release's CEF is behind, `release_chromium.py` starts from that release's tag, never `main`.
  - It pins the new CEF, builds, runs the Chromium checks and publishes the next patch.
  - Then `main` gets the same Chromium in a commit by github-actions[bot]. Pull before new work.
  - A failure opens one issue. A `trial` dispatch runs everything but publishing.
- **Updates in the app.** `AppUpdates` runs Sparkle only when Info.plist has a feed and key, never in test mode.
  - The feed is signed, and release notes travel inside it.
  - Ikago draws its own update UI (`AppUpdateDriver`, `UpdateCard`). Security updates can't be skipped.
  - Sparkle is pinned in `CEF/sparkle-lock.json`.
- **Secrets** are kept in two places:
  - On the Mac, in the login keychain: the Developer ID certificate, the `ikago-notary` profile and the EdDSA update
    key. Back the key up with `release.py --export-update-key`.
  - On GitHub, only in the `release` environment, which only `main` may use. Replace them with
    `gh secret set … --env release`, reading from a file or a prompt. Never replace the update key: installed copies
    trust only the one they shipped with.
- **Test builds.** `scripts/install_test.sh` installs `/Applications/Ikago Test.app` with the same signature and data
  as the real Ikago, never touching it. Only one of the two may run (`ensureOnlyCopy`). It never updates itself.
- **Crash reports** (`App/CrashReports.swift`) never send anything.
  - `Running.json` stays in the data folder while Ikago runs, and an `atexit` handler removes it.
  - If it's still there at the next launch, a card asks whether to report it (`CrashReportCard`).
    Only on yes does Ikago zip a summary, its `.ips` files and JetsamEvents (scrubbed of names) into Downloads and
    show it in Finder; the person sends it on. Not Now marks those reports handled.
  - Help ▸ Save Crash Report does the same for the last 7 days.
  - Symbolicate Ikago's frames with the matching binary in `out/symbols/`.
- **Credits.** Packaging copies every required license into `Acknowledgements`; a missing one stops the build.

## Traps

- **A release must be marked Latest, never a pre-release.** The feed URL is `releases/latest/download/appcast.xml`.
- **A feature release refuses to publish while a newer stable Chromium is out,** so people never go back to an older
  Chromium. Update CEF first.
- **Sparkle's installer may not write into the app group container.** `AppUpdates.prepareSparkleFolder()` links its
  folder outside. Copies before build 23 can't self-update, so the feed marks itself information-only for them
  (`firstSelfUpdatingBuild`).
- **Every change to updates needs a real update** from a published release; checks can't reproduce what macOS allows
  the installer.
- **A bad release is fixed by a higher version.** Never delete or move a tag.
- **Never commit or paste a certificate, key or password.**
- **macOS may write no `.ips` at all** (it throttles apps that crash often, and can kill ReportCrash when memory is
  short), so the crash summary must stand alone.
- **Packaging keeps only English CEF locale packs,** plus `en.lproj` as the fallback, ICU and the shared `.pak` files.
