import 'dart:typed_data';

import '../pdq/pdq_engine.dart';

class MatchEdge {
  const MatchEdge(this.a, this.b, this.distance);
  final int a;
  final int b;
  final int distance;
}

/// LSH kiểu band: chia 256 bit thành 16 band x 16 bit. Hai ảnh là ứng viên
/// nếu trùng ít nhất một band. Chỉ đảm bảo bắt được mọi cặp có Hamming <= 15;
/// với ngưỡng cao hơn, recall là xác suất (cần benchmark).
///
/// [flat]: 4 word/ảnh. [has]: 1 nếu ảnh có hash. Bucket quá lớn (ảnh trắng/đen
/// hoặc ảnh gần như đồng nhất) bị bỏ qua để tránh bùng nổ số cặp.
List<MatchEdge> findNearEdges({
  required Uint64List flat,
  required Uint8List has,
  required int n,
  required int maxHamming,
  int maxBucket = 48,
  int exactBelow = 6000,
}) {
  final edges = <MatchEdge>[];
  // Thư viện không quá lớn: so mọi cặp, không bỏ sót cặp nào (kể cả Hamming
  // cao, nơi LSH chỉ bắt được theo xác suất). ~18 triệu phép so cho 6000 ảnh.
  if (n <= exactBelow) {
    for (var i = 0; i < n; i++) {
      if (has[i] == 0) continue;
      for (var j = i + 1; j < n; j++) {
        if (has[j] == 0) continue;
        final d = hammingFlat(flat, i, j);
        if (d <= maxHamming) edges.add(MatchEdge(i, j, d));
      }
    }
    return edges;
  }
  final seen = <int>{};
  for (var band = 0; band < 16; band++) {
    final word = band >> 2;
    final shift = (band & 3) * 16;
    final buckets = <int, List<int>>{};
    for (var i = 0; i < n; i++) {
      if (has[i] == 0) continue;
      final key = (flat[i * 4 + word] >>> shift) & 0xFFFF;
      (buckets[key] ??= <int>[]).add(i);
    }
    for (final bucket in buckets.values) {
      if (bucket.length < 2 || bucket.length > maxBucket) continue;
      for (var x = 0; x < bucket.length; x++) {
        for (var y = x + 1; y < bucket.length; y++) {
          final i = bucket[x];
          final j = bucket[y];
          if (!seen.add(i * n + j)) continue;
          final d = hammingFlat(flat, i, j);
          if (d <= maxHamming) edges.add(MatchEdge(i, j, d));
        }
      }
    }
  }
  return edges;
}

class UnionFind {
  UnionFind(int n) : _p = List<int>.generate(n, (i) => i);
  final List<int> _p;

  int find(int x) {
    while (_p[x] != x) {
      _p[x] = _p[_p[x]];
      x = _p[x];
    }
    return x;
  }

  void union(int a, int b) {
    final ra = find(a);
    final rb = find(b);
    if (ra != rb) _p[rb] = ra;
  }
}
