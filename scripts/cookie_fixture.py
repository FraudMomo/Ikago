"""Cross-site cookie and storage fixture shared by the WebKit and Chromium check servers.

Open /cookie-set on one site (say localhost) as a top-level page, then frame /cookie-echo from another
site (127.0.0.1). The frame posts what it can see of the first site's state to its parent."""
import json

SET = b"""<!doctype html><title>Cookie set</title><script>
try { localStorage.setItem('ikago_tp', '1') } catch (e) {}
document.title = 'cookies set'
</script>"""


def respond(handler, path):
    if path == '/cookie-set':
        handler.send_response(200)
        handler.send_header('Content-Type', 'text/html')
        handler.send_header('Set-Cookie', 'ikago_secure=1; Path=/; SameSite=None; Secure')
        handler.send_header('Set-Cookie', 'ikago_none=1; Path=/; SameSite=None')
        handler.send_header('Content-Length', str(len(SET)))
        handler.end_headers()
        handler.wfile.write(SET)
        return True
    if path == '/cookie-echo':
        header = json.dumps(handler.headers.get('Cookie', ''))
        body = ("<!doctype html><script>let storage = null; try { storage = localStorage.getItem('ikago_tp') } catch (e) { storage = 'error' }"
                f"parent.postMessage({{ikagoCookies: true, header: {header}, cookie: document.cookie, storage}}, '*')</script>").encode()
        handler.send_response(200)
        handler.send_header('Content-Type', 'text/html')
        handler.send_header('Content-Length', str(len(body)))
        handler.end_headers()
        handler.wfile.write(body)
        return True
    return False
