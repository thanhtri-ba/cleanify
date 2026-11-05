import 'dart:typed_data';

import 'package:cleanify/core/scanner/regroup.dart';
import 'package:cleanify/engines/lsh/candidate_index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

AssetEntity _a(String id, {int w = 100}) =>
    AssetEntity(id: id, typeInt: 1, width: w, height: 100);

/// Hash 256 bit: [bits] bit đầu bằng 1, còn lại 0 -> Hamming giữa hai hash là hiệu số bit.
Uint64List _hashes(List<int> ones) {
  final f = Uint64List(ones.length * 4);
  for (var i = 0; i < ones.length; i++) {
    for (var b = 0; b < ones[i]; b++) {
      f[i * 4 + (b >> 6)] |= (1 << (b & 63));
    }
  }
  return f;
}

PdqIndex _index(List<int> ones, List<MatchEdge> edges) => PdqIndex(
      assets: [for (var i = 0; i < ones.length; i++) _a('p$i', w: 100 - i)],
      shas: List<String?>.filled(ones.length, null),
      flat: _hashes(ones),
      has: Uint8List.fromList(List.filled(ones.length, 1)),
      edges: edges,
      maxEdgeHamming: 70,
    );

void main() {
  group('regroupDuplicates', () {
    // p0 = 0 bit, p1 = 20 bit (Hamming 20 so với p0), p2 = 50 bit (Hamming 50).
    final idx = _index([0, 20, 50], [
      const MatchEdge(0, 1, 20),
      const MatchEdge(0, 2, 50),
      const MatchEdge(1, 2, 30),
    ]);

    test('ngưỡng chặt chỉ gom cặp gần nhau', () {
      final g = regroupDuplicates(idx, 32);
      expect(g.length, 1);
      expect(g.first.items.map((e) => e.asset.id), ['p0', 'p1']);
    });

    test('ngưỡng rộng gom thêm ảnh; chỉ giữ ảnh gần đại diện', () {
      final g = regroupDuplicates(idx, 50);
      expect(g.length, 1);
      expect(g.first.items.map((e) => e.asset.id), ['p0', 'p1', 'p2']);
      expect(g.first.items.last.similarity, closeTo(100 * (1 - 50 / 256), 1e-9));
    });

    test('ảnh đã xóa bị bỏ qua', () {
      final i2 = _index([0, 20, 50], idx.edges)..removed.add('p1');
      final g = regroupDuplicates(i2, 50);
      expect(g.single.items.map((e) => e.asset.id), ['p0', 'p2']);
    });

    test('ngưỡng không vượt quá ngưỡng cạnh lúc quét', () {
      expect(regroupDuplicates(idx, 200).length, 1);
    });
  });

  test('hammingForSimilarity', () {
    expect(hammingForSimilarity(87.5), 32);
    expect(hammingForSimilarity(100), 0);
  });
}
