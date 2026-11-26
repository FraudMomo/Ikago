#!/bin/zsh
# A hands-on demo of passwords, autofill and agents: a debug build of Ikago on a throwaway profile (its own session,
# passwords, cards, website data and agent port), filled with sample data, opened on a local demo site.
# Your Ikago and Ikago Test are never touched, and both can stay open. Quit the demo (⌘Q) to throw it all away.
#   scripts/demo.sh             WebKit
#   scripts/demo.sh --chromium  Chromium
#   --no-build                  reuse the last debug build
set -euo pipefail
cd "$(dirname "$0")/.."
engine="" build=1
for arg in "$@"; do
    case $arg in
        --chromium) engine=",chromium" ;;
        --no-build) build=0 ;;
        *) print -u2 "Unknown option $arg"; exit 2 ;;
    esac
done
work="$(mktemp -d "${TMPDIR:-/tmp}/ikago-demo.XXXXXX")"
server_pid=""
cleanup() {
    [[ -z "$server_pid" ]] || kill "$server_pid" 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT INT TERM
(( build )) && { print 'Building the debug app…'; python3 scripts/build.py --flavor debug --jobs 4 > "$work/build.log" 2>&1 || { tail -30 "$work/build.log"; exit 1; } }
mkdir -p "$work/profile"
python3 scripts/demo/demo_server.py scripts/demo/site "$work/port" "$work/profile" > "$work/server.log" 2>&1 &
server_pid=$!
for _ in {1..100}; do [[ -s "$work/port" ]] && break; sleep 0.05; done
port="$(cat "$work/port")"
print "Demo site: http://ikago-demo.localhost:$port/  (quit the demo app to end)"
IKAGO_TEST_MODE=1 IKAGO_TEST_PROFILE="$work/profile" IKAGO_TEST_ACTIONS="demo:$port$engine" \
    build/debug/Ikago.app/Contents/MacOS/Ikago > "$work/app.log" 2>&1 || true
print 'Demo closed; its profile was deleted.'
