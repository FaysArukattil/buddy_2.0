import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/utils/icon_helper.dart';
import 'package:buddy/views/widgets/animated_money_text.dart';
import 'package:buddy/services/firestore_service.dart';
import 'package:buddy/views/screens/add_transaction_screen.dart';
import 'package:buddy/services/pdf_service.dart';
import 'package:buddy/utils/app_snackbar.dart';
import 'package:buddy/models/transaction.dart';
import 'package:buddy/views/widgets/buddy_loading_indicator.dart';

class TransactionDetailScreen extends StatefulWidget {
  final Map<String, dynamic> data;
  const TransactionDetailScreen({super.key, required this.data});

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  bool _isDownloading = false;

  bool get _isIncome =>
      (widget.data['type'] as String?)?.toLowerCase().trim() == 'income';

  DateTime get _parsedDate {
    final raw = widget.data['date'];
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
    return DateTime.now();
  }

  double get _parsedAmount {
    final raw = widget.data['amount'];
    if (raw is num) return raw.toDouble();
    return 0.0;
  }

  String? get _note {
    final raw = (widget.data['note'] as String?)?.trim();
    return TransactionModel.cleanNoteText(raw);
  }

  String get _category =>
      (widget.data['category'] as String?)?.trim() ?? 'Other';

  String get _title {
    if (_note != null && _note!.isNotEmpty) return _note!;
    final customTitle = (widget.data['title'] as String?)?.trim();
    final cleanTitle = TransactionModel.cleanNoteText(customTitle);
    if (cleanTitle != null && cleanTitle.isNotEmpty) return cleanTitle;
    return _category;
  }

  bool get _isAutoDetected =>
      widget.data['auto_detected'] == true ||
      widget.data['autoDetected'] == true;

  String? get _source => widget.data['notificationSource'] as String?;

