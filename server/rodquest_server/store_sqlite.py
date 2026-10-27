"""Хранилище на SQLite — для тестов и локального сервера на компьютере."""

from __future__ import annotations

import json
import sqlite3
import threading

from .core import Row

SCHEMA = """
CREATE TABLE IF NOT EXISTS guilds (guild_id TEXT PRIMARY KEY, name TEXT, rev INTEGER, created_at INTEGER);
CREATE TABLE IF NOT EXISTS devices (token_hash TEXT PRIMARY KEY, device_id TEXT, guild_id TEXT, role TEXT,
  name TEXT, hero_ids TEXT, created_at INTEGER, last_seen INTEGER);
CREATE INDEX IF NOT EXISTS devices_guild ON devices (guild_id);
CREATE TABLE IF NOT EXISTS invites (code TEXT PRIMARY KEY, guild_id TEXT, role TEXT, expires_at INTEGER,
  created_by TEXT);
CREATE TABLE IF NOT EXISTS entities (guild_id TEXT, key TEXT, rev INTEGER, data TEXT, scope TEXT,
  updated_at INTEGER, updated_by TEXT, PRIMARY KEY (guild_id, key));
CREATE INDEX IF NOT EXISTS entities_rev ON entities (guild_id, rev);
CREATE TABLE IF NOT EXISTS guild_emails (email TEXT PRIMARY KEY, guild_id TEXT);
CREATE TABLE IF NOT EXISTS email_codes (id TEXT PRIMARY KEY, code_hash TEXT, salt TEXT, guild_id TEXT,
  expires_at INTEGER, attempts INTEGER);
CREATE TABLE IF NOT EXISTS limits (key TEXT PRIMARY KEY, window_start INTEGER, hits INTEGER);
CREATE TABLE IF NOT EXISTS alliances (ally_id TEXT PRIMARY KEY, doc TEXT, ver INTEGER, updated_at INTEGER);
CREATE TABLE IF NOT EXISTS ally_links (guild_id TEXT PRIMARY KEY, ally_id TEXT);
"""


