# Buddy — Handoff State

**Last updated:** 2026-10-31T12:37:00+05:30
**Last agent:** Amendments integration

## Current State
- Step 0 (handoff docs) is COMPLETE — all 7 files created (including RELEASE_CHECKLIST.md)
- Plan amendments (A–E) integrated into TASKS.md and DECISIONS.md
- No code changes have been made yet
- Codebase has been fully scanned and documented in PROJECT_CONTEXT.md

## What Was Being Done
- Integrating plan amendments into handoff documentation

## What Is Half-Done
- Nothing — docs are updated, code work hasn't started

## Exact Next Step
**Start Task 1: Forced / Prompted App Update**
1. Add `in_app_update` and `firebase_remote_config` packages to `pubspec.yaml`
2. Run `flutter pub get`
3. Create `lib/services/update_service.dart` with all hardening requirements:
   - Numeric segment-by-segment version comparison
   - Skip in_app_update for debug/non-Play-Store builds
   - Remote Config in-app defaults
   - In-memory dialog guard + daily SharedPreferences limit
   - Force update ignores daily limit
   - All wrapped in try/catch
4. Integrate into app startup flow (splash_screen.dart + main.dart _MyAppState)
5. Update DECISIONS.md with Remote Config keys

## Known Bugs
- None introduced (haven't touched code yet)

## Key Amendments to Remember
- **A) Task 1:** Numeric version comparison, skip in_app_update for debug/non-Play, in-app defaults, double-prompt guard
- **B) Task 2:** Separate country/currency/locale, bundle Noto Sans for PDF, single source of truth, display-only change
- **C) Task 3:** Single shared JSON schema (assets/parsing/bank_rules.json) for Dart+Kotlin, shared test vectors, identify by pkg+sender
- **D) Task 4:** NEW — Privacy-safe Firebase Analytics events (parse_success/ignored/failed)
- **E) Task 5:** NEW — Release checklist (Firestore rules, Data Safety, migration test, staged rollout)

## Things the Next Agent Must Not Redo
- Do NOT re-scan the codebase — it's all in PROJECT_CONTEXT.md
- Do NOT recreate docs/agent/ — all 7 files exist
- Do NOT skip reading TASKS.md — check for current status
- The Indian SMS parsing in NotificationListener.kt is ~1307 lines and WORKS — do NOT rewrite without regression tests
- Amendments A–E are already integrated into TASKS.md and DECISIONS.md
