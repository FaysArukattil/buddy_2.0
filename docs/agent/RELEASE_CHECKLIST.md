# Buddy — Release Checklist

> This checklist must be completed before any release that includes the changes from Tasks 1–4.

## Firestore Security Rules
- [ ] Add validation for new user document fields:
  - `countryCode` — string, max 2 chars, required format `[A-Z]{2}`
  - `currencyCode` — string, max 3 chars, required format `[A-Z]{3}`
  - `localeCode` — string, max 10 chars, format like `en_US`, `hi_IN`
  - `currencySymbol` — string, max 5 chars
- [ ] Ensure only the owning user (`request.auth.uid == userId`) can read/write these fields
- [ ] Deploy updated rules BEFORE releasing the app update

## Play Console Data Safety Form
- [ ] Update Data Safety form to declare:
  - Country selection (collected, not shared, required for app functionality)
  - Currency preference (collected, not shared, required for app functionality)
  - Anonymous analytics events (collected, not shared, analytics purpose)
- [ ] Declare that no SMS content is transmitted off-device

## Privacy Policy Updates
- [ ] Update privacy policy to mention:
  - Country and currency preferences are stored in Firebase Firestore
  - Anonymous parse success/failure analytics (no message content)
  - SMS content is processed on-device only and never uploaded

## Migration Testing
- [ ] Test on a build with existing user data (India/INR user):
  1. Install the OLD version, create some transactions
  2. Upgrade to the NEW version
  3. Verify: app opens without crash
  4. Verify: defaults to India / INR / en_IN silently
  5. Verify: all existing transactions display with ₹ symbol
  6. Verify: SMS auto-detection still works correctly
  7. Verify: home screen widget still shows ₹ amounts
  8. Verify: PDF export shows Rs. / ₹ correctly with new Unicode font
  9. Verify: changing currency in Settings works and refreshes everything
  10. Verify: onboarding is NOT forced for existing users

## Version Bump
- [ ] Bump `versionName` in `pubspec.yaml` (e.g. 17.1.0 → 18.0.0)
- [ ] Bump `versionCode` (build number) (e.g. +18 → +19)
- [ ] Update Remote Config `latest_version` to match the new version

## Pre-Release Checks
- [ ] `flutter analyze` — zero warnings, zero errors
- [ ] `flutter test` — all Dart tests pass
- [ ] Kotlin unit tests — all pass (including India regression)
- [ ] Manual smoke test on a physical device
- [ ] Test with airplane mode (offline behavior)
- [ ] Test fresh install (new user onboarding flow)

## Release Process
- [ ] Build signed AAB: `flutter build appbundle --release`
- [ ] Upload to Play Console
- [ ] **Staged rollout: 10-20% first**
- [ ] Monitor crash reports for 24-48 hours
- [ ] If stable: expand to 100%
- [ ] **ONLY AFTER 100% rollout:**
  - [ ] Set Remote Config `min_supported_version` to force old versions to update
  - [ ] Set Remote Config `force_update` = true only if critical
  - [ ] NEVER set min_supported_version before the new version is live

## Post-Release
- [ ] Monitor Firebase Analytics for parse_success/ignored/failed events
- [ ] Check which banks/countries are hitting parse_failed
- [ ] Update bank_rules.json via Remote Config if needed (no new release required)
