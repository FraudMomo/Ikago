#!/usr/bin/env python3
"""Report whether a newer SVT-AV1 release exists than the one pinned in CEF/svtav1-lock.json. Changes nothing.

The encoder only sees frames macOS has already decoded, never web content, so updates are deliberate: pin the new
version's .tar.bz2 with its SHA-256, cross-checked against an independent source such as Homebrew's formula."""
import json
from pathlib import Path
import shutil
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
RELEASES = 'https://gitlab.com/api/v4/projects/AOMediaCodec%2FSVT-AV1/releases?per_page=5'


def main():
    pinned = json.loads((ROOT/'CEF/svtav1-lock.json').read_text())['version']
    with urllib.request.urlopen(RELEASES, timeout=30) as response:
        releases = json.load(response)
    latest = max((r['tag_name'].lstrip('v') for r in releases), key=lambda v: tuple(int(p) for p in v.split('.') if p.isdigit()))
    print(f'Pinned: SVT-AV1 {pinned}\nLatest release: SVT-AV1 {latest}')
    if latest == pinned:
        print('Up to date.')
        return
    url = f'https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v{latest}/SVT-AV1-v{latest}.tar.bz2'
    print(f'Newer release available: {url}')
    if shutil.which('brew'):
        info = subprocess.run(['brew', 'info', '--json=v2', 'svt-av1'], capture_output=True, text=True)
        try:
            formula = json.loads(info.stdout)['formulae'][0]
            stable = formula['urls']['stable']
            if stable['url'] == url:
                print(f'Homebrew publishes SHA-256 {stable["checksum"]} for it: pin that once your own download matches.')
            else:
                print(f'Homebrew is at {formula["versions"]["stable"]}; wait for it or another independent checksum before pinning.')
        except (ValueError, KeyError, IndexError):
            print('Homebrew had no usable checksum; find another independent one before pinning.')


if __name__ == '__main__':
    main()
