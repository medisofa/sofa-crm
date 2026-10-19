import unittest
from datetime import datetime, timedelta, timezone

STAFF = {"admin", "super_admin", "assistant", "billing", "glosas", "auditor"}

def permitted(user, org, memberships, exceptions, now):
    active = [m for m in memberships if m["user"] == user and m["active"]]
    staff = any(m["kind"] == "operator" and m["role"] in STAFF for m in active)
    if staff:
        # Model fixture: operator access to clients is explicitly assigned, never global.
        return any(m["org"] == org and m["kind"] == "client" for m in active)
    clients = [m for m in active if m["kind"] == "client"]
    if not any(m["org"] == org for m in clients):
        return False
    if len(clients) == 1:
        return True
    primary = min(clients, key=lambda m: m["created"])["org"]
    if org == primary:
        return True
    return any(e["user"] == user and e["org"] == org
               and e["until"] > now and not e["revoked"] for e in exceptions)

class PolicyModelTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 10, 18, tzinfo=timezone.utc)
        self.ms = [
            dict(user="A", org="A", kind="client", role="client", active=True, created=1),
            dict(user="B", org="B", kind="client", role="client", active=True, created=1),
        ]

    def test_isolation(self):
        self.assertTrue(permitted("A", "A", self.ms, [], self.now))
        self.assertFalse(permitted("A", "B", self.ms, [], self.now))
        self.assertFalse(permitted("B", "A", self.ms, [], self.now))

    def test_second_org_requires_exception(self):
        m = self.ms + [dict(user="A", org="B", kind="client", role="capturer", active=True, created=2)]
        self.assertFalse(permitted("A", "B", m, [], self.now))
        e = [dict(user="A", org="B", until=self.now + timedelta(days=1), revoked=False)]
        self.assertTrue(permitted("A", "B", m, e, self.now))
        self.assertFalse(permitted("A", "B", m, e, self.now + timedelta(days=2)))
        e[0]["revoked"] = True
        self.assertFalse(permitted("A", "B", m, e, self.now))

    def test_operator_exception_is_not_global(self):
        m = self.ms + [
            dict(user="S", org="SOFA", kind="operator", role="billing", active=True, created=1),
            dict(user="S", org="A", kind="client", role="billing", active=True, created=2),
        ]
        self.assertTrue(permitted("S", "A", m, [], self.now))
        self.assertFalse(permitted("S", "B", m, [], self.now))

    def test_inactive_does_not_grant(self):
        m = [dict(user="A", org="A", kind="client", role="client", active=False, created=1)]
        self.assertFalse(permitted("A", "A", m, [], self.now))

if __name__ == "__main__":
    unittest.main(verbosity=2)
