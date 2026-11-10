#!/bin/zsh
# Build and run deterministic feature checks without using the personal profile.
set -euo pipefail
cd "$(dirname "$0")/.."
work="$(mktemp -d)"
server_pid=""
cleanup() {
    if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; fi
    rm -rf "$work"
}
trap cleanup EXIT
mkdir -p "$work/fixtures"
cat > "$work/fixtures/index.html" <<'HTML'
<!doctype html><title>Ikago fixture</title><link rel="icon" href="/icon.svg"><h1>Browser feature fixture</h1>
HTML
cat > "$work/fixtures/icon.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><rect width="32" height="32" fill="green"/></svg>
SVG
cat > "$work/fixtures/focus.html" <<'HTML'
<!doctype html><title>New tab focus fixture</title><input id="site-focus" autofocus><script>addEventListener('load', () => setTimeout(() => document.getElementById('site-focus').focus(), 100));</script>
HTML
cat > "$work/fixtures/links.html" <<'HTML'
<!doctype html><title>Link fixture</title><style>a,button{display:block;margin:30px;padding:15px}</style>
<a id="normal" href="/middle-target"><span>Middle click link</span></a>
<a id="blank" href="/middle-blank" target="_blank">Blank link</a>
<button id="popup" onclick="window.open('/popup.html','ikago-popup-fixture')">Popup</button>
HTML
cat > "$work/fixtures/login.html" <<'HTML'
<!doctype html><title>Login fixture</title><style>input{display:block;margin:12px;width:220px}</style>
<form id="signin"><input id="username" name="username" autocomplete="username"><input id="password" type="password"></form>
<form id="step"><input id="identifier" type="email" name="identifier"></form>
<form id="news"><input id="newsletter-name" name="name"><input id="newsletter-email" type="email" name="email"></form>
<input id="search" type="search" name="user-search">
HTML
for fixture in middle-target middle-blank popup.html; do
    print '<!doctype html><title>Target fixture</title><h1>Target</h1>' > "$work/fixtures/$fixture"
done
python3 scripts/browser-fixture-server.py "$work/fixtures" "$work/port" > "$work/server.log" 2>&1 &
server_pid=$!
for attempt in {1..100}; do
    [[ -s "$work/port" ]] && break
    sleep 0.05
done
port="$(cat "$work/port")"
python3 scripts/build.py --flavor debug --jobs 4 > /dev/null
IKAGO_TEST_MODE=1 IKAGO_TEST_AUTO_APPROVE=1 IKAGO_TEST_PROFILE="$work/profile" \
IKAGO_TEST_ACTIONS="open:http://127.0.0.1:$port/;wait:2;new:http://127.0.0.1:$port/?second;wait:2;chromechecks;featurechecks;importchecks;storebridgechecks;downloadchecks:http://127.0.0.1:$port;tabanimationchecks;securitychecks:http://127.0.0.1:$port;privacychecks:http://127.0.0.1:$port;defaultbrowserchecks;autocompletechecks;tabplacementchecks;middleclickchecks:http://127.0.0.1:$port;passwordautofillchecks:http://127.0.0.1:$port;newtabfocuschecks:http://127.0.0.1:$port;topbarpolishchecks:http://127.0.0.1:$port;taboverflowchecks;sizingchecks;quit" \
    "build/debug/Ikago.app/Contents/MacOS/Ikago" > "$work/checks.log" 2>&1
# Split fixtures exercise native pane controls in a separate window/profile so their
# temporary tab/session state cannot influence the long-running chrome geometry fixtures.
IKAGO_TEST_MODE=1 IKAGO_TEST_PROFILE="$work/split-profile" \
IKAGO_TEST_ACTIONS="glass:off;page:settings;wait:1;engine:chromium;wait:1;engine:webkit;wait:1;glass:on;wait:1;engine:chromium;wait:1;engine:webkit;wait:1;downloadpopupchecks;extensionstoragechecks;faviconstabilitychecks;sidebarinteractionchecks;tabreorderingchecks;essentialschecks;bookmarknavigationchecks;protectedaddresschecks;bookmarkbarchecks;topbarlayoutchecks;splitinteractionchecks;quit" \
    "build/debug/Ikago.app/Contents/MacOS/Ikago" >> "$work/checks.log" 2>&1
IKAGO_TEST_MODE=1 IKAGO_TEST_PROFILE="$work/background-profile" \
IKAGO_TEST_ACTIONS="backgroundtabchecks:http://127.0.0.1:$port;quit" \
    "build/debug/Ikago.app/Contents/MacOS/Ikago" >> "$work/checks.log" 2>&1
# Website data across a relaunch: two processes sharing one disposable store identifier.
storage_uuid="$(uuidgen)"
for phase in write read; do
    IKAGO_TEST_MODE=1 IKAGO_TEST_STORAGE_UUID="$storage_uuid" IKAGO_TEST_PROFILE="$work/persistence-$phase" \
    IKAGO_TEST_ACTIONS="wait:2;datapersistencechecks:$phase|http://127.0.0.1:$port;quit" \
        "build/debug/Ikago.app/Contents/MacOS/Ikago" >> "$work/checks.log" 2>&1
done
cat "$work/checks.log"
if ! grep -q 'featurechecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'chromechecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'importchecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'splitinteractionchecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'backgroundtabchecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'downloadpopupchecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'extensionstoragechecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'faviconstabilitychecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'sidebarinteractionchecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'tabreorderingchecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'essentialschecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'bookmarknavigationchecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'bookmarkbarchecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'topbarlayoutchecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'protectedaddresschecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'tabanimationchecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'securitychecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'privacychecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'defaultbrowserchecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'autocompletechecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'tabplacementchecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'middleclickchecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'passwordautofillchecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'topbarpolishchecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'newtabfocuschecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'taboverflowchecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'sizingchecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'importaccesschecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'tabgroupchecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'downloadchecks PASS failures=0' "$work/checks.log" \
    || ! grep -q 'datapersistencechecks write PASS failures=0' "$work/checks.log" \
    || ! grep -q 'datapersistencechecks read PASS failures=0' "$work/checks.log" \
    || ! grep -q 'pass = 1' "$work/checks.log" \
    || grep -q 'IKTEST.*FAIL' "$work/checks.log"; then
    grep -E 'IKTEST.*(FAIL|failures=[1-9])' "$work/checks.log" >&2 || true
    print -u2 'Browser feature checks failed (a suite above failed, or one did not report).'
    exit 1
fi
print 'All browser feature checks passed.'
