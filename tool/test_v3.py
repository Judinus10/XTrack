import sqlite3
import unittest
from pathlib import Path

assets = Path(__file__).resolve().parents[1] / "assets"
class Upgrade(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        self.addCleanup(self.db.close)
        self.db.execute("PRAGMA foreign_keys=ON")
        for n in range(1, 5):
            self.db.executescript((assets / f"v{n}.sql").read_text())
        self.db.execute("INSERT INTO transactions(kind,amount,account,category,day) VALUES('Income',76543,1,1,'2026-11-01')")
        self.db.execute("INSERT INTO tasks(name,priority,category,day) VALUES('Review','High','Work','2026-11-25')")
        self.db.executescript((assets / "v5.sql").read_text())

    def test_upgrade(self):
        self.assertEqual(self.db.execute("SELECT delta FROM ledger_entries").fetchall(), [(76543,)])
        self.assertEqual(self.db.execute("SELECT name,stage FROM tasks").fetchall(), [('Review', 'To Do')])
        self.assertFalse(self.db.execute("PRAGMA foreign_key_check").fetchall())

    def test_principal(self):
        for i, kind, sign in [(1, 'Debt', 1), (2, 'Lending', -1)]:
            self.db.execute("INSERT INTO loans VALUES(?,?,?,1,50000,'2026-11-01','2027-01-01')", (i, kind, kind))
            self.db.execute("INSERT INTO repayments VALUES(?,?,1,'2026-11-25',10000,0)", (i, i))
            self.assertEqual(self.db.execute("SELECT SUM(delta) FROM ledger_entries").fetchone()[0], 116543 if sign == 1 else 76543)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM transactions").fetchone()[0], 1)

    def test_one_active_session(self):
        self.db.execute("INSERT INTO focus_sessions(name,started) VALUES('Study',123)")
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO focus_sessions(name,started) VALUES('Study',124)")

    def test_schedule_deduplication(self):
        self.db.execute("INSERT INTO recurring(name,kind,amount,account,category,next,frequency,anchor) VALUES('Pay','Income',100,1,1,'2026-11-25','Monthly',25)")
        self.db.execute("INSERT INTO occurrences(rule,day) VALUES(1,'2026-11-25')")
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO occurrences(rule,day) VALUES(1,'2026-11-25')")

if __name__ == '__main__':
    unittest.main()
