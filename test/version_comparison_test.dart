import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Version Comparison Tests', () {
    // Simulate the version comparison logic
    int compareVersions(String v1, String v2) {
      final parts1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final parts2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      final maxLength =
          parts1.length > parts2.length ? parts1.length : parts2.length;

      for (int i = 0; i < maxLength; i++) {
        final p1 = i < parts1.length ? parts1[i] : 0;
        final p2 = i < parts2.length ? parts2[i] : 0;

        if (p1 < p2) return -1;
        if (p1 > p2) return 1;
      }

      return 0;
    }

    // Simulate the tag name processing
    String extractVersion(String tagName) {
      return tagName
          .replaceFirst('v', '')
          .replaceFirst(RegExp(r'\(.*\)'), '')
          .trim();
    }

    test('Extract version from various tag formats', () {
      expect(extractVersion('v1.0.6'), '1.0.6');
      expect(extractVersion('1.0.6'), '1.0.6');
      expect(extractVersion('v1.0.6(1024)'), '1.0.6');
      expect(extractVersion('1.0.6(1024)'), '1.0.6');
      expect(extractVersion('v1.0.5(0721)'), '1.0.5');
    });

    test('Current version 1.0.5 vs new version 1.0.6', () {
      final current = '1.0.5';
      final latest = extractVersion('v1.0.6');
      expect(compareVersions(current, latest), -1); // 1.0.5 < 1.0.6
    });

    test('Current version 1.0.5 vs new version 1.0.6(1024)', () {
      final current = '1.0.5';
      final latest = extractVersion('v1.0.6(1024)');
      expect(compareVersions(current, latest), -1); // 1.0.5 < 1.0.6
    });

    test('Current version 1.0.5 vs same version 1.0.5', () {
      final current = '1.0.5';
      final latest = extractVersion('v1.0.5');
      expect(compareVersions(current, latest), 0); // 1.0.5 = 1.0.5
    });

    test('Current version 1.0.5 vs same version 1.0.5(0721)', () {
      final current = '1.0.5';
      final latest = extractVersion('v1.0.5(0721)');
      expect(compareVersions(current, latest), 0); // 1.0.5 = 1.0.5
    });

    test('Current version 1.0.6 vs old version 1.0.5', () {
      final current = '1.0.6';
      final latest = extractVersion('v1.0.5');
      expect(compareVersions(current, latest), 1); // 1.0.6 > 1.0.5
    });

    test('Various version comparisons', () {
      expect(compareVersions('1.0.5', '1.0.6'), -1);
      expect(compareVersions('1.0.5', '1.1.0'), -1);
      expect(compareVersions('1.0.5', '2.0.0'), -1);
      expect(compareVersions('1.0.6', '1.0.5'), 1);
      expect(compareVersions('1.1.0', '1.0.5'), 1);
      expect(compareVersions('2.0.0', '1.0.5'), 1);
      expect(compareVersions('1.0.5', '1.0.5'), 0);
    });
  });
}
