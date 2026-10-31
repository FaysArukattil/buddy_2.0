# Buddy — Handoff State

**Last updated:** 2026-10-31T12:30:00+05:30
**Last agent:** Initial setup

## Current State
- Step 0 (handoff docs) is COMPLETE
- No code changes have been made yet
- Codebase has been fully scanned and documented in PROJECT_CONTEXT.md

## What Was Being Done
- Setting up the handoff documentation system
- Scanning the entire codebase to understand architecture, currency references, and SMS parsing

## What Is Half-Done
- Nothing — docs are complete, code work hasn't started

## Exact Next Step
**Start Task 1: Forced / Prompted App Update**
1. Add `in_app_update` and `firebase_remote_config` packages to `pubspec.yaml`
2. Run `flutter pub get`
3. Create `lib/services/update_service.dart`
4. Integrate into app startup flow

## Known Bugs
- None introduced (haven't touched code yet)

## Commands to Run
```bash
cd "/Users/faysarukattil/Desktop/Personal Projects/buddy_2.0"
flutter pub get
flutter analyze
flutter test
```

## Things the Next Agent Must Not Redo
- Do NOT re-scan the codebase — it's all in PROJECT_CONTEXT.md
- Do NOT recreate the docs/agent/ folder — it exists
- Do NOT skip reading the task list — check TASKS.md for current status
- The Indian SMS parsing in NotificationListener.kt is ~1307 lines and WORKS — do NOT rewrite it without regression tests first

## Key Architecture Notes
- State management is `ValueNotifier` + `ValueListenableBuilder` (no Provider)
- Widget data flows: Flutter → MethodChannel → SharedPreferences → Kotlin widget providers
- SMS parsing: Kotlin NotificationListenerService → SharedPreferences → Flutter sync on app open
- Firestore path: `users/{uid}/transactions`, `users/{uid}/categories`
- User prefs path: `users/{uid}` document (includeDebtsInHome, homeBalanceMode)
- Currency will be added to user doc: countryCode, currencyCode, currencySymbol
