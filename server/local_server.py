"""Локальный сервер для разработки: python local_server.py [порт]

Данные — в файле rodquest_local.db рядом со скриптом. Коды из писем
печатаются в консоль и возвращаются в ответе (devCode).
"""

import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from rodquest_server.core import Api, http_call
from rodquest_server.mailer import PrintMailer
from rodquest_server.store_sqlite import SqliteStore

api = Api(SqliteStore(str(Path(__file__).with_name("rodquest_local.db"))), PrintMailer(), dev_codes=True)


class Handler(BaseHTTPRequestHandler):
    def _go(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n) if n else b""
        status, headers, out = http_call(api, self.command, dict(self.headers), body, self.client_address[0])
        self.send_response(status)
        for k, v in headers.items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    do_POST = do_OPTIONS = do_GET = _go


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8787
    print(f"Родквест: локальный сервер на http://0.0.0.0:{port}")
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
