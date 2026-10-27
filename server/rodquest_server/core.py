"""Родквест — сервер синхронизации семьи (v0.8) и гильдий (v0.9).

Один HTTP-адрес, все запросы — POST с JSON {"op": "...", ...}.
Устройство авторизуется заголовком `X-Rodquest-Token: <token>` (заголовок
Authorization в Yandex Cloud Functions занят: шлюз проверяет его как IAM-токен).

Данные гильдии — набор сущностей «ключ → JSON» (герой, цель, запись ленты…).
Каждое изменение получает номер ревизии гильдии: устройство забирает всё, что
новее его последней ревизии (pull), и отправляет свои изменения с ревизией, от
которой оно их сделало (push). Если сущность за это время поменял кто-то ещё —
сервер возвращает конфликт и свежую версию, устройство сливает правки и
отправляет снова.

Видимость (scope) сущности:
  all              — видят все устройства гильдии;
  adults           — только устройства взрослых (бюджет, PIN родителя);
  private:<heroId> — только устройства, на которых играет этот герой.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import re
import secrets
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Optional

API_VERSION = 2

# Коды приглашения: без похожих символов (0/O, 1/I/L).
CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
CODE_LEN = 8
INVITE_TTL_MS = 48 * 3600 * 1000

EMAIL_CODE_TTL_MS = 15 * 60 * 1000
EMAIL_CODE_ATTEMPTS = 5

MAX_CHANGES = 500
MAX_KEY = 200
MAX_DATA = 64 * 1024
PULL_LIMIT = 500
MAX_NAME = 60
MAX_HEROES = 16

ROLES = ("adult", "kid")
KEY_RE = re.compile(r"^[a-z]{2,12}/[A-Za-z0-9_\-.:|]{1,180}$")
EMAIL_RE = re.compile(r"^[^@\s]{1,64}@[^@\s]{1,190}\.[^@\s]{2,}$")


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message


def now_ms() -> int:
    return int(time.time() * 1000)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def hash_code(code: str, salt: str) -> str:
    return hashlib.sha256(f"{salt}:{code}".encode()).hexdigest()


def new_id(n: int = 12) -> str:
    return secrets.token_urlsafe(n)[:n].replace("-", "a").replace("_", "b")


def new_invite_code() -> str:
    return "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LEN))


def normalize_code(raw: str) -> str:
    return re.sub(r"[^A-Za-z0-9]", "", raw or "").upper()


def normalize_email(raw: str) -> str:
    return (raw or "").strip().lower()


def mask_email(email: str) -> str:
    name, _, domain = email.partition("@")
    if len(name) <= 2:
        shown = name[:1] + "*"
    else:
        shown = name[0] + "*" * (len(name) - 2) + name[-1]
    return f"{shown}@{domain}"


def visible(scope: str, device: dict) -> bool:
    if scope == "all":
        return True
    if scope == "adults":
        return device["role"] == "adult"
    if scope.startswith("private:"):
        return scope[len("private:"):] in device["hero_ids"]
    return False


def valid_scope(scope: Any) -> bool:
    return isinstance(scope, str) and (
        scope in ("all", "adults") or (scope.startswith("private:") and 8 < len(scope) <= 100)
    )


@dataclass
class Change:
    key: str
    data: Optional[str]  # JSON-строка; None — удалить
    base: int
    scope: str


@dataclass
class Row:
    key: str
    rev: int
    data: Optional[str]
    scope: str


@dataclass
class PushPlan:
    writes: list = field(default_factory=list)  # list[Row]
    results: list = field(default_factory=list)
    new_rev: int = 0


def plan_push(guild_rev: int, changes: list, current: dict, device: dict) -> PushPlan:
    """Чистая функция: какие изменения записать и что ответить устройству.

    current — ключ → Row (текущее состояние на сервере).
    """
    plan = PushPlan(new_rev=guild_rev)
    kid = device["role"] != "adult"
    for ch in changes:
        cur = current.get(ch.key)
        if kid and (ch.scope == "adults" or (cur is not None and cur.scope == "adults")):
            plan.results.append({"k": ch.key, "denied": True})
            continue
        if cur is not None and cur.rev > ch.base:
            res = {"k": ch.key, "conflict": True, "r": cur.rev}
            if visible(cur.scope, device):
                res["d"] = cur.data
                res["s"] = cur.scope
            else:
                res["d"] = None
                res["s"] = cur.scope
            plan.results.append(res)
            continue
        if ch.data is None and (cur is None or cur.data is None):
            plan.results.append({"k": ch.key, "ok": True, "r": cur.rev if cur else 0})
            continue
        if cur is not None and cur.data == ch.data and cur.scope == ch.scope:
            plan.results.append({"k": ch.key, "ok": True, "r": cur.rev})
            continue
        plan.new_rev += 1
        plan.writes.append(Row(ch.key, plan.new_rev, ch.data, ch.scope))
        plan.results.append({"k": ch.key, "ok": True, "r": plan.new_rev})
    return plan


# v0.9: гильдия — союз семей, кланов и одиночек (см. alliance.py).
# Импорт здесь, после общих помощников: alliance.py берёт их из этого модуля.
from .alliance import AllianceOps  # noqa: E402


class Mailer:
    """Отправка писем. В проде — SMTP (см. mailer.py)."""

    def send_code(self, email: str, code: str, purpose: str) -> None:  # pragma: no cover
        raise ApiError(503, "mail_off", "Отправка писем не настроена на сервере")


class Api(AllianceOps):
    def __init__(self, store, mailer: Optional[Mailer] = None, clock: Callable[[], int] = now_ms,
                 dev_codes: bool = False):
        self.store = store
        self.mailer = mailer or Mailer()
        self.clock = clock
        # Только для локальной разработки: код из письма возвращается в ответе.
        self.dev_codes = dev_codes

    # ---------- вход ----------

    def handle(self, body: dict, token: Optional[str], ip: str = "") -> dict:
        op = body.get("op")
        fn = self.OPS.get(op)
        if fn is None:
            raise ApiError(400, "bad_op", "Неизвестная операция")
        public = op in self.PUBLIC
        device = None
        if not public:
            device = self._auth(token)
        out = fn(self, body, device, ip)
        out.setdefault("ok", True)
        out["api"] = API_VERSION
        out["serverTime"] = self.clock()
        return out

    def _auth(self, token: Optional[str]) -> dict:
        if not token:
            raise ApiError(401, "no_token", "Устройство не подключено")
        dev = self.store.get_device(hash_token(token))
        if dev is None:
            raise ApiError(401, "revoked", "Устройство отключено от гильдии")
        now = self.clock()
        if now - dev.get("last_seen", 0) > 10 * 60 * 1000:
            self.store.touch_device(dev["token_hash"], now)
        return dev

    def _limit(self, key: str, window_ms: int, max_hits: int) -> None:
        if not self.store.hit_limit(key, self.clock(), window_ms, max_hits):
            raise ApiError(429, "too_many", "Слишком много попыток, попробуйте позже")

    @staticmethod
    def _name(raw: Any, fallback: str) -> str:
        s = str(raw or "").strip()[:MAX_NAME]
        return s or fallback

    @staticmethod
    def _hero_ids(raw: Any) -> list:
        if not isinstance(raw, list):
            return []
        out = []
        for h in raw[:MAX_HEROES]:
            if isinstance(h, str) and 0 < len(h) <= 64 and h not in out:
                out.append(h)
        return out

    def _new_device(self, guild_id: str, role: str, name: str, hero_ids: list) -> dict:
        token = secrets.token_urlsafe(32)
        dev = {
            "token_hash": hash_token(token),
            "device_id": new_id(10),
            "guild_id": guild_id,
            "role": role,
            "name": name,
            "hero_ids": hero_ids,
            "created_at": self.clock(),
            "last_seen": self.clock(),
        }
        self.store.add_device(dev)
        return {"token": token, "deviceId": dev["device_id"], "guildId": guild_id, "role": role}

    @staticmethod
    def _need_adult(device: dict) -> None:
        if device["role"] != "adult":
            raise ApiError(403, "adults_only", "Это может сделать только взрослый")

    # ---------- операции ----------

    def op_ping(self, body, device, ip):
        return {"pong": True}

    def op_create_guild(self, body, device, ip):
        self._limit(f"create:{ip}", 3600_000, 10)
        guild_id = new_id(14)
        name = self._name(body.get("name"), "Гильдия")
        self.store.create_guild(guild_id, name, self.clock())
        out = self._new_device(guild_id, "adult", self._name(body.get("deviceName"), "Устройство"),
                               self._hero_ids(body.get("heroIds")))
        out["guildName"] = name
        return out

    def op_invite(self, body, device, ip):
        self._need_adult(device)
        role = body.get("role", "adult")
        if role not in ROLES:
            raise ApiError(400, "bad_role", "Неизвестная роль")
        self._limit(f"invite:{device['guild_id']}", 3600_000, 30)
        expires = self.clock() + INVITE_TTL_MS
        code = new_invite_code()
        self.store.put_invite({
            "code": code, "guild_id": device["guild_id"], "role": role,
            "expires_at": expires, "created_by": device["device_id"],
        })
        return {"code": code, "role": role, "expiresAt": expires}

    def op_join(self, body, device, ip):
        self._limit(f"join:{ip}", 3600_000, 20)
        code = normalize_code(body.get("code", ""))
        inv = self.store.take_invite(code) if len(code) == CODE_LEN else None
        if inv is None or inv["expires_at"] < self.clock() or inv.get("role") not in ROLES:
            raise ApiError(404, "bad_code", "Код не подошёл или устарел — попросите новый")
        guild = self.store.get_guild(inv["guild_id"])
        if guild is None:
            raise ApiError(404, "bad_code", "Гильдия не найдена")
        out = self._new_device(inv["guild_id"], inv["role"], self._name(body.get("deviceName"), "Устройство"),
                               self._hero_ids(body.get("heroIds")))
        out["guildName"] = guild["name"]
        return out

    def op_set_heroes(self, body, device, ip):
        heroes = self._hero_ids(body.get("heroIds"))
        self.store.update_device(device["token_hash"], hero_ids=heroes)
        return {"heroIds": heroes}

    def op_pull(self, body, device, ip):
        since = body.get("since", 0)
        if not isinstance(since, int) or since < 0:
            since = 0
        guild = self.store.get_guild(device["guild_id"])
        if guild is None:
            raise ApiError(401, "revoked", "Гильдия удалена")
        rev = guild["rev"]
        if since >= rev:
            return {"rev": rev, "changes": [], "more": False, "guildName": guild["name"], "role": device["role"]}
        rows = self.store.pull(device["guild_id"], since, PULL_LIMIT + 1)
        more = len(rows) > PULL_LIMIT
        rows = rows[:PULL_LIMIT]
        changes = []
        for r in rows:
            seen = visible(r.scope, device)
            if since == 0 and (not seen or r.data is None):
                continue  # новому устройству удалённое и чужое не нужно
            changes.append({"k": r.key, "r": r.rev, "d": r.data if seen else None})
        last = rows[-1].rev if more and rows else rev
        return {"rev": last, "changes": changes, "more": more, "guildName": guild["name"], "role": device["role"]}

    def op_push(self, body, device, ip):
        raw = body.get("changes")
        if not isinstance(raw, list) or len(raw) > MAX_CHANGES:
            raise ApiError(400, "bad_changes", "Неверный список изменений")
        changes, seen = [], set()
        for c in raw:
            if not isinstance(c, dict):
                raise ApiError(400, "bad_changes", "Неверное изменение")
            k, d, base, scope = c.get("k"), c.get("d"), c.get("base", 0), c.get("s", "all")
            if not isinstance(k, str) or len(k) > MAX_KEY or not KEY_RE.match(k) or k in seen:
                raise ApiError(400, "bad_key", f"Неверный ключ: {k!r}")
            if d is not None and (not isinstance(d, str) or len(d.encode()) > MAX_DATA):
                raise ApiError(400, "bad_data", f"Слишком большие данные: {k}")
            if d is not None:
                try:
                    json.loads(d)
                except ValueError:
                    raise ApiError(400, "bad_data", f"Данные не JSON: {k}")
            if not isinstance(base, int) or base < 0:
                base = 0
            if not valid_scope(scope):
                raise ApiError(400, "bad_scope", f"Неверная видимость: {k}")
            seen.add(k)
            changes.append(Change(k, d, base, scope))
        if not changes:
            guild = self.store.get_guild(device["guild_id"])
            return {"rev": guild["rev"] if guild else 0, "results": []}
        rev, results = self.store.push(device["guild_id"], changes, device, self.clock(), plan_push)
        return {"rev": rev, "results": results}

    def op_guild(self, body, device, ip):
        guild = self.store.get_guild(device["guild_id"])
        if guild is None:
            raise ApiError(401, "revoked", "Гильдия удалена")
        email = self.store.guild_email(device["guild_id"])
        return {
            "guildId": device["guild_id"], "guildName": guild["name"], "rev": guild["rev"],
            "role": device["role"], "deviceId": device["device_id"],
            "email": mask_email(email) if email else None,
        }

    def op_devices(self, body, device, ip):
        out = []
        for d in self.store.list_devices(device["guild_id"]):
            out.append({
                "id": d["device_id"], "name": d["name"], "role": d["role"],
                "heroIds": d["hero_ids"], "createdAt": d["created_at"], "lastSeen": d["last_seen"],
                "me": d["device_id"] == device["device_id"],
            })
        out.sort(key=lambda x: x["createdAt"])
        return {"devices": out}

    def op_revoke(self, body, device, ip):
        self._need_adult(device)
        target = body.get("deviceId")
        for d in self.store.list_devices(device["guild_id"]):
            if d["device_id"] == target:
                self.store.delete_device(d["token_hash"])
                return {"revoked": True}
        raise ApiError(404, "no_device", "Устройство не найдено")

    def op_leave(self, body, device, ip):
        self.store.delete_device(device["token_hash"])
        return {"left": True}

    # ---------- почта ----------

    def _send_code(self, email: str, purpose: str, guild_id: str) -> dict:
        self._limit(f"mail:{email}", 3600_000, 5)
        code = f"{secrets.randbelow(1_000_000):06d}"
        salt = new_id(8)
        self.store.put_email_code({
            "id": f"{purpose}:{email}", "code_hash": hash_code(code, salt), "salt": salt,
            "guild_id": guild_id, "expires_at": self.clock() + EMAIL_CODE_TTL_MS, "attempts": 0,
        })
        self.mailer.send_code(email, code, purpose)
        return {"sent": True, **({"devCode": code} if self.dev_codes else {})}

    def _check_code(self, email: str, purpose: str, code: str) -> str:
        rec = self.store.get_email_code(f"{purpose}:{email}")
        if rec is None or rec["expires_at"] < self.clock() or rec["attempts"] >= EMAIL_CODE_ATTEMPTS:
            raise ApiError(400, "bad_email_code", "Код устарел — запросите новый")
        if not hmac.compare_digest(rec["code_hash"], hash_code(str(code or "").strip(), rec["salt"])):
            self.store.bump_email_code(rec["id"])
            raise ApiError(400, "bad_email_code", "Неверный код из письма")
        self.store.delete_email_code(rec["id"])
        return rec["guild_id"]

    def _email(self, body) -> str:
        email = normalize_email(body.get("email", ""))
        if not EMAIL_RE.match(email) or len(email) > 254:
            raise ApiError(400, "bad_email", "Проверьте адрес почты")
        return email

    def op_email_link_start(self, body, device, ip):
        self._need_adult(device)
        email = self._email(body)
        owner = self.store.guild_by_email(email)
        if owner is not None and owner != device["guild_id"]:
            raise ApiError(409, "email_taken", "Эта почта уже привязана к другой гильдии")
        return self._send_code(email, "link", device["guild_id"])

    def op_email_link_finish(self, body, device, ip):
        self._need_adult(device)
        email = self._email(body)
        guild_id = self._check_code(email, "link", body.get("code"))
        if guild_id != device["guild_id"]:
            raise ApiError(400, "bad_email_code", "Код от другой гильдии")
        self.store.set_guild_email(device["guild_id"], email)
        return {"email": mask_email(email)}

    def op_email_unlink(self, body, device, ip):
        self._need_adult(device)
        self.store.set_guild_email(device["guild_id"], None)
        return {"email": None}

    def op_recover_start(self, body, device, ip):
        self._limit(f"recover:{ip}", 3600_000, 10)
        email = self._email(body)
        guild_id = self.store.guild_by_email(email)
        if guild_id is None:
            # Не сообщаем, привязана ли почта, — просто «письмо отправлено».
            return {"sent": True}
        return self._send_code(email, "recover", guild_id)

    def op_recover_finish(self, body, device, ip):
        self._limit(f"recover:{ip}", 3600_000, 10)
        email = self._email(body)
        guild_id = self._check_code(email, "recover", body.get("code"))
        guild = self.store.get_guild(guild_id)
        if guild is None:
            raise ApiError(404, "no_guild", "Гильдия не найдена")
        out = self._new_device(guild_id, "adult", self._name(body.get("deviceName"), "Устройство"),
                               self._hero_ids(body.get("heroIds")))
        out["guildName"] = guild["name"]
        return out

    OPS = {
        "ping": op_ping,
        "create_guild": op_create_guild,
        "invite": op_invite,
        "join": op_join,
        "set_heroes": op_set_heroes,
        "pull": op_pull,
        "push": op_push,
        "guild": op_guild,
        "devices": op_devices,
        "revoke": op_revoke,
        "leave": op_leave,
        "email_link_start": op_email_link_start,
        "email_link_finish": op_email_link_finish,
        "email_unlink": op_email_unlink,
        "recover_start": op_recover_start,
        "recover_finish": op_recover_finish,
        **AllianceOps.ALLY_OPS,
    }
    PUBLIC = {"ping", "create_guild", "join", "recover_start", "recover_finish"}


# ---------- HTTP-обёртка (общая для облака и локального сервера) ----------

CORS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, X-Rodquest-Token",
    "Access-Control-Max-Age": "86400",
}


def http_call(api: Api, method: str, headers: dict, body: bytes, ip: str = "") -> tuple:
    """→ (status, headers, body_bytes)"""
    if method == "OPTIONS":
        return 204, dict(CORS), b""
    h = {k.lower(): v for k, v in (headers or {}).items()}
    out_headers = {"Content-Type": "application/json; charset=utf-8", **CORS}
    if method != "POST":
        return 405, out_headers, json.dumps({"ok": False, "error": "method"}).encode()
    token = (h.get("x-rodquest-token") or "").strip() or None
    if token is None:
        auth = h.get("authorization", "")
        token = auth[7:].strip() if auth.lower().startswith("bearer ") else None
    try:
        if len(body) > 4 * 1024 * 1024:
            raise ApiError(413, "too_big", "Слишком большой запрос")
        try:
            data = json.loads(body.decode("utf-8") or "{}")
        except (ValueError, UnicodeDecodeError):
            raise ApiError(400, "bad_json", "Запрос — не JSON")
        if not isinstance(data, dict):
            raise ApiError(400, "bad_json", "Запрос — не объект JSON")
        out = api.handle(data, token, ip)
        return 200, out_headers, json.dumps(out, ensure_ascii=False).encode()
    except ApiError as e:
        return e.status, out_headers, json.dumps(
            {"ok": False, "error": e.code, "message": e.message}, ensure_ascii=False).encode()
    except Exception as e:  # noqa: BLE001 — показать причину, а не пустую 502
        import traceback
        traceback.print_exc()
        return 500, out_headers, json.dumps(
            {"ok": False, "error": "internal", "message": f"Ошибка сервера: {type(e).__name__}: {e}"[:300]},
            ensure_ascii=False).encode()
