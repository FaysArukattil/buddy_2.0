# Buddy — Handoff State

**Last updated:** 2026-10-31T14:17:00+05:30
**Last completed task:** Task 4 — Privacy-safe Firebase Analytics for parser monitoring
**Git HEAD:** e1d5131 (Task 3) + uncommitted Task 4 changes (commit pending)

---

## Completed Tasks

| Task | Status | Commit |
|------|--------|--------|
| Step 0 — Handoff system | ✅ DONE | — |
| Task 1 — Forced/Prompted App Update | ✅ DONE | `cce44af` |
| Task 2 — Country/Currency Selection & Global Symbol | ✅ DONE | `04b9c6d`, `8454a3c` |
| Task 3 — Global Bank SMS Parsing architecture | ✅ DONE | `e1d5131` |
| Task 4 — Firebase Analytics (parser monitoring) | ✅ DONE | to be committed |
| Task 5 — Release Checklist | 🔴 NOT STARTED | — |

---

## Current State (after Task 4)

- `flutter analyze` → **No issues**
- `flutter test` → **130 tests, all pass** (was 115; +15 new analytics tests)
- `pubspec.yaml` has `firebase_analytics: ^11.3.6` (fetched)
- `android/app/build.gradle.kts` has `implementation("com.google.firebase:firebase-analytics-ktx")`
- Task 4 changes are **not yet committed** — commit immediately before starting Task 5

---

## Task 4 — What Was Done

### New Files
- `lib/services/parse_analytics_service.dart` — privacy-safe analytics service
  - 3 events: `parse_success`, `parse_ignored`, `parse_failed`
  - `ParseIgnoreReason` constants: `otp`, `promo`, `no_amount`, `no_verb`, `no_bank_id`, `auto_detect_off`, `duplicate`
  - `ParseFailedReason` constants: `invalid_amount`, `unknown`, `no_rule`
  - Every call wrapped in try/catch — analytics **NEVER** crashes the parser
  - NEVER logs: message text, amounts, merchant names, account numbers
  - Only logs: country_code (ISO 3166-1), source_pkg (app package name), parser_used, reason_code
- `test/parse_analytics_service_test.dart` — 15 tests verifying non-throwing behavior

### Modified Files
- `lib/services/notification_service.dart`
  - Added `dart:async` (unawaited) import
  - Added `parse_analytics_service.dart` import
  - After successful Firestore sync in `syncSavedTransactions()`: calls `ParseAnalyticsService.logParseSuccess()` with `country_code` and `parser_used` read from the SharedPrefs JSON written by Kotlin
- `android/app/src/main/kotlin/com/faysarukattil/buddy/NotificationListener.kt`
  - Added `android.os.Bundle` and `com.google.firebase.analytics.FirebaseAnalytics` imports
  - Added `logParserEvent()` private helper (wraps Firebase Analytics; all in try/catch)
  - `parseTransaction()`: reads `country_code` from SharedPrefs (lazy val); logs `parse_ignored` at every rejection point (otp, promo, no_verb, no_bank_id, no_amount); logs `parse_failed` for invalid_amount
  - `onNotificationPosted()`: logs `parse_success` after successful `saveTransaction()`
  - `saveTransaction()`: now writes `country_code` and `parser_used: "india"` into the SharedPrefs JSON so the Dart sync path can read them for analytics
- `android/app/build.gradle.kts`
  - Added `implementation("com.google.firebase:firebase-analytics-ktx")`

---

## Exact Next Step: Task 5 — Release Checklist

### 5.0 Commit Task 4 first
```bash
cd "/Users/faysarukattil/Desktop/Personal Projects/buddy_2.0"
git add -A
git commit -m "Task 4: Privacy-safe parser monitoring via Firebase Analytics"
```

### 5.1 Check Firestore security rules
- Look for `firestore.rules` in project root
- Add read/write rules for new user doc fields: `countryCode`, `currencyCode`, `localeCode`, `currencySymbol`
- These are stored at `users/{uid}` (the user document)

### 5.2 Bump version
In `pubspec.yaml`:
```yaml
version: 17.2.0+19
```
In `android/app/build.gradle.kts` — version is read from `flutter.versionCode` / `flutter.versionName` (from pubspec), so only pubspec needs updating.

### 5.3 Run full verification
```bash
flutter analyze   # must be clean
flutter test      # must pass (130 tests)
```

### 5.4 Kotlin tests
```bash
cd android && ./gradlew test
```
Runs `BankSmsParserTest.kt` — protects India parsing. Requires Android SDK / Gradle.

### 5.5 Update HANDOFF.md + TASKS.md, final git commit
Commit message: `Task 5: Release prep — bump version, security rules, release checklist`

---

## Architecture Decisions (key ones — see DECISIONS.md for full list)

| # | Decision |
|---|----------|
| 1 | Indian SMS parsing stays hardcoded in Kotlin `NotificationListener.kt` — never touched |
| 2 | Non-India parsing: `GenericParser` + `bank_rules.json` (Dart side only) |
| 3 | `CurrencyService` is the single source of truth for currency — no hardcoded ₹ |
| 4 | Existing users default to India/INR/en_IN silently — no forced re-onboarding |
| 5 | Currency change = display-only; no value conversion |
| 6 | Analytics events NEVER include message text, amounts, names, account numbers |
| 7 | `Task 3C` (bank_rules.json via Remote Config): `reloadFromRemoteConfig()` is implemented; wiring to actual RC fetch is **deferred post-launch** |

---

## Critical Constraints

- **NEVER change** `NotificationListener.kt` Indian parsing logic (add-only; `BankSmsParserTest.kt` is the regression guard)
- **NEVER force existing users** through onboarding again
- All update checks, analytics, and parsing wrapped in try/catch — nothing may crash the app
- Git commands require `BypassSandbox: true`; Flutter commands require `BypassSandbox: true`
- After EVERY sub-task: tick TASKS.md, update HANDOFF.md, git commit

---

## Test Suite State

| File | Tests | Status |
|------|-------|--------|
| `test/update_service_test.dart` | 12 | ✅ pass |
| `test/deduplication_and_note_clean_test.dart` | 5 | ✅ pass |
| `test/withdrawal_sms_test.dart` | varies | ✅ pass |
| `test/parsing/dart_parser_test.dart` | 62 | ✅ pass |
| `test/parse_analytics_service_test.dart` | 15 | ✅ pass |
| Other widget/network/pdf tests | ~36 | ✅ pass |
| **Total** | **130** | **✅ all pass** |
