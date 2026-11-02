# 🚀 Buddy v17.3.0 — Parser Pattern Extraction & Global Feature Report

**Generated:** 2026-11-02  
**Target Version:** `17.3.0+20`  
**Git Branch:** `main`  
**Status:** All Core Phases & Pattern Enhancements Complete ✅

---

## 1. Executive Summary

This report documents the end-to-end transformation of **Buddy** from an India-only SMS expense tracker into a **high-precision, global auto-detection system** capable of parsing bank notifications and SMS across any currency and country.

In addition to the core architecture developed in v17.3.0, we conducted a deep technical inspection of two leading open-source transaction parsing projects:
1. **`sarim2000/pennywiseai-tracker`** (178 Kotlin bank parsers, heuristics, and category mappings)
2. **`saurabhgupta050890/transaction-sms-parser`** (TypeScript/Node library, UPI/VPA extraction)

Rather than copying foreign code or bloating Buddy with 180 individual Kotlin classes, we distilled the **underlying recognition patterns, regex rules, anti-spam heuristics, and merchant cleaning techniques**, integrating them into Buddy's unified, Remote Config-driven architecture.

---

## 2. Journey So Far: What Was Achieved Step-by-Step

### Phase 0: Baseline & Safe Release Rules
- Established strict handoff protocols (`README_FIRST.md`, `PROJECT_CONTEXT.md`, `TASKS.md`, `HANDOFF.md`, `DECISIONS.md`).
- Established the **India Freeze Rule**: The existing Indian SMS parsing pipeline remains byte-for-byte identical, executes first, and is protected by `BankSmsParserTest.kt` regression tests.
- All parsing runs **100% on-device** (Play Store privacy compliance; no SMS content is ever uploaded or logged).

### Task 1: Prompted & Forced In-App Updates
- Integrated `in_app_update` (Google Play Core) + `firebase_remote_config`.
- Created `UpdateService.dart`: Performs numeric segment-by-segment version comparison (`1.10.0 > 1.9.0`), handles daily prompt limits, and supports force-update banners.

### Task 2: Multi-Currency & Regional Formatting
- Created `CurrencyService.dart` managing `countryCode`, `currencyCode`, `localeCode`, and `currencySymbol` independently (e.g., an expat in UAE tracking in USD with British number formatting).
- Bundled **Noto Sans** Unicode font to guarantee reliable symbol rendering in PDF export and UI (`₹`, `AED`, `$`, `€`, `£`, `₦`, `₵`, `KSh`, etc.).
- Created a searchable 45-country onboarding & settings picker with instant UI and Android Home Widget refresh.
- Synced currency preferences with Cloud Firestore and local `SharedPreferences`.

### Task 3 & Task 6: Global Native Parsing Architecture
- **Zero-Duplication Rule Engine**: Bundled single source of truth `assets/parsing/bank_rules.json` inside APK assets (`flutter_assets/assets/parsing/bank_rules.json`).
- **Native Android Listener**: Created `GlobalBankParser.kt` and `GlobalParserRegistry.kt` reading directly from APK assets to parse bank/wallet push notifications while the Flutter app is in background or killed.
- **Universal Format Support**:
  - European format (`1.234,56`) — Germany, France, Spain, Brazil.
  - Standard format (`1,234.56`) — US, UK, India, Middle East, Anglophone Africa.
  - Indonesian dot-thousands zero-decimal format (`100.000` IDR).
  - 3-decimal Middle Eastern currencies (`KWD`, `BHD`, `OMR`).
- **Production Pipeline Reuse**: All post-parsing actions (saving to SQLite, deduplication, categorization, transaction added notifications, widget updates, Firestore sync) reuse the battle-tested Indian pipeline.
- **Phased Rollout Gates**: Built `GlobalParsingService.dart` with Remote Config flags:
  - `enable_global_native_parsing`: Boolean master switch (default `false`).
  - `global_parsing_countries`: Country code allowlist for gradual geographic expansion (e.g. `"AE,SA"`).
- **Privacy-Safe Telemetry**: Added Firebase Analytics tracking (`parse_success`, `parse_ignored`, `parse_failed`) logging only non-PII technical parameters (`country_code`, `source_package`, `parser_used`, `reason`).

---

## 3. Reference Project Comparison & Pattern Extraction

| Dimension | PennyWise (`pennywiseai-tracker`) | Transaction-SMS-Parser | **Buddy 2.0 (Our Project)** |
|---|---|---|---|
| **Architecture** | 180 individual Kotlin bank classes | Monolithic TypeScript library | **Unified data-driven JSON (`bank_rules.json`) + Remote Config** |
| **Over-the-Air Updates** | ❌ No (requires full Play Store APK release for any bank change) | ❌ No (npm package update) | **✅ Yes (Remote Config rules delivery without app updates)** |
| **Cross-Platform Parity** | Native Android only | Node/JS only | **✅ 100% parity between Dart (foreground) & Kotlin (background)** |
| **India Regression Risk** | High (diffuse bank parsers) | N/A (India-focused) | **Zero (India path frozen, runs first, guarded by test suite)** |

### Extracted Patterns Integrated into Buddy:

#### 1. Credit Limit Clause Masking (`CREDIT_LIMIT_CLAUSE`)
- **Problem**: Credit card SMS notifications frequently state:  
  `"Your card ending 1234 has been debited for AED 85.50 at Starbucks. Avl Limit: AED 25,000.00."`  
  Without special handling, naive regexes can capture `25,000.00` instead of `85.50`.
