import 'dart:math' as math;
import 'dart:typed_data';

/// Một cặp ảnh, theo chỉ số trong danh sách ảnh của lô.
class LocalPair {
  const LocalPair(this.a, this.b);
  final int a;
  final int b;
}

/// So khớp điểm đặc trưng cục bộ (ORB + RANSAC). Chịu được crop, zoom, nét vẽ,
/// chụp lệch khung, những ca mà hash PDQ và embedding toàn ảnh bỏ sót.
///
/// Phần cài đặt dùng OpenCV nằm ngoài lib/ (xem spike/opencv_local_matcher.dart.txt)
/// để app vẫn biên dịch khi chưa thêm thư viện OpenCV.
abstract class LocalFeatureMatcher {
  /// Với mỗi cặp trong [pairs] (chỉ số vào [photos], mỗi phần tử là JPEG/PNG đã
  /// thu nhỏ), trả về số điểm khớp đã qua RANSAC (inlier); 0 nếu không khớp hoặc
  /// không đủ điểm. Độ dài kết quả bằng [pairs].
  Future<List<int>> matchPairs(List<Uint8List> photos, List<LocalPair> pairs);
}

/// Một lô công việc: các ảnh cần đọc (chỉ số trong thư viện) và các cặp cần so
/// (chỉ số vào [photos]).
class LocalBatch {
  const LocalBatch(this.photos, this.pairs);
  final List<int> photos;
  final List<LocalPair> pairs;
}

/// Chọn cặp ứng viên theo thời gian chụp: mỗi ảnh chỉ so với tối đa [neighbors]
/// ảnh kế tiếp trong dãy đã sắp theo thời gian và cách nhau không quá [window].
/// Mỗi cặp xuất hiện đúng một lần. Cặp có [skip] = true (vd. đã cùng nhóm) bị bỏ.
///
/// Chia thành lô [stride] ảnh để không phải giữ cả thư viện trong bộ nhớ.
List<LocalBatch> planLocalBatches({
  required List<DateTime> times,
  int neighbors = 6,
  Duration window = const Duration(minutes: 5),
  int stride = 16,
  bool Function(int a, int b)? skip,
}) {
  final n = times.length;
  final order = List<int>.generate(n, (i) => i)
    ..sort((a, b) {
      final c = times[a].compareTo(times[b]);
      return c != 0 ? c : a.compareTo(b);
    });
  final out = <LocalBatch>[];
  for (var s = 0; s < n; s += stride) {
    final pos = <(int, int)>[];
    final pEnd = math.min(s + stride, n);
    for (var p = s; p < pEnd; p++) {
      final qEnd = math.min(p + neighbors, n - 1);
      for (var q = p + 1; q <= qEnd; q++) {
        final a = order[p];
        final b = order[q];
        // Đã sắp theo thời gian: ảnh sau chỉ có thể xa hơn.
        if (times[b].difference(times[a]) > window) break;
        if (skip != null && skip(a, b)) continue;
        pos.add((p, q));
      }
    }
    if (pos.isEmpty) continue;
    final used = <int>{for (final e in pos) ...[e.$1, e.$2]}.toList()..sort();
    final idx = {for (var k = 0; k < used.length; k++) used[k]: k};
    out.add(LocalBatch(
      [for (final p in used) order[p]],
      [for (final e in pos) LocalPair(idx[e.$1]!, idx[e.$2]!)],
    ));
  }
  return out;
}
