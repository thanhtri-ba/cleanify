import 'package:cleanify/engines/features/local_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 8);

  test('planLocalBatches: mỗi cặp kề nhau trong cửa sổ xuất hiện đúng một lần', () {
    // 40 ảnh, cách nhau 30 giây, sắp theo thời gian ngược để thử việc sắp xếp.
    final times = [for (var i = 0; i < 40; i++) t0.add(Duration(seconds: 30 * (39 - i)))];
    final batches = planLocalBatches(times: times, neighbors: 3, stride: 8);
    final seen = <String>{};
    for (final b in batches) {
      for (final p in b.pairs) {
        expect(p.a, inInclusiveRange(0, b.photos.length - 1));
        expect(p.b, inInclusiveRange(0, b.photos.length - 1));
        final x = b.photos[p.a], y = b.photos[p.b];
        expect(seen.add(x < y ? '$x-$y' : '$y-$x'), isTrue, reason: 'cặp lặp');
      }
    }
    // Dãy 40 ảnh, mỗi ảnh nối với 3 ảnh kế tiếp: 37*3 + 2 + 1 = 114 cặp.
    expect(seen.length, 114);
  });

  test('planLocalBatches: tôn trọng cửa sổ thời gian và skip', () {
    final times = [
      t0,
      t0.add(const Duration(minutes: 1)),
      t0.add(const Duration(minutes: 30)),
      t0.add(const Duration(minutes: 31)),
    ];
    final all = planLocalBatches(times: times, window: const Duration(minutes: 5));
    final pairs = <String>{
      for (final b in all)
        for (final p in b.pairs) '${b.photos[p.a]}-${b.photos[p.b]}'
    };
    expect(pairs, {'0-1', '2-3'});
    final skipped = planLocalBatches(
        times: times,
        window: const Duration(minutes: 5),
        skip: (a, b) => a == 0 || b == 0);
    final p2 = <String>{
      for (final b in skipped)
        for (final p in b.pairs) '${b.photos[p.a]}-${b.photos[p.b]}'
    };
    expect(p2, {'2-3'});
  });

  test('planLocalBatches: không có ảnh hoặc một ảnh thì không có lô', () {
    expect(planLocalBatches(times: const []), isEmpty);
    expect(planLocalBatches(times: [t0]), isEmpty);
  });
}
