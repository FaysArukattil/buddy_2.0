# Buddy — Task Checklist

## Step 0: Handoff System
- [x] Create `/docs/agent/README_FIRST.md`
- [x] Create `/docs/agent/PROJECT_CONTEXT.md`
- [x] Create `/docs/agent/TASKS.md`
- [x] Create `/docs/agent/HANDOFF.md`
- [x] Create `/docs/agent/DECISIONS.md`
- [x] Create `/docs/agent/PARSING_RESEARCH.md` (placeholder)

## Task 1: Forced / Prompted App Update
- [ ] 1.1 Add `in_app_update` package to pubspec.yaml
- [ ] 1.2 Add `firebase_remote_config` package to pubspec.yaml
- [ ] 1.3 Create `lib/services/update_service.dart` with:
  - [ ] Play Core in-app update (flexible default, immediate for critical)
  - [ ] Firebase Remote Config fallback (min_supported_version, latest_version, force_update, update_message)
  - [ ] Version comparison logic using `package_info_plus`
  - [ ] Blocking dialog for version < min_supported_version
  - [ ] Dismissible dialog for version < latest_version (once per day)
  - [ ] Check on app start and on resume
  - [ ] Silent failure handling (offline, debug, sideloaded)
- [ ] 1.4 Integrate update check into `main.dart` / `splash_screen.dart` / `_MyAppState`
- [ ] 1.5 Document Remote Config keys in DECISIONS.md
- [ ] 1.6 Run `flutter analyze` — pass
- [ ] 1.7 Run tests — pass
- [ ] 1.8 Git commit

## Task 2: Country / Currency Selection & Global Currency Symbol

### 2B: Central CurrencyService & replace hardcoded symbols
- [ ] 2B.1 Create `lib/services/currency_service.dart` (CurrencyService singleton)
  - [ ] Currency formatting via `intl` NumberFormat.currency
  - [ ] Handle symbol position, decimal separators, digit grouping
  - [ ] Handle Indian numbering (1,23,456) vs international (123,456) vs European (1.234,56)
  - [ ] Handle 0-decimal currencies (JPY, KRW)
  - [ ] Compact format (K, M, B / L, Cr for India)
- [ ] 2B.2 Refactor `lib/utils/format_utils.dart` to delegate to CurrencyService
- [ ] 2B.3 Replace hardcoded ₹ in Dart views:
  - [ ] `borrow_lend_screen.dart`
  - [ ] `add_transaction_screen.dart`
  - [ ] `transaction_detail_screen.dart`
  - [ ] `animated_money_text.dart`
  - [ ] `notification_helper.dart`
  - [ ] `debt_service.dart`
  - [ ] `onboarding_screen.dart` (features/onboarding)
- [ ] 2B.4 Update `pdf_service.dart` to use CurrencyService
- [ ] 2B.5 Update `widget_service.dart` to pass currency symbol to native
- [ ] 2B.6 Update Kotlin `BuddyWidgetProvider.kt` formatCompactCurrency to use dynamic symbol
- [ ] 2B.7 Update Kotlin `NotificationActionReciever.kt` and `DuplicateConfirmationActivity.kt`
- [ ] 2B.8 Update XML widget layouts (default text values)
- [ ] 2B.9 Update `notification_test_helper.dart`
- [ ] 2B.10 Run `flutter analyze` — pass
- [ ] 2B.11 Git commit

### 2C: Settings — Currency/Country option
- [ ] 2C.1 Add country/currency option to `setting_modal.dart`
- [ ] 2C.2 Country change updates Firebase + local cache + refreshes UI
- [ ] 2C.3 Show note: "Only display symbol changes, values are not converted"
- [ ] 2C.4 Run `flutter analyze` — pass
- [ ] 2C.5 Git commit

### 2D: Migration for existing live users
- [ ] 2D.1 Auto-default existing users to India/INR (no country saved = India)
- [ ] 2D.2 Show non-blocking country selection prompt (or in Settings)
- [ ] 2D.3 Do NOT force existing users through onboarding again
- [ ] 2D.4 Run `flutter analyze` — pass
- [ ] 2D.5 Git commit

### 2A: Onboarding — Country selection page
- [ ] 2A.1 Add `country_picker` package (or local JSON dataset) — decide & log
- [ ] 2A.2 Create country selection onboarding page (searchable, flag, currency)
- [ ] 2A.3 Pre-select smart default from device locale
- [ ] 2A.4 Save to Firebase (countryCode, currencyCode, currencySymbol) + SharedPrefs
- [ ] 2A.5 Integrate into onboarding flow
- [ ] 2A.6 Run `flutter analyze` — pass
- [ ] 2A.7 Run tests — pass
- [ ] 2A.8 Git commit

## Task 3: Global Bank SMS Parsing

### 3A: Research
- [ ] 3A.1 Research India (current baseline — document existing patterns)
- [ ] 3A.2 Research South Asia (Pakistan, Bangladesh, Sri Lanka, Nepal)
- [ ] 3A.3 Research Middle East (UAE, Saudi Arabia, Qatar, Kuwait, Bahrain, Oman)
- [ ] 3A.4 Research Africa (Nigeria, Kenya, South Africa, Ghana, Tanzania, Egypt)
- [ ] 3A.5 Research Europe (UK, Germany, France, Spain, Italy, Netherlands, Turkey)
- [ ] 3A.6 Research North America (USA, Canada, Mexico)
- [ ] 3A.7 Research Latin America (Brazil, Argentina, Colombia, Chile)
- [ ] 3A.8 Research East & Southeast Asia (Japan, South Korea, Indonesia, Philippines, Thailand, Vietnam, Malaysia)
- [ ] 3A.9 Research Oceania (Australia, New Zealand)
- [ ] 3A.10 Write up all results in PARSING_RESEARCH.md

### 3B: Architecture & Implementation
- [ ] 3B.1 Write regression tests for existing Indian SMS parsing (sample messages from notification_test_helper.dart)
- [ ] 3B.2 Design BankParser interface and country parser registry
- [ ] 3B.3 Create `lib/parsing/` folder structure
- [ ] 3B.4 Create `lib/parsing/bank_parser.dart` (interface)
- [ ] 3B.5 Create `lib/parsing/parser_registry.dart` (registry + fallback)
- [ ] 3B.6 Create `lib/parsing/generic_parser.dart` (multilingual fallback)
- [ ] 3B.7 Extract current Indian parsing into `lib/parsing/countries/india_parser.dart`
- [ ] 3B.8 Create parsers for researched countries (data-driven configs)
- [ ] 3B.9 Integrate new parser system into NotificationListener.kt
- [ ] 3B.10 Write unit tests per country (debit + credit + negative case)
- [ ] 3B.11 Verify all existing Indian tests still pass
- [ ] 3B.12 Run `flutter analyze` — pass
- [ ] 3B.13 Git commit

### 3C: Constraints documentation
- [ ] 3C.1 Note in DECISIONS.md: SMS parsing stays on-device, no server upload
- [ ] 3C.2 Note in DECISIONS.md: iOS/non-SMS countries need manual entry (future)
