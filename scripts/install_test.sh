#!/bin/zsh
# Build Ikago Test and install it as /Applications/Ikago Test.app, beside the installed Ikago, which is never touched.
# It has the same app ID and signature, so it opens the same tabs, history, passwords and Keychain items without
# asking; because of that only one of the two can be open at a time. It never updates itself: run this again.
set -euo pipefail
cd "$(dirname "$0")/.."
target='/Applications/Ikago Test.app'
if pgrep -f "^$target/Contents/MacOS/Ikago" >/dev/null; then
    print -u2 'Ikago Test is open. Quit it, then run this again.'
    exit 1
fi
IKAGO_TEST_BUILD=1 python3 scripts/build.py --flavor release --jobs "${IKAGO_BUILD_JOBS:-4}"
built=build/Ikago.app
# Another signature would lose access to the shared data and Keychain items.
signature="$(codesign -dv --verbose=2 "$built" 2>&1)"
[[ "$signature" == *'Authority=Developer ID Application'* ]] || {
    print -u2 'Ikago Test needs the Developer ID certificate to share Ikago’s data; installation stopped.'
    exit 1
}
staging="$(mktemp -d /Applications/.ikago-test.XXXXXX)"
trap 'rm -rf "$staging"' EXIT
/usr/bin/ditto "$built" "$staging/Ikago Test.app"
[[ ! -d "$target" ]] || /usr/bin/trash "$target"
mv "$staging/Ikago Test.app" "$target"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$target"
print "Installed $target. Quit Ikago before opening it."
