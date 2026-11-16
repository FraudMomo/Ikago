#!/usr/bin/env python3
"""The pinned Chromium (CEF/cef-lock.json): which stable CEF is newest, and moving the pin to it.

  python3 scripts/chromium_lock.py            pinned and latest stable, as JSON
  python3 scripts/chromium_lock.py --bump     download and verify the latest stable, then pin it

The archive is checked against the size and SHA-1 the CEF index publishes; its SHA-256 goes into the lock, and
fetch_cef.py checks all three on every later download.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
LOCK = 'CEF/cef-lock.json'
SWIFT = 'Ikago/Engine/Shared/BrowserEngine.swift'


def version_key(entry):
    """Chromium version first, then CEF's own build, since CEF can ship fixes on the same Chromium."""
    cef = re.match(r'[\d.]+', entry['cef_version']).group(0)
    return tuple(int(part) for part in entry['chromium_version'].split('.')), tuple(int(part) for part in cef.split('.'))


def read_lock(root=ROOT):
    return json.loads((Path(root)/LOCK).read_text())


def latest_release(lock):
    with urllib.request.urlopen(lock['index'], timeout=60) as response:
        index = json.load(response)
    versions = [v for v in index[lock['platform']]['versions'] if v.get('channel') == lock['channel']]
    return max(versions, key=version_key)


def is_behind(lock, release):
    return version_key(release) > version_key(lock)


def new_lock(lock, release):
    file = next(f for f in release['files'] if f['type'] == lock.get('distribution', 'minimal'))
    return lock | {'cef_version': release['cef_version'], 'cef_commit': release.get('cef_commit', ''),
                   'chromium_version': release['chromium_version'], 'archive': file['name'],
                   'size': file['size'], 'sha1': file['sha1'], 'sha256': ''}


def download(lock, destination):
    """Verifies the size and SHA-1 the index publishes, and records a SHA-256 for the lock."""
    url = 'https://cef-builds.spotifycdn.com/' + urllib.parse.quote(lock['archive'])
    sha1, sha256, size = hashlib.sha1(), hashlib.sha256(), 0
    Path(destination).parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url, timeout=120) as source, Path(destination).open('wb') as output:
        while chunk := source.read(1024*1024):
            size += len(chunk)
            if size > lock['size']:
                raise RuntimeError('The CEF download is larger than published.')
            sha1.update(chunk)
            sha256.update(chunk)
            output.write(chunk)
    if size != lock['size'] or sha1.hexdigest() != lock['sha1']:
        raise RuntimeError('The CEF download failed verification.')
    lock['sha256'] = sha256.hexdigest()


def apply_version(root, lock):
    """The two source files that name the pinned release."""
    root = Path(root)
    (root/LOCK).write_text(json.dumps(lock, indent=2) + '\n')
    swift = root/SWIFT
    text, count = re.subn(r'(static let chromium = ")[\d.]+(")', rf'\g<1>{lock["chromium_version"]}\g<2>', swift.read_text())
    if count != 1:
        raise RuntimeError('Could not find the Chromium version constant.')
    swift.write_text(text)


def bump(root=ROOT):
    """Pins the latest stable release, downloaded into .cef/ and verified. Returns the new lock, or None if current."""
    lock = read_lock(root)
    release = latest_release(lock)
    if not is_behind(lock, release):
        return None
    target = new_lock(lock, release)
    download(target, Path(root)/'.cef'/target['archive'])
    apply_version(root, target)
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--bump', action='store_true', help='Pin the latest stable release')
    args = parser.parse_args()
    if args.bump:
        target = bump()
        print(f'Pinned Chromium {target["chromium_version"]}.' if target else 'Already on the latest stable Chromium.')
        return
    lock = read_lock()
    release = latest_release(lock)
    json.dump({'pinned': lock['chromium_version'], 'latest': release['chromium_version'],
               'behind': is_behind(lock, release)}, sys.stdout)
    print()


if __name__ == '__main__':
    main()
