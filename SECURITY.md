# Security

Ikago is pre-release software. No version carries a security-support guarantee yet, and the
project has not had an independent security audit.

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub's
[private vulnerability reporting](../../security/advisories/new) for this repository. Do not
open a public issue. Include the affected version or commit, steps to reproduce, and the
impact you observed. Never include real credentials, cookies or personal data in a report.

You should receive an acknowledgement within a few days. Fixes are released before
details are made public.

## Security model

**Engines.** WebKit pages run in WebKit's sandboxed web-content processes, and engine fixes
ship with macOS updates. Chromium pages run in Chromium's sandboxed helper processes. Ikago
pins a specific CEF release and updates it through a separate pipeline: download, verify the
checksum, build, run the full check suite, require a valid signature, and install only while
Ikago is closed. Certificate validation is never disabled or bypassed.

**Permissions fail closed.** Camera, microphone and file downloads are denied unless you
allow them for the requesting site. A request that is dropped, for example because its tab
closed, is denied. WebKit's popup blocker stays on, and only user-initiated popups open, as tabs.

**Isolated scripts.** Scripts that Ikago runs inside pages use an isolated content world that
pages can neither see nor modify.

**Network.** HTTPS is required by default, with exceptions only for sites you choose. Tracker
blocking runs as native content rules. Third-party cookies are blocked and third-party
storage is partitioned on both engines.

**Phishing warnings.** Ikago detects look-alike addresses and checks public phishing lists.
The lists are downloaded and matched on this Mac, so the addresses you visit are never sent
anywhere. This is not a live verdict service, and a brand-new site can slip through.
Chromium's live Safe Browsing service is not enabled, because it needs an API key.

**Data at rest.** History, sessions, download history and favicons are encrypted with
AES-GCM. The key is kept in the login Keychain. A team-signed build keeps all browsing data in
an app group container that macOS denies to apps from other developers.

**Passwords.** Ikago's vault encrypts each password to a Secure Enclave key, and every fill
needs Touch ID or the Mac password. Site names and usernames are sealed too. A login is
filled only when you click the key in a sign-in field. Pages can't trigger a fill.

**Extensions.** Chrome Web Store packages must be valid CRX3 files, signed with the
extension's own key and the Web Store's publisher key, before they are unpacked. A
permission review appears before install, and again when an update asks for more access.
A failed update keeps the working copy.

**Downloads.** Files are saved, never opened or executed automatically, and carry the macOS
quarantine flag. Each site asks before it saves files.

**Private windows** keep favicons in memory and leave downloads out of the saved history.

## Test isolation

Debug-only test mode (`IKAGO_TEST_MODE`) uses in-memory website data and a temporary session
folder. The Chromium checks use disposable profiles, a mock keychain and fake capture
devices. Neither is compiled into release builds, and neither reads your real data.
