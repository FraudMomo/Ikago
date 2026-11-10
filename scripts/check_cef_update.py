#!/usr/bin/env python3
"""Report whether a newer stable CEF is published than the one pinned in CEF/cef-lock.json."""
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def key(version):
    return tuple(int(part) for part in version.split('.'))


def main():
    lock = json.loads((ROOT/'CEF/cef-lock.json').read_text())
    with urllib.request.urlopen(lock['index'], timeout=60) as response:
        index = json.load(response)
    versions = [v for v in index[lock['platform']]['versions'] if v.get('channel') == lock['channel']]
    latest = max(versions, key=lambda v: key(v['chromium_version']))
    pinned, newest = lock['chromium_version'], latest['chromium_version']
    print(f'Pinned: Chromium {pinned}\nLatest {lock["channel"]}: Chromium {newest} ({latest["cef_version"]})')
    if key(newest) > key(pinned):
        print('A newer release is available. It may contain security fixes.')
        raise SystemExit(1)
    print('Up to date.')


if __name__ == '__main__':
    main()
