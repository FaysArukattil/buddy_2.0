# Buddy — Handoff State

**Last updated:** 2026-10-31T14:20:00+05:30
**Status: ALL TASKS COMPLETE ✅**
**Version:** `17.2.0+19` (bumped from 17.1.0+18)

---

## Task Status

| Task | Status | Commit |
|------|--------|--------|
| Step 0 — Handoff system | ✅ DONE | — |
| Task 1 — Forced/Prompted App Update | ✅ DONE | `cce44af` |
| Task 2 — Country/Currency Selection & Global Symbol | ✅ DONE | `04b9c6d`, `8454a3c` |
| Task 3 — Global Bank SMS Parsing architecture | ✅ DONE | `e1d5131` |
| Task 4 — Firebase Analytics (parser monitoring) | ✅ DONE | `c86ab4f` |
| Task 5 — Release Checklist | ✅ DONE | to be committed |

---

## Final Verification

- `flutter analyze` → **No issues** ✅
- `flutter test` → **130 tests, all pass** ✅
- `pubspec.yaml` version → `17.2.0+19` ✅
- `firestore.rules` → **No changes needed** — existing `allow read, write` covers all new fields ✅

---

## What the Next Human/Agent Needs to Do

These items require **manual action or physical device access** — they cannot be automated:

### Immediate (before build)
1. **Run Kotlin tests** (requires Android SDK):
   ```bash
   cd android && ./gradlew test
   ```
   Runs `BankSmsParserTest.kt` — protects India SMS parsing regression.

2. **Update Play Console Data Safety form** — new analytics events + country/currency preferences need to be declared.

3. **Update Privacy Policy** — note that country/currency prefs are stored in Firestore; analytics events contain no financial data.

### Build & deploy
```bash
flutter build appbundle --release
```
Upload to Play Console. Start with **10% staged rollout**.

### After 100% rollout — set Remote Config:
```
min_supported_version: "17.2.0"
latest_version: "17.2.0"
force_update: false
```
⚠️ NEVER set `min_supported_version` before the new version has reached 100% rollout.

### Post-release
- Monitor Firebase Analytics → `parse_success`, `parse_ignored`, `parse_failed` events
- `parse_failed` by `country_code` shows which banks need `bank_rules.json` fixes
- Fix bank rules via Remote Config (no new Play Store release needed)

---

## Architecture Summary (for new agents)

| Component | File | Role |
|-----------|------|------|
| Update service | `lib/services/update_service.dart` | Play Core + Remote Config version checking |
| Currency service | `lib/services/currency_service.dart` | Single source of truth for symbol/formatting |
| Currency picker | `lib/views/widgets/currency_picker_sheet.dart` | 45-country searchable picker |
| Bank parser interface | `lib/parsing/bank_parser.dart` | Abstract `BankParser` + `ParsedTransaction` model |
| Parser registry | `lib/parsing/parser_registry.dart` | Loads `bank_rules.json`, routes by country |
| Generic parser | `lib/parsing/generic_parser.dart` | Data-driven, handles 40+ countries |
| Bank rules | `assets/parsing/bank_rules.json` | 42 country rules (India entry = docs only) |
| Parse analytics | `lib/services/parse_analytics_service.dart` | Privacy-safe parse event logging |
| India SMS parser | `NotificationListener.kt` | Hardcoded Kotlin; NEVER touch this |

### Key Constraints
- **India parser in `NotificationListener.kt` is frozen** — add-only, `BankSmsParserTest.kt` is the regression guard
- **Never force existing users** through onboarding (they default to India/INR/en_IN)
- **All analytics wrapped in try/catch** — Firebase failures must never crash the app
- **`bank_rules.json` + `ParserRegistry`** are the Dart-side parsers for non-India countries
- **`ParserRegistry.reloadFromRemoteConfig(json)`** is implemented and ready to wire — deferred post-launch (see DECISIONS.md #22)

---

## Files Changed Since v17.1.0+18 (by task)

### Task 1 (commit `cce44af`)
- `pubspec.yaml` — added `in_app_update`, `firebase_remote_config`
- `lib/services/update_service.dart` — NEW
- `lib/main.dart` — navigatorKey, resume update check
- `lib/views/screens/onboarding/splashscreen/splash_screen.dart` — post-nav update check
- `test/update_service_test.dart` — NEW (12 tests)

### Task 2 (commits `04b9c6d`, `8454a3c`)
- `lib/services/currency_service.dart` — NEW (singleton, 3 fields, formatters)
- `lib/utils/format_utils.dart` — delegates to CurrencyService
- `lib/services/pdf_service.dart` — Noto Sans + CurrencyService
- `lib/views/widgets/currency_picker_sheet.dart` — NEW (45 countries)
- `lib/features/onboarding/onboarding_screen.dart` — new user picker
- `lib/views/widgets/setting_modal.dart` — Currency & region section
- `lib/services/widget_service.dart` — passes symbol to native
- `android/.../BuddyWidgetProvider.kt` — dynamic symbol
- `android/.../NotificationActionReciever.kt` — reads symbol
- `android/.../DuplicateConfirmationActivity.kt` — reads symbol
- XML widget layouts — ₹ defaults → `--`
- `assets/fonts/NotoSans-Regular.ttf`, `NotoSans-Bold.ttf` — NEW

### Task 3 (commit `e1d5131`)
- `assets/parsing/bank_rules.json` — NEW (42 rules)
- `lib/parsing/bank_parser.dart` — NEW
- `lib/parsing/parser_registry.dart` — NEW
- `lib/parsing/generic_parser.dart` — NEW
- `lib/services/app_init_helper.dart` — parser init on startup
- `test/parsing/bank_sms_test_vectors.json` — NEW (50+ vectors)
- `test/parsing/dart_parser_test.dart` — NEW (62 tests)
- `android/app/src/test/.../BankSmsParserTest.kt` — NEW
- `docs/agent/PARSING_RESEARCH.md` — NEW

### Task 4 (commit `c86ab4f`)
- `lib/services/parse_analytics_service.dart` — NEW
- `test/parse_analytics_service_test.dart` — NEW (15 tests)
- `lib/services/notification_service.dart` — logParseSuccess after sync
- `android/.../NotificationListener.kt` — logParserEvent helper + calls
- `android/app/build.gradle.kts` — firebase-analytics-ktx

### Task 5 (this commit)
- `pubspec.yaml` — version 17.1.0+18 → 17.2.0+19
- `docs/agent/RELEASE_CHECKLIST.md` — updated for v17.2.0+19
- `docs/agent/TASKS.md`, `HANDOFF.md`, `DECISIONS.md` — updated