  Map<String, dynamic> get _entrySourceInfo {
    if (!_isAutoDetected) {
      return {
        'name': 'Manual Entry',
        'subtitle': 'Created manually in Buddy',
        'badge': 'Manual',
        'icon': Icons.touch_app_rounded,
        'iconColor': const Color(0xFFFFD54F),
      };
    }

    final raw = (_source ?? '').trim();
    if (raw.isEmpty) {
      return {
        'name': 'Bank SMS',
        'subtitle': 'Smart Auto-Detection',
        'badge': 'Auto',
        'icon': Icons.sms_rounded,
        'iconColor': const Color(0xFF80CBC4),
      };
    }

    final lower = raw.toLowerCase();

    // 1. UPI & Payment Apps
    if (lower.contains('paisa') ||
        lower.contains('gpay') ||
        lower.contains('google pay')) {
      return {
        'name': 'Google Pay',
        'subtitle': 'Auto-detected payment',
        'badge': 'UPI',
        'icon': Icons.account_balance_wallet_rounded,
        'iconColor': const Color(0xFF4285F4),
      };
    }

    if (lower.contains('phonepe')) {
      return {
        'name': 'PhonePe',
        'subtitle': 'Auto-detected payment',
        'badge': 'UPI',
        'icon': Icons.account_balance_wallet_rounded,
        'iconColor': const Color(0xFF6739B7),
      };
    }

    if (lower.contains('paytm') || lower.contains('one97')) {
      return {
        'name': 'Paytm',
        'subtitle': 'Auto-detected payment',
        'badge': 'UPI',
        'icon': Icons.account_balance_wallet_rounded,
        'iconColor': const Color(0xFF00BAF2),
      };
    }

    if (lower.contains('amazon')) {
      return {
        'name': 'Amazon Pay',
        'subtitle': 'Auto-detected payment',
        'badge': 'UPI',
        'icon': Icons.shopping_bag_rounded,
        'iconColor': const Color(0xFFFF9900),
      };
    }

    if (lower.contains('cred') || lower.contains('dreamplug')) {
      return {
        'name': 'CRED',
        'subtitle': 'Auto-detected card/payment',
        'badge': 'Credit Card',
        'icon': Icons.credit_card_rounded,
        'iconColor': const Color(0xFFECEFF1),
      };
    }

    if (lower.contains('bhim') || lower.contains('npci')) {
      return {
        'name': 'BHIM UPI',
        'subtitle': 'Auto-detected payment',
        'badge': 'UPI',
        'icon': Icons.account_balance_rounded,
        'iconColor': const Color(0xFF00A859),
      };
    }

    if (lower.contains('whatsapp')) {
      return {
        'name': 'WhatsApp Pay',
        'subtitle': 'Auto-detected payment',
        'badge': 'UPI',
        'icon': Icons.chat_bubble_rounded,
        'iconColor': const Color(0xFF25D366),
      };
    }

    // 2. Popular Indian Banks (Apps & SMS Senders)
    final isSms = lower.contains('sms') ||
        lower.contains('message') ||
        raw.contains('-');

    if (lower.contains('sbi')) {
      return {
        'name': isSms ? 'SBI (Bank SMS)' : 'State Bank of India',
        'subtitle': isSms ? 'Smart SMS Detection' : 'Auto-detected bank alert',
        'badge': isSms ? 'SMS' : 'Bank',
        'icon': isSms ? Icons.sms_rounded : Icons.account_balance_rounded,
        'iconColor': const Color(0xFF29B6F6),
      };
    }

    if (lower.contains('hdfc')) {
      return {
        'name': isSms ? 'HDFC Bank (SMS)' : 'HDFC Bank',
        'subtitle': isSms ? 'Smart SMS Detection' : 'Auto-detected bank alert',
        'badge': isSms ? 'SMS' : 'Bank',
        'icon': isSms ? Icons.sms_rounded : Icons.account_balance_rounded,
        'iconColor': const Color(0xFF004C8F),
      };
    }

    if (lower.contains('icici')) {
      return {
        'name': isSms ? 'ICICI Bank (SMS)' : 'ICICI Bank',
        'subtitle': isSms ? 'Smart SMS Detection' : 'Auto-detected bank alert',
        'badge': isSms ? 'SMS' : 'Bank',
        'icon': isSms ? Icons.sms_rounded : Icons.account_balance_rounded,
        'iconColor': const Color(0xFFFF7043),
      };
    }

    if (lower.contains('axis')) {
      return {
        'name': isSms ? 'Axis Bank (SMS)' : 'Axis Bank',
        'subtitle': isSms ? 'Smart SMS Detection' : 'Auto-detected bank alert',
        'badge': isSms ? 'SMS' : 'Bank',
        'icon': isSms ? Icons.sms_rounded : Icons.account_balance_rounded,
        'iconColor': const Color(0xFF97144D),
      };
    }

    if (lower.contains('kotak')) {
      return {
        'name': isSms ? 'Kotak Bank (SMS)' : 'Kotak Mahindra Bank',
        'subtitle': isSms ? 'Smart SMS Detection' : 'Auto-detected bank alert',
        'badge': isSms ? 'SMS' : 'Bank',
        'icon': isSms ? Icons.sms_rounded : Icons.account_balance_rounded,
        'iconColor': const Color(0xFFE53935),
      };
    }

    if (lower.contains('federal') ||
        lower.contains('fedalert') ||
        lower.contains('fedmobile')) {
      return {
        'name': isSms ? 'Federal Bank (SMS)' : 'Federal Bank',
        'subtitle': isSms ? 'Smart SMS Detection' : 'Auto-detected bank alert',
        'badge': isSms ? 'SMS' : 'Bank',
        'icon': isSms ? Icons.sms_rounded : Icons.account_balance_rounded,
        'iconColor': const Color(0xFFFFB300),
      };
    }

    if (lower.contains('idfc')) {
      return {
        'name': isSms ? 'IDFC FIRST (SMS)' : 'IDFC FIRST Bank',
        'subtitle': isSms ? 'Smart SMS Detection' : 'Auto-detected bank alert',
        'badge': isSms ? 'SMS' : 'Bank',
        'icon': isSms ? Icons.sms_rounded : Icons.account_balance_rounded,
        'iconColor': const Color(0xFF9C27B0),
      };
    }

    if (lower.contains('canara')) {
      return {
        'name': isSms ? 'Canara Bank (SMS)' : 'Canara Bank',
        'subtitle': isSms ? 'Smart SMS Detection' : 'Auto-detected bank alert',
        'badge': isSms ? 'SMS' : 'Bank',
        'icon': isSms ? Icons.sms_rounded : Icons.account_balance_rounded,
        'iconColor': const Color(0xFF00ACC1),
      };
    }

    if (lower.contains('baroda') || lower.contains('bob')) {
      return {
        'name': isSms ? 'Bank of Baroda (SMS)' : 'Bank of Baroda',
        'subtitle': isSms ? 'Smart SMS Detection' : 'Auto-detected bank alert',
        'badge': isSms ? 'SMS' : 'Bank',
        'icon': isSms ? Icons.sms_rounded : Icons.account_balance_rounded,
        'iconColor': const Color(0xFFF4511E),
      };
    }

    if (lower.contains('pnb')) {
      return {
        'name': isSms ? 'PNB (Bank SMS)' : 'Punjab National Bank',
        'subtitle': isSms ? 'Smart SMS Detection' : 'Auto-detected bank alert',
        'badge': isSms ? 'SMS' : 'Bank',
        'icon': isSms ? Icons.sms_rounded : Icons.account_balance_rounded,
        'iconColor': const Color(0xFFFFC107),
      };
    }

    if (lower.contains('union')) {
      return {
        'name': isSms ? 'Union Bank (SMS)' : 'Union Bank',
        'subtitle': isSms ? 'Smart SMS Detection' : 'Auto-detected bank alert',
        'badge': isSms ? 'SMS' : 'Bank',
        'icon': isSms ? Icons.sms_rounded : Icons.account_balance_rounded,
        'iconColor': const Color(0xFF0288D1),
      };
    }

    if (lower.contains('indusind')) {
      return {
        'name': isSms ? 'IndusInd Bank (SMS)' : 'IndusInd Bank',
        'subtitle': isSms ? 'Smart SMS Detection' : 'Auto-detected bank alert',
        'badge': isSms ? 'SMS' : 'Bank',
        'icon': isSms ? Icons.sms_rounded : Icons.account_balance_rounded,
        'iconColor': const Color(0xFF880E4F),
      };
    }

    // 3. SMS App Packages
    if (lower.contains('messaging') ||
        lower.contains('mms') ||
        lower.contains('sms')) {
      return {
        'name': 'Bank SMS Alert',
        'subtitle': 'Auto-detected via SMS',
        'badge': 'SMS',
        'icon': Icons.sms_rounded,
        'iconColor': const Color(0xFF80CBC4),
      };
    }

    // 4. Indian Bank SMS header codes (e.g. "VK-HDFCBK", "AD-SBIPAY", "CP-AXISBK")
    final headerRegex = RegExp(r'^[A-Za-z]{2}-([A-Za-z0-9]+)$');
    final match = headerRegex.firstMatch(raw);
    if (match != null) {
      final code = match.group(1)?.toUpperCase() ?? raw.toUpperCase();
      return {
        'name': 'Bank SMS ($code)',
        'subtitle': 'Smart SMS Detection',
        'badge': 'SMS',
        'icon': Icons.sms_rounded,
        'iconColor': const Color(0xFF80CBC4),
      };
    }

    // 5. Clean string without package dots
    if (!raw.contains('.')) {
      return {
        'name': raw,
        'subtitle': 'Auto-detected',
        'badge': 'Auto',
        'icon': Icons.auto_awesome,
        'iconColor': const Color(0xFF80CBC4),
      };
    }

    // 6. Generic package name fallback: clean into capitalized app title
    final parts = raw.split('.').where((p) =>
        p != 'com' &&
        p != 'android' &&
        p != 'apps' &&
        p != 'app' &&
        p != 'user' &&
        p.isNotEmpty).toList();
    final cleanName = parts.isNotEmpty
        ? parts.last.substring(0, 1).toUpperCase() + parts.last.substring(1)
        : raw;

    return {
      'name': cleanName,
      'subtitle': 'Auto-detected application',
      'badge': 'Auto',
      'icon': Icons.auto_awesome,
      'iconColor': const Color(0xFF80CBC4),
    };
  }

