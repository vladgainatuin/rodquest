"""Родквест — гильдия (v0.9): союз семей, кланов и одиночных героев.

С версии 0.9 семья (или клан, или личный путь «Только я») — это «пространство»
синхронизации (в коде сервера по-прежнему guild_id, см. core.py). Гильдия —
уровень выше: в неё вступают целые семьи и кланы, а также одиночные игроки,
чтобы вместе идти к общим целям.

Гильдия хранится одним JSON-документом (она маленькая: до 30 участников,
40 целей, 100 записей ленты). Все действия — отдельные операции `ally_*`,
права проверяет сервер:

  глава гильдии   — всё, плюс выдаёт права и передаёт главенство;
  права участникам (выдаёт глава, только взрослым):
    settings — название, герб и девиз гильдии;
    invite   — приглашать семьи, кланы и одиночек (коды);
    members  — исключать участников;
    goals    — создавать, менять и удалять цели гильдии;
    announce — объявления в ленте гильдии.
  вклад в цели гильдии может вносить любой герой, в том числе юнга.

Кто действует: устройство передаёт heroId — героя, который играет на этом
устройстве (он должен быть в списке героев устройства). Ссылка на героя —
"<пространство>|<герой>".
"""

from __future__ import annotations

import json
from typing import Any, Optional

from .core import ApiError, new_id, new_invite_code, normalize_code, CODE_LEN, INVITE_TTL_MS

PERMS = ("settings", "invite", "members", "goals", "announce")
KINDS = ("family", "clan", "solo")

MAX_MEMBERS = 30
MAX_HEROES_PER_MEMBER = 16
MAX_GOALS = 40
KEEP_DONE_GOALS = 20
MAX_FEED = 100
MAX_CONTRIB_KEYS = 300
MAX_TARGET = 1_000_000
MAX_AMOUNT = 10_000
MAX_TEXT = 300
MAX_TITLE = 80
MAX_NAME = 60

INVITE_PREFIX = "ally:"


# ---------- проверка входных данных ----------

def _s(raw: Any, limit: int, fallback: str = "") -> str:
    s = str(raw if raw is not None else "").strip()[:limit]
    return s or fallback


def _emoji(raw: Any, fallback: str) -> str:
    s = str(raw or "").strip()
    return s[:8] if s else fallback


def _int(raw: Any, lo: int, hi: int) -> Optional[int]:
    if isinstance(raw, bool) or not isinstance(raw, (int, float)):
        return None
    v = int(raw)
    if v < lo or v > hi:
        return None
    return v


def clean_member(raw: Any, space: str, now: int, joined: Optional[int] = None) -> dict:
    """Карточка участника: семья, клан или одиночка с его героями."""
    if not isinstance(raw, dict):
        raw = {}
    kind = raw.get("kind") if raw.get("kind") in KINDS else "family"
    heroes = {}
    src = raw.get("heroes") if isinstance(raw.get("heroes"), dict) else {}
    for hid, h in list(src.items())[:MAX_HEROES_PER_MEMBER]:
        if not isinstance(hid, str) or not (0 < len(hid) <= 64) or not isinstance(h, dict):
            continue
        heroes[hid] = {"n": _s(h.get("n"), MAX_NAME, "Герой"), "a": _emoji(h.get("a"), "🧙"), "k": h.get("k") is True}
    return {
        "kind": kind,
        "name": _s(raw.get("name"), MAX_NAME, "Семья" if kind == "family" else "Клан" if kind == "clan" else "Герой"),
        "emoji": _emoji(raw.get("emoji"), {"family": "🏡", "clan": "⚔️", "solo": "🧭"}[kind]),
        "heroes": heroes,
        "joinedAt": joined if joined is not None else now,
    }


def ref(space: str, hero: str) -> str:
    return f"{space}|{hero}"


def split_ref(r: str) -> tuple:
    space, _, hero = (r or "").partition("|")
    return space, hero


