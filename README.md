# XTrack V3 development build

Offline Flutter Android personal tracker. Apply the replacement ZIP at the V2 project root, or extract the full source and open the folder containing pubspec.yaml. Make an encrypted V2 backup before upgrading. Preserve the Android application ID and use the same signing key when updating an existing installation.

## Build

Use Flutter 3.32.8, Android SDK 35 and Java 17. From the project root run:

    flutter pub get
    flutter analyze
    flutter test
    flutter build apk --debug

The expected output is build/app/outputs/flutter-apk/app-debug.apk. The repository also includes a manually triggered Android debug build workflow.

## Implemented

Five main tabs, contextual Quick Add, configurable dashboard, task agenda and week selector, project assignments, task times, subtasks, Kanban, persistent focus sessions and goal milestones. Personal includes weight history, water, sleep, exercise, measurements, mood and journal entries. Finance adds category and monthly budgets, manual asset values, debts, lending, repayment history, net worth, recurring postings and subscriptions. Recurring amounts catch up when the database refreshes. PDF summaries and transaction CSV import/export are under More. CSV import expects the export column order and unambiguous account/category names. Recycle bin supports tasks, habits, goals, transactions, personal logs, budgets and assets. Select reminder snooze duration in Settings.

## Migration and verification

Schema version 5 extends the V2 version 4 schema. Loan principal movements enter the ledger separately from income and expenses. Restore accepts schema versions 3–5. Keep forecasts and anticipated maturity amounts outside actual balances.

Run python tool/test_database.py and python tool/test_v3.py. Eight earlier checks and four V3 SQLite checks passed. Flutter SDK was unavailable in the delivery environment. Dependency resolution, analyzer, widget tests, Android build, actual notification delivery, rendered screens and Android file exports require validation.

## Outstanding scope

The full requested V3 specification is incomplete. Outstanding areas include automatic encrypted backup retention, receipt and progress-photo attachments, expanded security history and configurable auto-lock, complete notification history/quiet hours/briefings, widgets and shortcuts, cash-flow forecast, fixed deposit renewal and early withdrawal, budget alerts, manual-confirmation recurrence, detailed investment valuation history, recurring tasks and task templates, time blocks across all modules, quantity/duration/frequency habit schedules, advanced goal links, and complete cross-module analytics and reports. Personal records currently use simple dated logs. The planner lists scheduled tasks and habits. A focus session records elapsed time between start and finish.
