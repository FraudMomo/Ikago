#!/usr/bin/env python3
"""Make a public Ikago release: build, sign with Developer ID, notarize, package a DMG, sign the update feed, and
(with --publish) tag it and upload it to GitHub Releases, where every installed copy finds it through Sparkle.

  python3 scripts/release.py --check                 what's missing before a first release
  python3 scripts/release.py --version 0.3.0         build and notarize into out/release, nothing published
  python3 scripts/release.py --version 0.3.0 --publish      notes from BUILDS.md's Unreleased section
  python3 scripts/release.py --version 0.3.0 --publish --notes notes.md
  python3 scripts/release.py --export-update-key FILE / --import-update-key FILE   move the update key between Macs

Needs, once per Mac: a "Developer ID Application" certificate, notarization credentials saved with
`xcrun notarytool store-credentials ikago-notary`, and the update signing key in the login keychain. On GitHub
Actions (`release_chromium.py`) the same come from the environment: IKAGO_NOTARY_KEY (an App Store Connect API key
file) with IKAGO_NOTARY_KEY_ID and IKAGO_NOTARY_ISSUER, and IKAGO_UPDATE_KEY_FILE (the exported update key).

A feature release refuses to publish while a newer stable Chromium is out: users would otherwise get an older
Chromium than the automatic security releases gave them. Update it first (`chromium_lock.py --bump`).
"""
import argparse
import datetime
import email.utils
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from xml.sax.saxutils import escape, quoteattr

ROOT = Path(__file__).resolve().parents[1]
CONFIG_FILE = ROOT/'scripts/release.json'
BUILDS = ROOT/'BUILDS.md'
UNRELEASED = '## Unreleased'
CONFIG = json.loads(CONFIG_FILE.read_text())
SPARKLE_BIN = ROOT/'.sparkle/Sparkle/bin'
NOTARY_KEY = os.environ.get('IKAGO_NOTARY_KEY')
UPDATE_KEY_FILE = os.environ.get('IKAGO_UPDATE_KEY_FILE')
sys.path.insert(0, str(ROOT/'scripts'))
import chromium_lock  # noqa: E402
OUT = ROOT/'out/release'
APP = ROOT/'build/Ikago.app'


def run(*command, capture=False, check=True, env=None):
    print('→', ' '.join(str(part) for part in command), flush=True)
    result = subprocess.run([str(part) for part in command], cwd=ROOT, text=True, env=env,
                            capture_output=capture, check=False)
    if check and result.returncode:
        raise SystemExit(f'Failed: {command[0]} {command[1] if len(command) > 1 else ""}\n{result.stderr or ""}')
    return result


def quiet(*command):
    return subprocess.run([str(part) for part in command], cwd=ROOT, text=True, capture_output=True)


# MARK: Credentials

def notary_auth():
    """An App Store Connect API key on GitHub Actions, the saved keychain profile on a Mac."""
    if NOTARY_KEY:
        return ['--key', NOTARY_KEY, '--key-id', os.environ['IKAGO_NOTARY_KEY_ID'], '--issuer', os.environ['IKAGO_NOTARY_ISSUER']]
    return ['--keychain-profile', CONFIG['notaryProfile']]


def update_key():
    """How sign_update finds the private update key: a file on GitHub Actions, the login keychain on a Mac."""
    return ['--ed-key-file', UPDATE_KEY_FILE] if UPDATE_KEY_FILE else ['--account', CONFIG['updateKeyAccount']]


def public_update_key():
    if UPDATE_KEY_FILE:
        return quiet('swift', ROOT/'scripts/update_public_key.swift', UPDATE_KEY_FILE).stdout.strip()
    return quiet(SPARKLE_BIN/'generate_keys', '--account', CONFIG['updateKeyAccount'], '-p').stdout.strip()


# MARK: Checks