# ---------- документ гильдии ----------

def new_doc(aid: str, name: str, emblem: str, motto: str, space: str, hero: str, member: dict, now: int) -> dict:
    return {
        "id": aid,
        "name": name,
        "emblem": emblem,
        "motto": motto,
        "createdAt": now,
        "leader": ref(space, hero),
        "members": {space: member},
        "perms": {},
        "goals": [],
        "feed": [],
    }


def hero_name(doc: dict, r: str) -> str:
    space, hero = split_ref(r)
    m = doc["members"].get(space)
    if m is None:
        return "Герой"
    h = m["heroes"].get(hero)
    return h["n"] if h else m["name"]


def is_kid(doc: dict, r: str) -> bool:
    space, hero = split_ref(r)
    m = doc["members"].get(space)
    h = m["heroes"].get(hero) if m else None
    return bool(h and h.get("k"))


def can(doc: dict, r: str, perm: str) -> bool:
    if doc["leader"] == r:
        return True
    return perm in doc["perms"].get(r, [])


def add_feed(doc: dict, now: int, who: str, emoji: str, text: str) -> None:
    doc["feed"].insert(0, {"id": new_id(8), "at": now, "who": who, "n": hero_name(doc, who) if "|" in who
                           else doc["members"].get(who, {}).get("name", ""), "e": emoji, "t": text[:MAX_TEXT]})
    del doc["feed"][MAX_FEED:]


def member_word(kind: str) -> str:
    return {"family": "семья", "clan": "клан", "solo": "герой"}.get(kind, "участник")


def _drop_member(doc: dict, space: str) -> None:
    doc["members"].pop(space, None)
    for r in list(doc["perms"].keys()):
        if split_ref(r)[0] == space:
            del doc["perms"][r]


def _trim_goals(doc: dict) -> None:
    done = [g for g in doc["goals"] if g.get("done")]
    if len(done) > KEEP_DONE_GOALS:
        drop = {g["id"] for g in sorted(done, key=lambda g: g.get("doneAt") or 0)[: len(done) - KEEP_DONE_GOALS]}
        doc["goals"] = [g for g in doc["goals"] if g["id"] not in drop]


def _goal(doc: dict, gid: Any) -> dict:
    for g in doc["goals"]:
        if g["id"] == gid:
            return g
    raise ApiError(404, "no_goal", "Цель гильдии не найдена")


# ---------- операции (подключаются к Api в core.py) ----------

