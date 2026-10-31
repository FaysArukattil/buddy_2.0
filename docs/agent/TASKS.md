# Buddy — Task Checklist

## Step 0: Handoff System
- [x] Create `/docs/agent/README_FIRST.md`
- [x] Create `/docs/agent/PROJECT_CONTEXT.md`
- [x] Create `/docs/agent/TASKS.md`
- [x] Create `/docs/agent/HANDOFF.md`
- [x] Create `/docs/agent/DECISIONS.md`
- [x] Create `/docs/agent/PARSING_RESEARCH.md` (placeholder)
- [x] Create `/docs/agent/RELEASE_CHECKLIST.md`

## Task 1: Forced / Prompted App Update
- [x] 1.1 Add `in_app_update` and `firebase_remote_config` packages to pubspec.yaml → `pubspec.yaml`
- [x] 1.2 Create `lib/services/update_service.dart` with:
  - [x] Play Core in-app update (flexible default, immediate for critical)
  - [x] Skip in_app_update flow for debug builds and non-Play-Store installs
  - [x] Firebase Remote Config with in-app defaults for offline/first-launch
  - [x] Sensible minimumFetchInterval (12h prod, 60s debug)
  - [x] Numeric segment-by-segment version comparison (1.10.0 > 1.9.0), fallback to build number
  - [x] Blocking dialog for version < min_supported_version (opens Play Store listing)
  - [x] Dismissible dialog for version < latest_version (once/day via SharedPreferences)
  - [x] In-memory guard to prevent double prompts (dialog already showing?)
  - [x] Force update ignores daily limit
  - [x] Check on app start and on resume
  - [x] Silent failure handling (offline, debug, sideloaded) — all in try/catch, never blocks
- [x] 1.3 Integrate update check into `main.dart` / `splash_screen.dart` / `_MyAppState` → `lib/main.dart`, `lib/views/screens/onboarding/splashscreen/splash_screen.dart`
- [x] 1.4 Document Remote Config keys and version comparison logic in DECISIONS.md → `docs/agent/DECISIONS.md`
- [x] 1.5 Run `flutter analyze` — pass ✅
- [x] 1.6 Run tests — pass ✅ (53 tests: 41 existing + 12 new version comparison)
- [x] 1.7 Git commit → `cce44af`

## Task 2: Country / Currency Selection & Global Currency Symbol

### 2B: Central CurrencyService & replace hardcoded symbols
- [ ] 2B.1 Create `lib/services/currency_service.dart` (CurrencyService singleton)
  - [ ] Store three independent fields: countryCode, currencyCode, localeCode (+ derived currencySymbol)
  - [ ] Allow changing currency independently from country (e.g. UAE user tracking USD)
  - [ ] Digit grouping and decimal separators follow localeCode
  - [ ] Currency formatting via `intl` NumberFormat.currency
  - [ ] Handle Indian numbering (1,23,456) vs international (123,456) vs European (1.234,56)
  - [ ] Handle 0-decimal currencies (JPY, KRW)
  - [ ] Compact format (K, M, B / L, Cr for India)
  - [ ] Single source of truth — all UI, widgets, notifications, PDF, CSV, share texts read from here
  - [ ] On currency change: refresh UI, home widget, and scheduled notifications immediately
- [ ] 2B.2 Bundle Unicode font (Noto Sans) in assets for PDF export
  - [ ] Register in pubspec.yaml assets
  - [ ] Load in pdf_service.dart theme
  - [ ] Test PDF output with ≥5 currency symbols (₹ ₦ ৳ ₫ ₺ ₱ € $ £)
- [ ] 2B.3 Refactor `lib/utils/format_utils.dart` to delegate to CurrencyService
- [ ] 2B.4 Replace hardcoded ₹ in Dart views:
  - [ ] `borrow_lend_screen.dart`
  - [ ] `add_transaction_screen.dart`
  - [ ] `transaction_detail_screen.dart`
  - [ ] `animated_money_text.dart`
  - [ ] `notification_helper.dart`
  - [ ] `debt_service.dart`
  - [ ] `onboarding_screen.dart` (features/onboarding)
- [ ] 2B.5 Update `pdf_service.dart` to use CurrencyService + bundled Unicode font
- [ ] 2B.6 Update `widget_service.dart` to pass currency symbol to native
- [ ] 2B.7 Update Kotlin `BuddyWidgetProvider.kt` — dynamic symbol from SharedPrefs
- [ ] 2B.8 Update Kotlin `NotificationActionReciever.kt` and `DuplicateConfirmationActivity.kt`
- [ ] 2B.9 Update XML widget layouts (default text values)
- [ ] 2B.10 Update `notification_test_helper.dart`
- [ ] 2B.11 Update `export_manager.dart` (CSV/share text) to use CurrencyService
- [ ] 2B.12 Run `flutter analyze` — pass
- [ ] 2B.13 Git commit

### 2C: Settings — Currency/Country option
- [ ] 2C.1 Add country/currency option to `setting_modal.dart`
- [ ] 2C.2 Allow changing currency independently from country
- [ ] 2C.3 Country change updates Firebase (countryCode, currencyCode, localeCode, currencySymbol) + local cache + refreshes UI + home widget
- [ ] 2C.4 Show one-time note: "Only display symbol changes, values are not converted"
- [ ] 2C.5 Run `flutter analyze` — pass
- [ ] 2C.6 Git commit

### 2D: Migration for existing live users
- [ ] 2D.1 Auto-default existing users to India/INR/en_IN when no country saved
- [ ] 2D.2 Show non-blocking country selection prompt (or in Settings)
- [ ] 2D.3 Do NOT force existing users through onboarding again
- [ ] 2D.4 Run `flutter analyze` — pass
- [ ] 2D.5 Git commit

