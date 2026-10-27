"""Точка входа Yandex Cloud Functions: index.handler.

Функция вызывается напрямую по HTTPS (https://functions.yandexcloud.net/<id>),
все запросы — POST с JSON. Таблицы в YDB создаются при первом запуске.
"""

import base64

from rodquest_server.core import Api, http_call
from rodquest_server.mailer import SmtpMailer

_api = None


def _get_api():
    global _api
    if _api is None:
        from rodquest_server.store_ydb import YdbStore

        store = YdbStore()
        store.create_tables()
        _api = Api(store, SmtpMailer())
    return _api


def handler(event, context):
    method = (event or {}).get("httpMethod", "POST")
    headers = (event or {}).get("headers") or {}
    raw = (event or {}).get("body") or ""
    if (event or {}).get("isBase64Encoded"):
        body = base64.b64decode(raw)
    else:
        body = raw.encode("utf-8") if isinstance(raw, str) else raw
    ip = ((event or {}).get("requestContext") or {}).get("identity", {}).get("sourceIp", "")
    if method == "OPTIONS":
        status, out_headers, out = http_call(None, method, headers, body, ip)
    else:
        status, out_headers, out = http_call(_get_api(), method, headers, body, ip)
    return {
        "statusCode": status,
        "headers": out_headers,
        "body": out.decode("utf-8"),
        "isBase64Encoded": False,
    }