  String _formatTime(DateTime d) {
    return DateFormat('hh:mm a').format(d);
  }

  String _formatDate(DateTime dt) {
    return DateFormat('dd MMM yyyy').format(dt);
  }

  String _formatDayOfWeek(DateTime dt) {
    return DateFormat('EEEE').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final dt = _parsedDate;
    final catColor = AppColors.getCategoryColor(_category);
    final rawId = widget.data['id'] as String?;
    final shortId = (rawId != null && rawId.isNotEmpty)
        ? rawId.substring(0, math.min(10, rawId.length)).toUpperCase()
        : null;

    final incomeAccent = const Color(0xFF69F0AE);
    final expenseAccent = const Color(0xFFFF8A80);
    final statusColor = _isIncome ? incomeAccent : expenseAccent;

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── 1. SIGNATURE PAGE-STYLE TOP HERO CONTAINER ───
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? const [
                            Color(0xFF0F2624), // Deep spruce/emerald
                            Color(0xFF163E3B), // Signature deep teal
                            Color(0xFF1E5D57), // Teal glow
                          ]
                        : const [
                            Color(0xFF0F3632), // Signature dark emerald
                            Color(0xFF1E5D57), // Signature primary teal
                            Color(0xFF2C7A72), // Radiant teal highlight
                          ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(28),
                    bottomRight: Radius.circular(28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isDark
                              ? const Color(0xFF0F2624)
                              : const Color(0xFF0F3632))
                          .withValues(alpha: 0.32),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(
                  20,
                  MediaQuery.paddingOf(context).top + 28,
                  20,
                  24,
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    // Header Bar: Back Button, Title & Actions (Edit / Delete)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Back Button
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22),
                              ),
                            ),
                            child: const Icon(
                              Icons.arrow_back_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),

