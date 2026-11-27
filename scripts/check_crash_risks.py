#!/usr/bin/env python3
"""Static crash audit of a built Ikago.app: finds crashes that no click path reveals.

macOS ends an app outright (TCC, `__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__`) the first time its code touches a
privacy-protected service whose usage description is missing from Info.plist. Chromium reaches such services by
itself on certain sites (Bluetooth on Google sign-in, 0.7.2), so the only reliable check is what the binaries can
call: this reads every Mach-O in the bundle, maps the privacy APIs it imports to the keys and entitlements they
need, and compares Ikago's keys with the ones Chrome declares.

    python3 scripts/check_crash_risks.py [build/debug/Ikago.app]

Exit status 1 when a key is missing (a crash); entitlement gaps are warnings (the service is silently denied).
"""
import plistlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# (what it is, imported-symbol pattern, Info.plist keys that must all exist, hardened-runtime entitlement or None).
# Services in QUIET only deny access when their key is missing; the rest end the app.
QUIET = {'Location', 'Local network', 'Apple Events', 'Browser passkeys'}
RULES = [
    ('Bluetooth', r'IOBluetooth|CBCentralManager|CBPeripheralManager',
     ['NSBluetoothAlwaysUsageDescription'], None),
    ('Camera', r'AVCaptureDevice|AVCaptureSession', ['NSCameraUsageDescription'], 'com.apple.security.device.camera'),
    ('Microphone', r'AVCaptureDevice|AVAudioEngine|AudioDeviceStart', ['NSMicrophoneUsageDescription'],
     'com.apple.security.device.audio-input'),
    ('Location', r'CLLocationManager', ['NSLocationUsageDescription'], 'com.apple.security.personal-information.location'),
    ('System audio capture', r'AudioHardwareCreateProcessTap|CATapDescription', ['NSAudioCaptureUsageDescription'], None),
    ('Speech recognition', r'SFSpeechRecognizer', ['NSSpeechRecognitionUsageDescription'], None),
    ('Contacts', r'CNContactStore|ABAddressBook', ['NSContactsUsageDescription'], None),
    ('Calendars', r'EKEventStore', ['NSCalendarsFullAccessUsageDescription'], None),
    ('Photos', r'PHPhotoLibrary', ['NSPhotoLibraryUsageDescription'], None),
    ('Media library', r'MPMediaLibrary', ['NSAppleMusicUsageDescription'], None),
    ('HomeKit', r'HMHomeManager', ['NSHomeKitUsageDescription'], None),
    ('Apple Events', r'NSAppleScript|AEDeterminePermissionToAutomateTarget|SBApplication',
     ['NSAppleEventsUsageDescription'], 'com.apple.security.automation.apple-events'),
    ('Browser passkeys', r'ASAuthorizationWebBrowserPublicKeyCredentialManager',
     ['NSWebBrowserPublicKeyCredentialUsageDescription'], None),
    ('Local network', r'NWBrowser|DNSServiceBrowse|CWWiFiClient', ['NSLocalNetworkUsageDescription'], None),
]
# System frameworks the app links whose own code calls protected services for pages (not visible as imports).
LINKED = {
    'WebKit': ['NSCameraUsageDescription', 'NSMicrophoneUsageDescription', 'NSLocationUsageDescription',
               'NSSpeechRecognitionUsageDescription'],
}


def run(*command):
    return subprocess.run(command, capture_output=True, text=True).stdout


def binaries(app):
    for path in app.rglob('*'):
        if path.is_file() and not path.is_symlink() and path.stat().st_size > 4096:
            with path.open('rb') as handle:
                magic = handle.read(4)
            if magic in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe'):
                yield path


def main():
    app = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT/'build/debug/Ikago.app').resolve()
    info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    entitlements = plistlib.loads((ROOT/'Ikago/Resources/Ikago.entitlements').read_bytes())
    missing, warnings, used = [], [], []
    imports, linked = {}, set()
    for binary in binaries(app):
        imports[binary.relative_to(app)] = run('nm', '-u', '-j', str(binary))
        linked |= {Path(line.split()[0]).stem for line in run('otool', '-L', str(binary)).splitlines()[1:] if line.strip()}
    for name, pattern, keys, entitlement in RULES:
        callers = sorted({str(path).split('/Contents/')[-1].split('/')[-1] for path, text in imports.items()
                          if re.search(pattern, text)})
        if not callers:
            continue
        used.append(f'{name}: {", ".join(callers)}')
        for key in keys:
            if not info.get(key):
                text = f'{key} ({name}, imported by {", ".join(callers)})'
                (warnings if name in QUIET else missing).append(('quietly denied without ' if name in QUIET else '') + text)
        if entitlement and not entitlements.get(entitlement):
            warnings.append(f'{entitlement} entitlement missing: {name} is silently denied in signed builds')
    for framework, keys in LINKED.items():
        if framework in linked:
            missing += [f'{key} ({framework} pages)' for key in keys if not info.get(key)]
    chrome = Path('/Applications/Google Chrome.app/Contents/Resources/en.lproj/InfoPlist.strings')
    if chrome.exists():
        chrome_keys = plistlib.loads(chrome.read_bytes()) if chrome.read_bytes()[:6] == b'bplist' else {}
        if not chrome_keys:
            chrome_keys = dict(re.findall(r'"?(NS\w+UsageDescription)"?\s*=\s*"([^"]*)"', run('plutil', '-p', str(chrome))))
            chrome_keys |= {k: v for k, v in re.findall(r'"(NS\w+UsageDescription)" => "([^"]*)"', run('plutil', '-p', str(chrome)))}
        for key in sorted(k for k in chrome_keys if k.endswith('UsageDescription') and not info.get(k)):
            warnings.append(f'{key}: Chrome declares it, Ikago does not')
    print('Privacy services the bundle can reach:')
    for line in used:
        print(f'  {line}')
    for line in warnings:
        print(f'warning: {line}')
    for line in missing:
        print(f'CRASH: missing {line}')
    print('crash audit ' + ('FAIL' if missing else 'PASS') + f' missing={len(missing)} warnings={len(warnings)}')
    return 1 if missing else 0


if __name__ == '__main__':
    sys.exit(main())
