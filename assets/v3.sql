CREATE TABLE habit_schedules(id INTEGER PRIMARY KEY AUTOINCREMENT,habit INTEGER NOT NULL REFERENCES habits(id) ON DELETE CASCADE,day TEXT NOT NULL,days INTEGER NOT NULL CHECK(days BETWEEN 0 AND 127),UNIQUE(habit,day));
INSERT INTO habit_schedules(habit,day,days) SELECT id,start,days FROM habits;
CREATE VIEW ledger_entries AS SELECT id AS tx,day,account AS account_id,CASE WHEN kind='Income' THEN amount ELSE -amount END AS delta FROM transactions UNION ALL SELECT id,day,destination,amount FROM transactions WHERE kind='Transfer';
