#!/usr/bin/env python3
"""Fetch the pinned Sparkle release: the update framework bundled into Ikago, and its command-line tools
(generate_keys, sign_update) that release builds use. Nothing is compiled."""
import hashlib
import json
from pathlib import Path
import shutil
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
MAX_BYTES = 64 * 1024 * 1024
TARGET = ROOT/'.sparkle/Sparkle'


def fetch():
    lock = json.loads((ROOT/'CEF/sparkle-lock.json').read_text())
    cache = ROOT/'.sparkle'
    cache.mkdir(exist_ok=True)
    marker = TARGET/'.ikago-version'
    if marker.exists() and marker.read_text() == lock['sha256']:
        print(f'Pinned Sparkle {lock["version"]} already present: {TARGET}')
        return
    with tempfile.TemporaryDirectory(prefix='fetch-', dir=cache) as temporary:
        stage = Path(temporary)
        archive = stage/'sparkle.tar.xz'
        digest, size = hashlib.sha256(), 0
        with urllib.request.urlopen(lock['url'], timeout=60) as source, archive.open('wb') as output:
            while chunk := source.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_BYTES:
                    raise SystemExit('Sparkle download is larger than expected.')
                digest.update(chunk)
                output.write(chunk)
        if digest.hexdigest() != lock['sha256']:
            raise SystemExit('Sparkle download does not match the pinned checksum.')
        unpacked = stage/'unpacked'
        with tarfile.open(archive) as tar:
            tar.extractall(unpacked, filter='data')  # refuses links and paths outside the folder
        if not (unpacked/'Sparkle.framework').is_dir() or not (unpacked/'bin/sign_update').exists():
            raise SystemExit('Unexpected Sparkle archive layout.')
        (unpacked/'.ikago-version').write_text(lock['sha256'])
        shutil.rmtree(TARGET, ignore_errors=True)
        shutil.move(str(unpacked), TARGET)
    print(f'Fetched Sparkle {lock["version"]} into {TARGET}')


if __name__ == '__main__':
    fetch()
