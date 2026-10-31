# Buddy — Handoff State

**Last updated:** 2026-10-31T16:05:00+05:30  
**Status:** Task 6 (v17.3.0 Global Auto-Detection) ✅ ALL PHASES COMPLETE  
**Version:** `17.3.0+20` (bumped from 17.2.0+19)  
**Git Branch:** `main`  

---

## Task Status

| Task | Status | Commit / Notes |
|------|--------|----------------|
| Step 0 — Handoff system | ✅ DONE | `/docs/agent/` baseline docs |
| Task 1 — Forced/Prompted App Update | ✅ DONE | `cce44af` |
| Task 2 — Country/Currency Selection & Global Symbol | ✅ DONE | `04b9c6d`, `8454a3c` |
| Task 3 — Global Bank SMS Parsing architecture | ✅ DONE | `e1d5131` |
| Task 4 — Firebase Analytics (parser monitoring) | ✅ DONE | `c86ab4f` |
| Task 5 — Release Checklist | ✅ DONE | `26c7ec9` |
| **Audit v17.2.0** — Pre-release audit & bug fixes | ✅ DONE | `7303c1d` |
| **Task 6 Phase 1** — Dynamic currency symbol in native notification text | ✅ DONE | `de884ce` |
| **Task 6 Phase 2** — Deep research & PARSING_RESEARCH.md update | ✅ DONE | Regional formats, confidence table, SG & neo-banks |
| **Task 6 Phase 3** — Architecture & Design | ✅ DONE | Kotlin mirror + zero duplication asset loading |
| **Task 6 Phase 4** — Global native parser implementation | ✅ DONE | `GlobalBankParser.kt`, `GlobalParsingService.dart`, `NotificationListener.kt` |
| **Task 6 Testing & Release** — Parity test vectors, 100% test pass, version bump | ✅ DONE | 151 Dart tests, 45 Kotlin unit tests |

---

## Test Verification Summary

- `flutter analyze` → **No issues found!** ✅ (0 errors, 0 warnings, 0 lints)
- `flutter test` → **151/151 tests pass!** ✅
- `./gradlew :app:testDebugUnitTest` → **45/45 tests pass!** ✅
  - `BankSmsParserTest` (India regression guard)
  - `CurrencySymbolHelperTest` (SharedPrefs currency symbol resolution)
  - `GlobalBankParserTest` (global currency formats & negative ignore vectors)
- `pubspec.yaml` version → `17.3.0+20` ✅

---

## Architectural Implementation Details (Task 6)

### 1. Hard Rules Followed Strictly
- **India path is 100% frozen**: `NotificationListener.kt` India amount regexes and parsing (L214–293, L840–1035) were untouched. The India path runs FIRST, always.
- **Controlled Global Branch**: Only entered if:
  1. India `parseTransaction()` returns null
  2. Saved `countryCode` != `"IN"` (users with no saved country default to `"IN"` and never reach global branch)
  3. Remote Config flag `enable_global_native_parsing` is `true` in SharedPreferences
  4. User's `countryCode` is present in `global_parsing_countries` (or allowlist is empty/wildcard)
- **Zero Duplicate Rules**: Kotlin `GlobalBankParser` reads directly from the bundled asset `flutter_assets/assets/parsing/bank_rules.json` in the APK.
- **Pipeline Reuse**: Everything after parsing (`saveTransaction`, deduplication, category detection, notifications, home widget updates, Firebase Analytics) uses the exact same production pipeline as India.
- **On-Device Only**: No notification content, SMS text, account numbers, or personal data are ever transmitted or logged.

### 2. Files Added & Modified in Task 6
- `android/app/src/main/kotlin/com/faysarukattil/buddy/GlobalBankParser.kt` (NEW):
  - `GlobalBankParser`: Native Kotlin mirror of `GenericParser.dart` supporting European (`1.234,56`), Indonesian/Latin dot-thousands, zero-decimal (`JPY`, `IDR`), standard (`1,234.56`), and 3-decimal currencies (`KWD`, `BHD`).
  - `GlobalParserRegistry`: Thread-safe registry that loads `bank_rules.json` from assets, evaluates Remote Config flags from SharedPreferences, and parses notifications.
- `android/app/src/main/kotlin/com/faysarukattil/buddy/NotificationListener.kt`:
  - `getCurrencySymbol()` helper: Reads `currency_symbol` from SharedPrefs (`{packageName}_HomeWidgetPlugin`), with fallback `"₹"`.
  - Replaced hardcoded `"₹"` in duplicate confirmation and transaction added notifications.
  - Step 7 parsing branch: Calls `GlobalParserRegistry.instance.parseForCountry()` if eligible.
  - Extended package matching in `isFromFinancialApp()` for global banking & wallet packages.
- `lib/services/global_parsing_service.dart` (NEW):
  - Fetches Remote Config flags (`enable_global_native_parsing`, `global_parsing_countries`, `global_parsing_rules_json`).
  - Persists flags to SharedPreferences for native Android access while the Flutter app is closed.
  - Reloads `ParserRegistry` in Dart when custom rules JSON is provided.
- `lib/services/app_init_helper.dart`:
  - Initializes `GlobalParsingService.initialize()` alongside `ParserRegistry`.
- `lib/views/widgets/setting_modal.dart`:
  - Changed permission row title from `'Track bank SMS'` to `'Track bank notifications'`.
  - Added non-India informational tip banner under Currency & Region section.
- `lib/parsing/generic_parser.dart`:
  - Added `_universalIgnore` matching `GlobalBankParser.kt` (failed, declined, unsuccessful, cancelled, rejected, otp, etc.).
- `assets/parsing/bank_rules.json`:
  - Bumped to version 2; added Singapore (SG); updated GB, NG, DE, BR packages and keywords.
- `test/parsing/bank_sms_test_vectors.json`:
  - 76+ test vectors for both Dart and Kotlin unit tests.
- `android/app/build.gradle.kts`:
  - Added explicit Firebase Analytics version (`22.5.0`) and unit test dependencies (`junit:4.13.2`, `org.json:20180813`).

---

## What the Next Human/Agent Needs to Do

### 1. Build and Release (Google Play)
```bash
flutter build appbundle --release
```
- Upload the signed AAB (version `17.3.0+20`) to the Play Console (Internal Testing track first).
- Verify on real devices.
- Roll out to Production starting with a **10% staged rollout**.

### 2. Remote Config Deployment (Post-Release)
- App bundle is shipped with `enable_global_native_parsing: false` by default.
- Once the release is approved on Google Play and monitored, enable Remote Config gradually:
  ```json
  enable_global_native_parsing: true
  global_parsing_countries: "AE,SA"
  ```
- Monitor Firebase Analytics `parse_success`, `parse_ignored`, `parse_failed` filtered by `country_code` and `parser_used`.
- Expand country allowlist incrementally (`NG,KE,GB,US,SG,BR`).
