# Buddy — Handoff State

**Last updated:** 2026-10-31T15:20:00+05:30
**Status: Task 6 Phase 1 DONE — Phase 2 (research) IN PROGRESS**
**Version:** `17.2.0+19` (will bump to 17.3.0+20 at end of Task 6)
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
| Task 5 — Release Checklist | ✅ DONE | `26c7ec9` |
| **Audit v17.2.0** — Pre-release audit | ✅ DONE | see below |

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

---

## Audit v17.2.0 — Pre-Release Audit Results

**Audit date:** 2026-10-31  
**flutter analyze:** No issues ✅  
**flutter test:** 130/130 pass ✅  
**./gradlew test:** BLOCKED — JAVA_HOME not set (see below)

---

### 1. Hardcoded Symbol Audit

| File | Line(s) | Symbol | Status |
|------|---------|--------|--------|
| `lib/services/notification_helper.dart` | all | — | ✅ Uses `CurrencyService.formatFull()` |
| `lib/services/debt_service.dart` | all | — | ✅ Uses `CurrencyService.formatFull()` |
| `lib/views/screens/bottomnavbarscreen/borrow_lend_screen.dart` | all | — | ✅ Uses `FormatUtils.formatCurrency()` |
| `lib/views/screens/add_transaction_screen.dart` | all | — | ✅ Uses `CurrencyService.symbol` |
| `lib/views/screens/transaction_detail_screen.dart` | all | — | ✅ Uses `CurrencyService.formatSigned()` |
| `lib/utils/export_manager.dart` | all | — | ✅ Intentional — CSV/JSON exports use raw numbers only |
| `lib/features/onboarding/onboarding_screen.dart` | 19, 1403, 2069, 2114 | `₹0 forever` | ✅ Intentional — marketing copy meaning "free" |
| `lib/views/widgets/currency_picker_sheet.dart` | various | `Rs` | ✅ Intentional — correct official symbols for LKR/NPR/PKR |
| `lib/services/currency_service.dart` | constants | `₹`, `INR` | ✅ Intentional — India default constants |
| `android/.../DuplicateConfirmationActivity.kt` | 78 | `₹` | ✅ Reads from SharedPrefs — `₹` is fallback only |
| `android/.../NotificationActionReciever.kt` | 119 | `₹` | ✅ Reads from SharedPrefs — `₹` is fallback only |
| `android/.../BuddyWidgetProvider.kt` | 67, 69, 71 | `₹` | ✅ Reads from SharedPrefs — `₹` is fallback only |
| `android/.../NotificationListener.kt` | 214, 218, 281–293 | `₹`, `Rs`, `INR` | ✅ Intentional — India SMS regex patterns |
| `android/.../NotificationListener.kt` | 629, 653 | `₹` | ✅ Intentional — debug Log statements |
| `android/.../NotificationListener.kt` | **1323, 1324, 1326, 1347** | **`₹`** | 🔴 **BUG — hardcoded ₹ in notification text shown to non-India users** |

**Known issue (read-only file):** `NotificationListener.kt` lines 1323, 1324, 1326, 1347 build the user-visible notification text for `showDuplicateConfirmationNotification()` and `showTransactionAddedNotification()` using `"₹$amount"` directly. This file is frozen per audit constraints. A future task must replace these with the `currency_symbol` value read from SharedPreferences (same pattern as `DuplicateConfirmationActivity.kt` line 78).

---

### 2. Firebase Storage Check

**Write path (`CurrencyService._syncToFirestore`):**
- Writes `countryCode`, `currencyCode`, `localeCode`, `currencySymbol`, `updatedAt` to `/users/{uid}` with `merge: true` ✅
- Called from `setCountry()`, `setCurrency()`, `setLocale()` — covers onboarding and Settings ✅

**Read path (`CurrencyService.syncFromFirestore`):**
- Called from `lib/services/app_init_helper.dart:50` post-auth ✅
- Falls back to `IN / INR / en_IN / ₹` if fields are absent ✅ — existing users unaffected

**Firestore rules:** `/users/{userId}` rule is `allow read, write: if request.auth != null && request.auth.uid == userId` — covers all 4 new fields. **No changes needed.** ✅

