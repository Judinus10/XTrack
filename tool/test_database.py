"""Exercise the exact shipped SQL assets using an on-disk SQLite database."""
import sqlite3
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class DatabaseChecks(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.path = Path(self.folder.name) / "test.db"
        self.connect()
        for version in range(1, 4):
            self.migrate(version)
        self.db.execute(
            "INSERT INTO accounts(name,type,opening,icon,color) VALUES(?,?,?,?,?)",
            ("Bank", "Bank account", 45000, "Bank", "Green"),
        )
        self.db.commit()

    def connect(self):
        self.db = sqlite3.connect(self.path)
        self.db.execute("PRAGMA foreign_keys=ON")

    def migrate(self, version):
        self.db.executescript((ROOT / f"assets/v{version}.sql").read_text())

    def tearDown(self):
        self.db.close()
        self.folder.cleanup()

    def balances(self):
        return self.db.execute("""
            SELECT a.opening + COALESCE(SUM(l.delta),0) FROM accounts a
            LEFT JOIN ledger_entries l ON l.account_id=a.id
            GROUP BY a.id ORDER BY a.id
        """).fetchall()

    def transfer(self, amount=15001, destination=2):
        return self.db.execute("""
            INSERT INTO transactions(kind,amount,account,destination,day)
            VALUES('Transfer',?,1,?,'2026-11-21')
        """, (amount, destination)).lastrowid

    def test_transfer_lifecycle_and_restart(self):
        key = self.transfer()
        self.assertEqual(self.balances(), [(-15001,), (60001,)])
        self.db.execute("UPDATE transactions SET amount=12345 WHERE id=?", (key,))
        self.db.commit()
        self.db.close()
        self.connect()
        self.assertEqual(self.balances(), [(-12345,), (57345,)])
        self.assertEqual(self.db.execute(
            "SELECT COUNT(*) FROM transactions WHERE kind IN ('Income','Expense')"
        ).fetchone(), (0,))
        self.db.execute("DELETE FROM transactions WHERE id=?", (key,))
        self.assertEqual(self.balances(), [(0,), (45000,)])

    def test_invalid_transfers(self):
        for amount, dest in [(0, 2), (1.25, 2), (100, 1), (100, 999)]:
            with self.assertRaises(sqlite3.IntegrityError), self.db:
                self.transfer(amount, dest)
        self.assertEqual(self.balances(), [(0,), (45000,)])

    def test_income_expense_and_account_archive(self):
        for kind, category, amount in [('Income', 'Salary', 100000), ('Expense', 'Food', 5999)]:
            self.db.execute("""
                INSERT INTO transactions(kind,category,amount,account,day)
                SELECT ?,id,?,1,'2026-11-22' FROM categories WHERE name=? AND kind=?
            """, (kind, amount, category, kind))
        self.db.execute("UPDATE accounts SET archived=1 WHERE id=1")
        self.assertEqual(self.balances(), [(94001,), (45000,)])

    def test_habit_uniqueness_and_cascade(self):
        self.db.execute("""INSERT INTO habits(name,icon,color,days,start)
                           VALUES('Walk','Leaf','Green',31,'2026-11-01')""")
        self.db.execute("INSERT INTO habit_logs(habit,day) VALUES(1,'2026-11-20')")
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO habit_logs(habit,day) VALUES(1,'2026-11-20')")
        self.db.execute("INSERT INTO reminders(habit,minute) VALUES(1,540)")
        self.db.execute("DELETE FROM habits")
        for table in ["reminders", "habit_logs"]:
            self.assertEqual(self.db.execute(f"SELECT COUNT(*) FROM {table}").fetchone(), (0,))

    def test_failed_restore_rolls_back(self):
        self.transfer()
        self.db.commit()
        with self.assertRaises(sqlite3.IntegrityError), self.db:
            self.db.execute("DELETE FROM transactions")
            self.db.execute("DELETE FROM accounts")
            self.transfer()
        self.assertEqual(self.balances(), [(-15001,), (60001,)])

    def test_task_goal_theme_persist(self):
        self.db.execute("""INSERT INTO tasks(name,category,priority,day,completed)
                           VALUES('Read','Learning','High','2026-11-21','2026-11-22')""")
        self.db.execute("""INSERT INTO goals(name,category,target,current,unit,day,icon,color)
                           VALUES('Read','Learning',1200,300,'books','2026-12-31','Book','Blue')""")
        self.db.execute("UPDATE goals SET current=400")
        self.db.execute("INSERT INTO settings VALUES('theme','dark')")
        self.db.commit()
        self.db.close()
        self.connect()
        self.assertEqual(self.db.execute("SELECT completed FROM tasks").fetchone(), ('2026-11-22',))
        self.assertEqual(self.db.execute("SELECT target-current FROM goals").fetchone(), (800,))
        self.assertEqual(self.db.execute("SELECT value FROM settings WHERE key='theme'").fetchone(), ('dark',))

    def test_demo_clear_isolation(self):
        self.db.execute("""INSERT INTO accounts(name,type,opening,icon,color,demo)
                           VALUES('Example','Cash',123,'Wallet','Blue',1)""")
        self.db.execute("""INSERT INTO transactions(kind,amount,account,category,day,demo)
                           VALUES('Income',12,3,1,'2026-11-22',1)""")
        self.transfer()
        for table in ['transactions', 'accounts', 'habits', 'tasks', 'goals']:
            self.db.execute(f"DELETE FROM {table} WHERE demo=1")
        self.assertEqual(self.balances(), [(-15001,), (60001,)])

    def test_existing_install_migrates(self):
        with sqlite3.connect(':memory:') as db:
            db.executescript((ROOT / 'assets/v1.sql').read_text())
            db.execute("""INSERT INTO habits(name,icon,color,days,start)
                          VALUES('Run','Fitness','Green',31,'2026-01-01')""")
            for version in [2, 3]:
                db.executescript((ROOT / f'assets/v{version}.sql').read_text())
            self.assertEqual(db.execute("SELECT habit,day,days FROM habit_schedules").fetchone(),
                             (1, '2026-01-01', 31))


if __name__ == '__main__':
    unittest.main(verbosity=2)

