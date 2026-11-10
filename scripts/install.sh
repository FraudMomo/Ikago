#!/bin/zsh
# Build the release app and install it in /Applications. A running Ikago closes normally to save
# its session, then reopens. The previous copy goes to the Trash.
set -euo pipefail
cd "$(dirname "$0")/.."
# The auto updater passes a build it has already tested, and only runs while Ikago is closed.
if [[ -n "${IKAGO_INSTALL_SOURCE:-}" ]]; then
    built="$IKAGO_INSTALL_SOURCE"
else
    python3 scripts/build.py --flavor release --jobs "${IKAGO_BUILD_JOBS:-4}"
    built=build/Ikago.app
fi
[[ -s "$built/Contents/Resources/IkagoAppIcon.icns" ]] || {
    print -u2 'The app icon was not packaged; installation stopped.'
    exit 1
}
swift_cache="$PWD/out/ModuleCache"
staging="$(mktemp -d /Applications/.ikago-install.XXXXXX)"
trap 'rm -rf "$staging"' EXIT
/usr/bin/ditto "$built" "$staging/Ikago.app"
was_running=stopped
[[ -n "${IKAGO_INSTALL_SOURCE:-}" ]] || was_running="$(swift -module-cache-path "$swift_cache" scripts/refresh-dock.swift --prepare)"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [[ -d /Applications/Ikago.app ]]; then
    "$lsregister" -u /Applications/Ikago.app
    if [[ -n "${IKAGO_INSTALL_SOURCE:-}" ]]; then
        mv /Applications/Ikago.app "$staging/previous.app"  # a routine update shouldn't fill the Trash
    else
        /usr/bin/trash /Applications/Ikago.app
    fi
fi
mv "$staging/Ikago.app" /Applications/Ikago.app
/usr/bin/touch /Applications/Ikago.app
"$lsregister" -f /Applications/Ikago.app
if [[ -z "${IKAGO_INSTALL_SOURCE:-}" ]]; then
    swift -module-cache-path "$swift_cache" scripts/refresh-dock.swift
    # Reload the changed tile and icon, including tiles shown while Ikago is closed.
    /usr/bin/killall Dock 2>/dev/null || true
    python3 scripts/auto_update.py --install-agent
    [[ "$was_running" != running ]] || open /Applications/Ikago.app
fi
print 'Installed /Applications/Ikago.app'