---

### 3. Currency Change Refresh

| Surface | Status |
|---------|--------|
| Home screen amounts | 🔴 **FIXED** — `home_screen.dart` now listens to `CurrencyService.currencyNotifier`; `setState()` + `WidgetService.updateFromTransactions()` called on change |
| Home screen widget (Android) | ✅ Updated via `WidgetService.updateFromTransactions()` on currency change (wired in fix above) |
| PDF export | ✅ `pdf_service.dart` calls `CurrencyService.formatForPdf()` at render time |
| Scheduled / debt notifications | ✅ `notification_helper.dart` calls `CurrencyService.formatFull()` at fire time |

---

### 4. Non-India Notification Flow — VERDICT

> **Non-India auto-detect DOES NOT WORK when the app is closed.**

**What happens for a UAE bank or M-Pesa SMS:**

1. `onNotificationPosted()` fires (L570) — OS-managed, works when app is closed ✅
2. **Package filter (L673):** UAE banks are not in `FINANCIAL_APPS`, but the default SMS app (`com.samsung.android.messaging`, etc.) is always allowed. A UAE bank SMS arriving via the default SMS app **passes the package filter** ✅
3. **`parseTransaction()` (L700) — this is where it fails:** The amount pattern (L281) only matches `Rs.?|INR|₹` as currency identifiers. UAE bank SMS uses `AED` or bare numbers. The bank identifier check (L850–865) requires Indian-specific terms (`upi`, `imps`, `neft`, `rtgs`, `a/c`, specific Indian bank names). A typical UAE SMS like `"Your A/C has been debited AED 500.00"` fails amount extraction → `allAmounts.isEmpty()` → **returns null → not saved**.
4. **Dart `ParserRegistry` / `GenericParser`** for UAE (and all other non-India countries) is defined in `lib/parsing/parser_registry.dart` + `assets/parsing/bank_rules.json`. **These only run inside the Flutter engine** — i.e., only when the app is open and `syncSavedTransactions()` runs. Since Kotlin never saves a non-India transaction, the Dart parser never sees anything to process.

**Non-India users can only record transactions manually** until a Kotlin-side non-India parser is added, or an alternative mechanism is implemented (e.g., foreground service, WorkManager job, or the user opens the app while the notification is still in the shade).

**File/line references:**
- Package filter: `NotificationListener.kt` L673 `isFromFinancialApp()`
- Amount pattern: `NotificationListener.kt` L281 (regex: `Rs.?|INR|₹`)
- Bank ID check: `NotificationListener.kt` L850–865
- Dart parser entry: `lib/parsing/parser_registry.dart`, `lib/parsing/generic_parser.dart`
- Dart parser called from: `lib/services/notification_service.dart` `syncSavedTransactions()`
- Non-India rules: `assets/parsing/bank_rules.json`

**See also:** DECISIONS.md #26.

---

### 5. Test Results

```
flutter analyze:   No issues ✅  (5.0s)
flutter test:      130/130 tests pass ✅  (4s)
./gradlew test:    BLOCKED ❌
```

**`./gradlew test` failure reason:** `JAVA_HOME` is not set in the terminal session. Java IS installed via Android Studio.

**Fix (run once in terminal before `./gradlew test`):**
```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
cd "/Users/faysarukattil/Desktop/Personal Projects/buddy_2.0/android"
./gradlew test
```
Alternatively, open Android Studio → use the built-in Terminal tab (it auto-sets `JAVA_HOME`).

---

### Audit — Files Changed

- `lib/views/screens/bottomnavbarscreen/home_screen.dart`
  - Added `import 'package:buddy/services/currency_service.dart'`
  - `initState()` — added `CurrencyService.currencyNotifier.addListener(_onCurrencyChanged)`
  - New method `_onCurrencyChanged()` — `setState()` + `WidgetService.updateFromTransactions()`
  - `dispose()` — added `CurrencyService.currencyNotifier.removeListener(_onCurrencyChanged)`
- `docs/agent/HANDOFF.md` — audit results (this section)
- `docs/agent/TASKS.md` — audit task ticked
- `docs/agent/DECISIONS.md` — decision #26 added
