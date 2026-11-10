#!/usr/bin/env python3
"""Run the Chromium integration checks on loopback, on a disposable profile, with every window hidden."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import os
import shutil
import signal
import subprocess
import threading
import tempfile
import ssl
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
import cookie_fixture  # noqa: E402


class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()
    def do_GET(self):
        if cookie_fixture.respond(self, self.path.split('?')[0]): return
        if self.path == '/download':
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Disposition', 'attachment; filename="cef-fixture.txt"')
            self.send_header('Content-Length', '4096')
            self.end_headers()
            self.wfile.write(b'x' * 4096)
        else: super().do_GET()
    def log_message(self, *_args): pass


def main():
    handler = partial(Handler, directory=ROOT/'scripts/fixtures')
    server = ThreadingHTTPServer(('127.0.0.1', 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    log = ROOT/'out/cef-smoke.log'
    try:
        # IKAGO_CEF_SMOKE_PARENT puts the disposable profile elsewhere, such as inside protected storage
        # with a team-signed build, to prove Chromium's helpers can work there.
        parent = Path(os.environ.get('IKAGO_CEF_SMOKE_PARENT', str(ROOT/'out')))
        with tempfile.TemporaryDirectory(prefix='ikago-cef-smoke-', dir=parent) as profile:
            key, cert = Path(profile)/'key.pem', Path(profile)/'cert.pem'
            subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(cert),'-days','1','-subj','/CN=localhost'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
            tls = ThreadingHTTPServer(('127.0.0.1',0), handler)
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.load_cert_chain(cert,key)
            tls.socket = context.wrap_socket(tls.socket,server_side=True)
            tls_thread = threading.Thread(target=tls.serve_forever,daemon=True)
            tls_thread.start()
            try:
                run_launches(profile,server,log,tls.server_port)
            finally:
                tls.shutdown();tls.server_close();tls_thread.join()
        print(log.read_text())
        if log.read_text().count('CEF_SMOKE_SHUTDOWN_OK') != 2: raise SystemExit('Restart fixture did not finish both launches')
        if 'CEF_PASSWORDS_OK' not in log.read_text(): raise SystemExit('Password key fixture did not pass')
        if 'CEF_COOKIE_ISOLATION_OK' not in log.read_text(): raise SystemExit('Cookie isolation fixture did not pass')
    finally:
        server.shutdown(); server.server_close(); thread.join()


def run_launches(profile, server, log, tls_port):
    app = Path(os.environ.get('IKAGO_APP_PATH', str(ROOT/'build/checks/Ikago.app')))
    for reading in (False, True):
        with log.open('a' if reading else 'w') as output:
            args = [str(app/'Contents/MacOS/Ikago'), '--cef-smoke',
                f'http://127.0.0.1:{server.server_port}/', '--cef-smoke-root', profile,
                '--cef-smoke-untrusted-url', f'https://127.0.0.1:{tls_port}/']
            if reading: args.append('--cef-smoke-read')
            if not reading and os.environ.get('IKAGO_CEF_SAFE_BROWSING_PROBE') == '1':
                args.append('--cef-smoke-safe-browsing')
            child = subprocess.Popen(args, stdout=output, stderr=subprocess.STDOUT,
                start_new_session=True, env=dict(os.environ, IKAGO_CEF_FIXTURE_PROFILE=str(Path(profile)/'Shell')))
            try: code = child.wait(timeout=300 if '--cef-smoke-safe-browsing' in args else 120)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL); child.wait(); code = 124
        if code:
            # Chromium's own reason for aborting is here; the profile is about to be deleted.
            chromium_log = Path(profile)/'cef.log'
            if chromium_log.exists():
                shutil.copy(chromium_log, ROOT/'out/cef-last-failure.log')
            print(log.read_text())
            raise SystemExit(code)


if __name__ == '__main__': main()
