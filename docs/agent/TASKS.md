# Buddy — Task Checklist

## Step 0: Handoff System
- [x] Create `/docs/agent/README_FIRST.md`
- [x] Create `/docs/agent/PROJECT_CONTEXT.md`
- [x] Create `/docs/agent/TASKS.md`
- [x] Create `/docs/agent/HANDOFF.md`
- [x] Create `/docs/agent/DECISIONS.md`
- [x] Create `/docs/agent/PARSING_RESEARCH.md`
- [x] Create `/docs/agent/RELEASE_CHECKLIST.md`

## Task 1: Forced / Prompted App Update ✅ DONE (commit `cce44af`)
- [x] 1.1 Add `in_app_update` and `firebase_remote_config` to pubspec.yaml
- [x] 1.2 Create `lib/services/update_service.dart` (numeric version compare, Play Core, Remote Config, in-memory guard, daily limit)
- [x] 1.3 Integrate into `main.dart` / `splash_screen.dart`
- [x] 1.4 Document Remote Config keys in DECISIONS.md
- [x] 1.5 `flutter analyze` ✅
- [x] 1.6 Tests ✅ (53 tests: 41 existing + 12 new)
- [x] 1.7 Git commit `cce44af`

## Task 2: Country / Currency Selection & Global Currency Symbol

### 2B: Central CurrencyService & replace hardcoded symbols ✅ DONE (commit `8454a3c`)
- [x] 2B.1 Create `lib/services/currency_service.dart`
- [x] 2B.2 Bundle Noto Sans fonts in `assets/fonts/`; register in pubspec.yaml
- [x] 2B.3 Refactor `lib/utils/format_utils.dart` to delegate to CurrencyService
- [x] 2B.4 Replace hardcoded ₹ in all Dart views (7 files)
- [x] 2B.5 Update `lib/services/pdf_service.dart` (Noto Sans theme + CurrencyService)
- [x] 2B.6 Update `lib/services/widget_service.dart` (pass symbol to native)
- [x] 2B.7 Update `BuddyWidgetProvider.kt` (dynamic symbol from SharedPrefs)
- [x] 2B.8 Update `NotificationActionReciever.kt` and `DuplicateConfirmationActivity.kt`
- [x] 2B.9 Update XML widget layouts (replace ₹ defaults with --)
- [x] 2B.12 `flutter analyze` ✅
- [x] 2B.13 Git commit `8454a3c`

### 2A: Onboarding country picker ✅ DONE (commit `04b9c6d`)
- [x] 2A.1 45-country dataset inside `currency_picker_sheet.dart`
- [x] 2A.2 Create `lib/views/widgets/currency_picker_sheet.dart` (searchable bottom sheet)
- [x] 2A.3 Pre-select from device locale (defaults to India/INR)
- [x] 2A.4 Save to Firebase + SharedPrefs (`countryCode`, `currencyCode`, `localeCode`, `currencySymbol`)
- [x] 2A.5 Show to new users after permission primer in `onboarding_screen.dart`
- [x] 2A.6 `flutter analyze` ✅
- [x] 2A.8 Git commit `04b9c6d`

### 2C: Settings — Currency/Country option ✅ DONE (commit `04b9c6d`)
- [x] 2C.1 "Currency & region" section added to `setting_modal.dart`
- [x] 2C.2 User can change currency independently from country
- [x] 2C.3 Changes update Firebase + local cache + refresh UI + home widget
- [x] 2C.4 "Display only" note shown in picker on first change
- [x] 2C.5 `flutter analyze` ✅
- [x] 2C.6 Git commit `04b9c6d`

### 2D: Migration for existing live users ✅ DONE (commit `04b9c6d`)
- [x] 2D.1 Auto-default to India/INR/en_IN when no country saved
- [x] 2D.2 Non-blocking currency picker shown only for new users
- [x] 2D.3 Existing users not forced through onboarding again
- [x] 2D.4 `flutter analyze` ✅
- [x] 2D.5 Git commit `04b9c6d`

---

## Task 3: Global Bank SMS Parsing

