#!/usr/bin/env python3
"""The demo site for scripts/demo.sh, on this Mac only (127.0.0.1 and ::1), and a scripted demo agent.

Usage: demo_server.py <site folder> <port file> <profile folder>

Form posts are read and dropped, then redirected to the page they name, so sign-ins and checkouts "go through" without
keeping anything. POST /agent/start runs the demo agent against the demo Ikago's own agent server (its address and token
are in <profile>/demo-agent.json, written by the app's demo action); GET /agent/log is what it has done so far.
"""
import http.server
import json
import pathlib
import socket
import sys
import threading
import time
import urllib.request

SITE, PORT_FILE, PROFILE = map(pathlib.Path, sys.argv[1:4])
log_lock = threading.Lock()
agent = {'running': False, 'lines': []}


def note(kind, text):
    with log_lock:
        agent['lines'].append([kind, text])


class Agent:
    """A few MCP tool calls in a row, as Claude Code or Codex would send them."""

    def __init__(self):
        info = json.loads((PROFILE / 'demo-agent.json').read_text())
        self.endpoint, self.token, self.id = info['endpoint'], info['token'], 0
        self.rpc('initialize', {'protocolVersion': '2025-06-18', 'clientInfo': {'name': 'Demo Agent'}})

    def rpc(self, method, params):
        self.id += 1
        body = json.dumps({'jsonrpc': '2.0', 'id': self.id, 'method': method, 'params': params}).encode()
        request = urllib.request.Request(self.endpoint, body, {'Authorization': 'Bearer ' + self.token,
                                                              'Content-Type': 'application/json'})
        with urllib.request.urlopen(request, timeout=200) as response:  # an approval waits up to two minutes
            return json.load(response).get('result', {})

    def call(self, name, **arguments):
        result = self.rpc('tools/call', {'name': name, 'arguments': arguments})
        text = '\n'.join(c.get('text', '') for c in result.get('content', []) if c.get('type') == 'text')
        return text, bool(result.get('isError'))


def ref(outline, name):
    for line in outline.splitlines():
        if f'"{name}"' in line and '[' in line:
            return line[line.index('[') + 1:line.index(']')]
    return None


def first(text, lines=2):
    return '\n'.join(text.strip().splitlines()[:lines]) or '(nothing changed)'


def scenario():
    a = Agent()
    tabs, _ = a.call('tabs')
    line = next((l for l in tabs.splitlines() if 'agent.html' in l), None)
    if not line:
        return note('', 'Open the Demo Shop page first.')
    tab = line.split(' ', 1)[0]
    note('', f'Driving your tab {tab}.')
    a.call('tab_use', tab=tab)
    time.sleep(1)
    outline, _ = a.call('outline', tab=tab, all=True)
    secret = [l.strip() for l in outline.splitlines() if 'hidden from agents' in l or 'the person fills' in l or 'password "' in l]
    note('refused', 'What the agent sees of the secret fields:\n' + ('\n'.join(secret) or '(none found)'))

    def step(kind, title, name, *args, **extra):
        r = ref(outline, name)
        if not r:
            return note('', f'{title}: no "{name}" on the page')
        if kind == 'ask':
            note('ask', f'{title}… (Ikago should ask you)')
        else:
            note('', title + '…')
        text, failed = a.call(*args, tab=tab, ref=r, **extra)
        verdict = 'refused' if failed else 'done'
        note(verdict, ('✕ ' if failed else '✓ ') + first(text))
        time.sleep(1.2)

    step('', 'Searching for running shoes (no prompt)', 'Search', 'type', text='running shoes', submit=True)
    step('', 'Next page (no prompt)', 'Next page', 'click')
    step('', 'Typing a password', 'Password', 'type', text='hunter2')
    step('', 'Typing a card number', 'Card number', 'type', text='4000 0000 0000 0002')
    step('', 'Pressing keys into the security code', 'Security code', 'press', key='4')
    step('ask', 'Buying the shoes', 'Buy now', 'click')
    step('ask', 'Posting a review with Return', 'Your review', 'type', text='Great shoes', submit=True)
    step('ask', 'Deleting the account', 'Delete account', 'click')
    note('done', 'Finished. Press Start again to see what “Allow on site” remembered.')


def run_agent():
    try:
        scenario()
    except Exception as error:  # shown on the page; the demo keeps going
        note('refused', f'The demo agent stopped: {error}')
    finally:
        agent['running'] = False


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(SITE), **kwargs)

    def log_message(self, *args):
        pass

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def do_GET(self):
        if self.path == '/agent/log':
            with log_lock:
                body = json.dumps(agent).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()

    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', '0')))  # dropped: nothing is kept
        if self.path == '/agent/start':
            with log_lock:
                if not agent['running']:
                    agent.update(running=True, lines=[])
                    threading.Thread(target=run_agent, daemon=True).start()
            self.send_response(204)
            self.end_headers()
            return
        self.send_response(303)
        self.send_header('Location', self.path)
        self.send_header('Content-Length', '0')
        self.end_headers()


class Server4(http.server.ThreadingHTTPServer):
    daemon_threads = True


class Server6(Server4):
    address_family = socket.AF_INET6

    def server_bind(self):
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
        super().server_bind()


def main():
    # Two free ports in a row: the site's, and the demo Ikago's agent server's (port + 1).
    for _ in range(50):
        v4 = Server4(('127.0.0.1', 0), Handler)
        port, v6 = v4.server_address[1], None
        try:
            v6 = Server6(('::1', port), Handler)
            probe = socket.socket()
            probe.bind(('127.0.0.1', port + 1))
            probe.close()
            break
        except OSError:
            v4.server_close()
            if v6:
                v6.server_close()
    else:
        sys.exit('No free port for the demo.')
    threading.Thread(target=v6.serve_forever, daemon=True).start()
    PORT_FILE.write_text(str(port))
    v4.serve_forever()


if __name__ == '__main__':
    main()
