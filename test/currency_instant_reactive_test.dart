import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:buddy/services/currency_service.dart';
import 'package:buddy/utils/format_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CurrencyService.initialize();
  });

  tearDown(() async {
    // Reset to defaults
    await CurrencyService.setCountry(
      countryCode: CurrencyService.defaultCountryCode,
      currencyCode: CurrencyService.defaultCurrencyCode,
      currencySymbol: CurrencyService.defaultCurrencySymbol,
      localeCode: CurrencyService.defaultLocaleCode,
    );
  });

  group('Currency Numbers and Symbol Tests', () {
    test('Amounts always format with standard Western digits regardless of country', () async {
      // 1. UAE (Arabic locale ar_AE) - previously produced Arabic numerals or reversed RTL text
      await CurrencyService.setCountry(
        countryCode: 'AE',
        currencyCode: 'AED',
        currencySymbol: 'AED',
        localeCode: 'ar_AE',
      );
      expect(CurrencyService.formatFull(1250), 'AED1,250');
      expect(CurrencyService.formatFull(1250.50), 'AED1,250.50');
      expect(CurrencyService.formatCompact(15000), 'AED15K');
      expect(CurrencyService.formatCompact(1500000), 'AED1.5M');

      // 2. Bangladesh (Bengali locale bn_BD) - previously produced Bengali script digits ১২৩৪৫
      await CurrencyService.setCountry(
        countryCode: 'BD',
        currencyCode: 'BDT',
        currencySymbol: '৳',
        localeCode: 'bn_BD',
      );
      expect(CurrencyService.formatFull(1250), '৳1,250');
      expect(CurrencyService.formatFull(1250.75), '৳1,250.75');
      expect(CurrencyService.formatCompact(25000), '৳25K');

      // 3. Germany (de_DE) - previously used dot for thousands and comma for decimal
      await CurrencyService.setCountry(
        countryCode: 'DE',
        currencyCode: 'EUR',
        currencySymbol: '€',
        localeCode: 'de_DE',
      );
      expect(CurrencyService.formatFull(5400), '€5,400');
      expect(CurrencyService.formatFull(5400.25), '€5,400.25');

      // 4. Saudi Arabia (ar_SA)
      await CurrencyService.setCountry(
        countryCode: 'SA',
        currencyCode: 'SAR',
        currencySymbol: 'SAR',
        localeCode: 'ar_SA',
      );
      expect(CurrencyService.formatFull(99), 'SAR99');
      expect(CurrencyService.formatFull(99.99), 'SAR99.99');

      // 5. United States (USD)
      await CurrencyService.setCountry(
        countryCode: 'US',
        currencyCode: 'USD',
        currencySymbol: '\$',
        localeCode: 'en_US',
      );
      expect(CurrencyService.formatFull(1250), '\$1,250');
      expect(CurrencyService.formatFull(1250.50), '\$1,250.50');
      expect(CurrencyService.formatCompact(50000), '\$50K');

      // 6. Japan (JPY - Zero decimal currency)
      await CurrencyService.setCountry(
        countryCode: 'JP',
        currencyCode: 'JPY',
        currencySymbol: '¥',
        localeCode: 'ja_JP',
      );
      expect(CurrencyService.formatFull(3500), '¥3,500');
      expect(CurrencyService.formatFull(3500.8), '¥3,501');
      expect(CurrencyService.formatCompact(100000), '¥100K');

      // 7. India (INR)
      await CurrencyService.setCountry(
        countryCode: 'IN',
        currencyCode: 'INR',
        currencySymbol: '₹',
        localeCode: 'en_IN',
      );
      expect(CurrencyService.formatFull(123456), '₹1,23,456');
      expect(CurrencyService.formatCompact(150000), '₹1.5L');
      expect(CurrencyService.formatCompact(15000000), '₹1.5Cr');
    });

    test('FormatUtils delegates correctly with standard numbers and new symbols', () async {
      await CurrencyService.setCountry(
        countryCode: 'GB',
        currencyCode: 'GBP',
        currencySymbol: '£',
        localeCode: 'en_GB',
      );
      expect(FormatUtils.formatCurrency(850), '£850');
      expect(FormatUtils.formatCurrencyFull(850.50), '£850.50');
      expect(FormatUtils.formatCompactCurrency(20000), '£20K');
    });

    test('currencyNotifier fires immediately when setCountry is called', () async {
      int notifyCount = 0;
      void listener() {
        notifyCount++;
      }

      CurrencyService.currencyNotifier.addListener(listener);

      await CurrencyService.setCountry(
        countryCode: 'AE',
        currencyCode: 'AED',
        currencySymbol: 'AED',
        localeCode: 'ar_AE',
      );

      expect(notifyCount, 1);
      expect(CurrencyService.symbol, 'AED');

      await CurrencyService.setCountry(
        countryCode: 'FR',
        currencyCode: 'EUR',
        currencySymbol: '€',
        localeCode: 'fr_FR',
      );

      expect(notifyCount, 2);
      expect(CurrencyService.symbol, '€');

      CurrencyService.currencyNotifier.removeListener(listener);
    });
  });
}

