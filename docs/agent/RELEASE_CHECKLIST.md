# Buddy — Release Checklist

> **For version 17.2.0+19** — includes Tasks 1–4 changes.
> This is the pre-release checklist for deploying to Google Play.

---

## ✅ Already Done (in code)

- [x] **Version bumped** → `pubspec.yaml`: `version: 17.2.0+19`
  - `versionCode` = 19 (read from pubspec by `flutter.versionCode`)
  - `versionName` = 17.2.0 (read from pubspec by `flutter.versionName`)
- [x] **Firestore security rules reviewed** — `firestore.rules` already uses
  `allow read, write: if request.auth != null && request.auth.uid == userId`
  on the user document; this covers all new fields (`countryCode`, `currencyCode`,
  `localeCode`, `currencySymbol`) without any rule changes needed. ✅
- [x] `flutter analyze` — No issues ✅
- [x] `flutter test` — 130 tests, all pass ✅

---

## 🔲 Before Building the AAB

### Play Console — Data Safety Form
- [ ] Declare **Country selection** (user preference, stored in Firestore, not shared)
- [ ] Declare **Currency preference** (user preference, stored in Firestore, not shared)
- [ ] Declare **Anonymous analytics events** (parse_success/ignored/failed — no financial data; purpose: app analytics)
- [ ] Declare **no SMS content is transmitted off-device** (processed on-device only)

### Privacy Policy Updates
- [ ] Update privacy policy to mention:
  - Country and currency preferences are stored in Firebase Firestore
  - Anonymous parse success/failure analytics events (no message text, no amounts)
  - SMS content is processed entirely on-device and never uploaded

### Kotlin Unit Tests (requires Android SDK / Gradle)
```bash
cd android && ./gradlew test
```
- [ ] `BankSmsParserTest.kt` passes — protects Indian SMS parsing regression

### Manual Smoke Tests (physical device)
- [ ] **Migration test** — install OLD version, create transactions, upgrade:
  1. Defaults to India / INR / en_IN silently (no forced onboarding) ✅?
  2. All existing transactions show ₹ symbol ✅?
  3. SMS auto-detection still works ✅?
  4. Home screen widget still shows ₹ ✅?
  5. PDF export renders ₹ with Noto Sans font ✅?
  6. Changing currency in Settings works ✅?
- [ ] **Fresh install test** — new user onboarding shows currency picker ✅?
- [ ] **Offline test** — airplane mode, app still opens and displays data ✅?
- [ ] **Update prompt test** — trigger update check with Remote Config ✅?

---

## 🔲 Build & Release

```bash
flutter build appbundle --release
```

- [ ] Upload signed AAB to Play Console (Internal Testing track first)
- [ ] Verify the Internal Testing build on a real device
- [ ] Promote to Production — **staged rollout: 10% first**
- [ ] Monitor crash-free rate and ANR rate for 24–48 hours
- [ ] If stable → expand to 50% → 100%

---

## 🔲 Remote Config (AFTER new version is live at 100%)

> ⚠️ **NEVER set `min_supported_version` before the new version has reached 100% rollout**

```
min_supported_version: "17.2.0"
latest_version: "17.2.0"
force_update: false
update_message: ""
```

Set these keys in Firebase Console → Remote Config **only after** 100% rollout.

---

## 🔲 Post-Release Monitoring

- [ ] Firebase Analytics → `parse_success` event count increasing
- [ ] Firebase Analytics → `parse_ignored` breakdown by `reason_code` (expect `promo` + `otp` to dominate)
- [ ] Firebase Analytics → `parse_failed` breakdown by `country_code` (shows which banks need fixing)
- [ ] Crashlytics → no new crash signatures
- [ ] Play Console → rating / reviews — watch for complaints about currency display

---

## Future Work (post-launch)

| Item | Where documented |
|------|-----------------|
| Wire `ParserRegistry.reloadFromRemoteConfig()` to actual RC fetch | `DECISIONS.md` #22 |
| iOS / non-SMS country support (manual entry flow) | `DECISIONS.md` #18 |
| User-consented "report this message" button | `DECISIONS.md` #19 |
| Kotlin SMS parsing for non-India countries (current architecture: Dart-only) | `PARSING_RESEARCH.md` |
