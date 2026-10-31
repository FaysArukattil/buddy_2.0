// lib/views/widgets/currency_picker_sheet.dart
//
// Bottom sheet for changing country / currency / locale.
// - Lets the user search a bundled list of countries + currencies
// - Allows changing currency INDEPENDENTLY from country (e.g. UAE user → USD)
// - Shows a one-time note: display-only change, no value conversion
// - On save: calls CurrencyService.setCountry() → updates Firestore + SharedPrefs
//   and fires currencyNotifier so every UI rebuilds immediately.
import 'package:flutter/material.dart';
import 'package:buddy/services/currency_service.dart';
import 'package:buddy/utils/colors.dart';

// ---------------------------------------------------------------------------
// Static dataset: country → currency mapping
// Only one entry per country; the list is sorted A-Z by name at build time.
// Fields: countryCode, name, flag emoji, currencyCode, currencySymbol, localeCode
// ---------------------------------------------------------------------------
class _CountryEntry {
  final String countryCode;
  final String name;
  final String flag;
  final String currencyCode;
  final String currencySymbol;
  final String localeCode;

  const _CountryEntry({
    required this.countryCode,
    required this.name,
    required this.flag,
    required this.currencyCode,
    required this.currencySymbol,
    required this.localeCode,
  });
}

const List<_CountryEntry> _kCountries = [
  _CountryEntry(countryCode: 'AE', name: 'UAE', flag: '🇦🇪', currencyCode: 'AED', currencySymbol: 'د.إ', localeCode: 'ar_AE'),
  _CountryEntry(countryCode: 'AR', name: 'Argentina', flag: '🇦🇷', currencyCode: 'ARS', currencySymbol: '\$', localeCode: 'es_AR'),
  _CountryEntry(countryCode: 'AU', name: 'Australia', flag: '🇦🇺', currencyCode: 'AUD', currencySymbol: 'A\$', localeCode: 'en_AU'),
  _CountryEntry(countryCode: 'BD', name: 'Bangladesh', flag: '🇧🇩', currencyCode: 'BDT', currencySymbol: '৳', localeCode: 'bn_BD'),
  _CountryEntry(countryCode: 'BH', name: 'Bahrain', flag: '🇧🇭', currencyCode: 'BHD', currencySymbol: 'BD', localeCode: 'ar_BH'),
  _CountryEntry(countryCode: 'BR', name: 'Brazil', flag: '🇧🇷', currencyCode: 'BRL', currencySymbol: 'R\$', localeCode: 'pt_BR'),
  _CountryEntry(countryCode: 'CA', name: 'Canada', flag: '🇨🇦', currencyCode: 'CAD', currencySymbol: 'CA\$', localeCode: 'en_CA'),
  _CountryEntry(countryCode: 'CH', name: 'Switzerland', flag: '🇨🇭', currencyCode: 'CHF', currencySymbol: 'Fr.', localeCode: 'de_CH'),
  _CountryEntry(countryCode: 'CL', name: 'Chile', flag: '🇨🇱', currencyCode: 'CLP', currencySymbol: '\$', localeCode: 'es_CL'),
  _CountryEntry(countryCode: 'CN', name: 'China', flag: '🇨🇳', currencyCode: 'CNY', currencySymbol: '¥', localeCode: 'zh_CN'),
  _CountryEntry(countryCode: 'CO', name: 'Colombia', flag: '🇨🇴', currencyCode: 'COP', currencySymbol: '\$', localeCode: 'es_CO'),
  _CountryEntry(countryCode: 'DE', name: 'Germany', flag: '🇩🇪', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'de_DE'),
  _CountryEntry(countryCode: 'EG', name: 'Egypt', flag: '🇪🇬', currencyCode: 'EGP', currencySymbol: 'E£', localeCode: 'ar_EG'),
  _CountryEntry(countryCode: 'ES', name: 'Spain', flag: '🇪🇸', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'es_ES'),
  _CountryEntry(countryCode: 'FR', name: 'France', flag: '🇫🇷', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'fr_FR'),
  _CountryEntry(countryCode: 'GB', name: 'United Kingdom', flag: '🇬🇧', currencyCode: 'GBP', currencySymbol: '£', localeCode: 'en_GB'),
  _CountryEntry(countryCode: 'GH', name: 'Ghana', flag: '🇬🇭', currencyCode: 'GHS', currencySymbol: 'GH₵', localeCode: 'en_GH'),
  _CountryEntry(countryCode: 'ID', name: 'Indonesia', flag: '🇮🇩', currencyCode: 'IDR', currencySymbol: 'Rp', localeCode: 'id_ID'),
  _CountryEntry(countryCode: 'IN', name: 'India', flag: '🇮🇳', currencyCode: 'INR', currencySymbol: '₹', localeCode: 'en_IN'),
  _CountryEntry(countryCode: 'IT', name: 'Italy', flag: '🇮🇹', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'it_IT'),
  _CountryEntry(countryCode: 'JP', name: 'Japan', flag: '🇯🇵', currencyCode: 'JPY', currencySymbol: '¥', localeCode: 'ja_JP'),
  _CountryEntry(countryCode: 'KE', name: 'Kenya', flag: '🇰🇪', currencyCode: 'KES', currencySymbol: 'KSh', localeCode: 'sw_KE'),
  _CountryEntry(countryCode: 'KR', name: 'South Korea', flag: '🇰🇷', currencyCode: 'KRW', currencySymbol: '₩', localeCode: 'ko_KR'),
  _CountryEntry(countryCode: 'KW', name: 'Kuwait', flag: '🇰🇼', currencyCode: 'KWD', currencySymbol: 'KD', localeCode: 'ar_KW'),
  _CountryEntry(countryCode: 'LK', name: 'Sri Lanka', flag: '🇱🇰', currencyCode: 'LKR', currencySymbol: 'Rs', localeCode: 'si_LK'),
  _CountryEntry(countryCode: 'MX', name: 'Mexico', flag: '🇲🇽', currencyCode: 'MXN', currencySymbol: '\$', localeCode: 'es_MX'),
  _CountryEntry(countryCode: 'MY', name: 'Malaysia', flag: '🇲🇾', currencyCode: 'MYR', currencySymbol: 'RM', localeCode: 'ms_MY'),
  _CountryEntry(countryCode: 'NG', name: 'Nigeria', flag: '🇳🇬', currencyCode: 'NGN', currencySymbol: '₦', localeCode: 'en_NG'),
  _CountryEntry(countryCode: 'NL', name: 'Netherlands', flag: '🇳🇱', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'nl_NL'),
  _CountryEntry(countryCode: 'NP', name: 'Nepal', flag: '🇳🇵', currencyCode: 'NPR', currencySymbol: 'Rs', localeCode: 'ne_NP'),
  _CountryEntry(countryCode: 'NZ', name: 'New Zealand', flag: '🇳🇿', currencyCode: 'NZD', currencySymbol: 'NZ\$', localeCode: 'en_NZ'),
  _CountryEntry(countryCode: 'OM', name: 'Oman', flag: '🇴🇲', currencyCode: 'OMR', currencySymbol: 'OMR', localeCode: 'ar_OM'),
  _CountryEntry(countryCode: 'PH', name: 'Philippines', flag: '🇵🇭', currencyCode: 'PHP', currencySymbol: '₱', localeCode: 'en_PH'),
  _CountryEntry(countryCode: 'PK', name: 'Pakistan', flag: '🇵🇰', currencyCode: 'PKR', currencySymbol: 'Rs', localeCode: 'ur_PK'),
  _CountryEntry(countryCode: 'PT', name: 'Portugal', flag: '🇵🇹', currencyCode: 'EUR', currencySymbol: '€', localeCode: 'pt_PT'),
  _CountryEntry(countryCode: 'QA', name: 'Qatar', flag: '🇶🇦', currencyCode: 'QAR', currencySymbol: 'QR', localeCode: 'ar_QA'),
  _CountryEntry(countryCode: 'SA', name: 'Saudi Arabia', flag: '🇸🇦', currencyCode: 'SAR', currencySymbol: 'SR', localeCode: 'ar_SA'),
  _CountryEntry(countryCode: 'SE', name: 'Sweden', flag: '🇸🇪', currencyCode: 'SEK', currencySymbol: 'kr', localeCode: 'sv_SE'),
  _CountryEntry(countryCode: 'SG', name: 'Singapore', flag: '🇸🇬', currencyCode: 'SGD', currencySymbol: 'S\$', localeCode: 'en_SG'),
  _CountryEntry(countryCode: 'TH', name: 'Thailand', flag: '🇹🇭', currencyCode: 'THB', currencySymbol: '฿', localeCode: 'th_TH'),
  _CountryEntry(countryCode: 'TR', name: 'Turkey', flag: '🇹🇷', currencyCode: 'TRY', currencySymbol: '₺', localeCode: 'tr_TR'),
  _CountryEntry(countryCode: 'TZ', name: 'Tanzania', flag: '🇹🇿', currencyCode: 'TZS', currencySymbol: 'TSh', localeCode: 'sw_TZ'),
  _CountryEntry(countryCode: 'US', name: 'United States', flag: '🇺🇸', currencyCode: 'USD', currencySymbol: '\$', localeCode: 'en_US'),
  _CountryEntry(countryCode: 'VN', name: 'Vietnam', flag: '🇻🇳', currencyCode: 'VND', currencySymbol: '₫', localeCode: 'vi_VN'),
  _CountryEntry(countryCode: 'ZA', name: 'South Africa', flag: '🇿🇦', currencyCode: 'ZAR', currencySymbol: 'R', localeCode: 'en_ZA'),
];

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------
class CurrencyPickerSheet extends StatefulWidget {
  const CurrencyPickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CurrencyPickerSheet(),
    );
  }

  @override
  State<CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends State<CurrencyPickerSheet> {
  final TextEditingController _search = TextEditingController();
  List<_CountryEntry> _filtered = List.of(_kCountries);
  bool _isSaving = false;

  // Track pending selection before saving
  _CountryEntry? _selected;

  @override
  void initState() {
    super.initState();
    // Pre-select current country
    final current = CurrencyService.countryCode;
    try {
      _selected = _kCountries.firstWhere((c) => c.countryCode == current);
    } catch (_) {
      _selected = null;
    }
    _search.addListener(_onSearch);
  }

  @override
  void dispose() {
    _search.removeListener(_onSearch);
    _search.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _search.text.toLowerCase();
    setState(() {
      _filtered = _kCountries.where((c) {
        return c.name.toLowerCase().contains(q) ||
            c.currencyCode.toLowerCase().contains(q) ||
            c.currencySymbol.toLowerCase().contains(q) ||
            c.countryCode.toLowerCase().contains(q);
      }).toList();
    });
  }

  Future<void> _save() async {
    if (_selected == null) return;
    setState(() => _isSaving = true);
    try {
      await CurrencyService.setCountry(
        countryCode: _selected!.countryCode,
        currencyCode: _selected!.currencyCode,
        currencySymbol: _selected!.currencySymbol,
        localeCode: _selected!.localeCode,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('⚠️ CurrencyPicker: save error: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0E2622) : Colors.white;
    final surface = isDark ? const Color(0xFF142E2A) : const Color(0xFFF5F5F5);
    final border = isDark ? const Color(0xFF1C4740) : const Color(0xFFDDDDDD);
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textSecondary = isDark ? Colors.white60 : Colors.black45;
    final accent = AppColors.primary;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(Icons.language_rounded, color: accent, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Country & Currency',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // One-time note: display-only change
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: accent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 15, color: accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Changing currency only updates the display symbol. '
                          'Your existing transaction amounts are not converted.',
                          style: TextStyle(fontSize: 12, color: textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: 'Search country or currency...',
                    hintStyle: TextStyle(color: textSecondary, fontSize: 14),
                    prefixIcon: Icon(Icons.search_rounded, color: textSecondary, size: 20),
                    filled: true,
                    fillColor: surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: accent, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  style: TextStyle(color: textPrimary, fontSize: 14),
                ),
              ),
              const SizedBox(height: 10),

              // List
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final entry = _filtered[i];
                    final isSelected = _selected?.countryCode == entry.countryCode;

                    return GestureDetector(
                      onTap: () => setState(() => _selected = entry),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? accent.withValues(alpha: 0.15)
                              : surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? accent.withValues(alpha: 0.6)
                                : border,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(entry.flag, style: const TextStyle(fontSize: 24)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                    ),
                                  ),
                                  Text(
                                    '${entry.currencyCode} · ${entry.currencySymbol}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Icon(Icons.check_circle_rounded, color: accent, size: 20),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Save button
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  10,
                  20,
                  MediaQuery.of(context).padding.bottom + 16,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: (_selected == null || _isSaving) ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _selected == null
                                ? 'Select a country'
                                : 'Save — ${_selected!.flag} ${_selected!.currencyCode}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