class AllianceOps:
    """Операции гильдии. Смешивается с Api: нужны self.store и self.clock."""

    def _actor(self, body, device) -> str:
        hero = body.get("heroId")
        if not isinstance(hero, str) or hero not in device["hero_ids"]:
            raise ApiError(403, "no_hero", "Выберите героя на этом устройстве")
        return ref(device["guild_id"], hero)

    def _my_alliance(self, device) -> str:
        aid = self.store.alliance_of(device["guild_id"])
        if aid is None:
            raise ApiError(404, "no_alliance", "Вы пока не состоите в гильдии")
        return aid

    def _update(self, aid: str, fn):
        """fn(doc) → (doc | None — удалить, ответ, {пространство: гильдия | None}).

        Ответ дополняется свежей гильдией и её версией — устройству не нужен
        отдельный запрос, чтобы увидеть результат.
        """
        got = self.store.update_alliance(aid, fn)
        if got is None:
            raise ApiError(404, "no_alliance", "Гильдия не найдена")
        doc, ver, result = got
        return {**result, "alliance": doc, "ver": ver}

    @staticmethod
    def _need(doc, who, perm, text):
        if not can(doc, who, perm):
            raise ApiError(403, "no_rights", text)

    @staticmethod
    def _adult_device(device):
        if device["role"] != "adult":
            raise ApiError(403, "adults_only", "Это может сделать только взрослый")

    def _out(self, doc, ver):
        return {"alliance": doc, "ver": ver}

    # создать гильдию
    def op_ally_create(self, body, device, ip):
        self._adult_device(device)
        who = self._actor(body, device)
        if self.store.alliance_of(device["guild_id"]) is not None:
            raise ApiError(409, "in_alliance", "Вы уже в гильдии — сначала выйдите из неё")
        self._limit(f"ally_create:{device['guild_id']}", 3600_000, 5)
        now = self.clock()
        aid = new_id(14)
        member = clean_member(body.get("member"), device["guild_id"], now)
        doc = new_doc(aid, _s(body.get("name"), MAX_NAME, "Гильдия"), _emoji(body.get("emblem"), "🏰"),
                      _s(body.get("motto"), MAX_TEXT), device["guild_id"], split_ref(who)[1], member, now)
        add_feed(doc, now, who, "🏰", f"основал(а) гильдию «{doc['name']}»")
        self.store.create_alliance(aid, json.dumps(doc, ensure_ascii=False), now)
        self.store.set_alliance_of(device["guild_id"], aid)
        return self._out(doc, 1)

    # получить гильдию (с ver — только если изменилась)
    def op_ally_get(self, body, device, ip):
        aid = self.store.alliance_of(device["guild_id"])
        if aid is None:
            return {"alliance": None, "ver": 0}
        got = self.store.get_alliance(aid)
        if got is None:
            self.store.set_alliance_of(device["guild_id"], None)
            return {"alliance": None, "ver": 0}
        data, ver = got
        doc = json.loads(data)
        if device["guild_id"] not in doc["members"]:
            # Нас исключили.
            self.store.set_alliance_of(device["guild_id"], None)
            return {"alliance": None, "ver": 0, "kicked": True}
        if body.get("ver") == ver:
            return {"same": True, "ver": ver}
        return self._out(doc, ver)

    # обновить свою карточку (имя семьи, герои)
    def op_ally_member(self, body, device, ip):
        aid = self._my_alliance(device)
        space = device["guild_id"]
        now = self.clock()

        def fn(doc):
            old = doc["members"].get(space)
            if old is None:
                raise ApiError(404, "no_alliance", "Вы пока не состоите в гильдии")
            m = clean_member(body.get("member"), space, now, joined=old.get("joinedAt"))
            if m == old:
                return doc, {"same": True}, {}
            doc["members"][space] = m
            return doc, {}, {}

        return self._update(aid, fn)

    # приглашение
    def op_ally_invite(self, body, device, ip):
        who = self._actor(body, device)
        aid = self._my_alliance(device)
        got = self.store.get_alliance(aid)
        if got is None:
            raise ApiError(404, "no_alliance", "Гильдия не найдена")
        doc = json.loads(got[0])
        self._need(doc, who, "invite", "Приглашать может глава гильдии или тот, кому он дал это право")
        if len(doc["members"]) >= MAX_MEMBERS:
            raise ApiError(409, "full", f"В гильдии уже {MAX_MEMBERS} участников — больше нельзя")
        self._limit(f"ally_invite:{aid}", 3600_000, 30)
        code = new_invite_code()
        expires = self.clock() + INVITE_TTL_MS
        self.store.put_invite({"code": INVITE_PREFIX + code, "guild_id": aid, "role": "ally",
                               "expires_at": expires, "created_by": who})
        return {"code": code, "expiresAt": expires}

    # вступить по коду
    def op_ally_join(self, body, device, ip):
        self._adult_device(device)
        who = self._actor(body, device)
        self._limit(f"ally_join:{ip}", 3600_000, 20)
        space = device["guild_id"]
        if self.store.alliance_of(space) is not None:
            raise ApiError(409, "in_alliance", "Вы уже в гильдии — сначала выйдите из неё")
        code = normalize_code(body.get("code", ""))
        inv = self.store.take_invite(INVITE_PREFIX + code) if len(code) == CODE_LEN else None
        if inv is None or inv["expires_at"] < self.clock() or inv.get("role") != "ally":
            raise ApiError(404, "bad_code", "Код не подошёл или устарел — попросите новый")
        aid = inv["guild_id"]
        now = self.clock()
        member = clean_member(body.get("member"), space, now)

        def fn(doc):
            if len(doc["members"]) >= MAX_MEMBERS:
                raise ApiError(409, "full", f"В гильдии уже {MAX_MEMBERS} участников — больше нельзя")
            doc["members"][space] = member
            word = member_word(member["kind"])
            if member["kind"] == "solo":
                add_feed(doc, now, who, "🎉", "вступил(а) в гильдию")
            else:
                add_feed(doc, now, who, "🎉", f"привёл(а) в гильдию {word} «{member['name']}»")
            return doc, {}, {space: aid}

        if self.store.get_alliance(aid) is None:
            raise ApiError(404, "bad_code", "Гильдия не найдена")
        return self._update(aid, fn)

    # выйти
    def op_ally_leave(self, body, device, ip):
        self._adult_device(device)
        who = self._actor(body, device)
        aid = self._my_alliance(device)
        space = device["guild_id"]
        now = self.clock()

        def fn(doc):
            if split_ref(doc["leader"])[0] == space:
                if len(doc["members"]) > 1:
                    raise ApiError(409, "leader", "Глава не может выйти, пока в гильдии есть другие — "
                                                  "сначала передайте главенство")
                return None, {"left": True, "deleted": True}, {space: None}
            name = doc["members"].get(space, {}).get("name", "")
            _drop_member(doc, space)
            add_feed(doc, now, who, "🚪", f"вышел(шла) из гильдии вместе с «{name}»" if name else "вышел(шла) из гильдии")
            return doc, {"left": True}, {space: None}

        out = self._update(aid, fn)
        out["alliance"] = None
        return out

    # исключить участника
    def op_ally_kick(self, body, device, ip):
        self._adult_device(device)
        who = self._actor(body, device)
        aid = self._my_alliance(device)
        target = body.get("space")
        now = self.clock()

        def fn(doc):
            self._need(doc, who, "members", "Исключать может глава гильдии или тот, кому он дал это право")
            if target not in doc["members"]:
                raise ApiError(404, "no_member", "Участник не найден")
            if split_ref(doc["leader"])[0] == target:
                raise ApiError(403, "leader", "Нельзя исключить главу гильдии")
            if target == split_ref(who)[0]:
                raise ApiError(400, "self", "Чтобы уйти самим, нажмите «Выйти из гильдии»")
            name = doc["members"][target]["name"]
            _drop_member(doc, target)
            add_feed(doc, now, who, "🚫", f"исключил(а) из гильдии «{name}»")
            return doc, {}, {target: None}

        return self._update(aid, fn)

    # права участника (только глава)
    def op_ally_perms(self, body, device, ip):
        self._adult_device(device)
        who = self._actor(body, device)
        aid = self._my_alliance(device)
        target = body.get("target")
        raw = body.get("perms")
        if not isinstance(raw, list):
            raise ApiError(400, "bad_perms", "Неверный список прав")
        perms = [p for p in PERMS if p in raw]
        now = self.clock()

        def fn(doc):
            if doc["leader"] != who:
                raise ApiError(403, "no_rights", "Права раздаёт только глава гильдии")
            space, hero = split_ref(target if isinstance(target, str) else "")
            m = doc["members"].get(space)
            if m is None or hero not in m["heroes"]:
                raise ApiError(404, "no_member", "Герой не найден в гильдии")
            if target == doc["leader"]:
                raise ApiError(400, "leader", "У главы и так есть все права")
            if perms and m["heroes"][hero].get("k"):
                raise ApiError(403, "kid", "Права управления можно дать только взрослому")
            before = doc["perms"].get(target, [])
            if perms:
                doc["perms"][target] = perms
            else:
                doc["perms"].pop(target, None)
            if not before and perms:
                add_feed(doc, now, who, "🎖", f"дал(а) права управления гильдией: {hero_name(doc, target)}")
            elif before and not perms:
                add_feed(doc, now, who, "🎖", f"снял(а) права управления: {hero_name(doc, target)}")
            return doc, {}, {}

        return self._update(aid, fn)

    # передать главенство
    def op_ally_transfer(self, body, device, ip):
        self._adult_device(device)
        who = self._actor(body, device)
        aid = self._my_alliance(device)
        target = body.get("target")
        now = self.clock()

        def fn(doc):
            if doc["leader"] != who:
                raise ApiError(403, "no_rights", "Передать главенство может только глава гильдии")
            space, hero = split_ref(target if isinstance(target, str) else "")
            m = doc["members"].get(space)
            if m is None or hero not in m["heroes"]:
                raise ApiError(404, "no_member", "Герой не найден в гильдии")
            if m["heroes"][hero].get("k"):
                raise ApiError(403, "kid", "Главой гильдии может быть только взрослый")
            doc["leader"] = target
            doc["perms"].pop(target, None)
            # Бывший глава остаётся с полными правами — как заместитель.
            doc["perms"][who] = list(PERMS)
            add_feed(doc, now, who, "👑", f"передал(а) главенство: теперь глава — {hero_name(doc, target)}")
            return doc, {}, {}

        return self._update(aid, fn)

    # название, герб, девиз
    def op_ally_settings(self, body, device, ip):
        who = self._actor(body, device)
        aid = self._my_alliance(device)

        def fn(doc):
            self._need(doc, who, "settings", "Менять гильдию может глава или тот, кому он дал это право")
            doc["name"] = _s(body.get("name"), MAX_NAME, doc["name"])
            doc["emblem"] = _emoji(body.get("emblem"), doc["emblem"])
            if "motto" in body:
                doc["motto"] = _s(body.get("motto"), MAX_TEXT)
            return doc, {}, {}

        return self._update(aid, fn)

    # объявление
    def op_ally_announce(self, body, device, ip):
        who = self._actor(body, device)
        aid = self._my_alliance(device)
        text = _s(body.get("text"), MAX_TEXT)
        if not text:
            raise ApiError(400, "empty", "Напишите текст объявления")
        now = self.clock()

        def fn(doc):
            self._need(doc, who, "announce", "Объявления пишет глава или тот, кому он дал это право")
            add_feed(doc, now, who, "📣", text)
            return doc, {}, {}

        return self._update(aid, fn)

    # создать или изменить цель гильдии
    def op_ally_goal_save(self, body, device, ip):
        who = self._actor(body, device)
        aid = self._my_alliance(device)
        raw = body.get("goal")
        if not isinstance(raw, dict):
            raise ApiError(400, "bad_goal", "Неверная цель")
        title = _s(raw.get("title"), MAX_TITLE)
        target = _int(raw.get("target"), 1, MAX_TARGET)
        if not title or target is None:
            raise ApiError(400, "bad_goal", "Укажите название и сколько нужно сделать (от 1)")
        deadline = raw.get("deadline")
        deadline = deadline if isinstance(deadline, int) and deadline > 0 else None
        now = self.clock()

        def fn(doc):
            self._need(doc, who, "goals", "Цели гильдии ставит глава или тот, кому он дал это право")
            gid = raw.get("id")
            if gid:
                g = _goal(doc, gid)
                g.update(title=title, emoji=_emoji(raw.get("emoji"), g["emoji"]),
                         description=_s(raw.get("description"), MAX_TEXT), unit=_s(raw.get("unit"), 20, "раз"),
                         target=target, deadline=deadline)
                if not g["done"] and sum(g["contrib"].values()) >= target:
                    g["done"], g["doneAt"] = True, now
                    add_feed(doc, now, who, "🏆", f"цель гильдии «{title}» выполнена!")
                return doc, {"goalId": g["id"]}, {}
            if len([g for g in doc["goals"] if not g.get("done")]) >= MAX_GOALS:
                raise ApiError(409, "too_many", f"Активных целей уже {MAX_GOALS} — завершите или удалите старые")
            g = {
                "id": new_id(10), "title": title, "emoji": _emoji(raw.get("emoji"), "🎯"),
                "description": _s(raw.get("description"), MAX_TEXT), "unit": _s(raw.get("unit"), 20, "раз"),
                "target": target, "deadline": deadline, "createdBy": who, "createdAt": now,
                "done": False, "doneAt": None, "contrib": {},
            }
            doc["goals"].append(g)
            add_feed(doc, now, who, g["emoji"], f"поставил(а) цель гильдии «{title}»: {target} {g['unit']}")
            return doc, {"goalId": g["id"]}, {}

        return self._update(aid, fn)

    def op_ally_goal_delete(self, body, device, ip):
        who = self._actor(body, device)
        aid = self._my_alliance(device)

        def fn(doc):
            self._need(doc, who, "goals", "Цели гильдии удаляет глава или тот, кому он дал это право")
            g = _goal(doc, body.get("goalId"))
            doc["goals"] = [x for x in doc["goals"] if x["id"] != g["id"]]
            return doc, {}, {}

        return self._update(aid, fn)

    # вклад в цель — может любой герой гильдии
    def op_ally_contribute(self, body, device, ip):
        who = self._actor(body, device)
        aid = self._my_alliance(device)
        amount = _int(body.get("amount"), 1, MAX_AMOUNT)
        if amount is None:
            raise ApiError(400, "bad_amount", f"Вклад — от 1 до {MAX_AMOUNT}")
        self._limit(f"ally_contrib:{who}", 60_000, 30)
        now = self.clock()

        def fn(doc):
            space, hero = split_ref(who)
            m = doc["members"].get(space)
            if m is None:
                raise ApiError(404, "no_alliance", "Вы пока не состоите в гильдии")
            if hero not in m["heroes"]:
                # Новый герой семьи, карточка ещё не обновилась — добавим без имени.
                m["heroes"][hero] = {"n": _s(body.get("heroName"), MAX_NAME, "Герой"),
                                     "a": _emoji(body.get("heroAvatar"), "🧙"), "k": device["role"] != "adult"}
            g = _goal(doc, body.get("goalId"))
            if g["done"]:
                raise ApiError(409, "done", "Эта цель гильдии уже выполнена")
            if who not in g["contrib"] and len(g["contrib"]) >= MAX_CONTRIB_KEYS:
                raise ApiError(409, "too_many", "Слишком много участников цели")
            g["contrib"][who] = g["contrib"].get(who, 0) + amount
            total = sum(g["contrib"].values())
            completed = False
            if total >= g["target"]:
                g["done"], g["doneAt"] = True, now
                completed = True
                add_feed(doc, now, who, "🏆", f"завершил(а) цель гильдии «{g['title']}» — все молодцы!")
                _trim_goals(doc)
            return doc, {"total": total, "completed": completed}, {}

        return self._update(aid, fn)

    ALLY_OPS = {
        "ally_create": op_ally_create,
        "ally_get": op_ally_get,
        "ally_member": op_ally_member,
        "ally_invite": op_ally_invite,
        "ally_join": op_ally_join,
        "ally_leave": op_ally_leave,
        "ally_kick": op_ally_kick,
        "ally_perms": op_ally_perms,
        "ally_transfer": op_ally_transfer,
        "ally_settings": op_ally_settings,
        "ally_announce": op_ally_announce,
        "ally_goal_save": op_ally_goal_save,
        "ally_goal_delete": op_ally_goal_delete,
        "ally_contribute": op_ally_contribute,
    }
