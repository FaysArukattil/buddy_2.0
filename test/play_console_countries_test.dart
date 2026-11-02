// test/play_console_countries_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:buddy/data/countries_data.dart';
import 'package:buddy/parsing/parser_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final rulesFile = File('assets/parsing/bank_rules.json');
    final rulesJson = await rulesFile.readAsString();
    await ParserRegistry.instance.reloadFromRemoteConfig(rulesJson);
  });
  const playConsoleCountries = [
    'Albania',
    'Algeria',
    'Angola',
    'Antigua & Barbuda',
    'Argentina',
    'Armenia',
    'Aruba',
    'Australia',
    'Austria',
    'Azerbaijan',
    'Bahamas',
    'Bahrain',
    'Bangladesh',
    'Belarus',
    'Belgium',
    'Belize',
    'Benin',
    'Bermuda',
    'Bolivia',
    'Bosnia & Herzegovina',
    'Botswana',
    'Brazil',
    'British Virgin Islands',
    'Bulgaria',
    'Burkina Faso',
    'Cambodia',
    'Cameroon',
    'Canada',
    'Cape Verde',
    'Cayman Islands',
    'Chad',
    'Chile',
    'China',
    'Colombia',
    'Comoros',
    'Congo - Brazzaville',
    'Congo - Kinshasa',
    'Costa Rica',
    'Croatia',
    'Cuba',
    'Cyprus',
    'Czechia',
    'Côte d’Ivoire',
    'Denmark',
    'Djibouti',
    'Dominica',
    'Dominican Republic',
    'Ecuador',
    'Egypt',
    'El Salvador',
    'Eritrea',
    'Estonia',
    'Ethiopia',
    'Fiji',
    'Finland',
    'France',
    'Gabon',
    'Gambia',
    'Georgia',
    'Germany',
    'Ghana',
    'Gibraltar',
    'Greece',
    'Grenada',
    'Guatemala',
    'Guinea',
    'Guinea-Bissau',
    'Haiti',
    'Honduras',
    'Hong Kong',
    'Hungary',
    'Iceland',
    'India',
    'Indonesia',
    'Iran',
    'Iraq',
    'Ireland',
    'Israel',
    'Italy',
    'Jamaica',
    'Japan',
    'Jordan',
    'Kazakhstan',
    'Kenya',
    'Kuwait',
    'Kyrgyzstan',
    'Laos',
    'Latvia',
    'Lebanon',
    'Liberia',
    'Libya',
    'Liechtenstein',
    'Lithuania',
    'Luxembourg',
    'Macao',
    'Malaysia',
    'Maldives',
    'Mali',
    'Malta',
    'Mauritius',
    'Mexico',
    'Micronesia',
    'Moldova',
    'Monaco',
    'Mongolia',
    'Morocco',
    'Mozambique',
    'Myanmar (Burma)',
    'Namibia',
    'Nepal',
    'Netherlands',
    'New Zealand',
    'Nicaragua',
    'Niger',
    'Nigeria',
    'North Macedonia',
    'Norway',
    'Oman',
    'Pakistan',
    'Panama',
    'Papua New Guinea',
    'Paraguay',
    'Peru',
    'Philippines',
    'Poland',
    'Portugal',
    'Qatar',
    'Romania',
    'Russia',
    'Rwanda',
    'Samoa',
    'San Marino',
    'Saudi Arabia',
    'Senegal',
    'Serbia',
    'Seychelles',
    'Sierra Leone',
    'Singapore',
    'Slovakia',
    'Slovenia',
    'Solomon Islands',
    'Somalia',
    'South Africa',
    'South Korea',
    'Spain',
    'Sri Lanka',
    'St. Kitts & Nevis',
    'St. Lucia',
    'Sudan',
    'Suriname',
    'Sweden',
    'Switzerland',
    'Taiwan',
    'Tajikistan',
    'Tanzania',
    'Thailand',
    'Togo',
    'Tonga',
    'Trinidad & Tobago',
    'Tunisia',
    'Turkmenistan',
    'Turks & Caicos Islands',
    'Türkiye',
    'Uganda',
    'Ukraine',
    'United Arab Emirates',
    'United Kingdom',
    'United States',
    'Uruguay',
    'Uzbekistan',
    'Vanuatu',
    'Vatican City',
    'Venezuela',
    'Vietnam',
    'Yemen',
    'Zambia',
    'Zimbabwe',
    'Rest of World',
  ];

  group('Google Play Console All 178 Countries Verification', () {
    test('Every Play Console country is found in CountriesData', () {
      expect(playConsoleCountries.length, 178);

      for (final country in playConsoleCountries) {
        final matches = CountriesData.search(country);
        expect(
          matches.isNotEmpty,
          isTrue,
          reason: 'Country "$country" should be found in CountriesData',
        );
      }
    });

    test('All CountryEntries have valid flags, codes, and symbols', () {
      for (final entry in CountriesData.all) {
        expect(entry.countryCode.isNotEmpty, isTrue);
        expect(entry.name.isNotEmpty, isTrue);
        expect(entry.flag.isNotEmpty, isTrue);
        expect(entry.currencyCode.isNotEmpty, isTrue);
        expect(entry.currencySymbol.isNotEmpty, isTrue);
        expect(entry.localeCode.isNotEmpty, isTrue);

        // Ambiguous "Rs" symbol check: Pakistan must be ₨, not Rs
        if (entry.countryCode == 'PK') {
          expect(entry.currencySymbol, '₨');
        }
        // GCC currencies must use standard codes
        if (entry.countryCode == 'AE') {
          expect(entry.currencySymbol, 'AED');
        }
        if (entry.countryCode == 'SA') {
          expect(entry.currencySymbol, 'SAR');
        }
      }
    });

    test('ParserRegistry supports universal fallback for any country', () {
      // IN is handled by NotificationListener, all others supported
      expect(ParserRegistry.instance.supports('AE'), isTrue);
      expect(ParserRegistry.instance.supports('OTHER'), isTrue);
      expect(ParserRegistry.instance.supports('ARUBA_UNLISTED'), isTrue);
    });

    test('CountriesData.search aliases return expected country and rank it first', () {
      // Searching "usa" must return United States as #1
      final usaResults = CountriesData.search('usa');
      expect(usaResults, isNotEmpty);
      expect(usaResults.first.countryCode, 'US');
      expect(usaResults.first.name, 'United States');

      // Searching "uae" must return United Arab Emirates as #1
      final uaeResults = CountriesData.search('uae');
      expect(uaeResults, isNotEmpty);
      expect(uaeResults.first.countryCode, 'AE');

      // Searching "uk" must return United Kingdom as #1
      final ukResults = CountriesData.search('uk');
      expect(ukResults, isNotEmpty);
      expect(ukResults.first.countryCode, 'GB');

      // Searching "ksa" must return Saudi Arabia as #1
      final ksaResults = CountriesData.search('ksa');
      expect(ksaResults, isNotEmpty);
      expect(ksaResults.first.countryCode, 'SA');

      // Searching "america" must return United States as #1
      final americaResults = CountriesData.search('america');
      expect(americaResults, isNotEmpty);
      expect(americaResults.first.countryCode, 'US');

      // Searching "us" exact code ranks United States before Cyprus or Belarus
      final usResults = CountriesData.search('us');
      expect(usResults, isNotEmpty);
      expect(usResults.first.countryCode, 'US');
    });
  });
}
