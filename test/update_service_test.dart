// test/update_service_test.dart
import 'package:flutter_test/flutter_test.dart';

/// Tests for UpdateService version comparison logic.
/// The actual _isVersionLower method is private, so we replicate
/// the segment-by-segment numeric comparison here to validate the algorithm.
void main() {
  /// Compare versions numerically, segment by segment.
  /// Returns true if [installed] is strictly lower than [required].
  bool isVersionLower(String installed, String required) {
    final installedParts =
        installed.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    final requiredParts =
        required.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();

    final maxLen = installedParts.length > requiredParts.length
        ? installedParts.length
        : requiredParts.length;

    while (installedParts.length < maxLen) {
      installedParts.add(0);
    }
    while (requiredParts.length < maxLen) {
      requiredParts.add(0);
    }

    for (int i = 0; i < maxLen; i++) {
      if (installedParts[i] < requiredParts[i]) return true;
      if (installedParts[i] > requiredParts[i]) return false;
    }

    return false; // versions are equal
  }

  group('Version comparison (segment-by-segment numeric)', () {
    test('1.9.0 < 1.10.0 (numeric, not string comparison)', () {
      expect(isVersionLower('1.9.0', '1.10.0'), isTrue);
    });

    test('1.10.0 is NOT < 1.9.0', () {
      expect(isVersionLower('1.10.0', '1.9.0'), isFalse);
    });

    test('17.1.0 < 18.0.0', () {
      expect(isVersionLower('17.1.0', '18.0.0'), isTrue);
    });

    test('17.1.0 is NOT < 17.1.0 (equal)', () {
      expect(isVersionLower('17.1.0', '17.1.0'), isFalse);
    });

    test('17.1.0 is NOT < 17.0.0 (higher)', () {
      expect(isVersionLower('17.1.0', '17.0.0'), isFalse);
    });

    test('17.1.0 < 17.1.1 (patch bump)', () {
      expect(isVersionLower('17.1.0', '17.1.1'), isTrue);
    });

    test('1.0.0 < 2.0.0 (major bump)', () {
      expect(isVersionLower('1.0.0', '2.0.0'), isTrue);
    });

    test('Handles different segment counts: 1.0 < 1.0.1', () {
      expect(isVersionLower('1.0', '1.0.1'), isTrue);
    });

    test('Handles different segment counts: 1.0.0 vs 1.0 (equal)', () {
      expect(isVersionLower('1.0.0', '1.0'), isFalse);
    });

    test('Empty or malformed version fails safe (no update)', () {
      expect(isVersionLower('17.1.0', ''), isFalse);
      expect(isVersionLower('', '17.1.0'), isTrue);
    });

    test('Handles single segment: 17 < 18', () {
      expect(isVersionLower('17', '18'), isTrue);
    });

    test('Handles single segment: 18 is NOT < 17', () {
      expect(isVersionLower('18', '17'), isFalse);
    });
  });
}
