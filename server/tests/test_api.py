import json
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from rodquest_server.core import Api, ApiError, Mailer, http_call, plan_push, Change, Row  # noqa: E402
from rodquest_server.store_sqlite import SqliteStore  # noqa: E402


class FakeMailer(Mailer):
    def __init__(self):
        self.sent = []

    def send_code(self, email, code, purpose):
        self.sent.append((email, code, purpose))


class Clock:
    def __init__(self):
        self.t = 1_800_000_000_000

    def __call__(self):
        return self.t


class ApiTest(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.mail = FakeMailer()
        self.api = Api(SqliteStore(), self.mail, clock=self.clock)

    def call(self, op, token=None, ip="1.1.1.1", **body):
        return self.api.handle({"op": op, **body}, token, ip)

    def guild(self, heroes=("dad",)):
        return self.call("create_guild", name="Пешки", deviceName="Папин телефон", heroIds=list(heroes))

    def join(self, head, role="adult", heroes=()):
        code = self.call("invite", head["token"], role=role)["code"]
        return self.call("join", code=code[:4] + "-" + code[4:].lower(), deviceName="Телефон", heroIds=list(heroes))

    def push(self, dev, *changes):
        return self.call("push", dev["token"], changes=[
            {"k": k, "d": None if d is None else json.dumps(d), "base": base, "s": s} for k, d, base, s in changes
        ])

    # ---------- основное ----------

    def test_create_join_push_pull(self):
        head = self.guild()
        self.assertEqual(head["role"], "adult")
        r = self.push(head, ("hero/dad", {"id": "dad", "xp": 10}, 0, "all"),
                      ("goal/g1", {"id": "g1"}, 0, "all"))
        self.assertEqual(r["rev"], 2)
        self.assertTrue(all(x["ok"] for x in r["results"]))

        mom = self.join(head, heroes=["mom"])
        self.assertEqual(mom["guildName"], "Пешки")
        p = self.call("pull", mom["token"], since=0)
        self.assertEqual(p["rev"], 2)
        self.assertEqual({c["k"] for c in p["changes"]}, {"hero/dad", "goal/g1"})
        # Нового ничего — пустой ответ
        self.assertEqual(self.call("pull", mom["token"], since=2)["changes"], [])

    def test_invite_is_single_use_and_expires(self):
        head = self.guild()
        code = self.call("invite", head["token"], role="kid")["code"]
        self.call("join", code=code)
        with self.assertRaises(ApiError) as e:
            self.call("join", code=code)
        self.assertEqual(e.exception.code, "bad_code")
        code2 = self.call("invite", head["token"])["code"]
        self.clock.t += 49 * 3600 * 1000
        with self.assertRaises(ApiError):
            self.call("join", code=code2)

    def test_conflict_returns_fresh_version(self):
        head = self.guild()
        mom = self.join(head)
        self.push(head, ("hero/dad", {"xp": 10}, 0, "all"))  # rev 1
        r = self.push(mom, ("hero/dad", {"xp": 20}, 0, "all"))
        c = r["results"][0]
        self.assertTrue(c["conflict"])
        self.assertEqual(json.loads(c["d"]), {"xp": 10})
        self.assertEqual(c["r"], 1)
        r = self.push(mom, ("hero/dad", {"xp": 30}, 1, "all"))
        self.assertTrue(r["results"][0]["ok"])
        self.assertEqual(r["rev"], 2)

    def test_delete_and_tombstones(self):
        head = self.guild()
        mom = self.join(head)
        self.push(head, ("goal/a", {"t": 1}, 0, "all"), ("goal/b", {"t": 2}, 0, "all"))
        self.push(head, ("goal/a", None, 1, "all"))
        p = self.call("pull", mom["token"], since=0)
        self.assertEqual([c["k"] for c in p["changes"]], ["goal/b"])  # новому — без удалённых
        p = self.call("pull", mom["token"], since=2)
        self.assertEqual(p["changes"], [{"k": "goal/a", "r": 3, "d": None}])

    def test_same_data_is_not_a_new_revision(self):
        head = self.guild()
        self.push(head, ("goal/a", {"t": 1}, 0, "all"))
        r = self.push(head, ("goal/a", {"t": 1}, 1, "all"))
        self.assertEqual(r["rev"], 1)

    # ---------- видимость ----------

    def test_kid_cannot_see_or_write_budget(self):
        head = self.guild(heroes=["dad"])
        kid = self.join(head, role="kid", heroes=["kid"])
        self.push(head, ("money/m1", {"sum": 100}, 0, "adults"), ("goal/g", {"t": 1}, 0, "all"))
        p = self.call("pull", kid["token"], since=0)
        self.assertEqual([c["k"] for c in p["changes"]], ["goal/g"])
        r = self.push(kid, ("money/m1", {"sum": 0}, 1, "adults"), ("money/m2", {"sum": 5}, 0, "all"))
        self.assertTrue(r["results"][0]["denied"])
        # m2 с видимостью all — разрешено (это просто запись юнги, не бюджет)
        self.assertTrue(r["results"][1]["ok"])
        with self.assertRaises(ApiError):
            self.call("invite", kid["token"])

    def test_private_goals_only_on_owner_devices(self):
        head = self.guild(heroes=["dad"])
        mom = self.join(head, heroes=["mom"])
        self.push(head, ("goal/p", {"t": "секрет"}, 0, "private:dad"))
        self.assertEqual(self.call("pull", mom["token"], since=0)["changes"], [])
        self.assertEqual(len(self.call("pull", head["token"], since=0)["changes"]), 1)
        # Цель стала личной после того, как мама её получила — маме приходит удаление
        self.push(head, ("goal/s", {"t": 1}, 0, "all"))  # rev 2
        self.push(head, ("goal/s", {"t": 1}, 2, "private:dad"))  # rev 3
        p = self.call("pull", mom["token"], since=2)
        self.assertEqual(p["changes"], [{"k": "goal/s", "r": 3, "d": None}])
        # Мама начала играть за папу на своём телефоне — видит
        self.call("set_heroes", mom["token"], heroIds=["mom", "dad"])
        self.assertEqual(len(self.call("pull", mom["token"], since=0)["changes"]), 2)

    def test_conflict_hides_invisible_data(self):
        head = self.guild(heroes=["dad"])
        kid = self.join(head, role="kid", heroes=["kid"])
        self.push(head, ("goal/p", {"t": "секрет"}, 0, "private:dad"))
        r = self.push(kid, ("goal/p", {"t": "x"}, 0, "all"))
        self.assertTrue(r["results"][0]["conflict"])
        self.assertIsNone(r["results"][0]["d"])

    # ---------- проверки ----------

    def test_bad_input(self):
        head = self.guild()
        for bad in ([{"k": "BAD KEY", "d": "{}"}], [{"k": "goal/a", "d": "not json"}],
                    [{"k": "goal/a", "d": "{}", "s": "everyone"}], "x"):
            with self.assertRaises(ApiError):
                self.call("push", head["token"], changes=bad)
        with self.assertRaises(ApiError) as e:
            self.call("pull", "wrong-token", since=0)
        self.assertEqual(e.exception.status, 401)
        with self.assertRaises(ApiError):
            self.call("hack")

    def test_join_rate_limited(self):
        self.guild()
        for _ in range(20):
            with self.assertRaises(ApiError) as e:
                self.call("join", code="AAAAAAAA", ip="6.6.6.6")
            self.assertEqual(e.exception.code, "bad_code")
        with self.assertRaises(ApiError) as e:
            self.call("join", code="AAAAAAAA", ip="6.6.6.6")
        self.assertEqual(e.exception.code, "too_many")

    def test_pull_pages(self):
        head = self.guild()
        changes = [{"k": f"feed/{i}", "d": "{}", "base": 0, "s": "all"} for i in range(500)]
        self.call("push", head["token"], changes=changes)
        self.call("push", head["token"], changes=[dict(c, k=c["k"] + "x") for c in changes[:100]])
        p1 = self.call("pull", head["token"], since=0)
        self.assertTrue(p1["more"])
        self.assertEqual(len(p1["changes"]), 500)
        p2 = self.call("pull", head["token"], since=p1["rev"])
        self.assertFalse(p2["more"])
        self.assertEqual(len(p2["changes"]), 100)
        self.assertEqual(p2["rev"], 600)

    # ---------- устройства ----------

    def test_devices_and_revoke(self):
        head = self.guild()
        mom = self.join(head)
        devs = self.call("devices", head["token"])["devices"]
        self.assertEqual([d["me"] for d in devs], [True, False])
        self.call("revoke", head["token"], deviceId=mom["deviceId"])
        with self.assertRaises(ApiError) as e:
            self.call("pull", mom["token"], since=0)
        self.assertEqual(e.exception.code, "revoked")
        self.call("leave", head["token"])
        with self.assertRaises(ApiError):
            self.call("guild", head["token"])

    # ---------- почта ----------

    def test_email_link_and_recover(self):
        head = self.guild()
        self.call("email_link_start", head["token"], email=" Papa@Ya.ru ")
        email, code, purpose = self.mail.sent[-1]
        self.assertEqual((email, purpose), ("papa@ya.ru", "link"))
        with self.assertRaises(ApiError):
            self.call("email_link_finish", head["token"], email="papa@ya.ru", code="000000" if code != "000000" else "111111")
        r = self.call("email_link_finish", head["token"], email="papa@ya.ru", code=code)
        self.assertEqual(r["email"], "p**a@ya.ru")
        self.assertEqual(self.call("guild", head["token"])["email"], "p**a@ya.ru")

        # Неизвестная почта — «отправлено», но письма нет
        n = len(self.mail.sent)
        self.call("recover_start", email="nobody@ya.ru")
        self.assertEqual(len(self.mail.sent), n)

        self.call("recover_start", email="papa@ya.ru")
        _, code, purpose = self.mail.sent[-1]
        self.assertEqual(purpose, "recover")
        dev = self.call("recover_finish", email="papa@ya.ru", code=code, deviceName="Новый телефон")
        self.assertEqual(dev["role"], "adult")
        self.assertEqual(dev["guildId"], head["guildId"])
        # Код одноразовый
        with self.assertRaises(ApiError):
            self.call("recover_finish", email="papa@ya.ru", code=code)

    def test_email_code_attempts(self):
        head = self.guild()
        self.call("email_link_start", head["token"], email="a@b.ru")
        _, code, _ = self.mail.sent[-1]
        wrong = "%06d" % ((int(code) + 1) % 1_000_000)
        for _ in range(5):
            with self.assertRaises(ApiError):
                self.call("email_link_finish", head["token"], email="a@b.ru", code=wrong)
        with self.assertRaises(ApiError):
            self.call("email_link_finish", head["token"], email="a@b.ru", code=code)

    def test_email_taken_by_other_guild(self):
        a, b = self.guild(), self.guild()
        self.call("email_link_start", a["token"], email="x@y.ru")
        self.call("email_link_finish", a["token"], email="x@y.ru", code=self.mail.sent[-1][1])
        with self.assertRaises(ApiError) as e:
            self.call("email_link_start", b["token"], email="x@y.ru")
        self.assertEqual(e.exception.code, "email_taken")

    def test_kid_cannot_link_email(self):
        head = self.guild()
        kid = self.join(head, role="kid")
        with self.assertRaises(ApiError):
            self.call("email_link_start", kid["token"], email="k@y.ru")


class HttpTest(unittest.TestCase):
    def test_http_wrapper(self):
        api = Api(SqliteStore(), FakeMailer())
        s, h, b = http_call(api, "OPTIONS", {}, b"")
        self.assertEqual(s, 204)
        s, h, b = http_call(api, "POST", {}, json.dumps({"op": "create_guild", "name": "Г"}).encode())
        self.assertEqual(s, 200)
        token = json.loads(b)["token"]
        s, h, b = http_call(api, "POST", {"X-Rodquest-Token": token}, b'{"op":"pull","since":0}')
        self.assertEqual(s, 200)
        s, h, b = http_call(api, "POST", {"Authorization": f"Bearer {token}"}, b'{"op":"pull","since":0}')
        self.assertEqual(s, 200)
        self.assertEqual(json.loads(b)["rev"], 0)
        s, h, b = http_call(api, "POST", {}, b'{"op":"pull"}')
        self.assertEqual(s, 401)
        self.assertEqual(json.loads(b)["error"], "no_token")
        s, h, b = http_call(api, "POST", {}, b"garbage")
        self.assertEqual(s, 400)
        self.assertEqual(h["Access-Control-Allow-Origin"], "*")

    def test_cloud_handler_options_without_db(self):
        import index
        r = index.handler({"httpMethod": "OPTIONS", "headers": {}}, None)
        self.assertEqual(r["statusCode"], 204)


class PlanTest(unittest.TestCase):
    def test_plan_counts_revisions(self):
        dev = {"role": "adult", "hero_ids": []}
        plan = plan_push(5, [Change("a/1", "{}", 0, "all"), Change("a/2", None, 0, "all"),
                             Change("a/3", "{}", 3, "all")],
                         {"a/3": Row("a/3", 4, "{}", "all")}, dev)
        self.assertEqual(plan.new_rev, 6)
        self.assertEqual([w.key for w in plan.writes], ["a/1"])
        self.assertTrue(plan.results[2]["conflict"])


if __name__ == "__main__":
    unittest.main()
