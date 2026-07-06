// lib/views/widgets/settings_modal.dart
import 'package:flutter/material.dart';
import 'package:buddy/services/notification_service.dart';
import 'package:buddy/services/notification_helper.dart';
import 'package:buddy/repositories/transaction_repository.dart';
import 'package:buddy/utils/colors.dart';

class SettingsModal extends StatefulWidget {
  final VoidCallback onDataCleared;

  const SettingsModal({super.key, required this.onDataCleared});

  @override
  State<SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends State<SettingsModal> {
  bool _autoDetectionEnabled = false;
  bool _isLoading = true;
  Map<String, dynamic>? _debugInfo;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final enabled = await NotificationService.isAutoDetectionEnabled();
      // final info = await NotificationService.getDebugInfo();

      if (mounted) {
        setState(() {
          _autoDetectionEnabled = enabled;
          // _debugInfo = info;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading settings: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleAutoDetection(bool value) async {
    setState(() => _isLoading = true);

    try {
      if (value) {
        // Request notification permission first
        await NotificationHelper.requestNotificationPermission();

        // Request notification listener access
        final hasAccess = await NotificationService.requestNotificationAccess();

        if (!hasAccess) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '⚠️ Please grant notification access in settings',
              ),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );

          // Wait a bit for user to see the message
          await Future.delayed(const Duration(milliseconds: 500));

          // Re-check after user returns
          final recheckAccess =
              await NotificationService.requestNotificationAccess();
          if (!recheckAccess) {
            setState(() => _isLoading = false);
            return;
          }
        }

        // Enable auto-detection
        await NotificationService.setAutoDetectionEnabled(true);

        // Force start listener
        await NotificationService.stopListening();
        await NotificationService.startListening();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Auto-detection enabled successfully!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      } else {
        // Disable auto-detection
        await NotificationService.setAutoDetectionEnabled(false);
        await NotificationService.stopListening();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Auto-detection disabled'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }

      // Reload settings to get updated status
      await _loadSettings();
    } catch (e) {
      debugPrint('❌ Error toggling auto-detection: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _clearTodayData() async {
    final confirmed = await _showConfirmDialog(
      title: 'Clear Today\'s Data?',
      message:
          'This will delete all transactions from today. This cannot be undone.',
    );

    if (!confirmed) return;

    try {
      final repo = TransactionRepository();
      final rows = await repo.getAll();
      final today = DateTime.now();
      int deletedCount = 0;

      for (final r in rows) {
        final dateStr = r['date'] as String?;
        if (dateStr == null) continue;

        final dt = DateTime.tryParse(dateStr);
        if (dt != null &&
            dt.year == today.year &&
            dt.month == today.month &&
            dt.day == today.day) {
          await repo.delete(r['id'] as int);
          deletedCount++;
        }
      }

      if (!mounted) return;

      Navigator.pop(context); // Close modal
      widget.onDataCleared();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Deleted $deletedCount transaction(s) from today'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _clearThisMonthData() async {
    final confirmed = await _showConfirmDialog(
      title: 'Clear This Month\'s Data?',
      message:
          'This will delete all transactions from this month. This cannot be undone.',
    );

    if (!confirmed) return;

    try {
      final repo = TransactionRepository();
      final rows = await repo.getAll();
      final now = DateTime.now();
      int deletedCount = 0;

      for (final r in rows) {
        final dateStr = r['date'] as String?;
        if (dateStr == null) continue;

        final dt = DateTime.tryParse(dateStr);
        if (dt != null && dt.year == now.year && dt.month == now.month) {
          await repo.delete(r['id'] as int);
          deletedCount++;
        }
      }

      if (!mounted) return;

      Navigator.pop(context); // Close modal
      widget.onDataCleared();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Deleted $deletedCount transaction(s) from this month',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _clearAllData() async {
    final confirmed = await _showConfirmDialog(
      title: 'Clear All Data?',
      message:
          'This will delete ALL transactions permanently. This cannot be undone.',
      isDangerous: true,
    );

    if (!confirmed) return;

    try {
      final repo = TransactionRepository();
      final rows = await repo.getAll();
      int deletedCount = 0;

      for (final r in rows) {
        await repo.delete(r['id'] as int);
        deletedCount++;
      }

      if (!mounted) return;

      Navigator.pop(context); // Close modal
      widget.onDataCleared();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Deleted $deletedCount transaction(s)'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
    bool isDangerous = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: isDangerous ? Colors.red : AppColors.primary,
            ),
            child: Text(isDangerous ? 'Delete' : 'Confirm'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final isPermissionGranted = _debugInfo?['permission_granted'] == true;
    final isListenerActive = _debugInfo?['is_listening'] == true;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                const Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 24),

                // Auto-Detection Section
                const Text(
                  'Auto Transaction Detection',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),

                // Auto-Detection Toggle with Status
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _autoDetectionEnabled
                          ? AppColors.primary.withValues(alpha: .3)
                          : Colors.grey.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.notifications_active_rounded,
                              color: AppColors.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Auto-Detect Transactions',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Automatically add from notifications',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_isLoading)
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Switch(
                              value: _autoDetectionEnabled,
                              onChanged: _toggleAutoDetection,
                              activeTrackColor: AppColors.primary,
                              activeThumbColor: Colors.white,
                            ),
                        ],
                      ),

                      // Status Indicators
                      if (_debugInfo != null && _autoDetectionEnabled) ...[
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 12),

                        _buildStatusRow(
                          'Permission',
                          isPermissionGranted ? 'Granted' : 'Not Granted',
                          isPermissionGranted ? Colors.green : Colors.red,
                        ),
                        const SizedBox(height: 8),
                        _buildStatusRow(
                          'Listener',
                          isListenerActive ? 'Active' : 'Inactive',
                          isListenerActive ? Colors.green : Colors.orange,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Data Management Section
                const Text(
                  'Data Management',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),

                // Clear Today's Data
                _buildActionTile(
                  icon: Icons.today_rounded,
                  title: 'Clear Today\'s Data',
                  subtitle: 'Delete all transactions from today',
                  color: Colors.blue,
                  onTap: _clearTodayData,
                ),

                const SizedBox(height: 12),

                // Clear This Month's Data
                _buildActionTile(
                  icon: Icons.calendar_month_rounded,
                  title: 'Clear This Month',
                  subtitle: 'Delete all transactions from this month',
                  color: Colors.orange,
                  onTap: _clearThisMonthData,
                ),

                const SizedBox(height: 12),

                // Clear All Data
                _buildActionTile(
                  icon: Icons.delete_forever_rounded,
                  title: 'Clear All Data',
                  subtitle: 'Delete ALL transactions permanently',
                  color: Colors.red,
                  onTap: _clearAllData,
                  isDangerous: true,
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String status, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Text(
            status,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool isDangerous = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDangerous ? color : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
