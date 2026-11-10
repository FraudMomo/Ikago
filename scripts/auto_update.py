#!/usr/bin/env python3
"""Keep Ikago's Chromium current: check for a newer stable CEF, then build, test and install it.

Runs hourly from a LaunchAgent (--install-agent), and checks for a release every 6 hours. Everything
happens in a separate copy of the source, so a failure can't touch the installed app or the repository.
A new build is installed only after the full Chromium check suite passes on it, and only when it has a
real signature, because an ad hoc one would lose access to the Keychain. Installation waits until Ikago
isn't running. The app reads status.json to show progress and offer a relaunch.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
LABEL = 'app.ikago.updater'
UPDATES = Path.home()/'Library/Application Support/Ikago/Updates'
WORK = Path.home()/'Library/Caches/Ikago/Updater'
STATUS, STAGED, LOG = UPDATES/'status.json', UPDATES/'Ikago.app', UPDATES/'updater.log'
DISABLED, FORCE, RELAUNCH = UPDATES/'disabled', UPDATES/'check-now', UPDATES/'relaunch-after-install'
INSTALLED = '/Applications/Ikago.app/Contents/MacOS/Ikago'
CHECK_INTERVAL, RETRY_INTERVAL = 6*3600, 24*3600
MINIMUM_FREE_BYTES = 8 * 1024**3
PATH = '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'


def log(message):
    print(f'{time.strftime("%Y-%m-%d %H:%M:%S")} {message}', flush=True)


def read_status():
    try:
        return json.loads(STATUS.read_text())
    except (OSError, ValueError):
        return {}


def write_status(**fields):
    status = read_status() | fields
    temporary = STATUS.with_suffix('.tmp')
    temporary.write_text(json.dumps(status, indent=1))
    temporary.replace(STATUS)
    return status


def version_key(entry):
    """Chromium version first, then CEF's own build, since CEF can ship fixes on the same Chromium."""
    cef = re.match(r'[\d.]+', entry['cef_version']).group(0)
    return tuple(int(part) for part in entry['chromium_version'].split('.')), tuple(int(part) for part in cef.split('.'))


def latest_release(lock):
    with urllib.request.urlopen(lock['index'], timeout=60) as response:
        index = json.load(response)
    versions = [v for v in index[lock['platform']]['versions'] if v.get('channel') == lock['channel']]
    return max(versions, key=version_key)


def is_running():
    return subprocess.run(['pgrep', '-f', '^' + INSTALLED], capture_output=True).returncode == 0


def on_battery():
    result = subprocess.run(['pmset', '-g', 'batt'], capture_output=True, text=True)
    return 'Battery Power' in result.stdout


def download(lock, destination):
    """Verifies the size and SHA-1 the index publishes, and records a SHA-256 for the lock."""
    url = 'https://cef-builds.spotifycdn.com/' + urllib.parse.quote(lock['archive'])
    sha1, sha256, size = hashlib.sha1(), hashlib.sha256(), 0
    with urllib.request.urlopen(url, timeout=120) as source, destination.open('wb') as output:
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


def new_lock(lock, release):
    file = next(f for f in release['files'] if f['type'] == lock.get('distribution', 'minimal'))
    return lock | {'cef_version': release['cef_version'], 'cef_commit': release.get('cef_commit', ''),
                   'chromium_version': release['chromium_version'], 'archive': file['name'],
                   'size': file['size'], 'sha1': file['sha1'], 'sha256': ''}


def apply_version(root, lock):
    """The two source files that name the pinned release."""
    (root/'CEF/cef-lock.json').write_text(json.dumps(lock, indent=2) + '\n')
    swift = root/'Ikago/Engine/Shared/BrowserEngine.swift'
    text, count = re.subn(r'(static let chromium = ")[\d.]+(")', rf'\g<1>{lock["chromium_version"]}\g<2>', swift.read_text())
    if count != 1:
        raise RuntimeError('Could not find the Chromium version constant.')
    swift.write_text(text)


