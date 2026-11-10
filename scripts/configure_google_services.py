#!/usr/bin/env python3
"""User-run setup. Never invoked by builds or unattended fixtures."""
import getpass
import os
from pathlib import Path
import tempfile
import stat
import sys


def read_key(path):
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
    with os.fdopen(os.open(path, flags), 'rb') as source:
        info = os.fstat(source.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077 or not 0 < info.st_size <= 512:
            raise ValueError('Expected an owner-only regular API key file, at most 512 bytes.')
        key = source.read(513).decode('ascii').strip()
    if not key or len(key) > 512 or any(ord(c) <= 32 or ord(c) >= 127 for c in key):
        raise ValueError('Expected one non-empty ASCII API key token.')
    return key


def main():
    if not sys.stdin.isatty():
        raise SystemExit('Run this setup in Terminal so hidden key entry is available.')
    key = getpass.getpass('Google API key with Safe Browsing enabled (empty cancels): ').strip()
    if not key:
        return
    if len(key.encode('utf-8')) > 512 or any(ord(c) <= 32 or ord(c) >= 127 for c in key):
        raise SystemExit('Expected one ASCII key token, at most 512 bytes.')
    directory = Path.home() / 'Library/Application Support/Ikago'
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    if directory.is_symlink() or directory.stat().st_uid != os.getuid():
        raise SystemExit('The application data directory must be owned by you and not be a symbolic link.')
    descriptor, path = tempfile.mkstemp(prefix='.google-api-key-', dir=directory)
    try:
        with os.fdopen(descriptor, 'wb') as output:
            os.fchmod(output.fileno(), 0o600)
            output.write(key.encode('ascii'))
            output.flush()
            os.fsync(output.fileno())
        os.replace(path, directory / 'google-api-key')
    finally:
        if os.path.exists(path):
            os.unlink(path)
    print('Google service configuration saved. Quit and reopen Ikago, then verify a live warning.')


if __name__ == '__main__':
    main()
