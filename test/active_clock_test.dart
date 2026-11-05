import 'package:cleanify/core/scanner/active_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('không tính thời gian khi ra nền', () async {
    final c = ActiveClock()..start();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    c.setForeground(false);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    c.setForeground(true);
    expect(c.elapsed.inMilliseconds, lessThan(180));
    expect(c.backgroundTime.inMilliseconds, greaterThanOrEqualTo(190));
  });

  test('tạm dừng thì không chạy, ra nền lúc đang dừng không tính nền', () async {
    final c = ActiveClock()..start();
    c.stop();
    c.setForeground(false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.isRunning, isFalse);
    expect(c.backgroundTime.inMilliseconds, lessThan(20));
    c.setForeground(true);
    expect(c.isRunning, isFalse);
    c.start();
    expect(c.isRunning, isTrue);
  });

  test('ra nền lúc chưa start rồi start vẫn đúng', () {
    final c = ActiveClock()..setForeground(false);
    c.start();
    expect(c.isRunning, isFalse);
    c.setForeground(true);
    expect(c.isRunning, isTrue);
  });
}