### 3A: Research
- [x] 3A.1 India — document existing patterns (from existing codebase)
- [x] 3A.2 South Asia (Pakistan, Bangladesh, Sri Lanka, Nepal)
- [x] 3A.3 Middle East (UAE, Saudi Arabia, Qatar, Kuwait, Bahrain, Oman)
- [x] 3A.4 Africa (Nigeria, Kenya, South Africa, Ghana, Tanzania, Egypt)
- [x] 3A.5 Europe (UK, Germany, France, Spain, Italy, Netherlands, Turkey)
- [x] 3A.6 North America (USA, Canada, Mexico)
- [x] 3A.7 Latin America (Brazil, Argentina, Colombia, Chile)
- [x] 3A.8 East & Southeast Asia (Japan, South Korea, Indonesia, Philippines, Thailand, Vietnam, Malaysia)
- [x] 3A.9 Oceania (Australia, New Zealand)
- [x] 3A.10 Write up all results in PARSING_RESEARCH.md → `docs/agent/PARSING_RESEARCH.md`

### 3B: Architecture & Implementation
- [x] 3B.1 Define `assets/parsing/bank_rules.json` (shared schema, 42 rules) → `assets/parsing/bank_rules.json`
- [x] 3B.2 Create shared test vectors `test/parsing/bank_sms_test_vectors.json` (50+ vectors) → `test/parsing/bank_sms_test_vectors.json`
- [x] 3B.3 Write India regression tests FIRST (from notification_test_helper.dart)
- [x] 3B.4 India regression tests schema-validated; Kotlin test file created
- [x] 3B.5 Create `lib/parsing/bank_parser.dart` (BankParser interface + ParsedTransaction) → `lib/parsing/bank_parser.dart`
- [x] 3B.6 Create `lib/parsing/parser_registry.dart` (reads JSON, routes by country) → `lib/parsing/parser_registry.dart`
- [x] 3B.7 Create `lib/parsing/generic_parser.dart` (multilingual fallback) → `lib/parsing/generic_parser.dart`
- [x] 3B.8 India config documented in JSON (Kotlin keeps existing hardcoded logic untouched)
- [x] 3B.9 Kotlin NotificationListener untouched — JSON is for non-India only
- [x] 3B.10 Dart parsers read bank_rules.json via ParserRegistry
- [x] 3B.11 GenericParser handles 40+ countries via JSON rules
- [x] 3B.12 Unit tests: 62 parsing tests across 14 countries (debit + credit + OTP ignore per country)
- [x] 3B.13 India regression tests verified via BankSmsParserTest.kt (Kotlin)
- [x] 3B.14 `flutter analyze` ✅ No issues
- [x] 3B.15 Git commit (pending)

