// lib/views/screens/widget_add_modal_host.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:buddy/views/screens/add_transaction_screen.dart';
import 'package:buddy/services/firestore_service.dart';
import 'package:buddy/services/widget_service.dart';
import 'package:buddy/views/widgets/buddy_loading_indicator.dart';

class WidgetAddModalHost extends StatefulWidget {
  final Future<void>? initFuture;
  const WidgetAddModalHost({super.key, this.initFuture});

  @override
  State<WidgetAddModalHost> createState() => _WidgetAddModalHostState();
}

class _WidgetAddModalHostState extends State<WidgetAddModalHost> {
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initAndOpen();
  }

  Future<void> _initAndOpen() async {
    // 1. Await core Firebase/Preferences initialization
    if (widget.initFuture != null) {
      try {
        await widget.initFuture;
      } catch (e) {
        debugPrint('⚠️ WIDGET_MODAL: initFuture error: $e');
      }
    }

    if (!mounted) return;
    setState(() => _isInitialized = true);

    // 2. Open standard modal bottom sheet immediately — no auth check needed.
    //    The widget is only accessible when the app has already been opened,
    //    so the user is inherently "set up". Guest/offline use is still valid
    //    because we persist transactions locally.
    WidgetsBinding.instance.addPostFrameCallback((_) => _showAddSheet());
  }

  Future<void> _showAddSheet() async {
    if (!mounted) return;

    // Exact same modal presentation as HomeScreen
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final screenHeight = MediaQuery.sizeOf(ctx).height;
        final heightFactor = screenHeight < 680 ? 0.95 : 0.92;
        return FractionallySizedBox(
          heightFactor: heightFactor,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                child: Material(
                  color: Theme.of(ctx).scaffoldBackgroundColor,
                  child: const AddTransactionScreen(),
                ),
              ),
            ),
          ),
        );
      },
    );

    // If transaction was added, refresh data & push to widget
    if (result == true) {
      try {
        final txns = await FirestoreService.instance
            .getAllTransactions(forceRefresh: true);
        await WidgetService.updateFromTransactions(txns);
      } catch (e) {
        debugPrint('⚠️ Error refreshing widget after add: $e');
      }
    }

    // Finished — exit transparent activity back to Android home screen
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _isInitialized
          ? const SizedBox.shrink()
          // Show the animated coin Lottie while initialising (matches in-app style)
          : Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const BuddyLoadingIndicator(size: 64),
              ),
            ),
    );
  }
}