def run(command, cwd, stage, timeout):
    log(f'{stage}: {" ".join(map(str, command))}')
    environment = os.environ | {'PATH': PATH}
    try:
        result = subprocess.run(command, cwd=cwd, env=environment, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(f'{stage} timed out.') from error
    if result.returncode:
        raise RuntimeError(f'{stage} failed.')


def build_and_test(lock, source):
    python, work = sys.executable, source/'src'
    run(['rsync', '-a', '--delete', '--exclude', '/.git', '--exclude', '/build', '--exclude', '/out', '--exclude', '/.cef',
         f'{ROOT}/', f'{work}/'], source, 'Copying the source', 600)
    (work/'.cef').mkdir(exist_ok=True)
    write_status(state='updating', message=f'Downloading Chromium {lock["chromium_version"]}…')
    download(lock, work/'.cef'/lock['archive'])
    apply_version(work, lock)
    write_status(message=f'Building Chromium {lock["chromium_version"]}…')
    run([python, 'scripts/build.py', '--flavor', 'checks', '--jobs', '4'], work, 'Building the checks', 3600)
    write_status(message=f'Testing Chromium {lock["chromium_version"]}…')
    try:
        run([python, 'scripts/run_chromium_checks.py'], work, 'Running the checks', 1800)
    except RuntimeError:
        log('Checks failed once; trying again in case it was a timing problem.')
        run([python, 'scripts/run_chromium_checks.py'], work, 'Running the checks', 1800)
    run([python, 'scripts/build.py', '--flavor', 'release', '--jobs', '4'], work, 'Building the release', 3600)
    built = work/'build/Ikago.app'
    signature = subprocess.run(['codesign', '-dvv', str(built)], capture_output=True, text=True).stderr
    if 'Authority=Apple Development' not in signature and 'Authority=Developer ID' not in signature:
        # Usually a locked Keychain. An ad hoc build would lose the app's Keychain access, so wait and retry.
        raise RuntimeError('The build could not be signed, which usually means the Keychain was locked.')
    return built


def update(release, lock, pretend, install):
    target = new_lock(lock, release)
    WORK.mkdir(parents=True, exist_ok=True)
    try:
        built = build_and_test(target, WORK)
        if not install:
            log(f'Built and tested {target["chromium_version"]}; not installing, as asked.')
            write_status(state='tested', message=f'Chromium {target["chromium_version"]} built and passed its checks.')
            return
        if STAGED.exists():
            shutil.rmtree(STAGED)
        run(['ditto', str(built), str(STAGED)], WORK, 'Staging the build', 600)
        # Keep the repository on the same release, so a later manual build can't downgrade Chromium.
        if not pretend and json.loads((ROOT/'CEF/cef-lock.json').read_text())['cef_version'] == lock['cef_version']:
            apply_version(ROOT, target | {'sha256': json.loads((WORK/'src/CEF/cef-lock.json').read_text())['sha256']})
        write_status(state='ready', latest=target['chromium_version'], message=f'Chromium {target["chromium_version"]} is ready to install.')
        install_staged()
    finally:
        shutil.rmtree(WORK, ignore_errors=True)


def signing_team(app):
    """The Team ID of a validly signed Ikago bundle, or None. The staging folder is writable by any
    program running as you, so nothing in it is installed unless it is signed by the installed app's team."""
    app = str(app)
    verify = subprocess.run(['codesign', '--verify', '--deep', '--strict', app], capture_output=True)
    if verify.returncode:
        return None
    details = subprocess.run(['codesign', '-dvv', app], capture_output=True, text=True).stderr
    fields = dict(line.split('=', 1) for line in details.splitlines() if '=' in line)
    team = fields.get('TeamIdentifier', '')
    if fields.get('Identifier') != 'app.ikago.browser' or not team or team == 'not set':
        return None
    return team


def install_staged():
    if not STAGED.exists():
        return
    if is_running():
        log('Staged update waits for Ikago to quit.')
        return
    installed_team = signing_team(Path(INSTALLED).parents[2])
    if not installed_team or signing_team(STAGED) != installed_team:
        log('The staged update is not signed by the installed app’s team; removing it.')
        shutil.rmtree(STAGED, ignore_errors=True)
        write_status(state='failed', message='An update was refused because it wasn’t signed like the installed Ikago.')
        return
    environment = os.environ | {'PATH': PATH, 'IKAGO_INSTALL_SOURCE': str(STAGED)}
    result = subprocess.run(['/bin/zsh', str(ROOT/'scripts/install.sh')], cwd=ROOT, env=environment, timeout=300)
    if result.returncode:
        write_status(state='failed', message='The update was ready but could not be installed.')
        return
    shutil.rmtree(STAGED, ignore_errors=True)
    version = read_status().get('latest', '')
    write_status(state='current', pinned=version, message=f'Updated to Chromium {version}.')
    log(f'Installed Chromium {version}.')
    if RELAUNCH.exists():
        RELAUNCH.unlink()
        subprocess.run(['open', '/Applications/Ikago.app'])


def check(force, pretend, install):
    status = read_status()
    now = time.time()
    if not force and now - status.get('checkedAt', 0) < CHECK_INTERVAL:
        return
    lock = json.loads((ROOT/'CEF/cef-lock.json').read_text())
    if pretend:
        lock['chromium_version'], lock['cef_version'] = pretend, '1.0.0'
    release = latest_release(lock)
    latest, pinned = release['chromium_version'], lock['chromium_version']
    write_status(checkedAt=now, pinned=pinned, latest=latest)
    if version_key(release) <= version_key(lock):
        if status.get('state') not in ('ready',):
            write_status(state='current', message='Chromium is up to date.')
        return
    if status.get('state') == 'ready' and STAGED.exists() and status.get('latest') == latest:
        return
    if status.get('failedVersion') == release['cef_version'] and now - status.get('failedAt', 0) < RETRY_INTERVAL and not force:
        return
    if on_battery() and not force:
        write_status(state='waiting', message=f'Chromium {latest} is available. Building waits until the Mac is on power.')
        return
    if shutil.disk_usage(Path.home()).free < MINIMUM_FREE_BYTES:
        write_status(state='failed', message=f'Chromium {latest} is available, but there isn’t enough free disk space to build it.')
        return
    log(f'Updating Chromium {pinned} → {latest} ({release["cef_version"]}).')
    try:
        update(release, lock, bool(pretend), install)
    except Exception as error:  # Anything at all: report it and leave the installed app alone.
        log(f'Update failed: {error}')
        write_status(state='failed', failedVersion=release['cef_version'], failedAt=now,
                     message=f'Couldn’t update to Chromium {latest} automatically: {error}')


def install_agent():
    UPDATES.mkdir(parents=True, exist_ok=True)
    python = '/opt/homebrew/bin/python3' if Path('/opt/homebrew/bin/python3').exists() else sys.executable
    plist = Path.home()/'Library/LaunchAgents'/f'{LABEL}.plist'
    plist.parent.mkdir(exist_ok=True)
    arguments = ''.join(f'<string>{item}</string>' for item in (python, str(ROOT/'scripts/auto_update.py')))
    plist.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>{LABEL}</string>
<key>ProgramArguments</key><array>{arguments}</array>
<key>StartInterval</key><integer>3600</integer>
<key>RunAtLoad</key><true/>
<key>ProcessType</key><string>Background</string>
<key>LowPriorityIO</key><true/>
<key>Nice</key><integer>10</integer>
<key>LimitLoadToSessionType</key><string>Aqua</string>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>{PATH}</string></dict>
<key>StandardOutPath</key><string>{LOG}</string>
<key>StandardErrorPath</key><string>{LOG}</string>
</dict></plist>
''')
    domain = f'gui/{os.getuid()}'
    subprocess.run(['launchctl', 'bootout', f'{domain}/{LABEL}'], capture_output=True)
    subprocess.run(['launchctl', 'bootstrap', domain, str(plist)], check=True)
    print(f'Automatic Chromium updates are on ({plist}).')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install-agent', action='store_true', help='Turn on the hourly background job.')
    parser.add_argument('--force', action='store_true', help='Check now, whatever the schedule or power source.')
    parser.add_argument('--pretend-pinned', metavar='CHROMIUM', help='Test the pipeline by acting as if this older version were pinned.')
    parser.add_argument('--no-install', action='store_true', help='Build and test, but stage and install nothing.')
    args = parser.parse_args()
    if args.install_agent:
        return install_agent()
    UPDATES.mkdir(parents=True, exist_ok=True)
    with (UPDATES/'.lock').open('w') as lock_file:
        try:
            fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return log('Another update run is in progress.')
        if DISABLED.exists() and not args.force:
            return write_status(state='disabled', message='Automatic updates are off.')
        if not args.no_install:
            install_staged()
        force = args.force or FORCE.exists()
        FORCE.unlink(missing_ok=True)
        try:
            check(force, args.pretend_pinned, not args.no_install)
        except OSError as error:  # Offline, usually. Try again at the next run.
            log(f'Could not check for updates: {error}')


if __name__ == '__main__':
    main()
