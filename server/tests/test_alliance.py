"""Тесты гильдии v0.9: союз семей, кланов и одиночек, права, цели и вклад."""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from rodquest_server.core import Api, ApiError  # noqa: E402
from rodquest_server.store_sqlite import SqliteStore  # noqa: E402
from test_api import Clock, FakeMailer  # noqa: E402


def member(kind, name, heroes):
    return {"kind": kind, "name": name, "emoji": "🏡",
            "heroes": {h: {"n": h.title(), "a": "🧙", "k": h.startswith("kid")} for h in heroes}}


class AllianceTest(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.api = Api(SqliteStore(), FakeMailer(), clock=self.clock)
        self.ip = 0

    def call(self, op, token=None, **body):
        self.ip += 1  # разные адреса — не упираемся в ограничения частоты
        return self.api.handle({"op": op, **body}, token, f"10.0.0.{self.ip % 250}")

    def space(self, heroes, role="adult"):
        dev = self.call("create_guild", name="Семья", deviceName="Телефон", heroIds=list(heroes))
        if role == "kid":
            code = self.call("invite", dev["token"], role="kid")["code"]
            kid = self.call("join", code=code, deviceName="Телефон юнги", heroIds=["kid1"])
            return dev, kid
        return dev

    def ally(self, dev, hero, heroes, kind="family", name="Ивановы"):
        return self.call("ally_create", dev["token"], heroId=hero, name="Северный союз", emblem="🐺",
                         member=member(kind, name, heroes))

    def join(self, inviter, inviter_hero, dev, hero, heroes, kind="family", name="Петровы"):
        code = self.call("ally_invite", inviter["token"], heroId=inviter_hero)["code"]
        return self.call("ally_join", dev["token"], heroId=hero, code=code, member=member(kind, name, heroes))

    def test_families_clans_and_solo_join_one_guild(self):
        a = self.space(["dad", "kid1"])
        r = self.ally(a, "dad", ["dad", "kid1"])
        self.assertEqual(r["alliance"]["leader"], f"{a['guildId']}|dad")
        b = self.space(["mom"])
        c = self.space(["solo"])
        self.join(a, "dad", b, "mom", ["mom"], kind="clan", name="Клан Волков")
        r = self.join(a, "dad", c, "solo", ["solo"], kind="solo", name="Лёша")
        doc = r["alliance"]
        self.assertEqual(len(doc["members"]), 3)
        self.assertEqual({m["kind"] for m in doc["members"].values()}, {"family", "clan", "solo"})
        # Одна семья — одна гильдия.
        with self.assertRaises(ApiError) as e:
            self.ally(b, "mom", ["mom"])
        self.assertEqual(e.exception.code, "in_alliance")
        # Все видят одну гильдию, ver растёт; без изменений — короткий ответ.
        g = self.call("ally_get", c["token"])
        self.assertEqual(g["alliance"]["id"], doc["id"])
        self.assertTrue(self.call("ally_get", c["token"], ver=g["ver"])["same"])

    def test_family_invite_code_does_not_work_for_guild_and_back(self):
        a = self.space(["dad"])
        self.ally(a, "dad", ["dad"])
        ally_code = self.call("ally_invite", a["token"], heroId="dad")["code"]
        with self.assertRaises(ApiError):
            self.call("join", code=ally_code)
        fam_code = self.call("invite", a["token"])["code"]
        b = self.space(["mom"])
        with self.assertRaises(ApiError):
            self.call("ally_join", b["token"], heroId="mom", code=fam_code, member=member("family", "П", ["mom"]))
        # Код семьи после попытки не сгорел.
        self.call("join", code=fam_code)

    def test_rights_granted_by_leader(self):
        a = self.space(["dad"])
        self.ally(a, "dad", ["dad"])
        b = self.space(["mom"])
        self.join(a, "dad", b, "mom", ["mom"])
        mom = f"{b['guildId']}|mom"
        goal = {"title": "1000 отжиманий", "target": 1000, "unit": "раз"}
        # Без прав — нельзя ставить цели, приглашать, менять название.
        for op, body in [("ally_goal_save", {"goal": goal}), ("ally_invite", {}),
                         ("ally_settings", {"name": "Новое"}), ("ally_announce", {"text": "Привет"})]:
            with self.assertRaises(ApiError) as e:
                self.call(op, b["token"], heroId="mom", **body)
            self.assertEqual(e.exception.code, "no_rights", op)
        # Права раздаёт только глава.
        with self.assertRaises(ApiError):
            self.call("ally_perms", b["token"], heroId="mom", target=mom, perms=["goals"])
        r = self.call("ally_perms", a["token"], heroId="dad", target=mom, perms=["goals", "announce", "bogus"])
        self.assertEqual(r["alliance"]["perms"][mom], ["goals", "announce"])
        self.call("ally_goal_save", b["token"], heroId="mom", goal=goal)
        self.call("ally_announce", b["token"], heroId="mom", text="Все на зарядку!")
        with self.assertRaises(ApiError):
            self.call("ally_invite", b["token"], heroId="mom")
        # Снять права.
        r = self.call("ally_perms", a["token"], heroId="dad", target=mom, perms=[])
        self.assertNotIn(mom, r["alliance"]["perms"])

    def test_kid_can_contribute_but_not_manage(self):
        head, kid = self.space(["dad"], role="kid")
        self.call("set_heroes", kid["token"], heroIds=["kid1"])
        r = self.ally(head, "dad", ["dad", "kid1"])
        gid = self.call("ally_goal_save", head["token"], heroId="dad",
                        goal={"title": "Книги", "target": 3, "unit": "книги"})["goalId"]
        r = self.call("ally_contribute", kid["token"], heroId="kid1", goalId=gid, amount=1)
        self.assertEqual(r["total"], 1)
        with self.assertRaises(ApiError) as e:
            self.call("ally_perms", head["token"], heroId="dad", target=f"{head['guildId']}|kid1", perms=["goals"])
        self.assertEqual(e.exception.code, "kid")
        with self.assertRaises(ApiError):
            self.call("ally_leave", kid["token"], heroId="kid1")
        # Чужого героя устройство выдать за себя не может.
        with self.assertRaises(ApiError) as e:
            self.call("ally_contribute", kid["token"], heroId="dad", goalId=gid, amount=1)
        self.assertEqual(e.exception.code, "no_hero")

    def test_contributions_complete_goal(self):
        a = self.space(["dad"])
        self.ally(a, "dad", ["dad"])
        b = self.space(["mom"])
        self.join(a, "dad", b, "mom", ["mom"])
        gid = self.call("ally_goal_save", a["token"], heroId="dad",
                        goal={"title": "Пробежать 100 км", "target": 100, "unit": "км", "emoji": "🏃"})["goalId"]
        self.call("ally_contribute", a["token"], heroId="dad", goalId=gid, amount=60)
        r = self.call("ally_contribute", b["token"], heroId="mom", goalId=gid, amount=45)
        self.assertTrue(r["completed"])
        g = [x for x in r["alliance"]["goals"] if x["id"] == gid][0]
        self.assertTrue(g["done"])
        self.assertEqual(g["contrib"], {f"{a['guildId']}|dad": 60, f"{b['guildId']}|mom": 45})
        with self.assertRaises(ApiError) as e:
            self.call("ally_contribute", b["token"], heroId="mom", goalId=gid, amount=1)
        self.assertEqual(e.exception.code, "done")
        with self.assertRaises(ApiError):
            self.call("ally_contribute", b["token"], heroId="mom", goalId=gid, amount=0)

    def test_kick_leave_and_transfer(self):
        a = self.space(["dad"])
        self.ally(a, "dad", ["dad"])
        b = self.space(["mom"])
        c = self.space(["solo"])
        self.join(a, "dad", b, "mom", ["mom"])
        self.join(a, "dad", c, "solo", ["solo"], kind="solo")
        # Глава не уходит, пока есть другие.
        with self.assertRaises(ApiError) as e:
            self.call("ally_leave", a["token"], heroId="dad")
        self.assertEqual(e.exception.code, "leader")
        # Исключить может тот, у кого есть право.
        self.call("ally_perms", a["token"], heroId="dad", target=f"{b['guildId']}|mom", perms=["members"])
        r = self.call("ally_kick", b["token"], heroId="mom", space=c["guildId"])
        self.assertNotIn(c["guildId"], r["alliance"]["members"])
        self.assertIsNone(self.call("ally_get", c["token"])["alliance"])
        with self.assertRaises(ApiError):
            self.call("ally_kick", b["token"], heroId="mom", space=a["guildId"])  # главу — нельзя
        # Передать главенство и уйти.
        r = self.call("ally_transfer", a["token"], heroId="dad", target=f"{b['guildId']}|mom")
        self.assertEqual(r["alliance"]["leader"], f"{b['guildId']}|mom")
        self.call("ally_leave", a["token"], heroId="dad")
        doc = self.call("ally_get", b["token"])["alliance"]
        self.assertEqual(list(doc["members"]), [b["guildId"]])
        self.assertEqual(doc["perms"], {})
        # Последний участник уходит — гильдия удаляется.
        r = self.call("ally_leave", b["token"], heroId="mom")
        self.assertTrue(r["deleted"])
        self.assertIsNone(self.call("ally_get", b["token"])["alliance"])
        self.ally(b, "mom", ["mom"])  # можно основать новую

    def test_member_card_update_and_settings(self):
        a = self.space(["dad"])
        self.ally(a, "dad", ["dad"])
        r = self.call("ally_member", a["token"], member=member("clan", "Клан Ивановых", ["dad", "mom"]))
        m = r["alliance"]["members"][a["guildId"]]
        self.assertEqual(m["kind"], "clan")
        self.assertEqual(set(m["heroes"]), {"dad", "mom"})
        v = r["ver"]
        r = self.call("ally_member", a["token"], member=member("clan", "Клан Ивановых", ["dad", "mom"]))
        self.assertEqual(r["ver"], v)  # без изменений версия не растёт
        r = self.call("ally_settings", a["token"], heroId="dad", name="Южный союз", emblem="🦅", motto="Вместе!")
        self.assertEqual((r["alliance"]["name"], r["alliance"]["emblem"], r["alliance"]["motto"]),
                         ("Южный союз", "🦅", "Вместе!"))


if __name__ == "__main__":
    unittest.main()
