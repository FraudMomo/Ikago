---
name: ikago-verify
description: Build Ikago and check a change for real - the Debug test driver, window screenshots of the UI, Chromium checks, fuzz checks and crash walks. Use after changing Ikago's code, before saying a change works.
---

# Verify a change in Ikago

Pick the checks that cover what you changed. Measure; don't claim a fix from reading code.

## Build

```bash
python3 scripts/build.py --flavor debug      # test driver, fuzz checks (build/debug/Ikago.app)
python3 scripts/build.py --flavor checks     # Chromium runtime checks
python3 scripts/build.py --flavor asan       # Address Sanitizer, WebKit pages only
```

## Test driver (debug builds)

Launch with `open`, never by running the binary from a shell: a shell launch takes the terminal's macOS permissions
and hides privacy crashes. Steps are separated by `;`, so a step's own text can't contain one.

```bash
L=$(mktemp -d)/run.log
open -n -W -g --env IKAGO_TEST_MODE=1 --env "IKAGO_TEST_ACTIONS=wait:3;dump;quit" --stdout "$L" --stderr "$L" build/debug/Ikago.app
grep -a IKTEST "$L"
```

- Results are `IKTEST …` lines. Checks end with `IKTEST <name> PASS|FAIL`. Use `grep -a`, because logs hold binary
  data.
- Every step is a `case` in `Ikago/Checks/Debug/Driver/TestDriver*.swift`. Read the switch to find one; area checks
  are named `<area>checks` (for example `outlinechecks`, `findchecks`, `importchecks`, `windowchecks`).
- Test mode uses in-memory website data and a temporary session, and never touches the person's profile.
- `-g` keeps Ikago in the background. Never take focus or move the mouse while the person may be using the Mac.
- Another session may run Ikago at the same time. Don't kill other copies, and match logs to your own launch.

## Look at the UI

For any visible change, save screenshots and look at them before handing over:

```text
IKAGO_TEST_ACTIONS=wait:3;<steps that reach the state>;windowshot:/path/shot.png;quit
```

Then read the PNG. `pageshot`, `corners:<png>` and `railpoint:<y>,<prefix>` cover special cases. A locked screen
gives blank shots.

## Chromium

```bash
python3 scripts/build.py --flavor checks && python3 scripts/run_chromium_checks.py
```

It must end with every check passing and no visible Chromium window.

## Crashes and outside data

- The fuzz checks: `parserfuzzchecks` (import and extension files) and `mediaparserchecks` (X's video).
- Random walks: `python3 scripts/crash_explore.py --runs 10 --engine both`. A failing walk is saved; shrink it with
  `--replay <walk.json> --minimize`. `--focus` switches apps (takes focus), so ask first. `--import 97` starts from
  a large import.
- `python3 scripts/check_crash_risks.py` audits the `Info.plist` privacy keys.

## Hand over

Build Ikago Test for the person to try: `zsh scripts/install_test.sh` (run it in the background; it refuses while
Ikago Test is open).
