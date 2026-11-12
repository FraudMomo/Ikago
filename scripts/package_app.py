#!/usr/bin/env python3
"""Assemble and sign Ikago.app: Info.plist, assets, the CEF framework and its helper apps."""
import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import tempfile
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = 'app.ikago.browser'
VERSION = '0.2.0'
BUILD = '18'
HELPERS = ['', ' (Alerts)', ' (GPU)', ' (Plugin)', ' (Renderer)']


def signing_identity(flavor):
    """IKAGO_SIGN_IDENTITY wins. Release uses Apple Development when present; otherwise ad hoc."""
    if identity := os.environ.get('IKAGO_SIGN_IDENTITY'):
        return identity
    if flavor != 'release':
        return '-'
    found = subprocess.run(['security', 'find-identity', '-v', '-p', 'codesigning'], capture_output=True, text=True).stdout
    return 'Apple Development' if 'Apple Development' in found else '-'


def sign(path, identity, entitlements=None, deep=False):
    # A locked keychain would wait forever for someone to answer, so this has a time limit.
    command = ['codesign', '--force', '--timestamp=none', '--sign', identity]
    if deep:
        command.append('--deep')
    if entitlements:
        command += ['--options', 'runtime', '--entitlements', str(entitlements)]
    subprocess.run(command + [str(path)], check=True, timeout=120, capture_output=True)


def team_id(identity):
    """The team a signing identity belongs to, read from a signature it makes; None for ad hoc."""
    if identity == '-':
        return None
    with tempfile.TemporaryDirectory() as folder:
        probe = Path(folder)/'probe'
        shutil.copyfile('/usr/bin/true', probe)  # not copy2: system flags would block signing
        probe.chmod(0o755)
        sign(probe, identity)
        details = subprocess.run(['codesign', '-dv', str(probe)], capture_output=True, text=True).stderr
    match = re.search(r'^TeamIdentifier=([A-Z0-9]{10})$', details, re.MULTILINE)
    return match.group(1) if match else None


def with_app_group(entitlements, team):
    """Adds the team-prefixed app group whose container macOS locks to this team (ProtectedStorage)."""
    if not team:
        return entitlements
    values = plistlib.loads(Path(entitlements).read_bytes())
    values['com.apple.security.application-groups'] = [f'{team}.{BUNDLE_ID}']
    out = ROOT/'out'/f'{Path(entitlements).stem}-{team}.entitlements'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(plistlib.dumps(values))
    return out


def sign_bundle(app, framework, identity, entitlements):
    # --deep doesn't reach the framework's Libraries folder, and library validation rejects
    # anything left with a different team (such as libcef_sandbox.dylib), so sign those first.
    for library in (framework/'Libraries').rglob('*.dylib'):
        if not library.is_symlink():
            sign(library, identity)
    sign(framework, identity, deep=True)
    restricted = ROOT/('CEF/helper-restricted.entitlements' if identity != '-' else 'CEF/helper-restricted-development.entitlements')
    # Helpers read and write the Chromium profiles, so they need the same group as the app.
    team = team_id(identity)
    entitlements, restricted = with_app_group(entitlements, team), with_app_group(restricted, team)
    for helper in (app/'Contents/Frameworks').glob('Ikago Helper*.app'):
        # Only the base helper hosts Chromium's capture service; the others never need the devices.
        sign(helper, identity, entitlements if helper.name == 'Ikago Helper.app' else restricted)
    sign(app, identity, entitlements)


def package_cef_locales(framework, source_framework):
    """Match Ikago's English UI; preserve ICU and the engine's required fallback strings."""
    resources, source = framework/'Resources', source_framework/'Resources'
    english = [folder for folder in source.glob('*.lproj')
               if folder.stem == 'en' or folder.stem.startswith('en_')]
    if not (source/'en.lproj/locale.pak').is_file():
        raise SystemExit('CEF is missing its required English fallback locale.')
    # Restore retained resources when reusing a bundle that was packaged differently.
    for folder in english:
        target = resources/folder.name
        if not target.exists():
            shutil.copytree(folder, target)
    keep = {folder.name for folder in english}
    removed = 0
    for folder in resources.glob('*.lproj'):
        if folder.name not in keep:
            removed += sum(path.stat().st_size for path in folder.rglob('*') if path.is_file())
            shutil.rmtree(folder)
    print(f'CEF locale resources: English fallbacks retained; removed {removed / 1024**2:.2f} MiB', flush=True)


