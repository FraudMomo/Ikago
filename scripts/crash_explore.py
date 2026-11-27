#!/usr/bin/env python3
"""Crash explorer: random but replayable walks through Ikago's states, to find crashes that need a sequence of steps.

Each walk keeps a small model of the app (tabs, windows, Spaces, split, groups, full screen) and only takes steps
that make sense in its current state, leaning toward the edges where crashes live: 100 tabs, closing what another
step still uses, switching away and back. A walk is a list of Debug test driver actions (`TestDriver.swift`), run in a
debug build launched the way a person launches it (`open`, so macOS privacy checks apply to Ikago itself) with a
throwaway profile. A walk that ends in a new crash report, a hang or an early exit is saved with its seed; `--replay`
runs it again and `--minimize` shrinks it to the fewest steps that still crash the same way.

    python3 scripts/build.py --flavor debug
    python3 scripts/crash_explore.py --runs 20 --engine both          # explore
    python3 scripts/crash_explore.py --replay out/crash-explore/<run>.json --minimize

Windows appear while it runs; add --focus to include bringing Ikago forward and switching away (⌘Tab-like steps),
which takes focus from whatever you are doing. It never moves the pointer. Static causes (missing privacy keys) are
`check_crash_risks.py`'s job.
"""
import argparse
import functools
import http.server
import json
import os
import random
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT/'out/crash-explore'
REPORTS = Path.home()/'Library/Logs/DiagnosticReports'
MAX_TABS = 100  # Session.maxTabs
SITE = {
    'index.html': '<h1>Index</h1>' + ''.join(f'<p><a href="page{i}.html">Page {i}</a></p>' for i in range(5)),
    'long.html': '<h1>Long</h1>' + '<p>Text to scroll. ' * 3000,
    'form.html': '<form><input type=email name=email autocomplete=username><input type=password name=p>'
                 '<button>Next</button></form>',
    'heavy.html': '<script>for(let i=0;i<20000;i++){const d=document.createElement("div");d.textContent=i;'
                  'document.body.append(d)}</script>',
    'frames.html': ''.join(f'<iframe src="page{i}.html" width=200 height=120></iframe>' for i in range(6)),
    'redirect.html': '<script>let n=+(location.hash.slice(1)||0);if(n<20)setTimeout(()=>location.replace('
                     '"redirect.html#"+(n+1)),50)</script>Redirecting',
    'title.html': '<script>let i=0;setInterval(()=>document.title="Title "+(i++),30)</script>Busy title',
    'download.bin': 'x' * 200_000,  # served as application/octet-stream, so opening it downloads
    **{f'page{i}.html': f'<title>Page {i}</title><h1>Page {i}</h1><a href="index.html">Back</a>' for i in range(5)},
}
PAGES = list(SITE) + ['about:blank', 'ikago://history', 'ikago://settings', 'ikago://welcome', 'ikago://downloads',
                      'ikago://bookmarks', 'ikago://performance']
SETTINGS = ['general', 'appearance', 'toolbar', 'tabs', 'search', 'performance', 'extensions', 'history', 'security',
            'passwords', 'imports', 'about']


class Model:
    """What the walk believes the app looks like: enough to choose sensible steps, not a mirror of BrowserState."""
    def __init__(self, focus):
        self.tabs, self.windows, self.spaces, self.folders, self.closed = 1, 1, 1, 0, 0
        self.split = self.fullscreen = self.find = False
        self.focus = focus


def url(rng):
    page = rng.choice(PAGES)
    return page if ':' in page else '{site}/' + page