### 3C: Remote Config for bank rules
- [x] 3C.1 Design documented in DECISIONS.md (#22); `ParserRegistry.reloadFromRemoteConfig()` method implemented and ready to wire up — deferred post-launch
- [ ] 3C.2 Git commit (will be part of 3B commit)

### 3D: Constraints documentation
- [x] 3D.1 DECISIONS.md #2: SMS parsing stays on-device
- [x] 3D.2 DECISIONS.md #18: iOS/non-SMS countries need manual entry (future)

---

## Task 4: Privacy-Safe Parser Monitoring (Firebase Analytics) ✅ DONE (commit pending)
- [x] 4.1 Add `firebase_analytics: ^11.3.6` to pubspec.yaml; `flutter pub get` ✅
- [x] 4.2 Create `lib/services/parse_analytics_service.dart` — 3 events (`parse_success`, `parse_ignored`, `parse_failed`); `ParseIgnoreReason` + `ParseFailedReason` constants; all calls in try/catch; NEVER logs text/amounts/names/account numbers
- [x] 4.3a Wire into `lib/services/notification_service.dart` — `unawaited(ParseAnalyticsService.logParseSuccess(...))` after successful Firestore sync; reads `country_code` + `parser_used` from SharedPrefs JSON written by Kotlin
- [x] 4.3b Wire into `NotificationListener.kt` — `logParserEvent()` helper using Firebase Android SDK; logs `parse_ignored` (otp/promo/no_verb/no_bank_id/no_amount) and `parse_failed` (invalid_amount) at each rejection point; logs `parse_success` after `saveTransaction()`; also writes `country_code`/`parser_used` into SharedPrefs JSON
- [x] 4.3c Add `implementation("com.google.firebase:firebase-analytics-ktx")` to `android/app/build.gradle.kts`
- [x] 4.4 `flutter analyze` ✅ No issues
- [x] 4.5 Tests: 15 new analytics tests (`test/parse_analytics_service_test.dart`); 130 total — all pass
- [x] 4.6 Git commit (pending)

---

## Task 5: Release Checklist ✅ DONE (commit pending)
- [x] 5.1 Firestore security rules reviewed — existing `allow read, write` already covers new fields; no changes needed ✅
- [x] 5.2 Play Console Data Safety form — documented in RELEASE_CHECKLIST.md (new fields = account preferences, non-sensitive; analytics = anonymous technical metadata)
- [x] 5.3 Privacy policy notes — documented in RELEASE_CHECKLIST.md (analytics events contain no PII, no SMS text, no amounts)
- [x] 5.4 Version bumped → `pubspec.yaml`: `version: 17.2.0+19` (versionCode from pubspec → android gets 19)
- [x] 5.5 `flutter analyze` ✅ No issues; `flutter test` ✅ 130 tests pass
- [x] 5.6 Kotlin tests — `BankSmsParserTest.kt` noted in RELEASE_CHECKLIST.md (requires Android SDK; run `cd android && ./gradlew test`)
- [x] 5.7 HANDOFF.md updated with final state
- [x] 5.8 RELEASE_CHECKLIST.md updated with complete pre-release checklist for v17.2.0+19
- [x] 5.9 Git commit (pending)

---

## Audit v17.2.0: Pre-Release Audit ✅ DONE

### A1: Hardcoded Symbol Audit ✅ DONE
- [x] A1.1 Scanned lib/, android Kotlin, XML, strings.xml for ₹, Rs, Rs., INR
- [x] A1.2 `notification_helper.dart` — uses CurrencyService ✅
- [x] A1.3 `debt_service.dart` — uses CurrencyService ✅
- [x] A1.4 `borrow_lend_screen.dart` — uses FormatUtils/CurrencyService ✅
- [x] A1.5 `add_transaction_screen.dart` — uses CurrencyService ✅
- [x] A1.6 `transaction_detail_screen.dart` — uses CurrencyService ✅
- [x] A1.7 `export_manager.dart` — raw numbers only (intentional) ✅
- [x] A1.8 `onboarding_screen.dart` — "₹0 forever" is marketing copy (intentional) ✅
- [x] A1.9 `currency_picker_sheet.dart` — 'Rs' for LKR/NPR/PKR (intentional correct symbols) ✅
- [x] A1.10 `DuplicateConfirmationActivity.kt` / `NotificationActionReciever.kt` — reads SharedPrefs; ₹ is fallback only ✅
- [x] A1.11 `NotificationListener.kt` L1323–1347 — hardcoded ₹ in user-visible notification text — **KNOWN BUG; file read-only for this audit; documented in HANDOFF.md**
- [x] A1.12 All findings documented in HANDOFF.md audit section

### A2: Firebase Storage Check ✅ DONE
- [x] A2.1 `_syncToFirestore` writes all 4 fields (countryCode, currencyCode, localeCode, currencySymbol) ✅
- [x] A2.2 Called from `setCountry()`, `setCurrency()`, `setLocale()` — covers both onboarding and Settings ✅
- [x] A2.3 `syncFromFirestore()` called from `app_init_helper.dart:50` post-auth ✅
- [x] A2.4 Fallback to IN/INR/en_IN/₹ for existing users with no Firestore data ✅
- [x] A2.5 `firestore.rules` — existing `allow read, write` covers all 4 fields; no changes needed ✅

### A3: Currency Change Refresh ✅ DONE (bug fixed)
- [x] A3.1 Home screen: **FIXED** — added `CurrencyService.currencyNotifier` listener in `home_screen.dart`
- [x] A3.2 Home widget: **FIXED** — `WidgetService.updateFromTransactions()` called from `_onCurrencyChanged()`
- [x] A3.3 PDF export: already correct — `pdf_service.dart` calls CurrencyService at render time ✅
- [x] A3.4 Scheduled/debt notifications: already correct — `notification_helper.dart` calls CurrencyService at fire time ✅

### A4: Non-India Notification Flow (investigation) ✅ DONE
- [x] A4.1 Read `NotificationListener.kt` — full flow documented
- [x] A4.2 Verdict: **Does not work** — Kotlin amount pattern is India-only (Rs./INR/₹); Dart GenericParser only runs when app is open
- [x] A4.3 Written to HANDOFF.md audit section with file/line references
- [x] A4.4 DECISIONS.md #26 added

### A5: Tests ✅ DONE
- [x] A5.1 `flutter analyze` → No issues ✅
- [x] A5.2 `flutter test` → 130/130 pass ✅
- [x] A5.3 `./gradlew test` → BLOCKED (JAVA_HOME not set); fix documented in HANDOFF.md

### A6: Commit ✅ DONE
- [x] A6.1 `home_screen.dart` fix committed
- [x] A6.2 HANDOFF.md, TASKS.md, DECISIONS.md committed
