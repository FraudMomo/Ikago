#!/usr/bin/env python3
"""Make a public Ikago release: build, sign with Developer ID, notarize, package a DMG, sign the update feed, and
(with --publish) tag it and upload it to GitHub Releases, where every installed copy finds it through Sparkle.

  python3 scripts/release.py --check                 what's missing before a first release
  python3 scripts/release.py --version 0.3.0         build and notarize into out/release, nothing published
  python3 scripts/release.py --version 0.3.0 --publish --notes notes.md
  python3 scripts/release.py --export-update-key FILE / --import-update-key FILE   move the update key between Macs

Needs, once per Mac: a "Developer ID Application" certificate, notarization credentials saved with
`xcrun notarytool store-credentials ikago-notary`, and the update signing key in the login keychain.
"""
import argparse
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
CONFIG = json.loads(CONFIG_FILE.read_text())
SPARKLE_BIN = ROOT/'.sparkle/Sparkle/bin'
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


# MARK: Checks

def problems(publish):
    found = []
    identities = quiet('security', 'find-identity', '-v', '-p', 'codesigning').stdout
    if 'Developer ID Application' not in identities:
        found.append('No "Developer ID Application" certificate. Create one at developer.apple.com ▸ Certificates '
                     '(or Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates), then double-click it to add it to your keychain.')
    if quiet('xcrun', 'notarytool', 'history', '--keychain-profile', CONFIG['notaryProfile']).returncode:
        found.append(f'No notarization credentials. Run: xcrun notarytool store-credentials {CONFIG["notaryProfile"]} '
                     '--apple-id <your Apple ID> --team-id <your team ID>  (it asks for an app-specific password '
                     'from account.apple.com ▸ Sign-In and Security).')
    if not (SPARKLE_BIN/'sign_update').exists():
        run(sys.executable, ROOT/'scripts/fetch_sparkle.py')
    key = quiet(SPARKLE_BIN/'generate_keys', '--account', CONFIG['updateKeyAccount'], '-p').stdout.strip()
    if key != CONFIG['updatePublicKey']:
        found.append('The update signing key in your keychain is missing or differs from scripts/release.json. '
                     'Import your backup with --import-update-key FILE.')
    if publish:
        if quiet('git', 'status', '--porcelain').stdout.strip():
            found.append('There are uncommitted changes. Commit or stash them first.')
        if quiet('git', 'rev-parse', '--abbrev-ref', 'HEAD').stdout.strip() != 'main':
            found.append('Releases are made from the main branch.')
        if quiet('gh', 'auth', 'status').returncode:
            found.append('The GitHub CLI isn\'t signed in. Run: gh auth login')
    return found


# MARK: Steps

def notarize(path):
    """Submits to Apple's notary service and waits; on rejection prints Apple's log of what failed."""
    result = run('xcrun', 'notarytool', 'submit', path, '--keychain-profile', CONFIG['notaryProfile'],
                 '--wait', '--output-format', 'json', capture=True, check=False)
    info = json.loads(result.stdout or '{}')
    if info.get('status') != 'Accepted':
        if submission := info.get('id'):
            print(quiet('xcrun', 'notarytool', 'log', submission, '--keychain-profile', CONFIG['notaryProfile']).stdout)
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


def write_appcast(dmg, version, build):
    signed = run(SPARKLE_BIN/'sign_update', '--account', CONFIG['updateKeyAccount'], dmg, capture=True).stdout
    signature = re.search(r'sparkle:edSignature="([^"]+)"', signed)
    length = re.search(r'length="(\d+)"', signed)
    if not signature or not length:
        raise SystemExit(f'sign_update gave no signature: {signed}')
    repo, tag = CONFIG['repository'], f'v{version}'
    url = f'https://github.com/{repo}/releases/download/{tag}/{dmg.name}'
    appcast = f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Ikago</title>
    <link>https://github.com/{repo}</link>
    <item>
      <title>{escape(f"Ikago {version}")}</title>
      <pubDate>{email.utils.formatdate(time.time())}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/{repo}/releases/tag/{tag}</sparkle:releaseNotesLink>
      <enclosure url={quoteattr(url)} type="application/octet-stream" sparkle:edSignature={quoteattr(signature.group(1))} length="{length.group(1)}"/>
    </item>
  </channel>
</rss>
'''
    path = OUT/'appcast.xml'
    path.write_text(appcast)
    return path


def publish(version, dmg, appcast, notes):
    tag = f'v{version}'
    run('git', 'add', CONFIG_FILE)
    run('git', 'commit', '-m', f'chore(release): {version}')
    run('git', 'tag', '-a', tag, '-m', f'Ikago {version}')
    run('git', 'push', 'origin', 'main', tag)
    notes_args = ['--notes-file', notes] if notes else ['--generate-notes']
    run('gh', 'release', 'create', tag, dmg, appcast, '--repo', CONFIG['repository'], '--title', f'Ikago {version}',
        '--latest', *notes_args)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--version', help='The new version, such as 0.3.0 (the build number goes up by one)')
    parser.add_argument('--publish', action='store_true', help='Commit the version, tag, push and create the GitHub release')
    parser.add_argument('--notes', help='A Markdown file with the release notes (otherwise GitHub writes them)')
    parser.add_argument('--check', action='store_true', help='Only list what is missing')
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
    missing = problems(args.publish)
    if args.check or missing:
        for item in missing:
            print('•', item)
        if missing:
            raise SystemExit(1)
        print('Ready to release.')
        return
    if not args.version or not re.fullmatch(r'\d+\.\d+\.\d+', args.version):
        raise SystemExit('Give the new version as --version X.Y.Z')

    original = CONFIG_FILE.read_text()
    CONFIG.update(version=args.version, build=int(CONFIG['build']) + 1)
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
        appcast = write_appcast(dmg, args.version, CONFIG['build'])
    except BaseException:
        CONFIG_FILE.write_text(original)  # a failed release leaves the version as it was
        raise
    print(f'\nReady: {dmg}\n       {appcast}')
    if args.publish:
        publish(args.version, dmg, appcast, args.notes)
        print(f'Published Ikago {args.version}: https://github.com/{CONFIG["repository"]}/releases/tag/v{args.version}')
    else:
        CONFIG_FILE.write_text(original)  # a trial run doesn't use up the version
        print('Nothing was published. Run again with --publish to tag and upload it.')


if __name__ == '__main__':
    main()