def steps():
    """(weight, allowed in this state, action maker, effect on the model)."""
    def tabs_effect(m, n): m.tabs = min(MAX_TABS, m.tabs + n)
    return [
        (8, lambda m: m.tabs < MAX_TABS, lambda m, r: f'new:{url(r)}', lambda m, a: tabs_effect(m, 1)),
        (2, lambda m: m.tabs < MAX_TABS, lambda m, r: f'tabs:{r.choice([10, 30, 60, 99])},{url(r)}',
         lambda m, a: tabs_effect(m, int(a.split(':')[1].split(',')[0]))),
        # Closing a window's last tab quits Ikago by design, and per-Space counts drift, so keep a spare tab.
        (7, lambda m: m.tabs > 2, lambda m, r: 'close', lambda m, a: (setattr(m, 'tabs', m.tabs - 1), setattr(m, 'closed', m.closed + 1))),
        (3, lambda m: m.closed > 0, lambda m, r: 'reopen', lambda m, a: (setattr(m, 'tabs', m.tabs + 1), setattr(m, 'closed', m.closed - 1))),
        (5, lambda m: m.tabs > 0, lambda m, r: f'open:{url(r)}', None),
        (5, lambda m: m.tabs > 1, lambda m, r: 'next', None),
        (4, lambda m: m.tabs > 1, lambda m, r: f'select:{r.randint(1, m.tabs)}', None),
        (3, lambda m: m.tabs > 0, lambda m, r: 'back', None),
        (3, lambda m: m.tabs > 0, lambda m, r: 'pin', None),
        (3, lambda m: m.tabs > 1 and not m.split, lambda m, r: 'split', lambda m, a: setattr(m, 'split', True)),
        (2, lambda m: m.split, lambda m, r: r.choice(['unsplit', 'unsplitall', 'separate']), lambda m, a: setattr(m, 'split', False)),
        (2, lambda m: m.split, lambda m, r: 'rotate', None),
        (2, lambda m: m.tabs > 1 and m.windows < 4, lambda m, r: 'movetowindow',
         lambda m, a: (setattr(m, 'windows', m.windows + 1), setattr(m, 'tabs', m.tabs - 1))),
        (2, lambda m: m.windows > 1, lambda m, r: 'closewindow', lambda m, a: setattr(m, 'windows', m.windows - 1)),
        (2, lambda m: m.spaces < 5, lambda m, r: f'space:Space {m.spaces + 1}|star|{r.choice([0, 1])}',
         lambda m, a: setattr(m, 'spaces', m.spaces + 1)),
        (3, lambda m: m.spaces > 1, lambda m, r: f'switchspace:{r.randint(1, m.spaces)}', None),
        (1, lambda m: m.spaces > 1, lambda m, r: f'deletespace:{r.randint(1, m.spaces)}', lambda m, a: setattr(m, 'spaces', m.spaces - 1)),
        (2, lambda m: m.spaces > 1 and m.tabs > 0, lambda m, r: f'tospace:{r.randint(1, m.spaces)}', None),
        (2, lambda m: m.tabs > 0, lambda m, r: f'folder:Group {m.folders + 1}', lambda m, a: setattr(m, 'folders', m.folders + 1)),
        (2, lambda m: m.folders > 0, lambda m, r: r.choice(['togglefolder', 'unfolder']), None),
        (3, lambda m: True, lambda m, r: r.choice(['sidebar', 'rail', 'layout:tabs', 'layout:sidebar']), None),
        (2, lambda m: True, lambda m, r: 'mode:' + r.choice(['light', 'dark', 'system']), None),
        (1, lambda m: True, lambda m, r: 'addressstyle:' + r.choice(['integrated', 'floating']), None),
        (1, lambda m: True, lambda m, r: 'fullscreen', lambda m, a: setattr(m, 'fullscreen', not m.fullscreen)),
        (2, lambda m: m.tabs > 0 and not m.find, lambda m, r: 'find:' + r.choice(['Page', 'Text', 'zzz']), lambda m, a: setattr(m, 'find', True)),
        (2, lambda m: m.find, lambda m, r: 'findclose', lambda m, a: setattr(m, 'find', False)),
        (2, lambda m: True, lambda m, r: r.choice(['palette', 'palette:new']), None),
        (2, lambda m: True, lambda m, r: 'palettequery:' + r.choice(['page', 'ikago', 'a', 'localhost']), None),
        (1, lambda m: True, lambda m, r: 'palettecommit', None),
        (2, lambda m: m.tabs > 0, lambda m, r: r.choice(['zoomin', 'mute', 'bookmark']), None),
        (2, lambda m: m.tabs > 0, lambda m, r: f'pagescroll:{r.choice([0, 0.5, 1])}', None),
        (1, lambda m: True, lambda m, r: 'page:' + r.choice(['history', 'bookmarks', 'downloads', 'performance', 'settings']), None),
        (1, lambda m: True, lambda m, r: r.choice(['downloads', 'settings', 'savepage', 'savepage:off', 'assistant:off']), None),
        (3, lambda m: m.focus, lambda m, r: f'apptoggle:{r.randint(1, 6)}', None),
        (2, lambda m: m.focus, lambda m, r: r.choice(['deactivate', 'activate']), None),
        # Prompts, popups, downloads, previews, Settings and memory pressure: the paths random tab work never reaches.
        (2, lambda m: m.tabs > 0, lambda m, r: 'ask:' + r.choice(['location', 'notifications']), None),
        (2, lambda m: True, lambda m, r: 'permission:' + r.choice(['block', 'dismiss']), None),
        (2, lambda m: m.tabs > 0 and m.tabs < MAX_TABS - 1, lambda m, r: f'popup:{url(r)}', lambda m, a: tabs_effect(m, 1)),
        (1, lambda m: m.tabs > 0, lambda m, r: 'open:{site}/download.bin', None),
        (1, lambda m: True, lambda m, r: r.choice(['downloads', 'downloads']), None),
        (2, lambda m: m.tabs > 0, lambda m, r: r.choice(['peek', f'peeklink:{url(r)}']), None),
        (1, lambda m: True, lambda m, r: 'settingscategory:' + r.choice(SETTINGS), None),
        (2, lambda m: m.tabs > 2, lambda m, r: 'pressure:' + r.choice(['warning', 'critical', 'normal']), None),
        (4, lambda m: True, lambda m, r: f'wait:{r.choice([0.1, 0.3, 1, 2])}', None),
    ]


