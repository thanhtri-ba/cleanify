import 'package:cleanify/core/scanner/scan_mode.dart';
import 'package:cleanify/core/scanner/scan_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const dup = ScanMode(duplicates: true, similar: false);
  const sim = ScanMode(duplicates: false, similar: true);

  test('trọng số mỗi chế độ cộng lại bằng 1', () {
    for (final m in [dup, sim, const ScanMode(duplicates: true, similar: true)]) {
      expect(phaseWeights(m).values.fold(0.0, (a, b) => a + b), closeTo(1, 1e-9));
    }
  });

  test('hết đọc ảnh chưa phải 100%', () {
    final v = overallProgress(dup, const ScanProgress(ScanPhase.reading, 10, 10));
    expect(v, closeTo(0.60, 1e-9));
  });

  test('tiến độ tăng đơn điệu theo thứ tự giai đoạn thật', () {
    final seq = [
      const ScanProgress(ScanPhase.reading, 5, 10),
      const ScanProgress(ScanPhase.reading, 10, 10),
      const ScanProgress(ScanPhase.matching, 10, 10),
      const ScanProgress(ScanPhase.exact, 0, 4),
      const ScanProgress(ScanPhase.exact, 4, 4),
    ];
    var last = -1.0;
    for (final p in seq) {
      final v = overallProgress(dup, p);
      expect(v, greaterThanOrEqualTo(last));
      last = v;
    }
    expect(last, lessThan(1));
  });

  test('quét tương tự: AI chiếm phần lớn và không vượt 0,99', () {
    final v = overallProgress(sim, const ScanProgress(ScanPhase.embedding, 100, 100));
    expect(v, 0.99);
  });
}
