# Buddy — Project Context

## What Is Buddy?
Buddy is a **live production Flutter expense tracker** on the Google Play Store (`com.faysarukattil.buddy`). Current version: **17.1.0+18**. Real users already have it installed.

## Tech Stack
| Layer | Technology |
|-------|-----------|
| Framework | Flutter / Dart (SDK ^3.9.2) |
| Auth | Firebase Auth + Google Sign-In, guest accounts |
| Database | Cloud Firestore (users/{uid}/transactions, users/{uid}/categories) |
| Local Cache | SharedPreferences (transaction sync, preferences, theme) |
| State Management | `ValueNotifier` / `ValueListenableBuilder` (no Provider/Riverpod/Bloc) |
| Charts | `fl_chart` ^0.68.0 |
| PDF | `pdf` ^3.11.1, `printing` ^5.13.2 |
| Notifications | `flutter_local_notifications` ^19.5.0 |
| SMS Parsing | Native Kotlin `NotificationListenerService` (reads bank SMS notifications on Android) |
| Home Widget | Custom native Kotlin implementation via MethodChannel (`com.faysarukattil.buddy/widget`) — NO `home_widget` package |
| Currency (current) | Hardcoded ₹ (INR) everywhere, Indian numbering system (Lakh/Crore) |
| Internationalization | `intl` ^0.19.0 (only for date formatting currently) |
| Existing packages | `package_info_plus` ^10.2.2 already present |

## Folder Structure
```
lib/
├── main.dart                          # App entry, widgetAddMain entry, _initCoreServices
├── firebase_options.dart              # Firebase config (generated)
├── features/
│   └── onboarding/
│       └── onboarding_screen.dart     # Animated onboarding (2300+ lines, has ₹ refs)
├── models/
│   ├── transaction.dart               # TransactionModel (Firestore serialization, dedup)
│   ├── category.dart                  # Category model
│   ├── debt.dart                      # DebtModel (borrow/lend)
│   └── bill.dart                      # BillModel
├── services/
│   ├── app_init_helper.dart           # App startup: seed categories, sync transactions
│   ├── auth_service.dart              # Firebase Auth, guest linking
│   ├── firestore_service.dart         # Firestore CRUD, category seeding, dedup cleanup
│   ├── notification_service.dart      # MethodChannel to Kotlin, sync SharedPrefs→Firestore
│   ├── notification_helper.dart       # Local notification display (has ₹ refs)
│   ├── preference_service.dart        # ValueNotifier prefs (includeDebts, homeBalanceMode)
│   ├── widget_service.dart            # Push data to native widget via MethodChannel
│   ├── pdf_service.dart               # PDF generation (replaces ₹ with "Rs." for font safety)
│   ├── theme_service.dart             # Dark/light/system theme
│   ├── debt_service.dart              # Debt settlement logic (has ₹ refs)
│   ├── feedback_service.dart          # In-app feedback mailto
│   ├── support_service.dart           # "Buy me a chai" support prompt
│   ├── transaction_sync_helper.dart   # Transaction sync utilities
│   └── Network_services.dart          # Online/offline monitoring
├── utils/
│   ├── format_utils.dart              # FormatUtils.formatCurrency (₹, Indian numbering, Cr/L/k)
│   ├── export_manager.dart            # CSV/share export
│   ├── budget_manager.dart            # Budget tracking
│   ├── app_snackbar.dart              # Snackbar helper
│   ├── colors.dart                    # AppColors, category colors
│   ├── icon_helper.dart               # Icon codepoint mapping
│   ├── images.dart                    # Asset paths
│   └── notification_test_helper.dart  # Debug SMS simulation widget (has ₹/Rs/INR refs)
└── views/
    ├── screens/
    │   ├── onboarding/
    │   │   ├── auth_wrapper.dart       # Auth gate (login vs home)
    │   │   ├── onborading_screen.dart  # Legacy onboarding
    │   │   ├── login_screen.dart       # Email/Google login
    │   │   ├── signup_screen.dart      # Email/Google signup
    │   │   └── splashscreen/
    │   │       └── splash_screen.dart  # Splash → onboarding/auth
    │   ├── bottomnavbarscreen/
    │   │   ├── home_screen.dart        # Main dashboard (₹ via FormatUtils)
    │   │   ├── statistics_screen.dart  # Charts & analytics (₹ via FormatUtils)
    │   │   ├── profile_screen.dart     # User profile (₹ via FormatUtils)
    │   │   ├── bottom_navbar_screen.dart # Tab navigation
    │   │   └── borrow_lend_screen.dart # Debts (hardcoded ₹ in many places)
    │   ├── add_transaction_screen.dart # Add/edit transaction (₹ prefix in amount field)
    │   ├── transaction_detail_screen.dart # Detail view (₹ in amount display)
    │   ├── filtered_transactions_screen.dart # Filtered list (₹ via FormatUtils)
    │   └── widget_add_modal_host.dart  # Quick-add from widget
    └── widgets/
        ├── animated_money_text.dart    # Animated ₹ amount (uses FormatUtils)
        ├── setting_modal.dart          # Settings bottom sheet
        ├── offline_banner.dart         # Offline indicator
        └── ...

android/app/src/main/kotlin/com/faysarukattil/buddy/
├── NotificationListener.kt           # 1307 lines — THE SMS parser (India-only, ₹/Rs/INR)
├── NotificationActionReciever.kt      # Duplicate confirmation actions (₹ refs)
├── DuplicateConfirmationActivity.kt   # Duplicate confirmation UI (₹ refs)
├── BuddyWidgetProvider.kt            # Main home widget (₹ in formatCompactCurrency)
├── BuddyStatsWidgetProvider.kt       # Stats widget
├── BuddyQuickAddWidgetProvider.kt    # Quick-add widget
├── BuddyWidgetChannel.kt            # MethodChannel bridge
├── BuddyChartRenderer.kt            # Native canvas chart rendering
├── BuddyApplication.kt              # Application class
├── MainActivity.kt                   # Main activity
├── WidgetAddModalActivity.kt         # Widget add modal
└── BootReciever.kt                   # Boot receiver

android/app/src/main/res/layout/
├── widget_buddy.xml                   # Widget layouts (default ₹0 in TextViews)
├── widget_buddy_small.xml
├── widget_buddy_medium.xml
├── widget_buddy_large.xml
├── widget_buddy_page_today.xml        # Many ₹0 defaults
├── widget_buddy_page_month.xml        # Many ₹0 defaults
├── widget_buddy_page_donut.xml
├── widget_buddy_page_heatmap.xml
└── widget_buddy_stats.xml
```

