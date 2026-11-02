# Buddy v17.3.0 — Onboarding Flow Reordering & Keyboard-Safe Country Selection

**Date:** November 2026  
**Status:** Implemented & Verified (283/283 Flutter tests passed, 53/53 Android native tests passed)  
**Primary Files Modified:**
- [`lib/features/onboarding/onboarding_screen.dart`](file:///Users/faysarukattil/Desktop/Personal%20Projects/buddy_2.0/lib/features/onboarding/onboarding_screen.dart)
- [`test/onboarding_country_flow_test.dart`](file:///Users/faysarukattil/Desktop/Personal%20Projects/buddy_2.0/test/onboarding_country_flow_test.dart)

---

## 1. Problem Statement & Root Cause Analysis

### A. Keyboard Shrinking ("Tinky Preview")
- **Issue:** When a user focused the search bar in the country selector, the virtual keyboard opened and caused the entire screen to shrink down to a miniature (~35-40% scale) unreadable view.
- **Root Cause:**
  - In `lib/features/onboarding/onboarding_screen.dart`, all stages were wrapped inside `_buildHero`:
    ```dart
    Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: w,
          child: _buildMorphingStage(),
        ),
      ),
    )
    ```
  - While `FittedBox(fit: BoxFit.scaleDown)` was appropriate for static illustrations on small phone screens (such as the AutoLog card or Privacy Shield), wrapping an interactive form containing a `TextField`, horizontal chips, and a scrollable `ListView` caused `Scaffold`'s bottom inset resizing to squeeze the available height. `FittedBox` responded by uniformly shrinking fonts, icons, search inputs, and list rows into an unclickable miniature element.

### B. Onboarding Flow Ordering
- **Issue:** The Country & Currency selector was originally placed at the final step of onboarding. As a result, Steps 1, 2, and 3 were displaying generic or INR-centric placeholders rather than feeling custom-built for international users from the first second of using the app.

### C. Keyboard Auto-Close / Flickering on Tap
- **Issue:** When clicking on the search input, the keyboard would flash open and immediately dismiss/close automatically.
- **Root Cause:**
  1. **Structural Child Index Shifting:** The layout previously had `if (!keyboardOpen) ...[ _glass(preview card), SizedBox ]` above the `TextField` in a `Column`. When the IME began opening (`viewInsets.bottom > 0`), the preview card was removed from the tree. This shifted the `TextField`'s child index in the `Column` from index 5 to index 3 without keys. Flutter's element reconciliation treated this index change as an element replacement, detaching the active `EditableText`. Android's `InputMethodManager` detected the detachment of the focused view and immediately issued `hideSoftInput`, closing the keyboard.
  2. **Gesture Conflict:** The outer `GestureDetector` on the `Scaffold` had `behavior: HitTestBehavior.opaque` with `onHorizontalDragEnd`, which intercepted touch slop and typing drag gestures, firing navigation triggers that unfocused the input.
  3. **Unnecessary Focus Listener:** `_countrySearchFocus` had a listener invoking `setState(() {})` on focus change, triggering mid-event dispatch rebuilds.
- **Resolution:**
  1. **Permanent Fixed Hierarchy:** Removed conditional widget additions/removals above the search bar. The search bar is always at index 3, the chips at index 4, and the country list in `Expanded` at index 5. The `TextField` never shifts indices and never unmounts.
  2. **Disabled `onHorizontalDragEnd` on Step 0:** `onHorizontalDragEnd: _page == 0 ? null : ...`, eliminating gesture arena conflicts.
  3. **Clean Focus Model:** Removed the `FocusNode` listener; added `keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag` to the `ListView` so the keyboard stays up while typing and dismisses naturally on drag.

---

## 2. Architecture & Implementation

### A. Onboarding Flow Reordering (Country First)

The 4 onboarding steps have been reordered:

```
[ Step 0: Country & Currency Selection ]
       │
       ▼ (Immediately sets CurrencyService.countryCode & currencySymbol)
[ Step 1: Your spending logs itself ] ──▶ Localized Merchant, Payment Channel & Currency
       │
       ▼
[ Step 2: We never read your OTPs ]   ──▶ Localized Bank Alert Verification
       │
       ▼
[ Step 3: Every pro tool. {symbol}0 ] ──▶ Localized Heatmap, Debt, Category Hub & Conversion CTA
```

#### Step Meta Definitions:
1. **Step 0**:
   - Headline: `"Where are you based?\nChoose your currency."`
   - Subtitle: `"Auto-tracking and money symbols will be tuned specifically for your country."`
   - CTA: `"Continue"`
2. **Step 1**:
   - Headline: `"Your spending\nlogs itself."`
   - Subtitle: `"Pay with any bank or wallet as usual. Buddy spots the payment alert and logs it for you."`
   - CTA: `"Continue"`
3. **Step 2**:
   - Headline: `"We never read\nyour OTPs."`
   - Subtitle: `"Alerts are filtered on your phone. Bank OTPs and personal chats are ignored."`
   - CTA: `"Continue"`
4. **Step 3**:
   - Headline: `"Every pro tool.\n{symbol}0 forever."` (Dynamic: e.g. `₹0 forever.`, `$0 forever.`, `AED 0 forever.`, `£0 forever.`)
   - Subtitle: `"Heatmaps, category insights and friend-debt tracking are unlocked from day one."`
   - CTA: `"Start tracking free"`

---

### B. Dedicated Keyboard-Safe Layout (`_buildCountrySelectionScreen`)

1. **No `FittedBox` on Interactive Content**:
   - Step 0 completely bypasses `_buildHero` and renders directly via `_buildCountrySelectionScreen(isDark)`.
   - The country list is housed in an `Expanded` widget with a `ListView.separated`. When the virtual keyboard appears, the list naturally adapts its viewport height without scaling down any fonts or tap targets.

2. **Adaptive Header & Preview Card on Keyboard Focus**:
   - When keyboard is **closed**:
     - Large title and subtitle: *"Where are you based? / Choose your currency."*
     - Full live interactive preview card with flag, country name, currency code, and sample auto-logged transaction tile (`-$symbol$amount`).
   - When keyboard is **open**:
     - Title transitions to a compact row: *"Select Country & Currency"* + badge `${flag} ${currencyCode} (${symbol})`.
     - The preview card collapses to zero height, providing maximum vertical screen real estate for the search results.

3. **Pinned Suggestion Chips**:
   - Quick selection chips (`🇮🇳 India`, `🇦🇪 UAE`, `🇺🇸 USA`, `🇬🇧 UK`, `🇸🇦 Saudi`, `🇨🇦 Canada`, `🇦🇺 Australia`, `🇸🇬 Singapore`, `🇶🇦 Qatar`, `🌐 Other`) remain permanently pinned directly beneath the search bar.
   - Fixed earlier display issue where `United States`, `United Kingdom`, and `United Arab Emirates` all showed "United". Now each chip cleanly displays its proper recognizable name (`UAE`, `USA`, `UK`, `Saudi`, etc.).
   - Tapping any chip immediately selects the country, updates `CurrencyService`, and dismisses keyboard focus cleanly.

4. **Search Bar**:
   - Real-time search across 195+ countries and all 178 Google Play Console targeted regions.
   - Supports search by country name, ISO country code (e.g. `US`, `AE`, `IN`), currency code (e.g. `EUR`, `GBP`, `JPY`), or currency symbol (e.g. `€`, `¥`, `£`).
   - Includes one-tap clear button (`X`).

5. **Keyboard-Safe Bottom Action**:
   - When keyboard is closed: Full gradient button `"Continue"` with subtext `"Tuned for {Country} ({Code})"`.
   - When keyboard is open: Compact 44px gradient button `"Continue with {Symbol}"` positioned right above the IME, allowing users to proceed instantly without manually dismissing the keyboard.

---

### C. Downstream Country Personalization

When a user selects their country on Step 0, all subsequent screens immediately update:

| Selected Country | Currency Symbol | Step 1 Sample Merchant & Channel | Step 2 Verified Alert | Step 3 Pro Hub Zero Pill |
|---|---|---|---|---|
| **India (`IN`)** | `₹` | Fresh Basket Supermarket via UPI | Swiggy via UPI (official logo) | `₹0 / forever` |
| **United States (`US`)** | `$` | Trader Joe's via Apple Pay | Trader Joe's via Apple Pay | `$0 / forever` |
| **United Arab Emirates (`AE`)** | `AED` | Carrefour Supermarket via Debit Card | Carrefour via Debit Card | `AED 0 / forever` |
| **United Kingdom (`GB`)** | `£` | Sainsbury's Local via Contactless | Sainsbury's via Contactless | `£0 / forever` |
| **Saudi Arabia (`SA`)** | `SAR` | Panda Hypermarket via mada | Panda via mada | `SAR 0 / forever` |
| **Canada (`CA`)** | `CA$` | Loblaws Supermarket via Interac | Loblaws via Interac | `CA$0 / forever` |
| **Australia (`AU`)** | `A$` | Woolworths Metro via Tap & Pay | Woolworths via Tap & Pay | `A$0 / forever` |
| **Singapore (`SG`)** | `S$` | FairPrice Supermarket via PayNow | FairPrice via PayNow | `S$0 / forever` |
| **Japan (`JP`)** | `¥` | 7-Eleven Ginza via iD / Card | 7-Eleven via iD / Card | `¥0 / forever` |
| **Eurozone (`DE`/`FR`/`ES`)** | `€` | Carrefour Express via Card / Wallet | Carrefour Express via Card | `€0 / forever` |
| **Rest of World / Other** | Target Symbol | Local Grocery Market via Card / Wallet | Verified Bank Transaction | `{symbol}0 / forever` |

### D. National Pride & High-Converting Viewport Architecture

1. **National Pride Glass Card (`_nationalPrideTitle` & `_nationalPrideSubtitle`)**:
   - Rather than displaying a generic duplicate transaction card, Step 0 features an ultra-sleek, compact 48px National Pride Glass Card.
   - Highlights the user's selected country with tailored pride headlines and localized banking auto-tracking:
     - `Proudly Tuned for India 🇮🇳` — *Auto-detects UPI & 40+ Indian banks in ₹ (INR)*
     - `Optimized for UAE 🇦🇪` — *Auto-detects ENBD, ADCB, FAB & cards in AED*
     - `Built for United States 🇺🇸` — *Auto-detects Chase, BoA, Amex & Apple Pay in $*
     - `Tuned for United Kingdom 🇬🇧` — *Auto-detects Monzo, Barclays, Revolut & cards in £*
     - `Proudly Made for Saudi Arabia 🇸🇦` — *Auto-detects Al Rajhi, SNB, Riyad & mada in SAR*
     - `Tuned for Canada 🇨🇦` — *Auto-detects RBC, TD, Scotiabank & Interac in CA$*
     - `Optimized for Australia 🇦🇺` — *Auto-detects CommBank, ANZ, NAB & cards in A$*
     - `Tuned for Singapore 🇸🇬` — *Auto-detects DBS, OCBC, UOB & PayNow in S$*
     - `Tuned for Pakistan 🇵🇰` — *Auto-detects HBL, Meezan, Raast & JazzCash in Rs*
     - `Tuned for Bangladesh 🇧🇩` — *Auto-detects bKash, Nagad & local banks in ৳*
     - `Tuned for Nigeria 🇳🇬` — *Auto-detects GTBank, Access, Zenith & transfers in ₦*
     - `Tuned for Kenya 🇰🇪` — *Auto-detects M-PESA & Kenyan bank alerts in KSh*
     - `Optimized for Germany 🇩🇪` / `France 🇫🇷` / `Japan 🇯🇵` / `Brazil 🇧🇷` / All 178 Play Store Countries.

2. **Vertical Space Budget Math for Mobile Viewports**:
   - On a typical 780–800px mobile screen with a 330px IME keyboard:
     - Usable height: `~450–470px`.
     - Streamlined top elements (TopBar, Compact Header, Pride Card, SearchBar, Chips): `~180px`.
     - Bottom continue action is cleanly hidden when keyboard is open (`if (!keyboardOpen)` at index 6 after the list, ensuring indices 0..5 never shift).
     - **Resulting Expanded List Viewport:** **280–300px** of unconstrained vertical scroll space, fitting **6 to 7 full country rows** simultaneously while typing.

---

## 3. Verification & Test Coverage

### A. Flutter Unit & Widget Tests
Command: `flutter test`
- **Result:** **284 / 284 tests passed** (including 6 tests in `test/onboarding_country_flow_test.dart`):
  1. `Step 0 displays Country Selection first with search & popular chips` (Verified)
  2. `Selecting a country via chip updates CurrencyService immediately` (Verified)
  3. `Search input filters country list without crashing` (Verified)
  4. `Step 1 auto-log preview adapts to selected country` (Verified)
  5. `Step 3 Pro Hub displays selected country currency symbol and CTA` (Verified)
  6. `Tapping search field maintains focus without unmounting or closing keyboard` (Verified)

### B. Static Code Analysis
Command: `flutter analyze`
- **Result:** **0 issues found** across all files.

### C. Android Native Unit Tests
Command: `./gradlew :app:testDebugUnitTest`
- **Result:** **BUILD SUCCESSFUL** across 320 tasks (all 53 Android native test cases passed).