def problems(publish, tag_only=False, older_chromium=False):
    found = []
    identities = quiet('security', 'find-identity', '-v', '-p', 'codesigning').stdout
    if 'Developer ID Application' not in identities:
        found.append('No "Developer ID Application" certificate. Create one at developer.apple.com ▸ Certificates '
                     '(or Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates), then double-click it to add it to your keychain.')
    if quiet('xcrun', 'notarytool', 'history', *notary_auth()).returncode:
        found.append(f'No notarization credentials. Run: xcrun notarytool store-credentials {CONFIG["notaryProfile"]} '
                     '--apple-id <your Apple ID> --team-id <your team ID>  (it asks for an app-specific password '
                     'from account.apple.com ▸ Sign-In and Security).')
    if not (SPARKLE_BIN/'sign_update').exists():
        run(sys.executable, ROOT/'scripts/fetch_sparkle.py')
    if public_update_key() != CONFIG['updatePublicKey']:
        found.append('The update signing key in your keychain is missing or differs from scripts/release.json. '
                     'Import your backup with --import-update-key FILE.')
    if publish and not tag_only:
        if quiet('git', 'status', '--porcelain').stdout.strip():
            found.append('There are uncommitted changes. Commit or stash them first.')
        if quiet('git', 'rev-parse', '--abbrev-ref', 'HEAD').stdout.strip() != 'main':
            found.append('Releases are made from the main branch.')
        lock = chromium_lock.read_lock()
        latest = chromium_lock.latest_release(lock)
        if chromium_lock.is_behind(lock, latest) and not older_chromium:
            found.append(f'Chromium {latest["chromium_version"]} is out and this build has {lock["chromium_version"]}. '
                         'Update it first: python3 scripts/chromium_lock.py --bump, run the Chromium checks, and commit. '
                         '(--allow-older-chromium skips this.)')
    if publish:
        if quiet('gh', 'auth', 'status').returncode:
            found.append('The GitHub CLI isn\'t signed in. Run: gh auth login')
    return found


# MARK: Notes

def unreleased():
    """The changes listed under Unreleased in BUILDS.md."""
    text = BUILDS.read_text()
    if UNRELEASED not in text:
        return ''
    section = text.split(UNRELEASED, 1)[1]
    return section.split('\n## ', 1)[0].strip()


def write_notes(version):
    changes = unreleased()
    if not changes:
        raise SystemExit('BUILDS.md lists no changes under "## Unreleased"; add them, or pass --notes FILE.')
    notes = OUT/'notes.md'
    notes.write_text(f'''{changes}

**Requires macOS 26 or later on Apple silicon.** Installed copies update themselves (Ikago ▸ Check for Updates…).
New here? Open the DMG and drag Ikago to Applications.
''')
    print(f'Release notes for {version} from BUILDS.md: {notes}')
    return notes


def file_unreleased(version):
    """Moves Unreleased under the new version's heading and leaves an empty Unreleased above it."""
    text = BUILDS.read_text()
    if UNRELEASED not in text:
        return
    heading = f'## {version} — {datetime.date.today().isoformat()}'
    BUILDS.write_text(text.replace(UNRELEASED + '\n', f'{UNRELEASED}\n\n{heading}\n', 1))


# MARK: Steps

def notarize(path):
    """Submits to Apple's notary service and waits; on rejection prints Apple's log of what failed."""
    result = run('xcrun', 'notarytool', 'submit', path, *notary_auth(),
                 '--wait', '--output-format', 'json', capture=True, check=False)
    info = json.loads(result.stdout or '{}')
    if info.get('status') != 'Accepted':
        if submission := info.get('id'):
            print(quiet('xcrun', 'notarytool', 'log', submission, *notary_auth()).stdout)
        raise SystemExit(f'Notarization was not accepted: {info.get("status") or result.stderr}')
    print(f'Notarized {Path(path).name}', flush=True)


def verify_app():
    run('codesign', '--verify', '--deep', '--strict', '--verbose=2', APP)
    details = quiet('codesign', '-dv', '--verbose=4', APP).stderr
    if 'Authority=Developer ID Application' not in details or 'Timestamp=' not in details:
        raise SystemExit('The app is not signed with Developer ID and a secure timestamp.')
    entitlements = quiet('codesign', '-d', '--entitlements', '-', '--xml', APP).stdout
    if 'get-task-allow' in entitlements:
        raise SystemExit('The app allows debugging (get-task-allow); notarization would reject it.')