### 2A: Onboarding — Country selection page
- [ ] 2A.1 Add country dataset (package or local JSON) — decide & log
- [ ] 2A.2 Create country selection onboarding page (searchable, flag, currency)
- [ ] 2A.3 Pre-select smart default from device locale
- [ ] 2A.4 Save to Firebase (countryCode, currencyCode, localeCode, currencySymbol) + SharedPrefs
- [ ] 2A.5 Integrate into onboarding flow
- [ ] 2A.6 Run `flutter analyze` — pass
- [ ] 2A.7 Run tests — pass
- [ ] 2A.8 Git commit

## Task 3: Global Bank SMS Parsing

### 3A: Research
- [ ] 3A.1 Research India (document existing patterns as baseline — include package names, sender/title, debit/credit wording)
- [ ] 3A.2 Research South Asia (Pakistan, Bangladesh, Sri Lanka, Nepal)
- [ ] 3A.3 Research Middle East (UAE, Saudi Arabia, Qatar, Kuwait, Bahrain, Oman)
- [ ] 3A.4 Research Africa (Nigeria, Kenya, South Africa, Ghana, Tanzania, Egypt)
- [ ] 3A.5 Research Europe (UK, Germany, France, Spain, Italy, Netherlands, Turkey)
- [ ] 3A.6 Research North America (USA, Canada, Mexico)
- [ ] 3A.7 Research Latin America (Brazil, Argentina, Colombia, Chile)
- [ ] 3A.8 Research East & Southeast Asia (Japan, South Korea, Indonesia, Philippines, Thailand, Vietnam, Malaysia)
- [ ] 3A.9 Research Oceania (Australia, New Zealand)
- [ ] 3A.10 Write up all results in PARSING_RESEARCH.md (include: package names, notification title/sender, debit/credit wording, default SMS app packages)

### 3B: Architecture & Implementation
- [ ] 3B.1 Define shared JSON schema (`assets/parsing/bank_rules.json`) for both Dart and Kotlin
  - [ ] country, bank name, notification package names, sender/title patterns, debit keywords, credit keywords, amount format, currency markers, ignore patterns, confidence level
- [ ] 3B.2 Create shared test vectors file (message, source pkg, country, expected type, amount, currency, merchant)
- [ ] 3B.3 Write India regression test cases FIRST (from notification_test_helper.dart samples)
- [ ] 3B.4 Run India regression tests against current parser — all must pass before any changes
- [ ] 3B.5 Create `lib/parsing/bank_parser.dart` (BankParser interface)
- [ ] 3B.6 Create `lib/parsing/parser_registry.dart` (registry + fallback, reads JSON)
- [ ] 3B.7 Create `lib/parsing/generic_parser.dart` (multilingual fallback)
- [ ] 3B.8 Extract India config into shared JSON (Kotlin keeps existing hardcoded logic untouched; JSON is for other countries)
- [ ] 3B.9 Kotlin NotificationListener reads shared JSON for non-India countries
- [ ] 3B.10 Dart parsers read same JSON
- [ ] 3B.11 Create parsers for researched countries
- [ ] 3B.12 Write unit tests per country (debit + credit + negative case) — shared test vectors
- [ ] 3B.13 Verify all India regression tests still pass
- [ ] 3B.14 Run `flutter analyze` — pass
- [ ] 3B.15 Git commit

### 3C: Remote Config for bank rules (design or implement)
- [ ] 3C.1 Prepare for delivering bank_rules.json via Firebase Remote Config
  - [ ] Bundled asset as offline fallback
  - [ ] Validate JSON before use, fall back to bundled if invalid
  - [ ] Implement if straightforward, otherwise write design in DECISIONS.md + leave TODO
- [ ] 3C.2 Git commit

### 3D: Constraints documentation
- [ ] 3D.1 Note in DECISIONS.md: SMS parsing stays on-device, no server upload
- [ ] 3D.2 Note in DECISIONS.md: iOS/non-SMS countries need manual entry (future)

## Task 4: Privacy-Safe Parser Monitoring (Firebase Analytics)
- [ ] 4.1 Add `firebase_analytics` package to pubspec.yaml
- [ ] 4.2 Create anonymous analytics events:
  - [ ] `parse_success` — params: countryCode, source_package, parser_used (country/generic/india)
  - [ ] `parse_ignored` — params: countryCode, source_package, reason_code
  - [ ] `parse_failed` — params: countryCode, source_package, parser_used, reason_code
  - [ ] NEVER include message text, amounts, names, or account numbers
- [ ] 4.3 Integrate events into NotificationListener.kt and Dart parsers
- [ ] 4.4 Run `flutter analyze` — pass
- [ ] 4.5 Git commit

### 4-future: "Report this message" button (FUTURE — implement only if simple)
- [ ] 4-future.1 On unparsed/wrong item, user can tap "Report"
- [ ] 4-future.2 Asks user consent before sending
- [ ] 4-future.3 Sends redacted version only (digits, names, account numbers masked)
- [ ] NOTE: Skip if complex; note in DECISIONS.md

## Task 5: Release Checklist
- [ ] 5.1 Update Firestore security rules for new fields
- [ ] 5.2 Note Play Console Data Safety form updates needed
- [ ] 5.3 Note privacy policy updates needed
- [ ] 5.4 Test migration on build with existing user data
- [ ] 5.5 Bump versionName and versionCode
- [ ] 5.6 Run `flutter analyze`, all Dart tests, all Kotlin tests
- [ ] 5.7 Staged rollout (10-20%), watch crash reports
- [ ] 5.8 Set Remote Config min_supported_version ONLY after new version is live
