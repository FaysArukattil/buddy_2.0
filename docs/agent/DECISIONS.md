# Buddy — Design Decisions Log

| # | Decision | Reason |
|---|----------|--------|
| 1 | Use `ValueNotifier` + `ValueListenableBuilder` for state (no Provider/Riverpod) | Matches existing codebase pattern — minimal dependencies, simple reactive updates |
| 2 | SMS parsing stays entirely on-device | Google Play policy compliance; no server-side upload of SMS content |
| 3 | Existing users default to India / INR / en_IN when no country is saved | Preserves exact current behavior for all live users; nothing breaks |
| 4 | Currency change only changes display symbol, does NOT convert amounts | Converting historical data would require exchange rates and could cause confusion; simpler to just update display. Show one-time note in Settings. |
| 5 | Store three independent fields: countryCode, currencyCode, localeCode | Country ≠ currency ≠ locale. Example: user in UAE tracking expenses in USD with English locale. currencySymbol is derived from currencyCode, not stored as primary key. |
| 6 | Digit grouping and decimal separators follow localeCode, not currencyCode | A user's preferred number formatting (1,234.56 vs 1.234,56) is a locale choice, not a currency choice |
| 7 | Version comparison is numeric segment-by-segment (1.10.0 > 1.9.0) | String comparison would treat "1.9.0" > "1.10.0" incorrectly |
| 8 | Skip in_app_update for debug/non-Play-Store builds | in_app_update requires Play Store install; attempting it on sideloaded builds causes exceptions. Remote Config logic still runs; store button opens Play listing. |
| 9 | Remote Config in-app defaults set for offline/first-launch | App must work fully without network. Defaults: min_supported_version="1.0.0", latest_version=current, force_update=false, update_message="" |
| 10 | minimumFetchInterval: 12 hours (prod), 60 seconds (debug) | Avoids excessive fetches in production while allowing fast iteration in development |
| 11 | In-memory guard + SharedPreferences daily limit to prevent double update prompts | Multiple triggers (splash, resume, app start) could show multiple dialogs. Force update ignores daily limit. |
| 12 | Single shared JSON schema (assets/parsing/bank_rules.json) for Dart and Kotlin parsers | One source of truth for per-country bank rules; no duplicated logic. Kotlin keeps hardcoded India logic untouched; JSON is for new countries. |
| 13 | Shared test vectors file for Dart + Kotlin tests | Same test cases validate both parsers, ensuring consistency. India regression cases written first before any changes. |
| 14 | Identify banks by notification package name AND sender text | NotificationListener sees app package + notification title; using both provides more reliable identification |
| 15 | Bundle Unicode font (Noto Sans) for PDF export | Default PDF Helvetica font lacks glyphs for ₹ ₦ ৳ ₫ ₺ ₱ ₸ etc. Current workaround (replace ₹ with "Rs.") won't scale to global currencies. |
| 16 | Privacy-safe analytics: parse_success/ignored/failed events | Allowed params: countryCode, source package, parser used, reason code. NEVER message text, amounts, names, or account numbers. Lets us see which banks need fixing. |
| 17 | Prepare bank_rules.json for Remote Config delivery (bundled asset as offline fallback) | Lets us fix bank SMS format changes without a Play Store release. Validate JSON before use; fall back to bundled version if invalid. |
| 18 | iOS/non-SMS countries need manual entry — noted as future work | SMS parsing is Android-only. On iOS or in countries where banks don't send SMS, suggest manual entry or notification-based approach. Not built now. |
| 19 | "Report this message" button — future item if complex | User-consented redacted message reporting. Only if simple to implement; otherwise documented as future work. |

| 20 | India Kotlin parser remains hardcoded — JSON entry is documentation only | The India parser has been in production and is battle-tested. Rewiring it to JSON would risk regressions for the app's primary market. All other countries use GenericParser from JSON rules. |
| 21 | GenericParser.fromRule() builds a stateless parser per country from JSON | Stateless parsers are safe for concurrent calls; one instance per country cached in ParserRegistry |
| 22 | Task 3C (Remote Config for bank_rules.json) — design in place, implementation deferred | RemoteConfig can deliver the JSON string; ParserRegistry.reloadFromRemoteConfig(json) is implemented and ready. Wiring to Firebase Remote Config delivery is straightforward (similar to update_service.dart pattern) but adds fetch/validation complexity not worth the risk before v18. Add as a post-launch follow-up. |
| 23 | Zero-decimal currencies (JPY/KRW/IDR/VND/CLP) tracked in bank_rules.json decimalDigits field | Amount parsing strips thousands separators correctly; no fractional part expected. GenericParser._parseAmount() handles the Indonesian dot-thousands (50.000 = 50000) vs European comma-decimal correctly using decimalSeparator/thousandsSeparator. |

| 24 | Analytics implementation: Kotlin side uses Firebase Android SDK directly; Dart side uses firebase_analytics Dart package | Avoids MethodChannel round-trip for analytics calls. Kotlin NotificationListener logs `parse_ignored`/`parse_failed` at each rejection point inside `parseTransaction()`. The `parse_success` event is logged BOTH from Kotlin (at `saveTransaction()` in `onNotificationPosted`) AND from Dart (`syncSavedTransactions()` after Firestore write) — this double-counts successful parsings but is acceptable because analytics is for relative trend monitoring, not absolute counts. Kotlin also writes `country_code` and `parser_used` into the SharedPrefs JSON so the Dart side has them. |
| 25 | Source package name is logged as analytics parameter (non-PII) | The Android package name of the notification-sending app (e.g., `com.google.android.apps.messaging`) identifies which SMS app or banking app the notification came from. This is technical metadata, not personal data — it reveals nothing about the user's identity, contacts, or transactions. |

*(More decisions will be added as tasks progress)*
