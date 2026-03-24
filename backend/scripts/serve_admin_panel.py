#!/usr/bin/env python3

from __future__ import annotations

import argparse
import functools
import http.server
import socketserver
from pathlib import Path


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self) -> None:
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        super().end_headers()


class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True


def main() -> None:
    parser = argparse.ArgumentParser(description='Serve the admin panel with no-cache headers.')
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=5174)
    parser.add_argument('--directory', default='frontend/admin-panel')
    args = parser.parse_args()

    directory = Path(args.directory).resolve()
    handler = functools.partial(NoCacheHandler, directory=str(directory))

    with ReusableTCPServer((args.host, args.port), handler) as httpd:
        print(f'Admin panel server running on http://{args.host}:{args.port} -> {directory}')
        httpd.serve_forever()


if __name__ == '__main__':
    main()
