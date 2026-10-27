"""Хранилище в Yandex Database (serverless) — для облака.

Переменные окружения функции:
  YDB_ENDPOINT  — например grpcs://ydb.serverless.yandexcloud.net:2135
  YDB_DATABASE  — например /ru-central1/b1g.../etn...
Доступ — по сервисному аккаунту функции (роль ydb.editor).
"""

from __future__ import annotations

import json
import os

import ydb
import ydb.iam

from .core import Row

U = ydb.PrimitiveType.Utf8
I = ydb.PrimitiveType.Int64
OU = ydb.OptionalType(ydb.PrimitiveType.Utf8)

DDL = [
    """CREATE TABLE IF NOT EXISTS guilds (
        guild_id Utf8, name Utf8, rev Int64, created_at Int64,
        PRIMARY KEY (guild_id))""",
    """CREATE TABLE IF NOT EXISTS devices (
        token_hash Utf8, device_id Utf8, guild_id Utf8, role Utf8, name Utf8, hero_ids Utf8,
        created_at Int64, last_seen Int64,
        PRIMARY KEY (token_hash),
        INDEX idx_guild GLOBAL SYNC ON (guild_id))""",
    """CREATE TABLE IF NOT EXISTS invites (
        code Utf8, guild_id Utf8, role Utf8, expires_at Int64, created_by Utf8,
        PRIMARY KEY (code))""",
    """CREATE TABLE IF NOT EXISTS entities (
        guild_id Utf8, key Utf8, rev Int64, data Utf8, scope Utf8, updated_at Int64, updated_by Utf8,
        PRIMARY KEY (guild_id, key),
        INDEX idx_rev GLOBAL SYNC ON (guild_id, rev) COVER (data, scope))""",
    """CREATE TABLE IF NOT EXISTS guild_emails (
        email Utf8, guild_id Utf8,
        PRIMARY KEY (email),
        INDEX idx_guild GLOBAL SYNC ON (guild_id))""",
    """CREATE TABLE IF NOT EXISTS email_codes (
        id Utf8, code_hash Utf8, salt Utf8, guild_id Utf8, expires_at Int64, attempts Int64,
        PRIMARY KEY (id))""",
    """CREATE TABLE IF NOT EXISTS limits (
        key Utf8, window_start Int64, hits Int64,
        PRIMARY KEY (key))""",
    # v0.9: гильдии — союз семей, кланов и одиночек.
    """CREATE TABLE IF NOT EXISTS alliances (
        ally_id Utf8, doc Utf8, ver Int64, updated_at Int64,
        PRIMARY KEY (ally_id))""",
    """CREATE TABLE IF NOT EXISTS ally_links (
        guild_id Utf8, ally_id Utf8,
        PRIMARY KEY (guild_id),
        INDEX idx_ally GLOBAL SYNC ON (ally_id))""",
]

ENTITY_ROW = (
    ydb.StructType()
    .add_member("guild_id", U)
    .add_member("key", U)
    .add_member("rev", I)
    .add_member("data", OU)
    .add_member("scope", U)
    .add_member("updated_at", I)
    .add_member("updated_by", U)
)


def _v(value, t):
    return ydb.TypedValue(value, t)


