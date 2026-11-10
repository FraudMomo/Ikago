#!/usr/bin/env python3
"""Loopback-only slow responses for browser progress and download integration checks."""
import base64
import http.server
import pathlib
import sys
import time
import urllib.parse

import cookie_fixture


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=sys.argv[1], **kwargs)

    def do_POST(self):
        if urllib.parse.urlsplit(self.path).path == '/security-http-probe':
            self.server.security_post_hits = getattr(self.server, 'security_post_hits', 0) + 1
        self.rfile.read(int(self.headers.get('Content-Length', '0')))
        self.send_response(200)
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
        if cookie_fixture.respond(self, path):
            return
        if path == '/security-post-count':
            body = str(getattr(self.server, 'security_post_hits', 0)).encode()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(body)
            return
        if path == '/security-redirect':
            self.send_response(302)
            self.send_header('Location', f'http://localhost:{self.server.server_address[1]}/security-tracker.svg')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        if path == '/security-worker.js':
            body = b"self.onmessage=async e=>{try{await fetch(e.data,{mode:'no-cors'});self.postMessage('loaded')}catch{self.postMessage('blocked')}}"
            self.send_response(200)
            self.send_header('Content-Type', 'text/javascript')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path == '/security-count':
            body = str(getattr(self.server, 'security_hits', 0)).encode()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(body)
            return
        if path in ['/security-tracker.svg', '/security-http-probe']:
            self.server.security_hits = getattr(self.server, 'security_hits', 0) + 1
            body = b'<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><rect width="8" height="8" fill="blue"/></svg>'
            self.send_response(200)
            self.send_header('Content-Type', 'image/svg+xml')
            self.end_headers()
            self.wfile.write(body)
            return
        if path.startswith('/download'):
            unknown = path.endswith('unknown')
            body = b'Ikago download fixture\n' * 1024
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Disposition', 'attachment; filename="fixture.bin"')
            if not unknown:
                self.send_header('Content-Length', str(len(body) * 80))
            self.end_headers()
            try:
                for _ in range(80):
                    self.wfile.write(body)
                    self.wfile.flush()
                    time.sleep(0.06)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        if path == '/slow-page':
            body = b'<!doctype html><title>Loading fixture</title><h1>Loading test</h1><img src="/slow-image">'
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path == '/slow-image':
            time.sleep(6)
            body = base64.b64decode('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7')
            self.send_response(200)
            self.send_header('Content-Type', 'image/gif')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        super().do_GET()


with http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler) as server:
    pathlib.Path(sys.argv[2]).write_text(str(server.server_port))
    server.serve_forever()
