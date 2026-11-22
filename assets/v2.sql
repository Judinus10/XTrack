CREATE INDEX transactions_day ON transactions(day);
CREATE INDEX transactions_account ON transactions(account);
CREATE INDEX transactions_destination ON transactions(destination);
CREATE INDEX tasks_due ON tasks(day,completed);
CREATE INDEX habit_logs_day ON habit_logs(day);
