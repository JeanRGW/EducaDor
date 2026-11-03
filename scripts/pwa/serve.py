#!/usr/bin/env python3
"""Local-only Pages-like header/SPA server for shell smoke tests (not production)."""
import fnmatch
import http.server
import pathlib
import sys
from urllib.parse import urlsplit

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else 'build/web').resolve()
RULES = []
for line in (ROOT / '_headers').read_text().splitlines():
    if not line.strip():
        continue
    if not line.startswith(' '):
        RULES.append((line.strip(), {}))
    else:
        name, value = line.strip().split(':', 1)
        RULES[-1][1][name] = value.strip()


class Handler(http.server.SimpleHTTPRequestHandler):
    requested_path = '/'

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def log_message(self, *args):
        pass  # Never record bearer navigation URLs.

    def send_head(self):
        self.requested_path = urlsplit(self.path).path
        target = pathlib.Path(self.translate_path(self.path))
        if not target.exists():
            self.path = '/index.html'
        return super().send_head()

    def end_headers(self):
        headers = {}
        for pattern, values in RULES:
            if fnmatch.fnmatch(self.requested_path, pattern):
                headers.update(values)
        for name, value in headers.items():
            self.send_header(name, value)
        super().end_headers()


http.server.ThreadingHTTPServer(('127.0.0.1', 8773), Handler).serve_forever()
