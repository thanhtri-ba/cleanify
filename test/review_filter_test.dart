import 'package:flutter_test/flutter_test.dart';
import 'package:cleanify/features/scan/review_filter.dart';

void main() {
  test('activeCount đếm đúng số bộ lọc bật', () {
    expect(const ReviewFilter().activeCount, 0);
    expect(const ReviewFilter(size: SizeBand.two, hideFavorites: true).activeCount, 2);
    expect(const ReviewFilter(size: SizeBand.two).copyWith(size: SizeBand.all).isActive, false);
  });
}
