"""Static file server for the comp-review-ui single page application.

Serves the Angular build folder. Paths that are not files fall back to index.html, so the
Angular router handles deep links such as /jobs/<id>. index.html and config.json are sent
with no-cache, so a changed config.json takes effect on the next page load.

Usage: python spa_server.py --root /app/webui --port 12101 [--host 0.0.0.0]
"""

from __future__ import annotations

import argparse
import functools
import os
import posixpath
import urllib.parse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

NO_CACHE = {"/", "/index.html", "/config.json"}


class SpaHandler(SimpleHTTPRequestHandler):
    def _path_only(self) -> str:
        return posixpath.normpath(urllib.parse.urlsplit(self.path).path) or "/"

    def send_head(self):  # noqa: D401 - http.server hook
        local = self.translate_path(self.path)
        if not os.path.exists(local):
            # Unknown path: let the Angular router handle it.
            self.path = "/index.html"
        return super().send_head()

    def end_headers(self) -> None:
        path = self._path_only()
        if path in NO_CACHE or not os.path.splitext(path)[1]:
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("X-Content-Type-Options", "nosniff")
        super().end_headers()

    def log_message(self, fmt: str, *args) -> None:
        print(f"webui {self.address_string()} {fmt % args}", flush=True)


def main() -> None:
    p = argparse.ArgumentParser(description="Serve the comp-review-ui build with SPA fallback.")
    p.add_argument("--root", required=True, help="Folder that holds index.html.")
    p.add_argument("--host", default="0.0.0.0")
    p.add_argument("--port", type=int, default=12101)
    args = p.parse_args()

    handler = functools.partial(SpaHandler, directory=args.root)
    with ThreadingHTTPServer((args.host, args.port), handler) as httpd:
        print(f"comp-review-ui serving {args.root} on http://{args.host}:{args.port}", flush=True)
        httpd.serve_forever()


if __name__ == "__main__":
    main()