def make_dmg(version):
    stage = OUT/'dmg'
    shutil.rmtree(stage, ignore_errors=True)
    stage.mkdir(parents=True)
    run('ditto', APP, stage/'Ikago.app')
    (stage/'Applications').symlink_to('/Applications')
    dmg = OUT/f'Ikago-{version}.dmg'
    dmg.unlink(missing_ok=True)
    run('diskutil', 'image', 'create', 'from', '--format', 'ULFO', '--volumeName', f'Ikago {version}', stage, dmg)
    shutil.rmtree(stage)
    run('codesign', '--force', '--timestamp', '--sign', 'Developer ID Application', dmg)
    return dmg


def one_line_bullets(text):
    """BUILDS.md wraps long bullets; the feed carries each bullet on one line, since the update card in 0.4.0 reads
    every line as a bullet of its own."""
    lines = []
    for line in text.splitlines():
        if line.strip() and lines and not line.lstrip().startswith('- ') and line.startswith((' ', '\t')):
            lines[-1] += ' ' + line.strip()
        else:
            lines.append(line.rstrip())
    return '\n'.join(lines)


def write_appcast(dmg, version, build, changes, security=False):
    """The feed: this release, its changes as Markdown (Ikago's update card shows them), whether it is a security
    update (Sparkle's critical update), and the Chromium it carries. The whole feed is signed with the update key, and
    copies from 0.3.1 on accept only a signed feed (SURequireSignedFeed)."""
    signed = run(SPARKLE_BIN/'sign_update', *update_key(), dmg, capture=True).stdout
    signature = re.search(r'sparkle:edSignature="([^"]+)"', signed)
    length = re.search(r'length="(\d+)"', signed)
    if not signature or not length:
        raise SystemExit(f'sign_update gave no signature: {signed}')
    repo, tag = CONFIG['repository'], f'v{version}'
    url = f'https://github.com/{repo}/releases/download/{tag}/{dmg.name}'
    critical = '\n      <sparkle:criticalUpdate></sparkle:criticalUpdate>' if security else ''
    # Copies before `firstSelfUpdatingBuild` (0.4.1) can't install updates themselves (their Sparkle folder is
    # quarantined), so they get an information-only update: Sparkle's window links to the release page to download it.
    oldest = CONFIG.get('firstSelfUpdatingBuild')
    information_only = (f'\n      <sparkle:informationalUpdate><sparkle:belowVersion>{oldest}</sparkle:belowVersion>'
                        '</sparkle:informationalUpdate>') if oldest else ''
    appcast = f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:ikago="https://ikago.app/xml/updates">
  <channel>
    <title>Ikago</title>
    <link>https://github.com/{repo}</link>
    <item>
      <title>{escape(f"Ikago {version}")}</title>
      <pubDate>{email.utils.formatdate(time.time())}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <link>https://github.com/{repo}/releases/tag/{tag}</link>{information_only}
      <description sparkle:format="markdown"><![CDATA[{one_line_bullets(changes).replace("]]>", "]] >")}]]></description>
      <ikago:chromium>{escape(chromium_lock.read_lock()["chromium_version"])}</ikago:chromium>{critical}
      <enclosure url={quoteattr(url)} type="application/octet-stream" sparkle:edSignature={quoteattr(signature.group(1))} length="{length.group(1)}"/>
    </item>
  </channel>
