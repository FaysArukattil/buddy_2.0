import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:buddy/features/onboarding/onboarding_screen.dart';
import 'package:buddy/services/currency_service.dart';
import 'package:buddy/data/countries_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CurrencyService.setCountry(
      countryCode: CurrencyService.defaultCountryCode,
      currencyCode: CurrencyService.defaultCurrencyCode,
      currencySymbol: CurrencyService.defaultCurrencySymbol,
      localeCode: CurrencyService.defaultLocaleCode,
    );
  });

  group('Onboarding Flow Reordering & Country Selection Tests', () {
    testWidgets('Step 0 displays Country Selection first with search & popular chips',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // Step 0 Headline & Subtitle check
      expect(find.textContaining('Where are you based?'), findsOneWidget);
      expect(find.textContaining('Choose your currency'), findsOneWidget);

      // Search bar hint check
      expect(
        find.textContaining('Search 195+ countries or currencies...'),
        findsOneWidget,
      );

      // Popular chips check (e.g., India, UAE, USA)
      expect(find.text('India'), findsWidgets);
      expect(find.text('UAE'), findsOneWidget);
      expect(find.text('USA'), findsOneWidget);

      // "Continue" button is present
      expect(find.text('Continue'), findsWidgets);
    });

    testWidgets('Selecting a country via chip updates CurrencyService immediately',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // Tap the UAE chip
      final uaeChip = find.text('UAE');
      expect(uaeChip, findsOneWidget);
      await tester.tap(uaeChip);
      await tester.pump(const Duration(milliseconds: 300));

      // Verify CurrencyService reflects AED
      expect(CurrencyService.countryCode, 'AE');
      expect(CurrencyService.currencyCode, 'AED');
      expect(CurrencyService.symbol, 'AED');

      // The live preview card or tuned message should mention UAE
      expect(find.textContaining('United Arab Emirates'), findsWidgets);
    });

    testWidgets('Search input filters country list without crashing',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // Find search TextField
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      // Enter search query "Japan"
      await tester.enterText(searchField, 'Japan');
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Japan'), findsWidgets);

      // Tap on Japan item in the list (the last match, since the first match is the search text field itself)
      await tester.tap(find.text('Japan').last);
      await tester.pump(const Duration(milliseconds: 300));

      expect(CurrencyService.countryCode, 'JP');
      expect(CurrencyService.currencyCode, 'JPY');
      expect(CurrencyService.symbol, '¥');
    });

    testWidgets('Step 1 auto-log preview adapts to selected country',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // Select USA
      final usaChip = find.text('USA');
      await tester.tap(usaChip);
      await tester.pump(const Duration(milliseconds: 300));

      // Tap Continue to go to Step 1
      final continueBtn = find.text('Continue').first;
      await tester.tap(continueBtn);
      await tester.pump(const Duration(milliseconds: 600));

      // Step 1: "Your spending logs itself."
      expect(find.textContaining('Your spending'), findsOneWidget);
      expect(find.textContaining('logs itself'), findsOneWidget);

      // Should display USD formatted transaction alert
      expect(find.textContaining('Trader Joe\'s'), findsWidgets);
      expect(find.textContaining('\$'), findsWidgets);
    });

    testWidgets('Step 3 Pro Hub displays selected country currency symbol and CTA',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // Select UK (GB)
      final ukChip = find.text('UK');
      await tester.tap(ukChip);
      await tester.pump(const Duration(milliseconds: 300));

      // Advance through steps to Step 3
      // Step 0 -> Step 1
      await tester.tap(find.text('Continue').first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 600));

      // Step 1 -> Step 2
      await tester.tap(find.text('Continue').first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 600));

      // Step 2 -> Step 3
      await tester.tap(find.text('Continue').first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 600));

      // Step 3: Pro tools hub
      expect(find.textContaining('Every pro tool.'), findsOneWidget);
      expect(find.textContaining('£0 forever.'), findsOneWidget);

      // Zero pill should display £0 / forever
      expect(find.text('£0 / forever'), findsOneWidget);

      // CTA should be conversion button
      expect(find.text('Start tracking free'), findsOneWidget);
    });
  });
}