- **Solution**: Mask out `CREDIT_LIMIT_CLAUSE` before running amount extractors:
  ```kotlin
  val CREDIT_LIMIT_CLAUSE = Regex(
      """\b(?:Avl|Avail|Available)\.?\s+(?:Credit\s+)?(?:Limit|Lmt)\b\s*(?:is)?\s*:?\s*(?:INR|Rs\.?|₹|[A-Z]{3}|[$€£¥₩])?\s*[0-9,]*\.?\d+""",
      RegexOption.IGNORE_CASE
  )
  val textWithoutLimit = CREDIT_LIMIT_CLAUSE.replace(text, " ")
  ```
  Both `GlobalBankParser.kt` and `generic_parser.dart` now mask credit limits and treat `limit` / `avl limit` as non-transaction balance markers.

#### 2. Non-Transaction False-Positive Rejections
Added anti-noise filters learned from real-world banking edge cases:
- **ASBA / IPO Blocked Funds**: Earmarked funds (`"asba"`, `"is blocked in your"`, `"earmarked in your"`) are not debits.
- **Future Auto-Debit Reminders**: Notices like `"will be auto-debited on 15 Nov"` or `"mandate set for"` announce future actions. The actual debit arrives later, so ignoring reminders prevents double-counting.
- **Hyphenated OTPs**: Hyphenated `"one-time password"` (common in Amex SafeKey, Apple Pay, and international cards).
- **Convert-to-EMI Marketing Offers**: Marketing invitations like `"Convert your bill of Rs 18,500 into SmartEMI"` contain numbers and bank words but are promotional.
- **Overdue / Min Due Reminders**: `"min amount due"`, `"minimum amount due"`, `"is overdue"`, `"in arrears"`.
- **Arabic Failure & Decline Phrases**: Added detection for Middle East banking rejections (`"عملية مرفوضة"`, `"تم رفض العملية"`, `"فشل العملية"`, `"عملية فاشلة"`, `"تعذر إتمام العملية"`, `"لم تتم العملية"`, `"عملية غير ناجحة"`, `"رصيد غير كافي"`, `"الرقم السري"`).

#### 3. Merchant Name Extraction & Noise Stripping
- **Problem**: Previously, global notifications recorded the raw SMS body (truncated to 200 characters) as the note.
- **Solution**: Implemented `extractCleanNote()`:
  - **Lookaheads**: Matches counterparty after `at`, `to`, `towards`, `paid to`, `transfer to`:
    `\b(?:at|to|transfer\s+to|trf\s+to|paid\s+to|sent\s+to|towards)\s+([A-Za-z0-9&'][^,;:\n]*?)(?=\s+(?:on|at|via|using|with|ref|for|dated|avl|avail|available|bal|balance|txn|from|to)\b|\.(?:\s|$)|[,;:\n]|$)`
  - **Suffix Stripping**: Automatically strips noise suffixes (`PVT LTD`, `LTD`, `Ref No.`, `UPI`, `on DD/MM`, `at HH:mm`, trailing parentheses).
  - **`NOT_MERCHANT` Guard**: Rejects matches starting with `your`, `a/c`, `account`, `card`, `the`, or pure digits so account references are never mistaken for merchants.
  - **UPI VPA Parentheses Name**: Extracts display names from `VPA user@upi (Merchant Name)`.
  - Produces clean notes: `"Paid at STARBUCKS COFFEE"` or `"Paid to Apple Store"`.

#### 4. Expanded Multi-Regional Category Dictionaries
Enhanced `MERCHANT_CATEGORY_MAP` and `detectCategory()`:
- **Food Delivery & Dining**: Talabat, Deliveroo, Careem Food, Al Baik, Jollibee, Chipotle, Nando's, local canteens, dhabas, biryani houses, shawarma shops, bakeries.
- **Groceries & Supermarkets**: Carrefour, LuLu, Spinneys, Waitrose, Spar, DMart, JioMart.
- **Rides & Transport**: Careem, Grab, Bolt, Yango, Salik (Dubai toll), parking, toll gates.
- **Retail & Shopping**: IKEA, Shein, Temu, Costco, Target, Walmart, Zara, Centrepoint, Sharaf DG.
- **Utilities & Telecom**: DEWA, SEWA, STC, Etisalat, Du, Mobily, Ooredoo, Zain.

---

## 4. Verification & Test Status

All tests were executed and passed cleanly:

| Test Suite | Result | Details |
|---|---|---|
| `flutter analyze` | **0 issues** ✅ | Clean static analysis across all Dart files |
| `flutter test` | **158/158 passed** ✅ | Includes 7 newly added vectors for limit masking & ignore filters |
| `BankSmsParserTest.kt` (Android unit tests) | **100% passed** ✅ | India regression test vectors pass with zero regressions |
| `GlobalBankParserTest.kt` (Android unit tests) | **66/66 passed** ✅ | Non-India test vectors across 14+ countries pass with zero errors |
| Gradle unit test build | **BUILD SUCCESSFUL** ✅ | Completed in 14s (`:app:testDebugUnitTest`) |

---

## 5. What is Balance / Left to Do

The engineering work for Buddy v17.3.0 is **100% complete**. The remaining operational tasks are:

1. **Release Build & Google Play Upload**:
   - Run `flutter build appbundle --release` (version `17.3.0+20`).
   - Upload AAB to the Google Play Console (Internal Testing first, then 10% Production rollout).
2. **Post-Release Remote Config Activation**:
   - The app ships with `enable_global_native_parsing = false` as a safety default.
   - Once the rollout reaches users, enable the flag in Firebase Remote Config for initial test markets:
     ```json
     {
       "enable_global_native_parsing": true,
       "global_parsing_countries": "AE,SA"
     }
     ```
3. **Monitor Telemetry**:
   - Observe Firebase Analytics events (`parse_success`, `parse_ignored`, `parse_failed`) in Firebase Console.
   - Gradually add more countries (`GB, US, SG, NG, KE, BR`) to `global_parsing_countries`.
