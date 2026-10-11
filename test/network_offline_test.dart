import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buddy/services/Network_services.dart';
import 'package:buddy/views/widgets/offline_banner.dart';

void main() {
  group('Network & Offline State Handling Tests', () {
    setUp(() {
      NetworkHelper.isOnline.value = true;
    });

    test('NetworkHelper starts online and reacts to offline state', () {
      expect(NetworkHelper.isOnline.value, isTrue);
      expect(NetworkHelper.isConnected, isTrue);

      NetworkHelper.isOnline.value = false;
      expect(NetworkHelper.isOnline.value, isFalse);
      expect(NetworkHelper.isConnected, isFalse);

      NetworkHelper.isOnline.value = true;
      expect(NetworkHelper.isOnline.value, isTrue);
      expect(NetworkHelper.isConnected, isTrue);
    });

    testWidgets('OfflineBanner displays offline banner when network is down',
        (WidgetTester tester) async {
      NetworkHelper.isOnline.value = false;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Center(child: Text('Main Screen Content')),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: OfflineBanner(),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text("You're offline • Working locally"), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    });

    testWidgets('OfflineBanner displays back online banner when restored',
        (WidgetTester tester) async {
      NetworkHelper.isOnline.value = false;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: OfflineBanner(),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text("You're offline • Working locally"), findsOneWidget);

      // Now reconnect
      NetworkHelper.isOnline.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text("Back online • Syncing changes"), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done_rounded), findsOneWidget);
    });

    testWidgets(
        'OfflineBanner auto-collapses to corner network cut icon and re-expands on tap',
        (WidgetTester tester) async {
      NetworkHelper.isOnline.value = false;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: OfflineBanner(),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      // Initially full banner is shown
      expect(find.byKey(const ValueKey('full_pill_banner')), findsOneWidget);
      expect(find.text("You're offline • Working locally"), findsOneWidget);

      // Fast forward past 3500ms auto-collapse timer
      await tester.pump(const Duration(milliseconds: 3600));
      await tester.pumpAndSettle();

      // Now collapsed corner icon should be visible and full pill should not
      expect(find.byKey(const ValueKey('corner_cut_icon')), findsOneWidget);
      expect(find.text("You're offline • Working locally"), findsNothing);

      // Tap corner cut icon to re-expand
      await tester.tap(find.byKey(const ValueKey('corner_cut_icon')));
      await tester.pumpAndSettle();

      // Full banner should be re-expanded
      expect(find.byKey(const ValueKey('full_pill_banner')), findsOneWidget);
      expect(find.text("You're offline • Working locally"), findsOneWidget);
    });
  });
}
