#!/usr/bin/env python3
"""Build Ikago: the CEF bridge, the Swift app, then the signed bundle. Never compiles Chromium itself.

Flavors:
  release  build/Ikago.app          Optimized, no test code. Signed with your Apple Development identity.
  checks   build/checks/Ikago.app   Adds the Chromium runtime checks (scripts/run_chromium_checks.py).
  debug    build/debug/Ikago.app    Adds the WebKit test driver (scripts/check-browser-features.sh).
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
STATE = ROOT/'out/build-process.json'
APPS = {'release': 'build/Ikago.app', 'checks': 'build/checks/Ikago.app', 'debug': 'build/debug/Ikago.app'}
SWIFT_FLAGS = {'release': ['-O'], 'checks': ['-Onone', '-D', 'IKAGO_CHECKS'], 'debug': ['-Onone', '-D', 'DEBUG']}


def compile_swift(app, flavor, threads):
    """Compiles a snapshot, so edits made during a build can't produce a mixed binary."""
    snapshot = ROOT/'out/SwiftSources'
    shutil.rmtree(snapshot, ignore_errors=True)
    shutil.copytree(ROOT/'Ikago', snapshot)
    if flavor == 'release':
        shutil.rmtree(snapshot/'Checks')
    (app/'Contents/MacOS').mkdir(parents=True, exist_ok=True)
    return ['xcrun', 'swiftc', '-module-cache-path', str(ROOT/'out/ModuleCache'), '-swift-version', '6',
            *SWIFT_FLAGS[flavor], '-whole-module-optimization', '-num-threads', str(threads),
            '-target', 'arm64-apple-macos26.0', '-I', str(ROOT/'CEF/Bridge'), '-I', str(ROOT/'out/cef'),
            '-L', str(ROOT/'out/cef'), '-lIKCEFBridge', '-L', str(ROOT/'out/cef/libcef_dll_wrapper'), '-lcef_dll_wrapper',
            '-L', str(ROOT/'out/svtav1/install/lib'), '-lSvtAv1Enc', '-lc++', '-Xlinker', '-ObjC', '-framework', 'AppKit', '-framework', 'WebKit', '-framework', 'Security',
            '-framework', 'CoreAudio', '-framework', 'AVFoundation', '-framework', 'Accelerate', '-o', str(app/'Contents/MacOS/Ikago'), *map(str, sorted(snapshot.rglob('*.swift')))]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--flavor', choices=APPS, default='release')
    parser.add_argument('--jobs', type=int, default=2, choices=range(1, 9))
    parser.add_argument('--stop', action='store_true', help='Stop a running build')
    args = parser.parse_args()
    if args.stop:
        if not STATE.exists():
            print('No build is running.'); return
        pid = json.loads(STATE.read_text())['pid']
        # Confirm the recorded process is still this build before signalling it.
        command = subprocess.run(['ps', '-p', str(pid), '-o', 'command='], capture_output=True, text=True).stdout
        if str(Path(__file__).resolve()) not in command:
            print('Stale build record; nothing was stopped.'); STATE.unlink(); return
        os.kill(pid, signal.SIGTERM)
        print('Build stop requested.'); return
    (ROOT/'out').mkdir(exist_ok=True)
    if STATE.exists():
        try:
            os.kill(json.loads(STATE.read_text())['pid'], 0)
        except ProcessLookupError:
            STATE.unlink()
        else:
            raise SystemExit('A build is already running; stop it or wait for it to finish.')
    app = ROOT/APPS[args.flavor]
    running = subprocess.run(['ps', '-axo', 'comm='], capture_output=True, text=True, check=True).stdout.splitlines()
    if str(app/'Contents/MacOS/Ikago') in {line.strip() for line in running}:
        raise SystemExit(f'{app} is running. Quit it first; a running bundle cannot be overwritten.')
    child = None

    def stop(_signal, _frame):
        if child and child.poll() is None:
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL); child.wait()
        raise SystemExit(130)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    STATE.write_text(json.dumps({'pid': os.getpid()}))
    commands = [
        [sys.executable, str(ROOT/'scripts/fetch_cef.py')],
        [sys.executable, str(ROOT/'scripts/fetch_svtav1.py')],
        # SVT-AV1: encoder library only, static, for the media translation layer. Not Chromium.
        ['cmake', '-S', str(ROOT/'.svtav1/source'), '-B', str(ROOT/'out/svtav1/build'), '-G', 'Ninja', '-DCMAKE_BUILD_TYPE=Release',
         '-DCMAKE_OSX_ARCHITECTURES=arm64', '-DCMAKE_OSX_DEPLOYMENT_TARGET=26.0', '-DBUILD_SHARED_LIBS=OFF', '-DBUILD_APPS=OFF',
         '-DBUILD_TESTING=OFF', '-DREPRODUCIBLE_BUILDS=ON', '-DLOG_QUIET=ON', '-DCMAKE_INSTALL_PREFIX=' + str(ROOT/'out/svtav1/install')],
        ['cmake', '--build', str(ROOT/'out/svtav1/build'), '--target', 'install', '--parallel', str(args.jobs)],
        ['cmake', '-S', str(ROOT/'CEF'), '-B', str(ROOT/'out/cef'), '-G', 'Ninja', '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_OSX_ARCHITECTURES=arm64'],
        ['cmake', '--build', str(ROOT/'out/cef'), '--parallel', str(args.jobs)],
        lambda: compile_swift(app, args.flavor, min(4, args.jobs)),
        [sys.executable, str(ROOT/'scripts/package_app.py'), str(app), args.flavor],
    ]
    try:
        for step in commands:
            command = step() if callable(step) else step
            print('Running:', command[0], command[1], flush=True)
            child = subprocess.Popen(command, cwd=ROOT, start_new_session=True)
            if code := child.wait():
                raise SystemExit(code)
        print('Ready:', app)
    finally:
        STATE.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