## How SMS Reading/Parsing Works
1. **Android NotificationListenerService** (`NotificationListener.kt`) monitors all notifications
2. Filters to SMS apps + payment apps + bank apps
3. Rejects promotional/spam via keyword list
4. Determines debit vs credit via regex patterns (India-specific: `Rs`, `INR`, `₹`)
5. Extracts amount (excluding balance amounts), category (via merchant map), note, UPI ref
6. Saves to `SharedPreferences` as `flutter.txn_{hash}` JSON
7. On app open/resume, Flutter's `NotificationService.syncSavedTransactions()` reads SharedPrefs and pushes to Firestore
8. **All parsing is on-device** — no SMS content is uploaded to any server

## Firestore Schema
```
users/{uid}/
├── transactions/{docId}  → { amount, type, date, note, category, icon, autoDetected, notificationSource, notificationHash, createdAt }
├── categories/{docId}    → { name, icon, color, type, isDefault, order }
└── (user doc fields)     → { includeDebtsInHome, homeBalanceMode, updatedAt }
```

## How the App Is Built & Released
- Standard `flutter build appbundle` for Play Store
- Version in `pubspec.yaml`: `version: 17.1.0+18`
- App signing via Play App Signing
- Firebase config via `google-services.json`

## Hardcoded Currency Locations (₹/Rs/INR)
All files that have hardcoded Indian currency that need to change for Task 2:

### Dart files:
- `lib/utils/format_utils.dart` — ₹ prefix, Indian numbering (Lakh/Crore), formatCurrency/formatCompactCurrency
- `lib/features/onboarding/onboarding_screen.dart` — ₹240, ₹0, ₹448, ₹4,337, ₹1,450, ₹12,554 etc.
- `lib/views/screens/bottomnavbarscreen/borrow_lend_screen.dart` — ₹0.00, ₹ prefix in text fields
- `lib/views/screens/add_transaction_screen.dart` — ₹ prefix in amount input
- `lib/views/screens/transaction_detail_screen.dart` — ₹ prefix in amount display
- `lib/services/notification_helper.dart` — ₹ in notification text
- `lib/services/pdf_service.dart` — replaces ₹→"Rs.", formatCurrency uses "Rs."
- `lib/services/debt_service.dart` — ₹ in debug logs
- `lib/utils/notification_test_helper.dart` — ₹/Rs/INR in test SMS and regexes

### Kotlin files:
- `BuddyWidgetProvider.kt` — formatCompactCurrency with ₹, default "₹0" values
- `NotificationListener.kt` — ₹/Rs/INR in regex patterns (SMS parsing)
- `NotificationActionReciever.kt` — ₹ in notification text
- `DuplicateConfirmationActivity.kt` — ₹ in confirmation text

### XML layout files:
- `widget_buddy_page_today.xml` — 16× "₹0" default text
- `widget_buddy_page_month.xml` — 6× "₹0" default text
- `widget_buddy_large.xml` — 6× "₹0"/"+₹0" default text
- `widget_buddy_medium.xml` — 4× "₹0" default text
