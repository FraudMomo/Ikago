# Releasing Ikago

A maintainer's guide to how Ikago reaches people: what is set up, what runs by itself, and what to do by hand. The
technical detail behind each step is in [agents/distribution.md](agents/distribution.md).

## How an update reaches people

1. A release is published on GitHub Releases with two files: the notarized `Ikago-X.Y.Z.dmg` and a signed
   `appcast.xml` (the update feed).
2. Every installed copy reads `releases/latest/download/appcast.xml` once a day, and whenever someone picks
   Ikago ▸ Check for Updates….
3. Before installing, the app checks that the feed and the DMG are signed with the update key and by the Developer ID.
   Anything unsigned or tampered with is refused.
4. The update card at the top right of the window says what the update is (a security update with its Chromium
   version, new features, or both) and offers Update and Relaunch or Later. Security updates can't be skipped.

So a release only reaches people when it is marked **Latest** and is not a pre-release.

## Two kinds of release

### Chromium security releases: automatic

GitHub Actions does these without anyone's help (`.github/workflows/chromium-release.yml`).

- Every day at 06:23 UTC, a quick check compares the last release's Chromium with the latest stable CEF.
- If it is behind, a macOS runner takes the last release's tag (never `main`, so unfinished work can't ship), updates
  Chromium, builds, and runs the Chromium checks.
- It then notarizes and signs, and publishes the next patch version (for example 0.4.1 → 0.4.2) as a security update.
- `main` afterwards gets the new Chromium, version and BUILDS.md entry in a commit by `github-actions[bot]`. Pull before
  you start new work.
- If anything fails, nothing is published and an issue titled "Automatic Chromium release failed" opens with a link to
  the run.

To try the whole pipeline without publishing: Actions ▸ Chromium release ▸ Run workflow, with **trial** ticked (the
default).

### Feature releases: by hand, from the Mac

1. While working, add each change people will notice under `## Unreleased` in [BUILDS.md](../BUILDS.md), one bullet
   per change.
2. Check that the Mac is ready:

   ```bash
   python3 scripts/release.py --check
   ```

3. Optionally, build and notarize without publishing to look at the result in `out/release`:

   ```bash
   python3 scripts/release.py --version 0.5.0
   ```

4. Publish:

   ```bash
   python3 scripts/release.py --version 0.5.0 --publish
   ```

   This builds, notarizes, signs, moves the Unreleased notes under the new version, commits, tags `v0.5.0`, pushes,
   and creates the GitHub release.

A feature release refuses to publish while a newer stable Chromium is out, so it never takes people back to an older
Chromium. Update Chromium first (`python3 scripts/chromium_lock.py --bump`, then build and run the Chromium checks).

Version numbers: features bump the minor version (0.4 → 0.5), Chromium releases bump the patch. The build number in
`scripts/release.json` only ever goes up; Sparkle compares it, not the version.

## What is set up

### On the releasing Mac (login keychain)

- **Developer ID Application** certificate.
- Notarization credentials saved as the `ikago-notary` profile (`xcrun notarytool store-credentials`).
- The **update signing key** (EdDSA). Keep a backup somewhere safe and offline
  (`release.py --export-update-key FILE`). Losing it means installed copies can't verify new updates, and anyone
  holding it can sign them.

### On GitHub

All secrets live in the `release` environment, which only the `main` branch may use:

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_P12` | The Developer ID certificate and private key, exported as .p12, base64 |
| `DEVELOPER_ID_P12_PASSWORD` | The password chosen when exporting the .p12 |
| `NOTARY_API_KEY` | An App Store Connect API key (.p8 text, Developer role) for notarization |
| `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER` | That key's ID and issuer ID |
| `SPARKLE_UPDATE_KEY` | The exported update signing key |

Repository protection:

- **Rulesets:** "Protect main" blocks deleting `main` and force-pushes to it. "Protect release tags" stops `v*` tags
  from being deleted or moved, so a published version can't be swapped out.
- **Actions:** only GitHub's own actions are allowed, each pinned to a commit. Workflows start with no permissions.
  Workflows from outside contributors' pull requests wait for approval.
- **Secret scanning** and **push protection** are on. `.gitignore` keeps `*.p12`, `*.p8` and key files out of commits.

### Keeping secrets out of the repository

Never commit or paste a certificate, key, password or API key anywhere. Export files to the Desktop, upload them with
`gh secret set`, then delete them. The workflow writes keys only to the runner's temporary folder and removes them,
and the temporary signing keychain, when the job ends.

## Replacing a secret

Run from the repository folder, with `gh` signed in. Each command reads the value from a file or a hidden prompt, so it
never appears in the shell history.

- **Certificate expired or replaced:** export the new Developer ID Application certificate with its private key from
  Keychain Access as `.p12`, then:

  ```bash
  base64 -i ~/Desktop/ikago-id.p12 | gh secret set DEVELOPER_ID_P12 --env release
  ```

  ```bash
  gh secret set DEVELOPER_ID_P12_PASSWORD --env release
  ```

  Then delete the .p12 and run a trial.
- **Notary key revoked:** create a new key in App Store Connect ▸ Users and Access ▸ Integrations (Developer role), then:

  ```bash
  gh secret set NOTARY_API_KEY --env release < ~/Downloads/AuthKey_XXXX.p8
  ```

  Update `NOTARY_API_KEY_ID` the same way, then delete the .p8.
- **Update key:** never replace it. Installed copies only trust the public key they shipped with.

## When something goes wrong

- **The automatic release failed:** open the issue's run link. Signing or notarization errors usually mean an expired
  certificate or a revoked key (see above). Chromium check failures mean the new CEF broke something; fix it on
  `main`, then run the workflow again (untick **trial** to publish).
- **A bad release went out:** publish a fixed one with a higher version. Don't delete or move a tag. Deleting a GitHub
  release removes its page and DMG, but copies that already installed it keep it.
- **Updates download but won't install** ("Update Error!", "An error occurred while starting the installer"): read
  the log (below) for `Autoupdate`. Sparkle's installer is a separate process, so macOS rules about which processes
  may touch Ikago's folders apply to it, not to Ikago. Once fixed, raise `firstSelfUpdatingBuild` in
  `scripts/release.json` to the fixed build: the feed then shows older copies "needs a new download" instead of an
  install that fails. Put a download link first in the release notes, because copies from before 0.5.1 can only
  show the notes; their card can't open the page.
- **Every change to updates needs a real update:** checks can't reproduce what macOS allows the installer. Keep your
  own `/Applications/Ikago.app` on the published releases, and after publishing, let it update itself
  (Ikago ▸ Check for Updates…). If it fails, delete the release before anyone else gets it.
- **People can't install an update:** check the feed at
  `https://github.com/FraudMomo/Ikago/releases/latest/download/appcast.xml`, and the app's log
  (`/usr/bin/log show --last 10m --predicate 'process CONTAINS "Ikago" OR process CONTAINS "Autoupdate"'`).

## Testing beside your own copy

`scripts/install_test.sh` installs `/Applications/Ikago Test.app` next to the downloaded Ikago and never touches it.
It uses the same data and passwords, so only one of the two can be open at a time. Ikago Test never updates itself;
run the script again after changes. Your own `/Applications/Ikago.app` then updates like everyone else's.