class SqliteStore:
    def __init__(self, path: str = ":memory:"):
        self.db = sqlite3.connect(path, check_same_thread=False, isolation_level=None)
        self.db.row_factory = sqlite3.Row
        self.lock = threading.RLock()
        self.db.executescript(SCHEMA)

    def _one(self, sql, args=()):
        with self.lock:
            return self.db.execute(sql, args).fetchone()

    def _all(self, sql, args=()):
        with self.lock:
            return self.db.execute(sql, args).fetchall()

    def _exec(self, sql, args=()):
        with self.lock:
            self.db.execute(sql, args)

    # гильдии
    def create_guild(self, guild_id, name, now):
        self._exec("INSERT INTO guilds VALUES (?,?,0,?)", (guild_id, name, now))

    def get_guild(self, guild_id):
        r = self._one("SELECT * FROM guilds WHERE guild_id=?", (guild_id,))
        return dict(r) if r else None

    # устройства
    @staticmethod
    def _dev(r):
        if r is None:
            return None
        d = dict(r)
        d["hero_ids"] = json.loads(d["hero_ids"] or "[]")
        return d

    def add_device(self, dev):
        self._exec("INSERT INTO devices VALUES (?,?,?,?,?,?,?,?)", (
            dev["token_hash"], dev["device_id"], dev["guild_id"], dev["role"], dev["name"],
            json.dumps(dev["hero_ids"]), dev["created_at"], dev["last_seen"]))

    def get_device(self, token_hash):
        return self._dev(self._one("SELECT * FROM devices WHERE token_hash=?", (token_hash,)))

    def touch_device(self, token_hash, now):
        self._exec("UPDATE devices SET last_seen=? WHERE token_hash=?", (now, token_hash))

    def update_device(self, token_hash, hero_ids):
        self._exec("UPDATE devices SET hero_ids=? WHERE token_hash=?", (json.dumps(hero_ids), token_hash))

    def list_devices(self, guild_id):
        return [self._dev(r) for r in self._all("SELECT * FROM devices WHERE guild_id=?", (guild_id,))]

    def delete_device(self, token_hash):
        self._exec("DELETE FROM devices WHERE token_hash=?", (token_hash,))

    # приглашения
    def put_invite(self, inv):
        self._exec("INSERT INTO invites VALUES (?,?,?,?,?)",
                   (inv["code"], inv["guild_id"], inv["role"], inv["expires_at"], inv["created_by"]))

    def take_invite(self, code):
        with self.lock:
            r = self._one("SELECT * FROM invites WHERE code=?", (code,))
            if r is None:
                return None
            self._exec("DELETE FROM invites WHERE code=?", (code,))
            return dict(r)

    # сущности
    def pull(self, guild_id, since, limit):
        rows = self._all("SELECT key, rev, data, scope FROM entities WHERE guild_id=? AND rev>? "
                         "ORDER BY rev LIMIT ?", (guild_id, since, limit))
        return [Row(r["key"], r["rev"], r["data"], r["scope"]) for r in rows]

    def push(self, guild_id, changes, device, now, plan_fn):
        with self.lock:
            self.db.execute("BEGIN IMMEDIATE")
            try:
                g = self.db.execute("SELECT rev FROM guilds WHERE guild_id=?", (guild_id,)).fetchone()
                rev = g["rev"] if g else 0
                current = {}
                keys = [c.key for c in changes]
                for i in range(0, len(keys), 400):
                    part = keys[i:i + 400]
                    q = "SELECT key, rev, data, scope FROM entities WHERE guild_id=? AND key IN (%s)" % ",".join(
                        "?" * len(part))
                    for r in self.db.execute(q, [guild_id, *part]):
                        current[r["key"]] = Row(r["key"], r["rev"], r["data"], r["scope"])
                plan = plan_fn(rev, changes, current, device)
                for w in plan.writes:
                    self.db.execute("INSERT OR REPLACE INTO entities VALUES (?,?,?,?,?,?,?)",
                                    (guild_id, w.key, w.rev, w.data, w.scope, now, device["device_id"]))
                if plan.new_rev != rev:
                    self.db.execute("UPDATE guilds SET rev=? WHERE guild_id=?", (plan.new_rev, guild_id))
                self.db.execute("COMMIT")
                return plan.new_rev, plan.results
            except BaseException:
                self.db.execute("ROLLBACK")
                raise

    # почта
    def guild_email(self, guild_id):
        r = self._one("SELECT email FROM guild_emails WHERE guild_id=?", (guild_id,))
        return r["email"] if r else None

    def guild_by_email(self, email):
        r = self._one("SELECT guild_id FROM guild_emails WHERE email=?", (email,))
        return r["guild_id"] if r else None

    def set_guild_email(self, guild_id, email):
        with self.lock:
            self._exec("DELETE FROM guild_emails WHERE guild_id=?", (guild_id,))
            if email:
                self._exec("INSERT OR REPLACE INTO guild_emails VALUES (?,?)", (email, guild_id))

    def put_email_code(self, rec):
        self._exec("INSERT OR REPLACE INTO email_codes VALUES (?,?,?,?,?,?)", (
            rec["id"], rec["code_hash"], rec["salt"], rec["guild_id"], rec["expires_at"], rec["attempts"]))

    def get_email_code(self, id_):
        r = self._one("SELECT * FROM email_codes WHERE id=?", (id_,))
        return dict(r) if r else None

    def bump_email_code(self, id_):
        self._exec("UPDATE email_codes SET attempts=attempts+1 WHERE id=?", (id_,))

    def delete_email_code(self, id_):
        self._exec("DELETE FROM email_codes WHERE id=?", (id_,))

    # гильдии v0.9 (союз семей, кланов и одиночек)
    def create_alliance(self, ally_id, doc, now):
        self._exec("INSERT INTO alliances VALUES (?,?,1,?)", (ally_id, doc, now))

    def get_alliance(self, ally_id):
        r = self._one("SELECT doc, ver FROM alliances WHERE ally_id=?", (ally_id,))
        return (r["doc"], r["ver"]) if r else None

    def alliance_of(self, guild_id):
        r = self._one("SELECT ally_id FROM ally_links WHERE guild_id=?", (guild_id,))
        return r["ally_id"] if r else None

    def set_alliance_of(self, guild_id, ally_id):
        with self.lock:
            if ally_id is None:
                self._exec("DELETE FROM ally_links WHERE guild_id=?", (guild_id,))
            else:
                self._exec("INSERT OR REPLACE INTO ally_links VALUES (?,?)", (guild_id, ally_id))

    def update_alliance(self, ally_id, fn):
        """Прочитать, изменить и записать гильдию одной транзакцией.

        fn(doc) → (doc | None, ответ, ссылки). Возвращает (doc, ver, ответ) или None, если гильдии нет.
        """
        with self.lock:
            self.db.execute("BEGIN IMMEDIATE")
            try:
                r = self.db.execute("SELECT doc, ver FROM alliances WHERE ally_id=?", (ally_id,)).fetchone()
                if r is None:
                    self.db.execute("ROLLBACK")
                    return None
                doc, result, links = fn(json.loads(r["doc"]))
                ver = r["ver"]
                if doc is None:
                    self.db.execute("DELETE FROM alliances WHERE ally_id=?", (ally_id,))
                    self.db.execute("DELETE FROM ally_links WHERE ally_id=?", (ally_id,))
                    ver = 0
                elif not result.get("same"):
                    ver += 1
                    self.db.execute("UPDATE alliances SET doc=?, ver=? WHERE ally_id=?",
                                    (json.dumps(doc, ensure_ascii=False), ver, ally_id))
                for space, aid in links.items():
                    if aid is None:
                        self.db.execute("DELETE FROM ally_links WHERE guild_id=?", (space,))
                    else:
                        self.db.execute("INSERT OR REPLACE INTO ally_links VALUES (?,?)", (space, aid))
                self.db.execute("COMMIT")
                return doc, ver, result
            except BaseException:
                self.db.execute("ROLLBACK")
                raise

    # ограничение частоты
    def hit_limit(self, key, now, window_ms, max_hits):
        with self.lock:
            r = self._one("SELECT * FROM limits WHERE key=?", (key,))
            if r is None or now - r["window_start"] >= window_ms:
                self._exec("INSERT OR REPLACE INTO limits VALUES (?,?,1)", (key, now))
                return True
            if r["hits"] >= max_hits:
                return False
            self._exec("UPDATE limits SET hits=hits+1 WHERE key=?", (key,))
            return True
