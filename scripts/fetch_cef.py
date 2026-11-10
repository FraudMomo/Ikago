#!/usr/bin/env python3
"""Fetch only the pinned CEF binary SDK. Never configure, compile or launch."""
import hashlib
import json
from pathlib import Path
import shutil
import tarfile
import tempfile
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def fetch():
    lock = json.loads((ROOT / "CEF/cef-lock.json").read_text())
    cache = ROOT / ".cef"
    cache.mkdir(exist_ok=True)
    target = cache / "distribution"
    if target.exists():
        header = (target / "include/cef_version.h").read_text()
        if f'#define CEF_VERSION "{lock["cef_version"]}"' in header:
            print(f"Pinned CEF SDK already present: {target}")
            return
        print("The pinned CEF changed; the old SDK is replaced once the new one is verified.")
    with tempfile.TemporaryDirectory(prefix="fetch-", dir=cache) as temporary:
        stage = Path(temporary)
        archive = stage / "cef.tar.bz2"
        url = "https://cef-builds.spotifycdn.com/" + urllib.parse.quote(lock["archive"])
        sha1, sha256, size = hashlib.sha1(), hashlib.sha256(), 0
        # The auto updater leaves a download here. It's checked like any other.
        cached = cache / lock["archive"]
        opened = cached.open("rb") if cached.exists() else urllib.request.urlopen(url, timeout=60)
        with opened as source, archive.open("wb") as output:
            while chunk := source.read(1024 * 1024):
                size += len(chunk)
                if size > lock["size"]:
                    raise SystemExit("CEF download exceeds pinned size.")
                sha1.update(chunk)
                sha256.update(chunk)
                output.write(chunk)
        if (size, sha1.hexdigest(), sha256.hexdigest()) != (lock["size"], lock["sha1"], lock["sha256"]):
            raise SystemExit("CEF checksum mismatch; SDK was not installed.")
        with tarfile.open(archive) as bundle:
            expected = lock["archive"].removesuffix(".tar.bz2")
            if any(Path(item.name).parts[0] != expected for item in bundle.getmembers()):
                raise SystemExit("Unexpected CEF archive root.")
            bundle.extractall(stage, filter="data")
        if target.exists():
            shutil.rmtree(target)
        shutil.move(str(stage / expected), target)
        cached.unlink(missing_ok=True)
    print(f"Verified and installed CEF SDK: {target}")


if __name__ == "__main__":
    fetch()
