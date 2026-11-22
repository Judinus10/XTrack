# XTrack

An offline Android personal tracker built with Flutter, Riverpod, SQLCipher-backed SQLite, FL Chart, local notifications, secure storage and device biometrics. The initial database contains a zero-balance cash account and transaction categories. Settings → Demo records adds optional sample activity.

## Build the Android app

Use Flutter 3.32.8, JDK 17 and Android SDK Platform 35. Install Android SDK command-line tools, accept the Android licenses, and configure an emulator or an Android 6.0+ phone. The project includes the Gradle 8.10.2 wrapper. First-time dependency installation requires internet access on the development computer. The app's tracking features work offline.

From the folder containing `pubspec.yaml`:

```sh
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

The debug APK is written to `build/app/outputs/flutter-apk/app-debug.apk`. Install it with `adb install -r build/app/outputs/flutter-apk/app-debug.apk`, or use `flutter run`. Commit the generated `pubspec.lock` after the first successful dependency resolution.

The included **Android debug verification** GitHub Actions workflow can also be run manually in a repository containing this project. It runs the database checks, analysis and Flutter tests and attaches the APK after a successful build.

## Use the app

- **Home** shows this month's cash flow, today's tasks and habits, goals and recent transactions. The eye button hides financial amounts and financial charts across overview screens.
- **Quick Add** creates income, expenses, transfers, habits, tasks and goals. Create another account under Finance before transferring. Tap existing rows to edit. Transactions support search across accounts, category, date and description.
- **Finance** opens on the current month. Switch to week, year or all time. The balance card always shows the total ledger balance. Income and expense totals follow the selected date filter.
- **Habits** supports daily and selected-weekday schedules. Tap a day in the week strip to check in or undo. Arrows browse earlier weeks. History lists completion dates. Schedule changes take effect on the edit date.
- **Tasks** includes carried-over overdue tasks in Today. Upcoming shows future pending tasks. Completing a task records its completion date and cancels its reminder.
- **Goals** is accessible from Home → Active goals → View all. Choose Update progress to enter the new cumulative value. Goal values support two decimal places.
- **Analytics** is available beside This month on Home. Week begins on Monday. Monthly charts use seven-day groups starting on day 1. Yearly charts use months. Goal summaries use deadlines within the selected period.
- **Settings** controls system/light/dark appearance, currency labels, notifications, app lock, encrypted backup, demo data and reset.

## Data and calculation rules

- Money is parsed from decimal text directly into integer hundredths. The default unit is LKR. One tracker uses one currency display label. Changing it does not perform exchange-rate conversion.
- The SQLite ledger view derives both postings of a transfer from one transaction row. An edit or deletion affects both balances in the same commit. Only Income and Expense rows contribute to cash-flow charts.
- Opening balances form the starting baseline of the trend. Editing an opening balance revises that baseline. Archived accounts retain their history and continue to contribute their balance.
- Each habit and local date has one unique check-in. Streaks count consecutive scheduled days. A pending check-in today can still extend yesterday's streak. Archived intervals pause the schedule.
- Demo transactions use separate demo accounts. Clearing demo data also removes associated schedules, logs and reminders. Personal records remain in place.
- Writes run in SQLite transactions. Riverpod publishes a consistent snapshot to all active screens after each commit. Migrations are applied sequentially from SQL assets. Reminders and habit logs use cascading foreign keys.

## Reminders and security

Enable notifications in Settings and allow Android's notification permission. Set the time on a task or habit. Tasks use one local-time alarm. Habits repeat on the selected weekdays. Editing, completing, archiving, deleting, restoring and resetting reconcile the pending alarms. The app reconciles again on resume. Android may delay inexact reminders under power restrictions. Notification text is generic.

A random 256-bit SQLCipher password is kept in Flutter Secure Storage. The optional six-digit PIN uses a salted PBKDF2-HMAC-SHA256 verifier with 210,000 iterations. After five failures the device imposes progressively longer waits, up to 15 minutes. Attempt state persists across app restarts. Biometrics require an enabled PIN and a supported, enrolled device. The lock covers the current navigation stack when the app returns from the background. Android secure-window protection conceals app content in screenshots and recent-app previews.

Backups use a separate passphrase of at least ten characters, a random salt, PBKDF2-HMAC-SHA256 and authenticated AES-256-GCM encryption. Android's local document picker handles export and import. Restore replaces the current records in one transaction. Device authentication secrets and the database key are excluded. The current file size limit is 32 MiB. Keep the passphrase available for restore. Reset clears tracker records, preferences, alarms and app-lock configuration. The device database stays encrypted.

## Verification

**Executed in the delivery environment:** Eight Python/SQLite tests passed using the shipped schema, migration scripts and ledger view on disk. They cover transfer posting, edits and deletion, restart persistence, invalid transfers, income and expenses, archive behavior, habit uniqueness and cascades, task/goal/theme persistence, restore rollback and demo isolation. Android resource and manifest XML parsed successfully. The bundled Gradle wrapper JAR passed archive integrity checks.

```sh
python tool/test_database.py
```

**Unverified:** Flutter dependency resolution, static analysis, Flutter tests, native SQLCipher integration, APK compilation/installation, rendered layouts and theme changes, Android notification delivery, biometric prompts, background locking and Android backup picker behavior. The delivery environment lacked Flutter, Dart and the Android SDK. All four requested Flutter commands were attempted and stopped at “flutter: command not found”. No APK or resolved lockfile was generated.

`flutter test` runs the included money, streak, encrypted-backup and widget tests. The separate Android integration suite exercises native storage, pending notifications, cancellation, PIN attempts and reopening. **Use a disposable emulator** because the integration suite resets XTrack's data. For Android 13 or later, install the debug APK and grant notifications before the run:

```sh
adb shell pm grant lk.xtrack.app android.permission.POST_NOTIFICATIONS
flutter test integration_test/device_test.dart -d emulator-5554
```

For device acceptance, create a task reminder several minutes ahead and verify actual delivery with the screen off. Edit and delete another reminder and confirm the old one does not fire. Enable PIN and biometrics, background the app from an open editor, and verify that unlocking restores that editor. Export a backup, change a record, then restore the backup and check the restored value. Test with airplane mode enabled.

## Source layout

| Path | Responsibility |
| --- | --- |
| `lib/main.dart`, `lib/ui/` | Bootstrap, routing, app lock, shared widgets and themes |
| `lib/features/` | Dashboard, finance, charts, editors, tasks, habits, goals and settings |
| `lib/core/` | Store, scheduling, metrics, encryption and optional sample records |
| `assets/v*.sql` | Tables, constraints, indexes, schedule history and ledger view |
| `android/` | Native host, local file picker, timezone, biometrics and notification receivers |
| `test/`, `integration_test/`, `tool/` | Widget, domain, Android integration and host SQLite checks |

