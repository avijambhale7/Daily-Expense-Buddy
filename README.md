# Daily Expense Buddy

**Track Today. Spend Smarter.**

Daily Expense Buddy is a personal expense tracker for Android, iOS and the web,
built from one Flutter codebase. You can record an expense in a few seconds,
see daily, weekly, monthly and yearly totals, keep a daily tracking habit with
reminders, and sync everything across devices through Firebase.

---

## Contents

1. [Features](#features)
2. [Project structure](#project-structure)
3. [Architecture decisions](#architecture-decisions)
4. [Dependencies](#dependencies)
5. [Getting started](#getting-started)
6. [Firebase setup](#firebase-setup)
7. [Running locally with the Firebase Emulator Suite](#running-locally-with-the-firebase-emulator-suite)
8. [Running the app](#running-the-app)
9. [Testing](#testing)
10. [Building](#building)
11. [Deploying the web app](#deploying-the-web-app)
12. [Data model and storage conventions](#data-model-and-storage-conventions)
13. [Security and privacy](#security-and-privacy)
14. [Known limitations and remaining configuration](#known-limitations-and-remaining-configuration)
15. [Replacing the logo](#replacing-the-logo)

---

## Features

| Area | What works |
|---|---|
| Authentication | Email/password sign-up and login, logout, password reset email, email verification (required before any data access), session restore, account settings, account deletion with re-authentication. Links in Firebase emails open an in-app screen (`/auth/action`, Android App Link or web) that applies the code with Firebase and shows verified / expired / invalid / retry states. See [docs/EMAIL_VERIFICATION_SETUP.md](docs/EMAIL_VERIFICATION_SETUP.md) |
| Splash & intro | Short animated splash at launch. Four intro slides (Skip, Back, Next, Get started) shown once per device to signed-out visitors. Signed-in users never see them. They can be replayed from Settings → Feature tour |
| Expenses | Add, edit and delete. Past dates are supported. Amount is the only required field (category defaults to "Other"). Optional merchant, note and payment method. Duplicate-submit protection |
| Dashboard | Greeting, today's spending with a labelled progress ring (budget left today, or days tracked this week), Add Expense, this week / this month totals, this-week bar chart, recent expenses, today's completion status, missed-day prompt |
| History | Grouped list on phones, table on desktop. Search (merchant/note), date range, category, payment method, newest/oldest sorting. Every filter runs on the server with a page limit (composite indexes in `firestore.indexes.json`). "Clear filters (n)" also resets the search. Stale results from a previous filter are discarded. Incremental loading, CSV export of the current filters |
| Reports | Day, week, month, year and custom ranges with previous/next navigation. Total, average per calendar day, **estimated spending** (This week / This month: spent so far ÷ elapsed calendar days × days in the period; disabled while a past period is shown), highest/lowest day, monthly figures for years, category breakdown, comparison with the equivalent previous period |
| Lending & Borrowing | Money lent / borrowed with person, amount, date, optional due date and note. Partial repayments with date and note are stored as immutable history. Status: Outstanding, Partially repaid, Fully repaid, Cancelled. Overpayment is rejected (in the app and by the security rules). Totals for money lent, borrowed, returned to me, repaid by me and outstanding, per currency. Search by name, lent/borrowed filter, active/closed lists, one due-date reminder per loan. Kept separate from expense reports |
| Sound effects | Optional, off by default (Settings → Sound effects). Short bundled sounds after an expense is saved, a day is completed, a repayment is recorded or a loan is fully repaid. Played only after the write succeeded |
| Calendar | Month grid with daily totals and tracking status (completed / confirmed no expenses / not reviewed). Tap a day to review it, add expenses or complete it |
| Reminders | Daily reminder (default 22:00) with configurable follow-ups (default 22:45, 23:30), quiet hours, permission explanation before prompting. Reminders for a day are removed as soon as it is marked complete on any device |
| Budgets | Monthly overall budget plus optional per-category budgets. Threshold alerts (default 80% and 100%), sent at most once per budget, threshold and month across all devices |
| Categories | 12 built-in categories, plus custom ones. Rename, recolor or archive any category. Delete custom categories only when no expense uses them |
| Themes | Light, Dark and System (free). Ocean Blue, Forest Green, Sunset, Lavender and Midnight are premium palettes. Everything is driven by one theme pipeline, so components, charts and states all adapt |
| Currency | Reporting currency (INR, USD, EUR, GBP, JPY, AUD, CAD, AED, SGD, CHF, KWD) with correct minor-unit precision (JPY 0, KWD 3) and locale-aware formatting |
| Settings | Profile, currency, week start, number/date format, theme, reminders, budgets, categories, export, privacy, password reset, premium status, help, version, logout, delete account |
| Responsive UI | Phones get bottom navigation. Tablets get a navigation rail. Desktops/web get a sidebar dashboard layout with tables, hover states, tooltips and an Alt+N shortcut |

---

## Project structure

```
lib/
  main.dart                      Entry point → app/bootstrap.dart
  firebase_options.dart          PLACEHOLDER – replaced by `flutterfire configure`
  app/
    bootstrap.dart               Initialisation (locale, Firebase, notifications)
    firebase_initializer.dart    Firebase / emulator / App Check setup
    app.dart                     MaterialApp.router + theme + global providers
    app_dependencies.dart        Composition root (injectable for tests)
    router.dart, routes.dart     go_router config and the auth redirect guard
    session/                     Per-user session: repositories + long-lived cubits
  core/
    dates/                       LocalDate (calendar date type), ReportPeriod
    money/                       Currency config, integer money math, parser, formatter
    theme/                       Palettes, AppTheme (single ThemeData builder), tokens
    formatting/, validation/, errors/, logging/, widgets/
  domain/
    models/                      Expense, ExpenseCategory, Budget, DailyStatus,
                                 UserPreferences, UserProfile, ReportSummary, …
    repositories/                Repository interfaces
    services/                    ReportCalculator, BudgetCalculator, TrackingStatusService,
                                 ReminderPlanner, CsvExporter, ExpenseValidator
  data/firebase/                 Firebase Auth + Firestore implementations
  services/
    notifications/               Local notifications (mobile scheduling, web in-session)
    export/                      File download (web) / share sheet (mobile)
  features/                      auth, dashboard, expenses, history, reports,
                                 calendar, budgets, categories, reminders,
                                 settings, premium, export, shell
  shared/                        Charts and expense list tiles
assets/
  branding/                      Logo assets used in the app
  icons/                         Source images for launcher icons
  fonts/inter/                   Inter (SIL OFL 1.1), bundled
firestore.rules                  Security rules
firestore.indexes.json           Composite indexes
firebase.json                    Firestore, Hosting and emulator configuration
firebase/rules-tests/            Security-rules tests (Node, run on the emulator)
test/                            unit/, repository/, widget/ tests
integration_test/                End-to-end test against the emulators
```

Screens never query Firestore directly and never do their own money math.
They go through cubits and blocs, which call repositories and the calculation
services in `domain/services`.

---

## Architecture decisions

- **State management.** The app uses `flutter_bloc`. Most features use Cubits. History uses an
  event-driven BLoC (filters, search, load-more).
- **Material library.** The app imports `package:material_ui`, the official Material
  package that `go_router` 18 depends on. This avoids having two separate `Theme`
  and `MaterialApp` types in the app.
- **Money.** Every amount is an `int` number of **minor units**, using each currency's
  precision. Parsing goes from text straight to integers, with no floating point.
  Averages use integer division with half-away-from-zero rounding. A double
  appears only when a value is handed to the number formatter for display.
- **Dates.** An expense's calendar date is stored as a `yyyy-MM-dd` string and handled
  as the `LocalDate` type, so time zones can never move it to another day.
  `createdAt` and `updatedAt` are separate server timestamps.
- **Single-currency reporting.** Each expense stores its own currency. Reports and
  budgets include only expenses in the reporting currency. Expenses in other
  currencies are counted and flagged, never summed, and never converted with
  made-up exchange rates.
- **Concurrency.** Each expense has a `version` field. The security rules require
  `new version == stored version + 1`. If an edit made from stale data (for
  example offline on a second device) arrives later, the server rejects it
  instead of silently overwriting the newer change, and the user sees a "changed
  on another device" message.
- **Duplicate prevention.** The expense ID is generated when the form opens and
  written with `set()`, so re-submitting can't create a second document. The save
  button is also disabled while a save is in progress.
- **Offline and sync.** Firestore offline persistence is on for Android and iOS. Writes
  apply locally at once. If the server hasn't acknowledged a write within 4
  seconds, the UI says *"Saved on this device. It will sync when you are
  online"*, and expenses with pending changes show a cloud icon. A late server
  rejection is reported through `SyncIssueReporter`. On the web the cache is
  memory-only, so data doesn't stay in a shared browser.
- **Local storage.** No separate SQLite or Drift database is used. Firestore's own
  persistent cache is the local database for financial records. A second store
  would add a second sync path without adding value. `shared_preferences` holds
  only the theme, so it can be applied before sign-in.
- **Derived data.** Totals are always computed from the expense records. No
  aggregate documents are stored that could drift out of sync.
- **Session isolation.** A new `UserSession` (repositories bound to the
  authenticated UID, plus cubits and coordinators) is created on every sign-in
  and disposed on sign-out. On sign-out the mobile Firestore cache is cleared.

### Calculation definitions

These are implemented in `ReportCalculator` and unit-tested.

| Metric | Definition |
|---|---|
| Total | Sum of positive expenses in the reporting currency dated inside the period |
| Average per calendar day | Total ÷ elapsed calendar days of the period. For a past period that is every day. For the current period it counts days up to today. Future days are never counted |
| Average per spending day | Total ÷ distinct days with expenses. Not shown when there are none |
| Highest day | The day with the largest total |
| Lowest day | The smallest **non-zero** day. Zero days are reported separately as "days without expenses" |
| Comparison | Against the equivalent previous period: previous day, week, calendar month or year, or a custom range of the same length. No percentage is shown when the previous total is zero |
| Week | Seven days starting on the user's week-start day |

---

## Dependencies

| Package | Purpose |
|---|---|
| `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_app_check` | Firebase |
| `flutter_bloc`, `equatable` | State management |
| `go_router` | Routing, deep links, browser URLs, auth guard |
| `material_ui` | Material Design widgets |
| `fl_chart` | Charts |
| `intl` | Locale-aware currency, number and date formatting |
| `flutter_local_notifications`, `timezone`, `flutter_timezone` | Reminders |
| `shared_preferences` | Theme persistence only |
| `share_plus`, `path_provider`, `web` | CSV export |
| `package_info_plus` | App version in Settings |
| Dev: `fake_cloud_firestore`, `firebase_auth_mocks`, `bloc_test`, `mocktail`, `flutter_launcher_icons`, `integration_test` | Testing and tooling |

Built and verified with **Flutter 3.47.5 / Dart 3.13.4**.

---

## Getting started

```bash
flutter pub get
```

Without Firebase configuration the app starts on a **"Firebase setup required"**
screen. It never fakes a login. To configure Firebase, follow the next section,
or use the [emulators](#running-locally-with-the-firebase-emulator-suite) for
local development.

---

## Firebase setup

> Never use unrestricted "test mode" rules. Deploy `firestore.rules` from this
> repository before storing any real data.

1. **Create a Firebase project** in the [Firebase console](https://console.firebase.google.com).
2. **Install the CLIs** (Node.js is required):
   ```bash
   npm install -g firebase-tools
   firebase login
   dart pub global activate flutterfire_cli
   ```
3. **Register the apps and generate `lib/firebase_options.dart`** from the project root:
   ```bash
   flutterfire configure --platforms=android,ios,web
   ```
   - Android package name: `com.dailyexpensebuddy.app`
   - iOS bundle ID: `com.dailyexpensebuddy.app`

   This overwrites the placeholder `lib/firebase_options.dart`. It also writes
   `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`.
   These files contain client identifiers, not secrets.
4. **Enable Email/Password sign-in:** Console → Authentication → Sign-in method → Email/Password → Enable.
   Optionally, under Authentication → Settings, turn on *email enumeration protection*.
5. **Create Cloud Firestore:** Console → Firestore Database → Create database.
   Choose a location and start in **production mode**.
6. **Deploy the rules and indexes:**
   ```bash
   firebase use --add          # select your project
   firebase deploy --only firestore:rules,firestore:indexes
   ```
7. **Authorized domains (web):** Console → Authentication → Settings → Authorized domains.
   Add your hosting domain (`<project>.web.app` is added automatically) and any
   custom domain.
8. **App Check (recommended for production):**
   - Android: register the app with **Play Integrity**. You need your app's SHA-256 fingerprint.
   - iOS: register with **App Attest** (DeviceCheck is the fallback).
   - Web: create a **reCAPTCHA v3** site key and register it in App Check.
   - Build with `--dart-define=APP_CHECK=true --dart-define=RECAPTCHA_SITE_KEY=<public site key>`.
     Debug builds use debug providers. Register the debug token printed in the logs.
   - Turn on **enforcement** for Firestore only after you have verified the
     metrics. App Check is an extra layer; the security rules remain the access
     control.
9. **Premium entitlements (optional):** premium themes unlock when
   `users/{uid}/entitlements/premium` contains `{active: true, expiresAt?: Timestamp}`.
   The rules block client writes to this document. A trusted backend must write
   it, for example a Cloud Function that verifies Play or App Store purchases.
   For manual testing you can write it with the Firebase console or the Admin SDK.

### Account deletion backend (recommended)

The app deletes the user's data from the client in batches, and it must be
online to do so. It then deletes the Auth account. If you also want cleanup when
an account is deleted outside the app (for example from the console), install
the **Delete User Data** Firebase Extension configured for `users/{UID}`
(recursive), or deploy an equivalent Cloud Function.

---

## Running locally with the Firebase Emulator Suite

No real project or credentials are needed. The app connects to a `demo-` project.
The emulators need **Java 21+**.

```bash
firebase emulators:start --only auth,firestore --project demo-daily-expense-buddy
# in another terminal
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATOR=true
flutter run -d <android-emulator> --dart-define=USE_FIREBASE_EMULATOR=true   # uses 10.0.2.2
```

- On a physical device, add `--dart-define=FIREBASE_EMULATOR_HOST=<your PC's LAN IP>`
  and start the emulators with `--host 0.0.0.0` (or set `host` in `firebase.json`).
- Verification emails are not sent by the emulator. Open the Emulator UI at
  http://localhost:4000 → Authentication, or use the link printed in the
  emulator log, then press **"I've verified my email"** in the app.
- Debug Android builds allow cleartext HTTP so they can reach the emulators.
  Release builds don't.

---

## Running the app

```bash
flutter run -d chrome          # web
flutter run -d <android-id>    # Android device or emulator
flutter run -d <ios-id>        # iOS (macOS with Xcode required)
```

Optional build flags:

| Flag | Effect |
|---|---|
| `--dart-define=USE_FIREBASE_EMULATOR=true` | Use local emulators |
| `--dart-define=FIREBASE_EMULATOR_HOST=…` | Emulator host override |
| `--dart-define=APP_CHECK=true` | Activate App Check |
| `--dart-define=RECAPTCHA_SITE_KEY=…` | reCAPTCHA v3 site key (web App Check) |
| `--dart-define=PREMIUM_PREVIEW=true` | **Debug builds only**: preview premium themes |

---

## Testing

```bash
flutter analyze
flutter test                    # unit + repository + widget tests
```

- `test/unit`: money parsing and precision, rounding, dates, leap years, week
  starts, report periods, every report metric, dashboard figures, budgets, daily
  tracking states, reminder planning, CSV escaping, validation, theme
  persistence, and the route guard (including open-redirect protection).
- `test/repository`: the real Firestore repositories on `fake_cloud_firestore`.
  Covers CRUD, versioning, idempotent create, range queries, pagination,
  filters, per-user isolation, categories, statuses, preferences, alert claims,
  entitlement and data deletion.
- `test/widget`: the full app with fake Firebase. Covers the setup screen,
  welcome, login and sign-up validation, the email verification gate, the
  dashboard empty state, add-expense validation and save (which updates the
  dashboard and Firestore), phone, tablet and desktop navigation, dark-mode
  switching and persistence, the error state and sign-out.

**Security rules tests** (emulator, Java 21+):

```bash
cd firebase/rules-tests && npm install && cd ../..
firebase emulators:exec --only firestore --project demo-daily-expense-buddy \
  "npm --prefix firebase/rules-tests test"
```

**End-to-end integration test** (emulators plus an Android emulator or device):

```bash
firebase emulators:start --only auth,firestore --project demo-daily-expense-buddy
flutter test integration_test -d <android-device-id> --dart-define=USE_FIREBASE_EMULATOR=true
```

The test signs up, verifies the email through the emulator, adds, edits and
deletes expenses, receives a server-side change made "from another device",
checks reports, switches the theme, logs out and logs back in. These are
**emulator tests, not production tests.**

---

## Building

```bash
flutter build web --release
flutter build apk --debug
flutter build apk --release          # configure signing first (below)
flutter build appbundle --release    # for Google Play
flutter build ipa                    # macOS + Xcode + Apple developer account
```

**Android release signing:** the release build type currently signs with
debug keys so `flutter run --release` works. Before publishing, create a
keystore, add a `signingConfigs.release` block in `android/app/build.gradle.kts`
that reads its values from a `key.properties` file (don't commit that file),
and point `buildTypes.release` at it.
See https://docs.flutter.dev/deployment/android.

**Windows note:** `android/gradle.properties` sets `kotlin.incremental=false`.
Kotlin's incremental compiler fails when the pub cache and the project are on
different drives.

---

## Deploying the web app

```bash
flutter build web --release
firebase deploy --only hosting
```

`firebase.json` serves `build/web` with SPA rewrites (so deep links and refresh
work) and security headers. Add any custom domain to the Auth authorized
domains.

---

## Data model and storage conventions

```
users/{uid}                              displayName, createdAt, schemaVersion
users/{uid}/expenses/{id}                amountMinor:int, currency:'INR', categoryId, date:'yyyy-MM-dd',
                                         note?, merchant?, paymentMethod?, createdAt, updatedAt, version:int
users/{uid}/categories/{id}              overrides for built-ins + custom categories
users/{uid}/budgets/{overall|cat_<id>}   amountMinor, currency, categoryId?
users/{uid}/budget_alerts/{yyyy-MM}_{budgetId}   highest threshold already notified
users/{uid}/daily_status/{yyyy-MM-dd}    status: 'completed' | 'no_expenses'
users/{uid}/loans/{id}                   direction:'lent'|'borrowed', personName, amountMinor, repaidMinor,
                                         currency, date, dueDate?, note?, settled, cancelled?, createdAt, updatedAt
users/{uid}/loans/{id}/repayments/{id}   amountMinor, date, note?, createdAt (immutable)
users/{uid}/settings/preferences         currency, week start, format locale, reminders, alert thresholds
users/{uid}/entitlements/premium         server-written only
```

- No daily-status document means **"not reviewed"**. A day without expenses is
  **not** treated as a confirmed zero-spending day.
- Changing the reporting currency doesn't change stored amounts. Each expense
  keeps its own currency.
- Deleted expenses are hard-deleted, so they disappear from every report on all
  devices.

---

## Security and privacy

- Every collection is scoped to `users/{uid}`, and the rules check
  `request.auth.uid == uid` **and** `email_verified == true`.
- Dates must be real calendar dates (`2025-02-31` and `2025-02-29` are
  rejected, `2024-02-29` is accepted).
- A loan repayment is accepted only in the same atomic write that raises the
  loan's `repaidMinor` by exactly its amount, and `repaidMinor` can never
  exceed the loan amount. Repayments cannot be edited.
- Writes are schema-validated: allowed keys, types, ranges, `yyyy-MM-dd` dates,
  ISO currency codes, positive integer amounts, server timestamps, and a version
  that increases by one.
- Clients can't write entitlements or other users' data. Any path not listed
  in the rules is denied.
- No service-account keys, Admin credentials or private API keys are in the
  client. The Firebase web config is public by design.
- Logs record component names and error codes only. They never include
  passwords, tokens, emails, amounts or notes.
- Passwords and sessions are handled only by Firebase Authentication.
- Post-login redirects accept only internal paths, which prevents open redirects.
- On the web, Firestore data is cached in memory only. On mobile, the cache is
  cleared on logout. Logout warns you if changes haven't synced yet.

---

## Known limitations and remaining configuration

**Requires your action**
- **Email branding and in-app links need console steps.** The subject, sender
  name, message and action URL of Firebase emails can only be changed in the
  Firebase Console. Follow
  [docs/EMAIL_VERIFICATION_SETUP.md](docs/EMAIL_VERIFICATION_SETUP.md). Until
  then, emails keep Firebase's default wording and links open Firebase's
  default page.
- **The web app isn't deployed to Hosting yet.** Run `flutter build web` and
  then `firebase deploy --only hosting`. The App Links file
  (`.well-known/assetlinks.json`) is served from there.
- **App Check is off by default.** Turn it on with `--dart-define=APP_CHECK=true`
  after registering the providers.
- **Release signing** (Android keystore, Apple certificates) isn't configured.
- **No purchases.** Premium themes need a server-written entitlement. The app
  never simulates a purchase.

**Platform limitations**
- **Web reminders** fire only while the app is open in a tab. Closed-tab
  reminders would need Firebase Cloud Messaging plus a backend scheduler, which
  isn't implemented. The plugin also registers its own service worker for
  notifications, and only once reminders are enabled.
- **Android reminders** use inexact alarms, so the OS may delay them by several
  minutes (Doze). Reminders are scheduled 14 days ahead and refreshed whenever
  the app opens. If the app isn't opened for over two weeks, reminders stop
  until the next launch.
- **iOS** allows at most 64 pending notifications. The plan uses at most 42
  (14 days × 3).
- **iOS hasn't been built or run.** This environment is Windows. The iOS
  project is configured (bundle ID, notification delegate), but you need macOS
  and Xcode to build it.

**Product scope**
- **Single reporting currency.** Expenses in other currencies are flagged and
  excluded from totals. There is no exchange-rate conversion: adding one needs
  a rate provider and stored historical rates per expense.
- **Loan reminders** follow the main daily-reminder switch and time. There is
  no separate switch.
- **Search** covers merchant and note within the loaded history pages, because
  Firestore has no full-text search. Load more to search further back.
- **Yearly reports** load that year's expenses, plus the previous year's for
  the comparison. That's fine for personal-scale data. Very large histories
  would benefit from monthly aggregate documents maintained by a Cloud Function.
- **Account deletion** runs from the client and requires a connection. If some
  data can't be deleted, the account is **not** deleted and the app says so.
- **Sync isn't a backup.** Use CSV export to keep your own copy.
- **The UI is in English.** Number and date formats follow the device locale or
  the chosen format locale.

---

## Replacing the logo

- `assets/branding/logo_mark.png`: the square logo mark used in the app, ideally
  transparent and at least 384×384.
- `assets/branding/logo_full.png` and `wordmark.png`: full logo and wordmark.
- `assets/icons/app_icon.png` (1024×1024, opaque) and
  `assets/icons/app_icon_foreground.png` (1024×1024, transparent, artwork
  within the central ~60%): launcher icon sources.

After replacing them, regenerate the launcher icons:

```bash
dart run flutter_launcher_icons
```

If a branding asset is missing, the app falls back to a vector wallet icon.

Fonts: Inter is bundled from `assets/fonts/inter/` under the SIL Open Font
License (`OFL.txt`).
# Daily-Expense-Buddy
