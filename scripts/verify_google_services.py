#!/usr/bin/env python3
"""Explicit user-run live verdict check; never run automatically by builds."""
import os
from pathlib import Path
import subprocess
import sys
from configure_google_services import read_key

ROOT = Path(__file__).resolve().parents[1]


def main():
    key = os.environ.get('GOOGLE_API_KEY')
    if not key:
        try:
            key = read_key(Path.home() / 'Library/Application Support/Ikago/google-api-key')
        except (OSError, ValueError) as error:
            raise SystemExit('No usable Google service key configuration. Run configure_google_services.py after obtaining a key.') from error
    checks = ROOT / 'build/checks/Ikago.app'
    environment = dict(os.environ, GOOGLE_API_KEY=key, IKAGO_CEF_SAFE_BROWSING_PROBE='1')
    if checks.exists() and 'IKAGO_APP_PATH' not in environment:
        environment['IKAGO_APP_PATH'] = str(checks)
    result = subprocess.run([sys.executable, str(ROOT / 'scripts/run_chromium_checks.py')], env=environment)
    if result.returncode:
        raise SystemExit(result.returncode)
    log = (ROOT / 'out/cef-smoke.log').read_text()
    if 'CEF_SAFE_BROWSING_INTERSTITIAL_OBSERVED' not in log:
        raise SystemExit('Live Safe Browsing remains unverified: no native threat-warning page was observed.')
    print('Verified a native Safe Browsing warning against the benign Google test fixture.')


if __name__ == '__main__':
    main()
