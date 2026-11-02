// lib/data/countries_data.dart
// Comprehensive dataset of world countries with ISO codes, flag emojis,
// currency codes, standard symbols, and default locales.
// Directly matches all 178 Google Play Console targeted countries/territories
// plus remaining global territories and "Other / Rest of World".

class CountryEntry {
  final String countryCode;
  final String name;
  final String flag;
  final String currencyCode;
  final String currencySymbol;
  final String localeCode;

  const CountryEntry({
    required this.countryCode,
    required this.name,
    required this.flag,
    required this.currencyCode,
    required this.currencySymbol,
    required this.localeCode,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CountryEntry &&
          runtimeType == other.runtimeType &&
          countryCode == other.countryCode;

  @override
  int get hashCode => countryCode.hashCode;
}

class CountriesData {
  CountriesData._();

  /// Top / popular countries surfaced as quick selection pills.
  static const List<String> popularCodes = [
    'IN', 'AE', 'US', 'GB', 'SA', 'CA', 'AU', 'SG', 'QA', 'OTHER',
  ];

  static List<CountryEntry> get popular =>
      popularCodes.map(findByCountryCode).toList();

  /// Default fallback entry (India for existing users).
  static const CountryEntry defaultCountry = CountryEntry(
    countryCode: 'IN',
    name: 'India',
    flag: '🇮🇳',
    currencyCode: 'INR',
    currencySymbol: '₹',
    localeCode: 'en_IN',
  );

  /// "Other / Rest of World" fallback for users whose country is not listed.
  static const CountryEntry otherCountry = CountryEntry(
    countryCode: 'OTHER',
    name: 'Other / Rest of World',
    flag: '🌐',
    currencyCode: 'USD',
    currencySymbol: '\$',
    localeCode: 'en_US',
  );

  /// Find country entry by 2-letter ISO country code.
  static CountryEntry findByCountryCode(String code) {
    final upper = code.trim().toUpperCase();
    if (upper == 'OTHER') return otherCountry;
    return all.firstWhere(
      (c) => c.countryCode == upper,
      orElse: () => defaultCountry,
    );
  }

  /// Search countries by name, code, currency code, or symbol.
  /// Handles both punctuation variations (& vs and, St. vs Saint, Czechia vs Czech Republic, etc.)
  static List<CountryEntry> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    final qNorm = q
        .replaceAll('&', 'and')
        .replaceAll('st.', 'saint')
        .replaceAll('turkey', 'türkiye');
    return all.where((c) {
      final nameLower = c.name.toLowerCase();
      final nameNorm = nameLower
          .replaceAll('&', 'and')
          .replaceAll('st.', 'saint')
          .replaceAll('turkey', 'türkiye');
      return nameLower.contains(q) ||
          nameNorm.contains(qNorm) ||
          c.countryCode.toLowerCase().contains(q) ||
          c.currencyCode.toLowerCase().contains(q) ||
          c.currencySymbol.toLowerCase().contains(q);
    }).toList();
  }

  /// All countries matching Google Play Console's 178 targeted locations
  /// plus global sovereign states and the Rest of World entry.
  static const List<CountryEntry> all = [
    CountryEntry(countryCode: 'AF', name: 'Afghanistan', flag: '🇦🇫', currencyCode: 'AFN', currencySymbol: '؋', localeCode: 'ps_AF'),
    CountryEntry(countryCode: 'AL', name: 'Albania', flag: '🇦🇱', currencyCode: 'ALL', currencySymbol: 'Lek', localeCode: 'sq_AL'),
    CountryEntry(countryCode: 'DZ', name: 'Algeria', flag: '🇩🇿', currencyCode: 'DZD', currencySymbol: 'DA', localeCode: 'ar_DZ'),
    CountryEntry(countryCode: 'AD', name: 'Andorra', flag: '🇦🇩', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'ca_AD'),
    CountryEntry(countryCode: 'AO', name: 'Angola', flag: '🇦🇴', currencyCode: 'AOA', currencySymbol: 'Kz', localeCode: 'pt_AO'),
    CountryEntry(countryCode: 'AG', name: 'Antigua & Barbuda', flag: '🇦🇬', currencyCode: 'XCD', currencySymbol: 'EC\$', localeCode: 'en_AG'),
    CountryEntry(countryCode: 'AR', name: 'Argentina', flag: '🇦🇷', currencyCode: 'ARS', currencySymbol: '\$', localeCode: 'es_AR'),
    CountryEntry(countryCode: 'AM', name: 'Armenia', flag: '🇦🇲', currencyCode: 'AMD', currencySymbol: '֏', localeCode: 'hy_AM'),
    CountryEntry(countryCode: 'AW', name: 'Aruba', flag: '🇦🇼', currencyCode: 'AWG', currencySymbol: 'Afl.', localeCode: 'nl_AW'),
    CountryEntry(countryCode: 'AU', name: 'Australia', flag: '🇦🇺', currencyCode: 'AUD', currencySymbol: 'A\$', localeCode: 'en_AU'),
    CountryEntry(countryCode: 'AT', name: 'Austria', flag: '🇦🇹', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'de_AT'),
    CountryEntry(countryCode: 'AZ', name: 'Azerbaijan', flag: '🇦🇿', currencyCode: 'AZN', currencySymbol: '₼', localeCode: 'az_AZ'),
    CountryEntry(countryCode: 'BS', name: 'Bahamas', flag: '🇧🇸', currencyCode: 'BSD', currencySymbol: 'B\$', localeCode: 'en_BS'),
    CountryEntry(countryCode: 'BH', name: 'Bahrain', flag: '🇧🇭', currencyCode: 'BHD', currencySymbol: 'BHD', localeCode: 'ar_BH'),
    CountryEntry(countryCode: 'BD', name: 'Bangladesh', flag: '🇧🇩', currencyCode: 'BDT', currencySymbol: '৳', localeCode: 'bn_BD'),
    CountryEntry(countryCode: 'BB', name: 'Barbados', flag: '🇧🇧', currencyCode: 'BBD', currencySymbol: 'Bds\$', localeCode: 'en_BB'),
    CountryEntry(countryCode: 'BY', name: 'Belarus', flag: '🇧🇾', currencyCode: 'BYN', currencySymbol: 'Br', localeCode: 'be_BY'),
    CountryEntry(countryCode: 'BE', name: 'Belgium', flag: '🇧🇪', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'nl_BE'),
    CountryEntry(countryCode: 'BZ', name: 'Belize', flag: '🇧🇿', currencyCode: 'BZD', currencySymbol: 'BZ\$', localeCode: 'en_BZ'),
    CountryEntry(countryCode: 'BJ', name: 'Benin', flag: '🇧🇯', currencyCode: 'XOF', currencySymbol: 'CFA', localeCode: 'fr_BJ'),
    CountryEntry(countryCode: 'BM', name: 'Bermuda', flag: '🇧🇲', currencyCode: 'BMD', currencySymbol: '\$', localeCode: 'en_BM'),
    CountryEntry(countryCode: 'BT', name: 'Bhutan', flag: '🇧🇹', currencyCode: 'BTN', currencySymbol: 'Nu.', localeCode: 'dz_BT'),
    CountryEntry(countryCode: 'BO', name: 'Bolivia', flag: '🇧🇴', currencyCode: 'BOB', currencySymbol: 'Bs.', localeCode: 'es_BO'),
    CountryEntry(countryCode: 'BA', name: 'Bosnia & Herzegovina', flag: '🇧🇦', currencyCode: 'BAM', currencySymbol: 'KM', localeCode: 'bs_BA'),
    CountryEntry(countryCode: 'BW', name: 'Botswana', flag: '🇧🇼', currencyCode: 'BWP', currencySymbol: 'P', localeCode: 'en_BW'),
    CountryEntry(countryCode: 'BR', name: 'Brazil', flag: '🇧🇷', currencyCode: 'BRL', currencySymbol: 'R\$', localeCode: 'pt_BR'),
    CountryEntry(countryCode: 'VG', name: 'British Virgin Islands', flag: '🇻🇬', currencyCode: 'USD', currencySymbol: '\$', localeCode: 'en_VG'),
    CountryEntry(countryCode: 'BN', name: 'Brunei', flag: '🇧🇳', currencyCode: 'BND', currencySymbol: 'B\$', localeCode: 'ms_BN'),
    CountryEntry(countryCode: 'BG', name: 'Bulgaria', flag: '🇧🇬', currencyCode: 'BGN', currencySymbol: 'лв', localeCode: 'bg_BG'),
    CountryEntry(countryCode: 'BF', name: 'Burkina Faso', flag: '🇧🇫', currencyCode: 'XOF', currencySymbol: 'CFA', localeCode: 'fr_BF'),
    CountryEntry(countryCode: 'BI', name: 'Burundi', flag: '🇧🇮', currencyCode: 'BIF', currencySymbol: 'FBu', localeCode: 'fr_BI'),
    CountryEntry(countryCode: 'CV', name: 'Cape Verde (Cabo Verde)', flag: '🇨🇻', currencyCode: 'CVE', currencySymbol: 'Esc', localeCode: 'pt_CV'),
    CountryEntry(countryCode: 'KH', name: 'Cambodia', flag: '🇰🇭', currencyCode: 'KHR', currencySymbol: '៛', localeCode: 'km_KH'),
    CountryEntry(countryCode: 'CM', name: 'Cameroon', flag: '🇨🇲', currencyCode: 'XAF', currencySymbol: 'FCFA', localeCode: 'fr_CM'),
    CountryEntry(countryCode: 'CA', name: 'Canada', flag: '🇨🇦', currencyCode: 'CAD', currencySymbol: 'CA\$', localeCode: 'en_CA'),
    CountryEntry(countryCode: 'KY', name: 'Cayman Islands', flag: '🇰🇾', currencyCode: 'KYD', currencySymbol: 'CI\$', localeCode: 'en_KY'),
    CountryEntry(countryCode: 'CF', name: 'Central African Republic', flag: '🇨🇫', currencyCode: 'XAF', currencySymbol: 'FCFA', localeCode: 'fr_CF'),
    CountryEntry(countryCode: 'TD', name: 'Chad', flag: '🇹🇩', currencyCode: 'XAF', currencySymbol: 'FCFA', localeCode: 'fr_TD'),
    CountryEntry(countryCode: 'CL', name: 'Chile', flag: '🇨🇱', currencyCode: 'CLP', currencySymbol: '\$', localeCode: 'es_CL'),
    CountryEntry(countryCode: 'CN', name: 'China', flag: '🇨🇳', currencyCode: 'CNY', currencySymbol: '¥', localeCode: 'zh_CN'),
    CountryEntry(countryCode: 'CO', name: 'Colombia', flag: '🇨🇴', currencyCode: 'COP', currencySymbol: '\$', localeCode: 'es_CO'),
    CountryEntry(countryCode: 'KM', name: 'Comoros', flag: '🇰🇲', currencyCode: 'KMF', currencySymbol: 'CF', localeCode: 'ar_KM'),
    CountryEntry(countryCode: 'CG', name: 'Congo - Brazzaville', flag: '🇨🇬', currencyCode: 'XAF', currencySymbol: 'FCFA', localeCode: 'fr_CG'),
    CountryEntry(countryCode: 'CD', name: 'Congo - Kinshasa (DR Congo)', flag: '🇨🇩', currencyCode: 'CDF', currencySymbol: 'FC', localeCode: 'fr_CD'),
    CountryEntry(countryCode: 'CR', name: 'Costa Rica', flag: '🇨🇷', currencyCode: 'CRC', currencySymbol: '₡', localeCode: 'es_CR'),
    CountryEntry(countryCode: 'CI', name: 'Côte d’Ivoire (Ivory Coast)', flag: '🇨🇮', currencyCode: 'XOF', currencySymbol: 'CFA', localeCode: 'fr_CI'),
    CountryEntry(countryCode: 'HR', name: 'Croatia', flag: '🇭🇷', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'hr_HR'),
    CountryEntry(countryCode: 'CU', name: 'Cuba', flag: '🇨🇺', currencyCode: 'CUP', currencySymbol: '\$', localeCode: 'es_CU'),
    CountryEntry(countryCode: 'CY', name: 'Cyprus', flag: '🇨🇾', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'el_CY'),
    CountryEntry(countryCode: 'CZ', name: 'Czechia (Czech Republic)', flag: '🇨🇿', currencyCode: 'CZK', currencySymbol: 'Kč', localeCode: 'cs_CZ'),
    CountryEntry(countryCode: 'DK', name: 'Denmark', flag: '🇩🇰', currencyCode: 'DKK', currencySymbol: 'kr.', localeCode: 'da_DK'),
    CountryEntry(countryCode: 'DJ', name: 'Djibouti', flag: '🇩🇯', currencyCode: 'DJF', currencySymbol: 'Fdj', localeCode: 'fr_DJ'),
    CountryEntry(countryCode: 'DM', name: 'Dominica', flag: '🇩🇲', currencyCode: 'XCD', currencySymbol: 'EC\$', localeCode: 'en_DM'),
    CountryEntry(countryCode: 'DO', name: 'Dominican Republic', flag: '🇩🇴', currencyCode: 'DOP', currencySymbol: 'RD\$', localeCode: 'es_DO'),
    CountryEntry(countryCode: 'EC', name: 'Ecuador', flag: '🇪🇨', currencyCode: 'USD', currencySymbol: '\$', localeCode: 'es_EC'),
    CountryEntry(countryCode: 'EG', name: 'Egypt', flag: '🇪🇬', currencyCode: 'EGP', currencySymbol: 'E£', localeCode: 'ar_EG'),
    CountryEntry(countryCode: 'SV', name: 'El Salvador', flag: '🇸🇻', currencyCode: 'USD', currencySymbol: '\$', localeCode: 'es_SV'),
    CountryEntry(countryCode: 'GQ', name: 'Equatorial Guinea', flag: '🇬🇶', currencyCode: 'XAF', currencySymbol: 'FCFA', localeCode: 'es_GQ'),
    CountryEntry(countryCode: 'ER', name: 'Eritrea', flag: '🇪🇷', currencyCode: 'ERN', currencySymbol: 'Nfk', localeCode: 'ti_ER'),
    CountryEntry(countryCode: 'EE', name: 'Estonia', flag: '🇪🇪', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'et_EE'),
    CountryEntry(countryCode: 'SZ', name: 'Eswatini', flag: '🇸🇿', currencyCode: 'SZL', currencySymbol: 'E', localeCode: 'en_SZ'),
    CountryEntry(countryCode: 'ET', name: 'Ethiopia', flag: '🇪🇹', currencyCode: 'ETB', currencySymbol: 'Br', localeCode: 'am_ET'),
    CountryEntry(countryCode: 'FJ', name: 'Fiji', flag: '🇫🇯', currencyCode: 'FJD', currencySymbol: 'FJ\$', localeCode: 'en_FJ'),
    CountryEntry(countryCode: 'FI', name: 'Finland', flag: '🇫🇮', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'fi_FI'),
    CountryEntry(countryCode: 'FR', name: 'France', flag: '🇫🇷', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'fr_FR'),
    CountryEntry(countryCode: 'GA', name: 'Gabon', flag: '🇬🇦', currencyCode: 'XAF', currencySymbol: 'FCFA', localeCode: 'fr_GA'),
    CountryEntry(countryCode: 'GM', name: 'Gambia', flag: '🇬🇲', currencyCode: 'GMD', currencySymbol: 'D', localeCode: 'en_GM'),
    CountryEntry(countryCode: 'GE', name: 'Georgia', flag: '🇬🇪', currencyCode: 'GEL', currencySymbol: '₾', localeCode: 'ka_GE'),
    CountryEntry(countryCode: 'DE', name: 'Germany', flag: '🇩🇪', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'de_DE'),
    CountryEntry(countryCode: 'GH', name: 'Ghana', flag: '🇬🇭', currencyCode: 'GHS', currencySymbol: 'GH₵', localeCode: 'en_GH'),
    CountryEntry(countryCode: 'GI', name: 'Gibraltar', flag: '🇬🇮', currencyCode: 'GIP', currencySymbol: '£', localeCode: 'en_GI'),
    CountryEntry(countryCode: 'GR', name: 'Greece', flag: '🇬🇷', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'el_GR'),
    CountryEntry(countryCode: 'GD', name: 'Grenada', flag: '🇬🇩', currencyCode: 'XCD', currencySymbol: 'EC\$', localeCode: 'en_GD'),
    CountryEntry(countryCode: 'GT', name: 'Guatemala', flag: '🇬🇹', currencyCode: 'GTQ', currencySymbol: 'Q', localeCode: 'es_GT'),
    CountryEntry(countryCode: 'GN', name: 'Guinea', flag: '🇬🇳', currencyCode: 'GNF', currencySymbol: 'FG', localeCode: 'fr_GN'),
    CountryEntry(countryCode: 'GW', name: 'Guinea-Bissau', flag: '🇬🇼', currencyCode: 'XOF', currencySymbol: 'CFA', localeCode: 'pt_GW'),
    CountryEntry(countryCode: 'GY', name: 'Guyana', flag: '🇬🇾', currencyCode: 'GYD', currencySymbol: 'G\$', localeCode: 'en_GY'),
    CountryEntry(countryCode: 'HT', name: 'Haiti', flag: '🇭🇹', currencyCode: 'HTG', currencySymbol: 'G', localeCode: 'fr_HT'),
    CountryEntry(countryCode: 'HN', name: 'Honduras', flag: '🇭🇳', currencyCode: 'HNL', currencySymbol: 'L', localeCode: 'es_HN'),
    CountryEntry(countryCode: 'HK', name: 'Hong Kong', flag: '🇭🇰', currencyCode: 'HKD', currencySymbol: 'HK\$', localeCode: 'zh_HK'),
    CountryEntry(countryCode: 'HU', name: 'Hungary', flag: '🇭🇺', currencyCode: 'HUF', currencySymbol: 'Ft', localeCode: 'hu_HU'),
    CountryEntry(countryCode: 'IS', name: 'Iceland', flag: '🇮🇸', currencyCode: 'ISK', currencySymbol: 'kr', localeCode: 'is_IS'),
    CountryEntry(countryCode: 'IN', name: 'India', flag: '🇮🇳', currencyCode: 'INR', currencySymbol: '₹', localeCode: 'en_IN'),
    CountryEntry(countryCode: 'ID', name: 'Indonesia', flag: '🇮🇩', currencyCode: 'IDR', currencySymbol: 'Rp', localeCode: 'id_ID'),
    CountryEntry(countryCode: 'IR', name: 'Iran', flag: '🇮🇷', currencyCode: 'IRR', currencySymbol: '﷼', localeCode: 'fa_IR'),
    CountryEntry(countryCode: 'IQ', name: 'Iraq', flag: '🇮🇶', currencyCode: 'IQD', currencySymbol: 'ID', localeCode: 'ar_IQ'),
    CountryEntry(countryCode: 'IE', name: 'Ireland', flag: '🇮🇪', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'en_IE'),
    CountryEntry(countryCode: 'IL', name: 'Israel', flag: '🇮🇱', currencyCode: 'ILS', currencySymbol: '₪', localeCode: 'he_IL'),
    CountryEntry(countryCode: 'IT', name: 'Italy', flag: '🇮🇹', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'it_IT'),
    CountryEntry(countryCode: 'JM', name: 'Jamaica', flag: '🇯🇲', currencyCode: 'JMD', currencySymbol: 'J\$', localeCode: 'en_JM'),
    CountryEntry(countryCode: 'JP', name: 'Japan', flag: '🇯🇵', currencyCode: 'JPY', currencySymbol: '¥', localeCode: 'ja_JP'),
    CountryEntry(countryCode: 'JO', name: 'Jordan', flag: '🇯🇴', currencyCode: 'JOD', currencySymbol: 'JD', localeCode: 'ar_JO'),
    CountryEntry(countryCode: 'KZ', name: 'Kazakhstan', flag: '🇰🇿', currencyCode: 'KZT', currencySymbol: '₸', localeCode: 'kk_KZ'),
    CountryEntry(countryCode: 'KE', name: 'Kenya', flag: '🇰🇪', currencyCode: 'KES', currencySymbol: 'KSh', localeCode: 'sw_KE'),
    CountryEntry(countryCode: 'KI', name: 'Kiribati', flag: '🇰🇮', currencyCode: 'AUD', currencySymbol: 'A\$', localeCode: 'en_KI'),
    CountryEntry(countryCode: 'XK', name: 'Kosovo', flag: '🇽🇰', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'sq_XK'),
    CountryEntry(countryCode: 'KW', name: 'Kuwait', flag: '🇰🇼', currencyCode: 'KWD', currencySymbol: 'KWD', localeCode: 'ar_KW'),
    CountryEntry(countryCode: 'KG', name: 'Kyrgyzstan', flag: '🇰🇬', currencyCode: 'KGS', currencySymbol: 'сом', localeCode: 'ky_KG'),
    CountryEntry(countryCode: 'LA', name: 'Laos', flag: '🇱🇦', currencyCode: 'LAK', currencySymbol: '₭', localeCode: 'lo_LA'),
    CountryEntry(countryCode: 'LV', name: 'Latvia', flag: '🇱🇻', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'lv_LV'),
    CountryEntry(countryCode: 'LB', name: 'Lebanon', flag: '🇱🇧', currencyCode: 'LBP', currencySymbol: 'L£', localeCode: 'ar_LB'),
    CountryEntry(countryCode: 'LS', name: 'Lesotho', flag: '🇱🇸', currencyCode: 'LSL', currencySymbol: 'M', localeCode: 'en_LS'),
    CountryEntry(countryCode: 'LR', name: 'Liberia', flag: '🇱🇷', currencyCode: 'LRD', currencySymbol: 'L\$', localeCode: 'en_LR'),
    CountryEntry(countryCode: 'LY', name: 'Libya', flag: '🇱🇾', currencyCode: 'LYD', currencySymbol: 'LD', localeCode: 'ar_LY'),
    CountryEntry(countryCode: 'LI', name: 'Liechtenstein', flag: '🇱🇮', currencyCode: 'CHF', currencySymbol: 'CHF', localeCode: 'de_LI'),
    CountryEntry(countryCode: 'LT', name: 'Lithuania', flag: '🇱🇹', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'lt_LT'),
    CountryEntry(countryCode: 'LU', name: 'Luxembourg', flag: '🇱🇺', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'fr_LU'),
    CountryEntry(countryCode: 'MO', name: 'Macao', flag: '🇲🇴', currencyCode: 'MOP', currencySymbol: 'MOP\$', localeCode: 'zh_MO'),
    CountryEntry(countryCode: 'MG', name: 'Madagascar', flag: '🇲🇬', currencyCode: 'MGA', currencySymbol: 'Ar', localeCode: 'mg_MG'),
    CountryEntry(countryCode: 'MW', name: 'Malawi', flag: '🇲🇼', currencyCode: 'MWK', currencySymbol: 'MK', localeCode: 'en_MW'),
    CountryEntry(countryCode: 'MY', name: 'Malaysia', flag: '🇲🇾', currencyCode: 'MYR', currencySymbol: 'RM', localeCode: 'ms_MY'),
    CountryEntry(countryCode: 'MV', name: 'Maldives', flag: '🇲🇻', currencyCode: 'MVR', currencySymbol: 'Rf', localeCode: 'dv_MV'),
    CountryEntry(countryCode: 'ML', name: 'Mali', flag: '🇲🇱', currencyCode: 'XOF', currencySymbol: 'CFA', localeCode: 'fr_ML'),
    CountryEntry(countryCode: 'MT', name: 'Malta', flag: '🇲🇹', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'mt_MT'),
    CountryEntry(countryCode: 'MH', name: 'Marshall Islands', flag: '🇲🇭', currencyCode: 'USD', currencySymbol: '\$', localeCode: 'en_MH'),
    CountryEntry(countryCode: 'MR', name: 'Mauritania', flag: '🇲🇷', currencyCode: 'MRU', currencySymbol: 'UM', localeCode: 'ar_MR'),
    CountryEntry(countryCode: 'MU', name: 'Mauritius', flag: '🇲🇺', currencyCode: 'MUR', currencySymbol: 'Rs.', localeCode: 'en_MU'),
    CountryEntry(countryCode: 'MX', name: 'Mexico', flag: '🇲🇽', currencyCode: 'MXN', currencySymbol: 'MX\$', localeCode: 'es_MX'),
    CountryEntry(countryCode: 'FM', name: 'Micronesia', flag: '🇫🇲', currencyCode: 'USD', currencySymbol: '\$', localeCode: 'en_FM'),
    CountryEntry(countryCode: 'MD', name: 'Moldova', flag: '🇲🇩', currencyCode: 'MDL', currencySymbol: 'L', localeCode: 'ro_MD'),
    CountryEntry(countryCode: 'MC', name: 'Monaco', flag: '🇲🇨', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'fr_MC'),
    CountryEntry(countryCode: 'MN', name: 'Mongolia', flag: '🇲🇳', currencyCode: 'MNT', currencySymbol: '₮', localeCode: 'mn_MN'),
    CountryEntry(countryCode: 'ME', name: 'Montenegro', flag: '🇲🇪', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'sr_ME'),
    CountryEntry(countryCode: 'MA', name: 'Morocco', flag: '🇲🇦', currencyCode: 'MAD', currencySymbol: 'DH', localeCode: 'ar_MA'),
    CountryEntry(countryCode: 'MZ', name: 'Mozambique', flag: '🇲🇿', currencyCode: 'MZN', currencySymbol: 'MT', localeCode: 'pt_MZ'),
    CountryEntry(countryCode: 'MM', name: 'Myanmar (Burma)', flag: '🇲🇲', currencyCode: 'MMK', currencySymbol: 'K', localeCode: 'my_MM'),
    CountryEntry(countryCode: 'NA', name: 'Namibia', flag: '🇳🇦', currencyCode: 'NAD', currencySymbol: 'N\$', localeCode: 'en_NA'),
    CountryEntry(countryCode: 'NR', name: 'Nauru', flag: '🇳🇷', currencyCode: 'AUD', currencySymbol: 'A\$', localeCode: 'en_NR'),
    CountryEntry(countryCode: 'NP', name: 'Nepal', flag: '🇳🇵', currencyCode: 'NPR', currencySymbol: 'Rs.', localeCode: 'ne_NP'),
    CountryEntry(countryCode: 'NL', name: 'Netherlands', flag: '🇳🇱', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'nl_NL'),
    CountryEntry(countryCode: 'NZ', name: 'New Zealand', flag: '🇳🇿', currencyCode: 'NZD', currencySymbol: 'NZ\$', localeCode: 'en_NZ'),
    CountryEntry(countryCode: 'NI', name: 'Nicaragua', flag: '🇳🇮', currencyCode: 'NIO', currencySymbol: 'C\$', localeCode: 'es_NI'),
    CountryEntry(countryCode: 'NE', name: 'Niger', flag: '🇳🇪', currencyCode: 'XOF', currencySymbol: 'CFA', localeCode: 'fr_NE'),
    CountryEntry(countryCode: 'NG', name: 'Nigeria', flag: '🇳🇬', currencyCode: 'NGN', currencySymbol: '₦', localeCode: 'en_NG'),
    CountryEntry(countryCode: 'MK', name: 'North Macedonia', flag: '🇲🇰', currencyCode: 'MKD', currencySymbol: 'ден', localeCode: 'mk_MK'),
    CountryEntry(countryCode: 'NO', name: 'Norway', flag: '🇳🇴', currencyCode: 'NOK', currencySymbol: 'kr', localeCode: 'nb_NO'),
    CountryEntry(countryCode: 'OM', name: 'Oman', flag: '🇴🇲', currencyCode: 'OMR', currencySymbol: 'OMR', localeCode: 'ar_OM'),
    CountryEntry(countryCode: 'PK', name: 'Pakistan', flag: '🇵🇰', currencyCode: 'PKR', currencySymbol: '₨', localeCode: 'ur_PK'),
    CountryEntry(countryCode: 'PW', name: 'Palau', flag: '🇵🇼', currencyCode: 'USD', currencySymbol: '\$', localeCode: 'en_PW'),
    CountryEntry(countryCode: 'PS', name: 'Palestine', flag: '🇵🇸', currencyCode: 'ILS', currencySymbol: '₪', localeCode: 'ar_PS'),
    CountryEntry(countryCode: 'PA', name: 'Panama', flag: '🇵🇦', currencyCode: 'USD', currencySymbol: '\$', localeCode: 'es_PA'),
    CountryEntry(countryCode: 'PG', name: 'Papua New Guinea', flag: '🇵🇬', currencyCode: 'PGK', currencySymbol: 'K', localeCode: 'en_PG'),
    CountryEntry(countryCode: 'PY', name: 'Paraguay', flag: '🇵🇾', currencyCode: 'PYG', currencySymbol: '₲', localeCode: 'es_PY'),
    CountryEntry(countryCode: 'PE', name: 'Peru', flag: '🇵🇪', currencyCode: 'PEN', currencySymbol: 'S/', localeCode: 'es_PE'),
    CountryEntry(countryCode: 'PH', name: 'Philippines', flag: '🇵🇭', currencyCode: 'PHP', currencySymbol: '₱', localeCode: 'en_PH'),
    CountryEntry(countryCode: 'PL', name: 'Poland', flag: '🇵🇱', currencyCode: 'PLN', currencySymbol: 'zł', localeCode: 'pl_PL'),
    CountryEntry(countryCode: 'PT', name: 'Portugal', flag: '🇵🇹', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'pt_PT'),
    CountryEntry(countryCode: 'PR', name: 'Puerto Rico', flag: '🇵🇷', currencyCode: 'USD', currencySymbol: '\$', localeCode: 'es_PR'),
    CountryEntry(countryCode: 'QA', name: 'Qatar', flag: '🇶🇦', currencyCode: 'QAR', currencySymbol: 'QAR', localeCode: 'ar_QA'),
    CountryEntry(countryCode: 'RO', name: 'Romania', flag: '🇷🇴', currencyCode: 'RON', currencySymbol: 'lei', localeCode: 'ro_RO'),
    CountryEntry(countryCode: 'RU', name: 'Russia', flag: '🇷🇺', currencyCode: 'RUB', currencySymbol: '₽', localeCode: 'ru_RU'),
    CountryEntry(countryCode: 'RW', name: 'Rwanda', flag: '🇷🇼', currencyCode: 'RWF', currencySymbol: 'RF', localeCode: 'rw_RW'),
    CountryEntry(countryCode: 'KN', name: 'St. Kitts & Nevis', flag: '🇰🇳', currencyCode: 'XCD', currencySymbol: 'EC\$', localeCode: 'en_KN'),
    CountryEntry(countryCode: 'LC', name: 'St. Lucia', flag: '🇱🇨', currencyCode: 'XCD', currencySymbol: 'EC\$', localeCode: 'en_LC'),
    CountryEntry(countryCode: 'VC', name: 'St. Vincent & Grenadines', flag: '🇻🇨', currencyCode: 'XCD', currencySymbol: 'EC\$', localeCode: 'en_VC'),
    CountryEntry(countryCode: 'WS', name: 'Samoa', flag: '🇼🇸', currencyCode: 'WST', currencySymbol: 'WS\$', localeCode: 'sm_WS'),
    CountryEntry(countryCode: 'SM', name: 'San Marino', flag: '🇸🇲', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'it_SM'),
    CountryEntry(countryCode: 'ST', name: 'Sao Tome and Principe', flag: '🇸🇹', currencyCode: 'STN', currencySymbol: 'Db', localeCode: 'pt_ST'),
    CountryEntry(countryCode: 'SA', name: 'Saudi Arabia', flag: '🇸🇦', currencyCode: 'SAR', currencySymbol: 'SAR', localeCode: 'ar_SA'),
    CountryEntry(countryCode: 'SN', name: 'Senegal', flag: '🇸🇳', currencyCode: 'XOF', currencySymbol: 'CFA', localeCode: 'fr_SN'),
    CountryEntry(countryCode: 'RS', name: 'Serbia', flag: '🇷🇸', currencyCode: 'RSD', currencySymbol: 'din.', localeCode: 'sr_RS'),
    CountryEntry(countryCode: 'SC', name: 'Seychelles', flag: '🇸🇨', currencyCode: 'SCR', currencySymbol: 'SR', localeCode: 'en_SC'),
    CountryEntry(countryCode: 'SL', name: 'Sierra Leone', flag: '🇸🇱', currencyCode: 'SLE', currencySymbol: 'Le', localeCode: 'en_SL'),
    CountryEntry(countryCode: 'SG', name: 'Singapore', flag: '🇸🇬', currencyCode: 'SGD', currencySymbol: 'S\$', localeCode: 'en_SG'),
    CountryEntry(countryCode: 'SK', name: 'Slovakia', flag: '🇸🇰', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'sk_SK'),
    CountryEntry(countryCode: 'SI', name: 'Slovenia', flag: '🇸🇮', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'sl_SI'),
    CountryEntry(countryCode: 'SB', name: 'Solomon Islands', flag: '🇸🇧', currencyCode: 'SBD', currencySymbol: 'SI\$', localeCode: 'en_SB'),
    CountryEntry(countryCode: 'SO', name: 'Somalia', flag: '🇸🇴', currencyCode: 'SOS', currencySymbol: 'Ssh', localeCode: 'so_SO'),
    CountryEntry(countryCode: 'ZA', name: 'South Africa', flag: '🇿🇦', currencyCode: 'ZAR', currencySymbol: 'R', localeCode: 'en_ZA'),
    CountryEntry(countryCode: 'KR', name: 'South Korea', flag: '🇰🇷', currencyCode: 'KRW', currencySymbol: '₩', localeCode: 'ko_KR'),
    CountryEntry(countryCode: 'SS', name: 'South Sudan', flag: '🇸🇸', currencyCode: 'SSP', currencySymbol: '£', localeCode: 'en_SS'),
    CountryEntry(countryCode: 'ES', name: 'Spain', flag: '🇪🇸', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'es_ES'),
    CountryEntry(countryCode: 'LK', name: 'Sri Lanka', flag: '🇱🇰', currencyCode: 'LKR', currencySymbol: 'Rs.', localeCode: 'si_LK'),
    CountryEntry(countryCode: 'SD', name: 'Sudan', flag: '🇸🇩', currencyCode: 'SDG', currencySymbol: 'SDG', localeCode: 'ar_SD'),
    CountryEntry(countryCode: 'SR', name: 'Suriname', flag: '🇸🇷', currencyCode: 'SRD', currencySymbol: '\$', localeCode: 'nl_SR'),
    CountryEntry(countryCode: 'SE', name: 'Sweden', flag: '🇸🇪', currencyCode: 'SEK', currencySymbol: 'kr', localeCode: 'sv_SE'),
    CountryEntry(countryCode: 'CH', name: 'Switzerland', flag: '🇨🇭', currencyCode: 'CHF', currencySymbol: 'CHF', localeCode: 'de_CH'),
    CountryEntry(countryCode: 'SY', name: 'Syria', flag: '🇸🇾', currencyCode: 'SYP', currencySymbol: '£S', localeCode: 'ar_SY'),
    CountryEntry(countryCode: 'TW', name: 'Taiwan', flag: '🇹🇼', currencyCode: 'TWD', currencySymbol: 'NT\$', localeCode: 'zh_TW'),
    CountryEntry(countryCode: 'TJ', name: 'Tajikistan', flag: '🇹🇯', currencyCode: 'TJS', currencySymbol: 'ЅМ', localeCode: 'tg_TJ'),
    CountryEntry(countryCode: 'TZ', name: 'Tanzania', flag: '🇹🇿', currencyCode: 'TZS', currencySymbol: 'TSh', localeCode: 'sw_TZ'),
    CountryEntry(countryCode: 'TH', name: 'Thailand', flag: '🇹🇭', currencyCode: 'THB', currencySymbol: '฿', localeCode: 'th_TH'),
    CountryEntry(countryCode: 'TL', name: 'Timor-Leste', flag: '🇹🇱', currencyCode: 'USD', currencySymbol: '\$', localeCode: 'pt_TL'),
    CountryEntry(countryCode: 'TG', name: 'Togo', flag: '🇹🇬', currencyCode: 'XOF', currencySymbol: 'CFA', localeCode: 'fr_TG'),
    CountryEntry(countryCode: 'TO', name: 'Tonga', flag: '🇹🇴', currencyCode: 'TOP', currencySymbol: 'T\$', localeCode: 'to_TO'),
    CountryEntry(countryCode: 'TT', name: 'Trinidad & Tobago', flag: '🇹🇹', currencyCode: 'TTD', currencySymbol: 'TT\$', localeCode: 'en_TT'),
    CountryEntry(countryCode: 'TN', name: 'Tunisia', flag: '🇹🇳', currencyCode: 'TND', currencySymbol: 'DT', localeCode: 'ar_TN'),
    CountryEntry(countryCode: 'TR', name: 'Türkiye (Turkey)', flag: '🇹🇷', currencyCode: 'TRY', currencySymbol: '₺', localeCode: 'tr_TR'),
    CountryEntry(countryCode: 'TM', name: 'Turkmenistan', flag: '🇹🇲', currencyCode: 'TMT', currencySymbol: 'm', localeCode: 'tk_TM'),
    CountryEntry(countryCode: 'TC', name: 'Turks & Caicos Islands', flag: '🇹🇨', currencyCode: 'USD', currencySymbol: '\$', localeCode: 'en_TC'),
    CountryEntry(countryCode: 'TV', name: 'Tuvalu', flag: '🇹🇻', currencyCode: 'AUD', currencySymbol: 'A\$', localeCode: 'en_TV'),
    CountryEntry(countryCode: 'UG', name: 'Uganda', flag: 'UGX', currencyCode: 'UGX', currencySymbol: 'USh', localeCode: 'sw_UG'),
    CountryEntry(countryCode: 'UA', name: 'Ukraine', flag: '🇺🇦', currencyCode: 'UAH', currencySymbol: '₴', localeCode: 'uk_UA'),
    CountryEntry(countryCode: 'AE', name: 'United Arab Emirates', flag: '🇦🇪', currencyCode: 'AED', currencySymbol: 'AED', localeCode: 'ar_AE'),
    CountryEntry(countryCode: 'GB', name: 'United Kingdom', flag: '🇬🇧', currencyCode: 'GBP', currencySymbol: '£', localeCode: 'en_GB'),
    CountryEntry(countryCode: 'US', name: 'United States', flag: '🇺🇸', currencyCode: 'USD', currencySymbol: '\$', localeCode: 'en_US'),
    CountryEntry(countryCode: 'UY', name: 'Uruguay', flag: '🇺🇾', currencyCode: 'UYU', currencySymbol: '\$U', localeCode: 'es_UY'),
    CountryEntry(countryCode: 'UZ', name: 'Uzbekistan', flag: '🇺🇿', currencyCode: 'UZS', currencySymbol: 'soʻm', localeCode: 'uz_UZ'),
    CountryEntry(countryCode: 'VU', name: 'Vanuatu', flag: '🇻🇺', currencyCode: 'VUV', currencySymbol: 'VT', localeCode: 'bi_VU'),
    CountryEntry(countryCode: 'VA', name: 'Vatican City', flag: '🇻🇦', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'it_VA'),
    CountryEntry(countryCode: 'VE', name: 'Venezuela', flag: '🇻🇪', currencyCode: 'VES', currencySymbol: 'Bs.', localeCode: 'es_VE'),
    CountryEntry(countryCode: 'VN', name: 'Vietnam', flag: '🇻🇳', currencyCode: 'VND', currencySymbol: '₫', localeCode: 'vi_VN'),
    CountryEntry(countryCode: 'YE', name: 'Yemen', flag: '🇾🇪', currencyCode: 'YER', currencySymbol: '﷼', localeCode: 'ar_YE'),
    CountryEntry(countryCode: 'ZM', name: 'Zambia', flag: '🇿🇲', currencyCode: 'ZMW', currencySymbol: 'ZK', localeCode: 'en_ZM'),
    CountryEntry(countryCode: 'ZW', name: 'Zimbabwe', flag: '🇿🇼', currencyCode: 'ZWL', currencySymbol: 'Z\$', localeCode: 'en_ZW'),
    CountryEntry(countryCode: 'OTHER', name: 'Other / Rest of World', flag: '🌐', currencyCode: 'USD', currencySymbol: '\$', localeCode: 'en_US'),
  ];
}
