import 'package:cleanify/core/scanner/scan_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatElapsed', () {
    test('dưới 1 phút', () {
      expect(formatElapsed(Duration.zero), '00:00');
      expect(formatElapsed(const Duration(seconds: 7)), '00:07');
    });

    test('dưới 1 giờ', () {
      expect(formatElapsed(const Duration(minutes: 3, seconds: 25)), '03:25');
      expect(formatElapsed(const Duration(minutes: 59, seconds: 59)), '59:59');
    });

    test('từ 1 giờ trở lên', () {
      expect(
        formatElapsed(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });
  });
}