class YdbStore:
    def __init__(self, endpoint: str | None = None, database: str | None = None, credentials=None):
        self.driver = ydb.Driver(
            endpoint=endpoint or os.environ["YDB_ENDPOINT"],
            database=database or os.environ["YDB_DATABASE"],
            credentials=credentials or ydb.iam.MetadataUrlCredentials(),
        )
        self.driver.wait(timeout=10, fail_fast=True)
        self.pool = ydb.QuerySessionPool(self.driver)

    def create_tables(self):
        for q in DDL:
            self.pool.execute_with_retries(q)

    # ---------- помощники ----------

    def _rows(self, query, params=None):
        sets = self.pool.execute_with_retries(query, params or {})
        return list(sets[0].rows) if sets else []

    def _exec(self, query, params=None):
        self.pool.execute_with_retries(query, params or {})

    @staticmethod
    def _tx_rows(tx, query, params=None):
        with tx.execute(query, params or {}) as results:
            sets = list(results)
        return list(sets[0].rows) if sets else []

    @staticmethod
    def _dev(r):
        if r is None:
            return None
        return {
            "token_hash": r["token_hash"], "device_id": r["device_id"], "guild_id": r["guild_id"],
            "role": r["role"], "name": r["name"], "hero_ids": json.loads(r["hero_ids"] or "[]"),
            "created_at": r["created_at"], "last_seen": r["last_seen"],
        }

    # ---------- гильдии ----------

    def create_guild(self, guild_id, name, now):
        self._exec(
            "UPSERT INTO guilds (guild_id, name, rev, created_at) VALUES ($g, $n, 0, $t);",
            {"$g": _v(guild_id, U), "$n": _v(name, U), "$t": _v(now, I)},
        )

    def get_guild(self, guild_id):
        rows = self._rows("SELECT guild_id, name, rev, created_at FROM guilds WHERE guild_id = $g;",
                          {"$g": _v(guild_id, U)})
        if not rows:
            return None
        r = rows[0]
        return {"guild_id": r["guild_id"], "name": r["name"], "rev": r["rev"], "created_at": r["created_at"]}

    # ---------- устройства ----------

    def add_device(self, dev):
        self._exec(
            """UPSERT INTO devices (token_hash, device_id, guild_id, role, name, hero_ids, created_at, last_seen)
               VALUES ($th, $id, $g, $role, $name, $heroes, $c, $s);""",
            {
                "$th": _v(dev["token_hash"], U), "$id": _v(dev["device_id"], U), "$g": _v(dev["guild_id"], U),
                "$role": _v(dev["role"], U), "$name": _v(dev["name"], U),
                "$heroes": _v(json.dumps(dev["hero_ids"]), U),
                "$c": _v(dev["created_at"], I), "$s": _v(dev["last_seen"], I),
            },
        )

    def get_device(self, token_hash):
        rows = self._rows("SELECT * FROM devices WHERE token_hash = $th;", {"$th": _v(token_hash, U)})
        return self._dev(rows[0]) if rows else None

    def touch_device(self, token_hash, now):
        self._exec("UPDATE devices SET last_seen = $s WHERE token_hash = $th;",
                   {"$s": _v(now, I), "$th": _v(token_hash, U)})

    def update_device(self, token_hash, hero_ids):
        self._exec("UPDATE devices SET hero_ids = $h WHERE token_hash = $th;",
                   {"$h": _v(json.dumps(hero_ids), U), "$th": _v(token_hash, U)})

    def list_devices(self, guild_id):
        rows = self._rows("SELECT * FROM devices VIEW idx_guild WHERE guild_id = $g;", {"$g": _v(guild_id, U)})
        return [self._dev(r) for r in rows]

    def delete_device(self, token_hash):
        self._exec("DELETE FROM devices WHERE token_hash = $th;", {"$th": _v(token_hash, U)})

    # ---------- приглашения ----------

    def put_invite(self, inv):
        self._exec(
            """UPSERT INTO invites (code, guild_id, role, expires_at, created_by)
               VALUES ($c, $g, $r, $e, $b);""",
            {"$c": _v(inv["code"], U), "$g": _v(inv["guild_id"], U), "$r": _v(inv["role"], U),
             "$e": _v(inv["expires_at"], I), "$b": _v(inv["created_by"], U)},
        )

    def take_invite(self, code):
        found = {}

        def callee(tx):
            found.clear()
            rows = self._tx_rows(tx, "SELECT * FROM invites WHERE code = $c;", {"$c": _v(code, U)})
            if not rows:
                return
            r = rows[0]
            found.update(code=r["code"], guild_id=r["guild_id"], role=r["role"],
                         expires_at=r["expires_at"], created_by=r["created_by"])
            with tx.execute("DELETE FROM invites WHERE code = $c;", {"$c": _v(code, U)}):
                pass

        self.pool.retry_tx_sync(callee, tx_mode=ydb.QuerySerializableReadWrite())
        return dict(found) if found else None

    # ---------- сущности ----------

    def pull(self, guild_id, since, limit):
        rows = self._rows(
            """SELECT key, rev, data, scope FROM entities VIEW idx_rev
               WHERE guild_id = $g AND rev > $since
               ORDER BY rev LIMIT $lim;""",
            {"$g": _v(guild_id, U), "$since": _v(since, I), "$lim": _v(limit, ydb.PrimitiveType.Uint64)},
        )
        return [Row(r["key"], r["rev"], r["data"], r["scope"]) for r in rows]

    def push(self, guild_id, changes, device, now, plan_fn):
        out = {}

        def callee(tx):
            g = self._tx_rows(tx, "SELECT rev FROM guilds WHERE guild_id = $g;", {"$g": _v(guild_id, U)})
            rev = g[0]["rev"] if g else 0
            current = {}
            keys = [c.key for c in changes]
            if keys:
                rows = self._tx_rows(
                    tx,
                    "SELECT key, rev, data, scope FROM entities WHERE guild_id = $g AND key IN $keys;",
                    {"$g": _v(guild_id, U), "$keys": _v(keys, ydb.ListType(U))},
                )
                for r in rows:
                    current[r["key"]] = Row(r["key"], r["rev"], r["data"], r["scope"])
            plan = plan_fn(rev, changes, current, device)
            if plan.writes:
                values = [
                    {"guild_id": guild_id, "key": w.key, "rev": w.rev, "data": w.data, "scope": w.scope,
                     "updated_at": now, "updated_by": device["device_id"]}
                    for w in plan.writes
                ]
                with tx.execute(
                    """UPSERT INTO entities SELECT * FROM AS_TABLE($rows);
                       UPDATE guilds SET rev = $rev WHERE guild_id = $g;""",
                    {"$rows": _v(values, ydb.ListType(ENTITY_ROW)), "$rev": _v(plan.new_rev, I),
                     "$g": _v(guild_id, U)},
                ):
                    pass
            out["rev"] = plan.new_rev
            out["results"] = plan.results

        self.pool.retry_tx_sync(callee, tx_mode=ydb.QuerySerializableReadWrite())
        return out["rev"], out["results"]

    # ---------- почта ----------

    def guild_email(self, guild_id):
        rows = self._rows("SELECT email FROM guild_emails VIEW idx_guild WHERE guild_id = $g;",
                          {"$g": _v(guild_id, U)})
        return rows[0]["email"] if rows else None

    def guild_by_email(self, email):
        rows = self._rows("SELECT guild_id FROM guild_emails WHERE email = $e;", {"$e": _v(email, U)})
        return rows[0]["guild_id"] if rows else None

    def set_guild_email(self, guild_id, email):
        old = self.guild_email(guild_id)
        if old:
            self._exec("DELETE FROM guild_emails WHERE email = $e;", {"$e": _v(old, U)})
        if email:
            self._exec("UPSERT INTO guild_emails (email, guild_id) VALUES ($e, $g);",
                       {"$e": _v(email, U), "$g": _v(guild_id, U)})

    def put_email_code(self, rec):
        self._exec(
            """UPSERT INTO email_codes (id, code_hash, salt, guild_id, expires_at, attempts)
               VALUES ($id, $h, $s, $g, $e, $a);""",
            {"$id": _v(rec["id"], U), "$h": _v(rec["code_hash"], U), "$s": _v(rec["salt"], U),
             "$g": _v(rec["guild_id"], U), "$e": _v(rec["expires_at"], I), "$a": _v(rec["attempts"], I)},
        )

    def get_email_code(self, id_):
        rows = self._rows("SELECT * FROM email_codes WHERE id = $id;", {"$id": _v(id_, U)})
        if not rows:
            return None
        r = rows[0]
        return {"id": r["id"], "code_hash": r["code_hash"], "salt": r["salt"], "guild_id": r["guild_id"],
                "expires_at": r["expires_at"], "attempts": r["attempts"]}

    def bump_email_code(self, id_):
        self._exec("UPDATE email_codes SET attempts = attempts + 1 WHERE id = $id;", {"$id": _v(id_, U)})

    def delete_email_code(self, id_):
        self._exec("DELETE FROM email_codes WHERE id = $id;", {"$id": _v(id_, U)})

    # ---------- гильдии v0.9 ----------

    def create_alliance(self, ally_id, doc, now):
        self._exec(
            "UPSERT INTO alliances (ally_id, doc, ver, updated_at) VALUES ($a, $d, 1, $t);",
            {"$a": _v(ally_id, U), "$d": _v(doc, U), "$t": _v(now, I)},
        )

    def get_alliance(self, ally_id):
        rows = self._rows("SELECT doc, ver FROM alliances WHERE ally_id = $a;", {"$a": _v(ally_id, U)})
        return (rows[0]["doc"], rows[0]["ver"]) if rows else None

    def alliance_of(self, guild_id):
        rows = self._rows("SELECT ally_id FROM ally_links WHERE guild_id = $g;", {"$g": _v(guild_id, U)})
        return rows[0]["ally_id"] if rows else None

    def set_alliance_of(self, guild_id, ally_id):
        if ally_id is None:
            self._exec("DELETE FROM ally_links WHERE guild_id = $g;", {"$g": _v(guild_id, U)})
        else:
            self._exec("UPSERT INTO ally_links (guild_id, ally_id) VALUES ($g, $a);",
                       {"$g": _v(guild_id, U), "$a": _v(ally_id, U)})

    def update_alliance(self, ally_id, fn):
        out = {}

        def callee(tx):
            out.clear()
            rows = self._tx_rows(tx, "SELECT doc, ver FROM alliances WHERE ally_id = $a;", {"$a": _v(ally_id, U)})
            if not rows:
                return
            doc, result, links = fn(json.loads(rows[0]["doc"]))
            ver = rows[0]["ver"]
            if doc is None:
                links = dict(links)
                for r in self._tx_rows(tx, "SELECT guild_id FROM ally_links VIEW idx_ally WHERE ally_id = $a;",
                                       {"$a": _v(ally_id, U)}):
                    links[r["guild_id"]] = None
                with tx.execute("DELETE FROM alliances WHERE ally_id = $a;", {"$a": _v(ally_id, U)}):
                    pass
                ver = 0
            elif not result.get("same"):
                ver += 1
                with tx.execute(
                    "UPDATE alliances SET doc = $d, ver = $v WHERE ally_id = $a;",
                    {"$d": _v(json.dumps(doc, ensure_ascii=False), U), "$v": _v(ver, I), "$a": _v(ally_id, U)},
                ):
                    pass
            for space, aid in links.items():
                if aid is None:
                    with tx.execute("DELETE FROM ally_links WHERE guild_id = $g;", {"$g": _v(space, U)}):
                        pass
                else:
                    with tx.execute("UPSERT INTO ally_links (guild_id, ally_id) VALUES ($g, $a);",
                                    {"$g": _v(space, U), "$a": _v(aid, U)}):
                        pass
            out["v"] = (doc, ver, result)

        self.pool.retry_tx_sync(callee, tx_mode=ydb.QuerySerializableReadWrite())
        return out.get("v")

    # ---------- ограничение частоты ----------

    def hit_limit(self, key, now, window_ms, max_hits):
        result = {}

        def callee(tx):
            rows = self._tx_rows(tx, "SELECT window_start, hits FROM limits WHERE key = $k;", {"$k": _v(key, U)})
            if not rows or now - rows[0]["window_start"] >= window_ms:
                start, hits = now, 1
            else:
                start, hits = rows[0]["window_start"], rows[0]["hits"] + 1
            if hits > max_hits:
                result["ok"] = False
                return
            with tx.execute("UPSERT INTO limits (key, window_start, hits) VALUES ($k, $s, $h);",
                            {"$k": _v(key, U), "$s": _v(start, I), "$h": _v(hits, I)}):
                pass
            result["ok"] = True

        self.pool.retry_tx_sync(callee, tx_mode=ydb.QuerySerializableReadWrite())
        return result.get("ok", False)