</rss>
'''
    path = OUT/'appcast.xml'
    path.write_text(appcast)
    run(SPARKLE_BIN/'sign_update', *update_key(), path)  # embeds the feed's signature
    return path


def publish(version, dmg, appcast, notes, tag_only=False):
    """From main: commits the version and BUILDS.md and pushes main with the tag. With `tag_only` (a Chromium release
    built on the last release's tag): commits every tracked change there and pushes only the tag;
    `release_chromium.py` brings main up to date."""
    tag = f'v{version}'
    if tag_only:
        run('git', 'add', '-A')
    else:
        file_unreleased(version)
        run('git', 'add', CONFIG_FILE, BUILDS)
    run('git', 'commit', '-m', f'chore(release): {version}')
    run('git', 'tag', '-a', tag, '-m', f'Ikago {version}')
    run('git', 'push', 'origin', tag) if tag_only else run('git', 'push', 'origin', 'main', tag)
    notes_args = ['--notes-file', notes] if notes else ['--generate-notes']
    run('gh', 'release', 'create', tag, dmg, appcast, '--repo', CONFIG['repository'], '--title', f'Ikago {version}',
        '--latest', *notes_args)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--version', help='The new version, such as 0.3.0 (the build number goes up by one)')
    parser.add_argument('--publish', action='store_true', help='Commit the version, tag, push and create the GitHub release')
    parser.add_argument('--notes', help='A Markdown file with the release notes (otherwise the Unreleased section of BUILDS.md)')
    parser.add_argument('--check', action='store_true', help='Only list what is missing')
    parser.add_argument('--security', action='store_true', help='Mark it a security update (Chromium releases)')
    parser.add_argument('--build', type=int, help='The build number (otherwise one more than release.json)')
    parser.add_argument('--tag-only', action='store_true', help=argparse.SUPPRESS)  # release_chromium.py
    parser.add_argument('--allow-older-chromium', action='store_true', help='Publish although a newer Chromium is out')
    parser.add_argument('--export-update-key', metavar='FILE', help='Write the update signing key to FILE for a backup')
    parser.add_argument('--import-update-key', metavar='FILE', help='Add the update signing key from FILE to this Mac')
    args = parser.parse_args()
    account = CONFIG['updateKeyAccount']
    if args.export_update_key:
        run(SPARKLE_BIN/'generate_keys', '--account', account, '-x', args.export_update_key)
        os.chmod(args.export_update_key, 0o600)
        print('Keep this file somewhere safe and private (a password manager or an encrypted drive), then delete it here.')
        return
    if args.import_update_key:
        run(SPARKLE_BIN/'generate_keys', '--account', account, '-f', args.import_update_key)
        return
    missing = problems(args.publish, args.tag_only, args.allow_older_chromium)
    if args.check or missing:
        for item in missing:
            print('•', item)
        if missing:
            raise SystemExit(1)
        print('Ready to release.')
        return
    if not args.version or not re.fullmatch(r'\d+\.\d+\.\d+', args.version):
        raise SystemExit('Give the new version as --version X.Y.Z')
    if not args.notes and not unreleased():
        raise SystemExit('BUILDS.md lists no changes under "## Unreleased"; add them, or pass --notes FILE.')

    original = CONFIG_FILE.read_text()
    CONFIG.update(version=args.version, build=args.build or int(CONFIG['build']) + 1)
    CONFIG_FILE.write_text(json.dumps(CONFIG, indent=2) + '\n')
    try:
        env = dict(os.environ, IKAGO_DISTRIBUTION='1')
        run(sys.executable, ROOT/'scripts/build.py', '--flavor', 'release', '--jobs', os.environ.get('IKAGO_BUILD_JOBS', '4'), env=env)
        verify_app()
        OUT.mkdir(parents=True, exist_ok=True)
        archive = OUT/'Ikago.zip'
        archive.unlink(missing_ok=True)
        run('ditto', '-c', '-k', '--keepParent', APP, archive)
        notarize(archive)
        archive.unlink()
        run('xcrun', 'stapler', 'staple', APP)
        dmg = make_dmg(args.version)
        notarize(dmg)
        run('xcrun', 'stapler', 'staple', dmg)
        run('spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose', dmg)
        changes = Path(args.notes).read_text().strip() if args.notes else unreleased()
        appcast = write_appcast(dmg, args.version, CONFIG['build'], changes, args.security)
        notes = args.notes or write_notes(args.version)
    except BaseException:
        CONFIG_FILE.write_text(original)  # a failed release leaves the version as it was
        raise
    print(f'\nReady: {dmg}\n       {appcast}')
    if args.publish:
        publish(args.version, dmg, appcast, notes, args.tag_only)
        print(f'Published Ikago {args.version}: https://github.com/{CONFIG["repository"]}/releases/tag/v{args.version}')
    else:
        CONFIG_FILE.write_text(original)  # a trial run doesn't use up the version
        print('Nothing was published. Run again with --publish to tag and upload it.')


if __name__ == '__main__':
    main()