def main():
    app, flavor = Path(sys.argv[1]), sys.argv[2]
    contents = app/'Contents'
    for folder in ('MacOS', 'Resources', 'Frameworks'):
        (contents/folder).mkdir(parents=True, exist_ok=True)

    info = plistlib.loads((ROOT/'Ikago/Resources/Info.plist').read_bytes())
    info.update(CFBundleExecutable='Ikago', CFBundleIdentifier=BUNDLE_ID, CFBundleName='Ikago', CFBundleDisplayName='Ikago',
                CFBundlePackageType='APPL', CFBundleShortVersionString=VERSION, CFBundleVersion=BUILD,
                NSPrincipalClass='IKCEFApplication', LSMinimumSystemVersion='26.0')
    (contents/'Info.plist').write_bytes(plistlib.dumps(info))

    if flavor == 'release':
        binary = contents/'MacOS/Ikago'
        # Keep a matching unstripped image for atos/sample symbolication outside the distributed app.
        digest = hashlib.sha256(binary.read_bytes()).hexdigest()[:16]
        symbols = ROOT/'out/symbols'/digest
        symbols.mkdir(parents=True, exist_ok=True)
        shutil.copy2(binary, symbols/'Ikago')
        subprocess.run(['xcrun', 'strip', '-x', str(binary)], check=True, capture_output=True)

    # Password matching groups sites by registrable domain (PublicSuffix.swift).
    shutil.copyfile(ROOT/'Ikago/Resources/public_suffix_list.dat', contents/'Resources/public_suffix_list.dat')

    framework = contents/'Frameworks/Chromium Embedded Framework.framework'
    source_framework = ROOT/'.cef/distribution/Release/Chromium Embedded Framework.framework'
    if framework.exists():
        # Reused app bundles must pick up SDK updates too, rather than keep an older signed framework.
        bundled = plistlib.loads((framework/'Resources/Info.plist').read_bytes())
        pinned = plistlib.loads((source_framework/'Resources/Info.plist').read_bytes())
        if bundled.get('CFBundleVersion') != pinned.get('CFBundleVersion'):
            shutil.rmtree(framework)
    if not framework.exists():
        shutil.copytree(source_framework, framework, symlinks=True)
    package_cef_locales(framework, source_framework)
    for suffix in HELPERS:
        name = 'Ikago Helper' + suffix
        helper = contents/'Frameworks'/(name + '.app')/'Contents'
        (helper/'MacOS').mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT/'out/cef/IkagoHelper', helper/'MacOS'/name)
        role = suffix.replace(' (', '.').replace(')', '').lower()
        (helper/'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleExecutable': name, 'CFBundleIdentifier': f'{BUNDLE_ID}.helper{role}', 'CFBundleName': name,
            'CFBundlePackageType': 'APPL', 'LSBackgroundOnly': True, 'LSMinimumSystemVersion': '26.0'}))
    subprocess.run(['xcrun', 'actool', str(ROOT/'Ikago/Resources/Assets.xcassets'), '--compile', str(contents/'Resources'),
                    '--platform', 'macosx', '--minimum-deployment-target', '26.0', '--app-icon', 'IkagoAppIcon',
                    '--output-partial-info-plist', str(ROOT/'out/asset-info.plist')], check=True, capture_output=True)

    identity = signing_identity(flavor)
    # Ad hoc signatures have no team, so only they need library validation turned off.
    entitlements = ROOT/('Ikago/Resources/Ikago.entitlements' if identity != '-' else 'CEF/development.entitlements')
    try:
        sign_bundle(app, framework, identity, entitlements)
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as error:
        if identity == '-':
            raise
        print(f'Signing with {identity} failed ({error}); signing ad hoc instead.', flush=True)
        identity = '-'
        sign_bundle(app, framework, identity, ROOT/'CEF/development.entitlements')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    print(f'Signed {app} with {"an ad hoc signature" if identity == "-" else identity}')


if __name__ == '__main__':
    main()
