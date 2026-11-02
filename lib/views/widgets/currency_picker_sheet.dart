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
import 'package:buddy/data/countries_data.dart';

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------
class CurrencyPickerSheet extends StatefulWidget {
  final bool isExistingUserPrompt;

  const CurrencyPickerSheet({
    super.key,
    this.isExistingUserPrompt = false,
  });

  static Future<void> show(
    BuildContext context, {
    bool isExistingUserPrompt = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CurrencyPickerSheet(
        isExistingUserPrompt: isExistingUserPrompt,
      ),
    );
  }

  @override
  State<CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends State<CurrencyPickerSheet> {
  final TextEditingController _search = TextEditingController();
  List<CountryEntry> _filtered = List.of(CountriesData.all);
  bool _isSaving = false;

  // Track pending selection before saving
  CountryEntry? _selected;

  @override
  void initState() {
    super.initState();
    // Pre-select current country
    final current = CurrencyService.countryCode;
    _selected = CountriesData.findByCountryCode(current);
    _search.addListener(_onSearch);
  }

  @override
  void dispose() {
    _search.removeListener(_onSearch);
    _search.dispose();
    super.dispose();
  }

  void _onSearch() {
    setState(() {
      _filtered = CountriesData.search(_search.text);
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
                    Icon(
                      widget.isExistingUserPrompt
                          ? Icons.public_rounded
                          : Icons.language_rounded,
                      color: accent,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.isExistingUserPrompt
                            ? 'Select Your Country & Currency'
                            : 'Country & Currency',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: textPrimary,
                        ),
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
                      Icon(Icons.info_outline_rounded, size: 16, color: accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.isExistingUserPrompt
                              ? 'Buddy now supports all 195+ countries! Please select your country so money logos and auto-tracking match your local currency. Existing transaction amounts remain unchanged.'
                              : 'Changing currency only updates the display symbol and auto-tracking rules. Your existing transaction amounts are not converted.',
                          style: TextStyle(
                            fontSize: 12,
                            color: textSecondary,
                            height: 1.35,
                          ),
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