                        // Title & Subtitle
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Transaction Details',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_isIncome ? "Income" : "Expense"} • Recorded in Buddy',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Action buttons: Edit & Delete
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Edit
                            GestureDetector(
                              onTap: _openEdit,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.22),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.edit_outlined,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Delete
                            GestureDetector(
                              onTap: _confirmDelete,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444)
                                      .withValues(alpha: 0.25),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFFEF4444)
                                        .withValues(alpha: 0.45),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Color(0xFFFF8A80),
                                  size: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // Contact / Category Hero Pill (Avatar + Title + Badges)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.24),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Category Avatar with subtle border
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: catColor.withValues(alpha: 0.22),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: catColor.withValues(alpha: 0.45),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: catColor.withValues(alpha: 0.20),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              IconHelper.getIcon(widget.data['icon']),
                              color: catColor,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _title,
                                  softWrap: true,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -0.2,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    // Category Tag
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        _category,
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),

                                    // Type Tag
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.20),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: statusColor.withValues(alpha: 0.45),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _isIncome
                                                ? Icons.arrow_upward_rounded
                                                : Icons.arrow_downward_rounded,
                                            size: 11,
                                            color: statusColor,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            _isIncome ? 'Income' : 'Expense',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                              color: statusColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Auto Detected Badge
                                    if (_isAutoDetected)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFF6366F1),
                                              Color(0xFF8B5CF6),
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.auto_awesome,
                                              size: 10,
                                              color: Colors.white,
                                            ),
                                            SizedBox(width: 3),
                                            Text(
                                              'Auto',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Amount Display
                    Text(
                      _isIncome ? 'Total Income Received' : 'Total Amount Spent',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.75),
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: AnimatedMoneyText(
                        value: _parsedAmount,
                        showSign: true,
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: statusColor,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Status Pill (Frosted Capsule)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 14,
                            color: incomeAccent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Recorded in Buddy',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // ─── 2. FROSTED METADATA INFO GRID ───
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                          width: 1.0,
                        ),
                      ),
                      child: Column(
                        children: [
                          // Grid Row 1: Date & Time
                          Row(
                            children: [
                              Expanded(
                                child: _buildMetaItem(
                                  icon: Icons.calendar_today_rounded,
                                  iconColor: const Color(0xFF69F0AE),
                                  label: 'Date',
                                  value: _formatDate(dt),
                                  subvalue: _formatDayOfWeek(dt),
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 44,
                                color: Colors.white.withValues(alpha: 0.20),
                                margin: const EdgeInsets.symmetric(horizontal: 10),
                              ),
                              Expanded(
                                child: _buildMetaItem(
                                  icon: Icons.access_time_rounded,
                                  iconColor: const Color(0xFF80CBC4),
                                  label: 'Time',
                                  value: _formatTime(dt),
                                  subvalue: 'Logged at',
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),
                          Divider(
                            color: Colors.white.withValues(alpha: 0.15),
                            height: 1,
                          ),
                          const SizedBox(height: 10),

                          // Grid Row 2: Category & Transaction ID
                          Row(
                            children: [
                              Expanded(
                                child: _buildMetaItem(
                                  icon: Icons.category_rounded,
                                  iconColor: catColor,
                                  label: 'Category',
                                  value: _category,
                                  subvalue: 'Classification',
                                ),
                              ),
                              if (rawId != null && rawId.isNotEmpty) ...[
                                Container(
                                  width: 1,
                                  height: 44,
                                  color: Colors.white.withValues(alpha: 0.20),
                                  margin: const EdgeInsets.symmetric(horizontal: 10),
                                ),
                                Expanded(
                                  child: _buildMetaItem(
                                    icon: Icons.tag_rounded,
                                    iconColor: Colors.white70,
                                    label: 'Transaction ID',
                                    value: '#${shortId ?? rawId}',
                                    subvalue: 'System Reference',
                                  ),
                                ),
                              ],
                            ],
                          ),

                          const SizedBox(height: 10),
                          Divider(
                            color: Colors.white.withValues(alpha: 0.15),
                            height: 1,
                          ),
                          const SizedBox(height: 10),

                          // Grid Row 3: Dedicated Full-Width Entry Source Tile
                          _buildEntrySourceTile(_entrySourceInfo),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ─── 3. LOWER SECTION (NOTE & PRIMARY/SECONDARY ACTIONS) ───
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Notes Card
                    if (_note != null && _note!.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.cardOf(context),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.borderOf(context).withValues(alpha: 0.6),
                            width: 1.2,
                          ),
                          boxShadow: AppColors.cardShadowOf(context),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.sticky_note_2_rounded,
                                    size: 15,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'NOTES & REMARKS',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textSecondaryOf(context),
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _note!,
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textPrimaryOf(context),
                                height: 1.4,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    // Primary Action: Open PDF Receipt
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 3,
                          shadowColor: AppColors.primary.withValues(alpha: 0.35),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _isDownloading ? null : _downloadPdf,
                        child: _isDownloading
                            ? const BuddyLoadingIndicator(size: 24)
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.file_open_rounded, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Open Receipt',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Helper: Build clean grid item inside the frosted emerald header
  Widget _buildMetaItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    String? subvalue,
    int? maxLines = 2,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: iconColor.withValues(alpha: 0.35),
              width: 0.8,
            ),
          ),
          child: Icon(icon, size: 15, color: iconColor),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.70),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: maxLines,
                overflow: maxLines == null ? TextOverflow.visible : TextOverflow.ellipsis,
                softWrap: true,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.2,
                  height: 1.25,
                ),
              ),
              if (subvalue != null) ...[
                const SizedBox(height: 1),
                Text(
                  subvalue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Helper: Dedicated full-width Entry Source tile
  Widget _buildEntrySourceTile(Map<String, dynamic> sourceInfo) {
    final icon = sourceInfo['icon'] as IconData;
    final iconColor = sourceInfo['iconColor'] as Color;
    final name = sourceInfo['name'] as String;
    final subtitle = sourceInfo['subtitle'] as String;
    final badge = sourceInfo['badge'] as String;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: iconColor.withValues(alpha: 0.35),
              width: 0.8,
            ),
          ),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ENTRY SOURCE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.70),
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                softWrap: true,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.2,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                softWrap: true,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.85),
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: iconColor.withValues(alpha: 0.40),
              width: 0.8,
            ),
          ),
          child: Text(
            badge,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: iconColor,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }

  // ── Actions: Download / Edit / Delete ──

  Future<void> _downloadPdf() async {
    setState(() => _isDownloading = true);

    try {
      final file = await PdfService.generateSingleTransactionPdf(widget.data);

      if (!mounted) return;

      final dt = _parsedDate;
      final catColor = AppColors.getCategoryColor(_category);
      final incomeAccent = const Color(0xFF69F0AE);
      final expenseAccent = const Color(0xFFFF8A80);
      final statusColor = _isIncome ? incomeAccent : expenseAccent;

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.cardOf(ctx),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Frosted Handle
                Container(
                  width: 42,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: AppColors.borderOf(ctx),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 18),

                // Header Bar with Icon, Title & Close Button
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF0F3632),
                            Color(0xFF1E5D57),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1E5D57).withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.description_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Receipt & Export',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimaryOf(ctx),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Digital PDF Statement ready',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondaryOf(ctx),
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceOf(ctx),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.borderOf(ctx).withValues(alpha: 0.6),
                          ),
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          color: AppColors.textSecondaryOf(ctx),
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Mini Transaction Preview Chip
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceOf(ctx),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.borderOf(ctx).withValues(alpha: 0.7),
                      width: 1.1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: catColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          IconHelper.getIcon(widget.data['icon']),
                          color: catColor,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimaryOf(ctx),
                              ),
                            ),
                            Text(
                              '${_formatDate(dt)} • ${_formatTime(dt)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondaryOf(ctx),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${_isIncome ? '+' : '-'} ₹${NumberFormat('#,##,##0.##').format(_parsedAmount)}',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Option 1: Open Document
                _buildSheetActionTile(
                  ctx,
                  icon: Icons.file_open_rounded,
                  iconColor: AppColors.primary,
                  title: 'Open Document',
                  subtitle: 'View high-resolution receipt on your device',
                  onTap: () {
                    Navigator.pop(ctx);
                    PdfService.openPdf(file);
                  },
                ),
                const SizedBox(height: 10),

                // Option 2: Share PDF
                _buildSheetActionTile(
                  ctx,
                  icon: Icons.share_rounded,
                  iconColor: AppColors.secondary,
                  title: 'Share PDF Receipt',
                  subtitle: 'Send via WhatsApp, Mail, Telegram, or AirDrop',
                  onTap: () {
                    Navigator.pop(ctx);
                    PdfService.sharePdf(file);
                  },
                ),
                const SizedBox(height: 10),

                // Option 3: Print Receipt
                _buildSheetActionTile(
                  ctx,
                  icon: Icons.print_rounded,
                  iconColor: const Color(0xFF10B981),
                  title: 'Print Receipt',
                  subtitle: 'Send to connected wireless printer',
                  onTap: () {
                    Navigator.pop(ctx);
                    PdfService.printPdf(file);
                  },
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(context, 'Error generating PDF: $e');
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  Widget _buildSheetActionTile(
    BuildContext ctx, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(ctx),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.borderOf(ctx).withValues(alpha: 0.7),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(ctx),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondaryOf(ctx),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondaryOf(ctx).withValues(alpha: 0.6),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openEdit() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(existingTransaction: widget.data),
      ),
    );
    if (result == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _confirmDelete() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardOf(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Delete transaction?',
          style: TextStyle(
            color: AppColors.textPrimaryOf(ctx),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to delete this transaction? This action cannot be undone.',
          style: TextStyle(
            color: AppColors.textSecondaryOf(ctx),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondaryOf(ctx)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.expense,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final id = widget.data['id'];
    if (id is String && id.isNotEmpty) {
      await FirestoreService.instance.deleteTransaction(id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    }
  }
}