def walk(seed, length, focus, imported=0):
    rng, model, actions = random.Random(seed), Model(focus), []
    table = steps()
    if imported:
        # Like the report: another browser's window imported (many tabs, groups, pinned), then ⌘Tab away and back.
        actions.append(f'importtabs:{imported},{{site}}/{rng.choice(["page1.html", "heavy.html", "frames.html", "long.html"])}')
        model.tabs, model.folders = min(MAX_TABS, 1 + imported), 1
        if focus:
            actions.append(f'apptoggle:{rng.randint(2, 6)}')
    while len(actions) < length:
        options = [s for s in table if s[1](model)]
        weight, _, make, effect = rng.choices(options, weights=[s[0] for s in options])[0]
        action = make(model, rng)
        actions.append(action)
        if effect:
            effect(model, action)
    return actions


def serve(folder):
    folder.mkdir(parents=True, exist_ok=True)
    for name, body in SITE.items():
        (folder/name).write_text(f'<!doctype html><meta charset=utf-8>{body}')
    class Quiet(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def handle(self):
            try:
                super().handle()
            except (BrokenPipeError, ConnectionResetError):
                pass  # a page closed mid-download: expected while walking
    handler = functools.partial(Quiet, directory=str(folder))
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return f'http://localhost:{server.server_address[1]}'


def reports():
    return {p: p.stat().st_mtime for p in REPORTS.glob('*.ips') if 'Ikago' in p.name}


def report_pid_matches(report, pid):
    """True when the report is for that process or one it started (a Chromium helper)."""
    for _ in range(20):  # ReportCrash may still be writing it
        try:
            body = json.loads(report.read_text(errors='replace').split('\n', 1)[1])
            return pid in (body.get('pid'), body.get('parentPid'), body.get('responsiblePid'))
        except (ValueError, IndexError):
            time.sleep(0.5)
    return True  # unreadable: keep it, the summary says so


def summarize(report):
    """One line saying how it died, plus a signature to tell crashes apart."""
    text = report.read_text(errors='replace')
    header, body = text.split('\n', 1)
    data, meta = json.loads(body), json.loads(header)
    exception = data.get('exception', {})
    termination = data.get('termination', {})
    images = data.get('usedImages', [])
    thread = next((t for t in data.get('threads', []) if t.get('triggered')), {})
    frames = []
    for frame in thread.get('frames', []):
        image = images[frame['imageIndex']].get('name', '?') if frame.get('imageIndex', -1) < len(images) else '?'
        if image.startswith(('libsystem_', 'libdyld', 'libdispatch', 'libxpc')):
            continue
        frames.append(f"{image}`{frame.get('symbol', hex(frame.get('imageOffset', 0)))}")
    reason = termination.get('namespace', '') + ' ' + ' '.join(termination.get('details', []) or [termination.get('indicator', '')])
    kind = exception.get('type', meta.get('bug_type', '?'))
    process = data.get('procName', report.name.split('-')[0])
    return {'report': str(report), 'process': process, 'kind': kind, 'reason': reason.strip()[:300],
            'frames': frames[:8], 'signature': f"{process}|{kind}|{'|'.join(frames[:3])}"}


def launch(app, profile, actions, site, timeout, focus, log):
    script = ';'.join(a.replace('{site}', site) for a in ['wait:1', 'pagekind'] + actions + ['wait:1', 'quit'])
    env = {'IKAGO_TEST_MODE': '1', 'IKAGO_TEST_PROFILE': str(profile), 'IKAGO_TEST_ACTIONS': script}
    for stale in (log, log.with_suffix('.err')):  # `open --stdout` appends: a replay must not read an earlier run
        stale.unlink(missing_ok=True)
    before, started = reports(), time.time()
    command = ['open', '-n', '-W', *([] if focus else ['-g']), '--stdout', str(log), '--stderr', str(log.with_suffix('.err'))]
    for key, value in env.items():
        command += ['--env', f'{key}={value}']
    process = subprocess.Popen(command + [str(app)])
    result = {'outcome': 'ok'}
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        result['outcome'] = 'hang'
        pids = subprocess.run(['pgrep', '-n', '-f', str(app/'Contents/MacOS/Ikago')], capture_output=True, text=True).stdout.split()
        if pids:
            sample = log.with_suffix('.sample.txt')
            subprocess.run(['sample', pids[0], '3', '-file', str(sample)], capture_output=True)
            result['sample'] = str(sample)
            subprocess.run(['kill', '-9', pids[0]])
        process.wait()
    output = log.read_text(errors='replace') if log.exists() else ''
    # An Address Sanitizer build (scripts/build.py --flavor asan) prints its finding to stderr and aborts.
    errors = log.with_suffix('.err').read_text(errors='replace') if log.with_suffix('.err').exists() else ''
    if 'ERROR: AddressSanitizer' in errors:
        finding = errors[errors.index('ERROR: AddressSanitizer'):].splitlines()
        result['asan'] = '\n'.join(finding[:40])
    ran = [line[len('IKTEST action '):] for line in output.splitlines() if line.startswith('IKTEST action ')]
    result['last_action'] = ran[-1] if ran else None
    kind = next((line.split() for line in output.splitlines() if line.startswith('IKTEST pagekind')), [])
    result['page'] = next((part.split('=', 1)[1] for part in kind if part.startswith('engine=')), kind[-1] if kind else None)
    if result['outcome'] == 'ok' and result['last_action'] != 'quit':
        # A normal quit (the last window closed) prints IKTEST exit; anything else ended the process from outside.
        result['outcome'] = 'quit by itself' if 'IKTEST exit' in output else 'killed'
    # Other agents and test suites may run Ikago at the same time: keep only reports from this launch's process
    # and its Chromium helpers. ReportCrash writes a report a few seconds after the process dies.
    pid = next((int(line.split()[-1]) for line in output.splitlines() if line.startswith('IKTEST pid ')), None)
    for _ in range(20 if result['outcome'] != 'ok' else 4):
        new = [p for p, mtime in reports().items() if p not in before and mtime >= started - 1
               and (pid is None or report_pid_matches(p, pid))]
        if new:
            break
        time.sleep(0.5)
    crashes = []
    for report in sorted(new):
        for _ in range(20):  # ReportCrash may still be writing it
            try:
                crashes.append(summarize(report))
                break
            except (ValueError, IndexError):
                time.sleep(0.5)
        else:
            crashes.append({'report': str(report), 'process': report.name.split('-')[0], 'kind': 'unreadable',
                            'reason': '', 'frames': [], 'signature': report.name.split('-')[0] + '|unreadable'})
    # ExcUserFault reports are faults macOS logged while the app kept running.
    fatal = [c for c in crashes if not Path(c['report']).name.startswith('ExcUserFault')]
    if fatal:
        result['outcome'] = 'crash'
    if 'asan' in result:
        result['outcome'] = 'memory error'
        crashes.insert(0, {'report': str(log.with_suffix('.err')), 'process': 'Ikago', 'kind': 'AddressSanitizer',
                           'reason': result['asan'].splitlines()[0][:300], 'frames': [l.strip() for l in result['asan'].splitlines()[1:9]],
                           'signature': 'asan|' + '|'.join(l.split(' in ')[-1].split(' ')[0] for l in result['asan'].splitlines()[1:4])})
    result['reports'] = crashes
    return result


def prepare_profile(app, engine, site, folder, timeout):
    """A pristine profile per engine; every walk starts from a copy of it."""
    pristine = folder/f'pristine-{engine}'
    if not pristine.exists():
        pristine.mkdir(parents=True)
        launch(app, pristine, [f'engine:{engine}', 'wait:1'], site, timeout, False, folder/f'setup-{engine}.log')
    return pristine


def run_once(app, engine, actions, site, folder, name, timeout, focus):
    pristine = prepare_profile(app, engine, site, folder, timeout)
    profile = folder/'profiles'/name
    shutil.rmtree(profile, ignore_errors=True)
    shutil.copytree(pristine, profile)
    result = launch(app, profile, actions, site, timeout, focus, folder/f'{name}.log')
    shutil.rmtree(profile, ignore_errors=True)
    runs_chromium = (result['page'] or '').lower() in ('chromium', 'cefwebtab')
    if result['page'] and runs_chromium != (engine == 'chromium'):
        print(f'  warning: {name} meant {engine} but Ikago ran {result["page"]}', flush=True)
    return result


def same_failure(result, expected):
    if expected['outcome'] != result['outcome']:
        return False
    if expected['outcome'] != 'crash':
        return True
    signatures = {r['signature'] for r in result['reports']}
    return any(r['signature'] in signatures for r in expected['reports'])


def minimize(app, run, site, folder, timeout, budget):
    """Delta debugging: drop chunks of steps while the walk still fails the same way."""
    actions, expected, tries = list(run['actions']), run['result'], 0
    chunks = 2
    while len(actions) >= 2 and tries < budget:
        size = max(1, len(actions) // chunks)
        shrunk = False
        for start in range(0, len(actions), size):
            candidate = actions[:start] + actions[start + size:]
            tries += 1
            result = run_once(app, run['engine'], candidate, site, folder, f'min-{run["seed"]}-{tries}', timeout, run['focus'])
            print(f'  minimize try {tries}: {len(candidate)} steps -> {result["outcome"]}', flush=True)
            if same_failure(result, expected):
                actions, shrunk = candidate, True
                chunks = max(chunks - 1, 2)
                break
            if tries >= budget:
                break
        if not shrunk:
            if size == 1:
                break
            chunks = min(len(actions), chunks * 2)
    return actions


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--app', default=str(ROOT/'build/debug/Ikago.app'))
    parser.add_argument('--runs', type=int, default=10)
    parser.add_argument('--steps', type=int, default=60)
    parser.add_argument('--seed', type=int, default=int(time.time()))
    parser.add_argument('--engine', choices=['webkit', 'chromium', 'both'], default='both')
    parser.add_argument('--timeout', type=int, default=0, help='seconds per walk (default: steps × 2 + 40)')
    parser.add_argument('--focus', action='store_true', help='include activating Ikago and switching away (takes focus)')
    parser.add_argument('--import', dest='imported', type=int, default=0,
                        help='start each walk by importing this many tabs (with groups, bookmarks, history)')
    parser.add_argument('--replay', help='a saved walk (.json) to run again')
    parser.add_argument('--minimize', action='store_true', help='with --replay: shrink it to the fewest failing steps')
    parser.add_argument('--budget', type=int, default=30, help='most relaunches --minimize may use')
    args = parser.parse_args()
    app = Path(args.app).resolve()
    if not app.exists():
        sys.exit(f'No app at {app}; build it with scripts/build.py --flavor debug')
    OUT.mkdir(parents=True, exist_ok=True)
    folder = OUT/'work'
    site = serve(folder/'site')
    timeout = args.timeout or args.steps * 2 + 40

    if args.replay:
        run = json.loads(Path(args.replay).read_text())
        result = run_once(app, run['engine'], run['actions'], site, folder, f'replay-{run["seed"]}', timeout, run['focus'])
        print(f'replay: {result["outcome"]} (was {run["result"]["outcome"]}), last step {result["last_action"]}')
        for report in result['reports']:
            print(f'  {report["process"]} {report["kind"]} {report["reason"]}\n    ' + '\n    '.join(report['frames']))
        if args.minimize and result['outcome'] != 'ok':
            run['result'] = result
            smallest = minimize(app, run, site, folder, timeout, args.budget)
            saved = Path(args.replay).with_suffix('.min.json')
            saved.write_text(json.dumps(run | {'actions': smallest}, indent=1))
            print(f'{len(smallest)} steps still fail: {saved}\n  ' + ';'.join(smallest))
        return

    engines = ['webkit', 'chromium'] if args.engine == 'both' else [args.engine]
    seen = {}
    for index in range(args.runs):
        seed, engine = args.seed + index, engines[index % len(engines)]
        actions = walk(seed, args.steps, args.focus, args.imported)
        result = run_once(app, engine, actions, site, folder, f'walk-{seed}', timeout, args.focus)
        line = f'walk {index + 1}/{args.runs} seed={seed} {engine}: {result["outcome"]}'
        if result['outcome'] not in ('ok', 'quit by itself'):
            run = {'seed': seed, 'engine': engine, 'focus': args.focus, 'actions': actions, 'result': result}
            saved = OUT/f'{result["outcome"].replace(" ", "-")}-{engine}-{seed}.json'
            saved.write_text(json.dumps(run, indent=1))
            key = next((r['signature'] for r in result['reports']), result['outcome'])
            seen.setdefault(key, []).append(str(saved))
            line += f' at "{result["last_action"]}" -> {saved.relative_to(ROOT)}'
            for report in result['reports']:
                line += f'\n    {report["process"]} {report["kind"]} {report["reason"][:160]}\n      ' + '\n      '.join(report['frames'][:5])
        print(line, flush=True)
    print(f'\n{len(seen)} distinct failure(s) in {args.runs} walks')
    for key, runs in seen.items():
        print(f'  {key}  ({len(runs)}×)  e.g. {runs[0]}')


if __name__ == '__main__':
    main()
