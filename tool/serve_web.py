#!/usr/bin/env python3
"""Local-only browser smoke-test server with production isolation headers."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()


if __name__ == '__main__':
    root = Path(__file__).resolve().parent.parent / 'build' / 'web'
    ThreadingHTTPServer(('127.0.0.1', 8139), partial(Handler, directory=str(root))).serve_forever()
