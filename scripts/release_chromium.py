#!/usr/bin/env python3
"""A Chromium security release, made by GitHub Actions (.github/workflows/chromium-release.yml) without anyone's help.

  python3 scripts/release_chromium.py --check     whether the last release's Chromium is behind (for the workflow)
  python3 scripts/release_chromium.py --trial     build, test, notarize and sign, publish nothing
  python3 scripts/release_chromium.py             the release itself

It starts from the last published release's tag, never from main, so unfinished work on main can't ship (only the release
tooling and the Chromium checks come from main). There it pins
the latest stable CEF (verified against the CEF index), builds it, runs the Chromium checks, and hands over to
release.py with the next patch version, marked as a security update. Then main gets the same Chromium, version and
BUILDS.md entry, so the next feature release builds on it. Any failure stops before anything is published.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
import chromium_lock  # noqa: E402

WORK = ROOT/'out/chromium-release'
# The release machinery comes from main, so signing, notarization and the signed feed are always the current ones; the
# app's sources, the build and its checks stay exactly as they were in the release.
TOOLING = ['scripts/release.py', 'scripts/chromium_lock.py', 'scripts/update_public_key.swift', 'scripts/package_app.py',
           'scripts/fetch_sparkle.py', 'CEF/sparkle-lock.json']
# The Chromium checks come from main too, so a fix to a check counts on the next run instead of waiting for a release.
# They never ship (release builds leave Checks/ out). If main's checks don't build against the release's code, the
# release's own checks run instead.
CHECKS = ['Ikago/Checks/Chromium', 'scripts/run_chromium_checks.py', 'scripts/cookie_fixture.py', 'scripts/fixtures']


def git(*args, cwd=ROOT, capture=True):
    result = subprocess.run(['git', *args], cwd=cwd, text=True, capture_output=capture)
    if result.returncode:
        raise SystemExit(f'git {" ".join(args)} failed:\n{result.stderr}')
    return result.stdout.strip() if capture else ''


def step(title, command, cwd, retries=0):
    print(f'\n== {title}', flush=True)
    for attempt in range(retries + 1):
        if subprocess.run(command, cwd=cwd).returncode == 0:
            return
        if attempt < retries:
            print(f'{title} failed; trying once more in case it was a timing problem.', flush=True)
    raise SystemExit(f'{title} failed.')


def use_checks(source):
    """Puts the Chromium checks from `source` (a folder, or None for the release tag's own) into the work tree."""
    for path in CHECKS:
        target = WORK/path
        if target.is_dir(): shutil.rmtree(target)
        elif target.exists(): target.unlink()
        if source is None:
            if subprocess.run(['git', 'cat-file', '-e', f'HEAD:{path}'], cwd=WORK, capture_output=True).returncode == 0:
                git('checkout', 'HEAD', '--', path, cwd=WORK)
        elif (source/path).is_dir():
            shutil.copytree(source/path, target)
        elif (source/path).exists():
            shutil.copy2(source/path, target)


def build_checks():
    """Builds the checks flavor with main's checks, falling back to the release's own when those don't build."""
    python = sys.executable
    command = [python, 'scripts/build.py', '--flavor', 'checks', '--jobs', '4']
    use_checks(ROOT)
    print('\n== Building the checks (with main\'s Chromium checks)', flush=True)
    if subprocess.run(command, cwd=WORK).returncode == 0:
        return
    print('Main\'s checks did not build against this release; using the release\'s own checks.', flush=True)
    use_checks(None)
    step('Building the checks', command, WORK)


def last_release_tag():
    tags = [t for t in git('tag', '--list', 'v*').split() if re.fullmatch(r'v\d+\.\d+\.\d+', t)]
    if not tags:
        raise SystemExit('There is no release tag to start from.')
    return max(tags, key=lambda t: tuple(int(p) for p in t[1:].split('.')))


def file_at(tag, path):
    return json.loads(git('show', f'{tag}:{path}'))


def next_patch(tag):
    major, minor, patch = (int(p) for p in tag[1:].split('.'))
    return f'{major}.{minor}.{patch + 1}'


def output(name, value):
    print(f'{name}={value}')
    if path := os.environ.get('GITHUB_OUTPUT'):
        with open(path, 'a') as file:
            file.write(f'{name}={value}\n')


def check():
    tag = last_release_tag()
    lock = file_at(tag, chromium_lock.LOCK)
    latest = chromium_lock.latest_release(lock)
    behind = chromium_lock.is_behind(lock, latest)
    print(f'{tag} has Chromium {lock["chromium_version"]}; the latest stable is {latest["chromium_version"]}.')
    output('needed', 'true' if behind else 'false')


def builds_entry(version, chromium):
    return (f'## {version} — {datetime.date.today().isoformat()}\n\n'
            f'- **Chromium {chromium}:** the latest security and stability fixes from the Chromium project.\n\n')


def update_main(version, build, lock, changes):
    """Main gets the release's Chromium (unless it already has a newer one), version and BUILDS.md entry."""
    git('fetch', 'origin', 'main')
    git('checkout', '-B', 'main', 'origin/main')
    current = chromium_lock.read_lock(ROOT)
    if chromium_lock.version_key(lock) > chromium_lock.version_key(current):
        chromium_lock.apply_version(ROOT, lock)
    config_file = ROOT/'scripts/release.json'
    config = json.loads(config_file.read_text())
    config['build'] = max(int(config['build']), build)
    if tuple(int(p) for p in version.split('.')) > tuple(int(p) for p in config['version'].split('.')):
        config['version'] = version
    config_file.write_text(json.dumps(config, indent=2) + '\n')
    builds = ROOT/'BUILDS.md'
    text = builds.read_text()
    head, marker, rest = text.partition('## Unreleased\n')
    if marker:
        unreleased, heading, older = rest.partition('\n## ')
        text = head + marker + unreleased.rstrip('\n') + '\n\n' + changes + (('## ' + older) if heading else '')
    else:
        text = text.rstrip('\n') + '\n\n' + changes
    builds.write_text(text.rstrip('\n') + '\n')
    git('add', '-u')
    git('commit', '-m', f'chore(release): {version} (Chromium {lock["chromium_version"]})')
    for attempt in range(2):
        if subprocess.run(['git', 'push', 'origin', 'main'], cwd=ROOT).returncode == 0:
            return
        git('pull', '--rebase', 'origin', 'main')
    raise SystemExit('Could not bring main up to date; the release itself is published.')


def release(trial):
    tag = last_release_tag()
    version = next_patch(tag)
    shutil.rmtree(WORK, ignore_errors=True)
    subprocess.run(['git', 'worktree', 'prune'], cwd=ROOT)
    git('worktree', 'add', '--detach', str(WORK), tag)
    try:
        for path in TOOLING:
            (WORK/path).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT/path, WORK/path)
        lock = chromium_lock.bump(WORK)
        if lock is None and not trial:
            print(f'{tag} already has the latest stable Chromium; nothing to release.')
            return
        lock = lock or chromium_lock.read_lock(WORK)
        python = sys.executable
        build_checks()
        step('Running the Chromium checks', [python, 'scripts/run_chromium_checks.py'], WORK, retries=1)
        main_build = json.loads(git('show', 'origin/main:scripts/release.json'))['build']
        build = max(int(file_at(tag, 'scripts/release.json')['build']), int(main_build)) + 1
        changes = builds_entry(version, lock['chromium_version'])
        notes = WORK/'out/chromium-notes.md'
        notes.parent.mkdir(parents=True, exist_ok=True)
        notes.write_text(changes.split('\n', 2)[2].strip() + '\n')
        command = [python, 'scripts/release.py', '--version', version, '--build', str(build), '--security',
                   '--notes', str(notes)]
        if not trial:
            command += ['--publish', '--tag-only']
        step('Releasing', command, WORK)
        if trial:
            print(f'\nTrial finished: Ikago {version} with Chromium {lock["chromium_version"]} built, passed its checks, '
                  'and was notarized and signed. Nothing was published.')
            return
        update_main(version, build, lock, changes)
        print(f'\nPublished Ikago {version} with Chromium {lock["chromium_version"]}.')
    finally:
        subprocess.run(['git', 'worktree', 'remove', '--force', str(WORK)], cwd=ROOT)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--check', action='store_true', help='Only say whether a release is needed')
    parser.add_argument('--trial', action='store_true', help='Everything but publishing')
    args = parser.parse_args()
    check() if args.check else release(args.trial)


if __name__ == '__main__':
    main()
