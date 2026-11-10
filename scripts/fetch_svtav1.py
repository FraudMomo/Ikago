#!/usr/bin/env python3
"""Fetch the pinned SVT-AV1 source (the AV1 encoder of the Chromium media translation layer). It is
compiled with the CEF bridge as a small static library; this never configures, compiles or runs anything."""
import hashlib
import json
from pathlib import Path
import shutil
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
MAX_BYTES = 64 * 1024 * 1024


def fetch():
    lock = json.loads((ROOT/'CEF/svtav1-lock.json').read_text())
    cache = ROOT/'.svtav1'
    cache.mkdir(exist_ok=True)
    target = cache/'source'
    marker = target/'.ikago-version'
    if marker.exists() and marker.read_text() == lock['sha256']:
        print(f'Pinned SVT-AV1 {lock["version"]} already present: {target}')
        return
    with tempfile.TemporaryDirectory(prefix='fetch-', dir=cache) as temporary:
        stage = Path(temporary)
        archive = stage/'svt-av1.tar.bz2'
        digest, size = hashlib.sha256(), 0
        cached = cache/Path(lock['url']).name
        opened = cached.open('rb') if cached.exists() else urllib.request.urlopen(lock['url'], timeout=60)
        with opened as source, archive.open('wb') as output:
            while chunk := source.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_BYTES:
                    raise SystemExit('SVT-AV1 download is larger than expected.')
                digest.update(chunk)
                output.write(chunk)
        if digest.hexdigest() != lock['sha256']:
            raise SystemExit('SVT-AV1 download does not match the pinned checksum.')
        unpacked = stage/'unpacked'
        with tarfile.open(archive) as tar:
            tar.extractall(unpacked, filter='data')  # refuses links and paths outside the folder
        roots = [p for p in unpacked.iterdir() if p.is_dir()]
        if len(roots) != 1 or not (roots[0]/'CMakeLists.txt').exists():
            raise SystemExit('Unexpected SVT-AV1 archive layout.')
        (roots[0]/'.ikago-version').write_text(lock['sha256'])
        shutil.rmtree(target, ignore_errors=True)
        shutil.move(str(roots[0]), target)
    print(f'Fetched SVT-AV1 {lock["version"]} into {target}')


if __name__ == '__main__':
    fetch()
