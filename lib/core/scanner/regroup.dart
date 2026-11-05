import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import '../../engines/lsh/candidate_index.dart';
import '../../engines/pdq/pdq_engine.dart';
import 'scan_session.dart';

/// Dữ liệu PDQ của một lần quét, giữ trong RAM để gom nhóm lại khi người dùng đổi
/// ngưỡng độ giống mà KHÔNG phải quét lại. [edges] chứa mọi cặp có Hamming
/// <= [maxEdgeHamming] (ngưỡng "tương tự" lúc quét), nên ngưỡng gom nhóm không được
/// vượt quá giá trị đó.
class PdqIndex {
  PdqIndex({
    required this.assets,
    required this.shas,
    required this.flat,
    required this.has,
    required this.edges,
    required this.maxEdgeHamming,
  });

  final List<AssetEntity> assets;
  final List<String?> shas;
  final Uint64List flat;
  final Uint8List has;
  final List<MatchEdge> edges;
  final int maxEdgeHamming;

  /// Ảnh đã bị xóa sau lúc quét: bỏ qua khi gom lại.
  final Set<String> removed = {};
}

/// Gom lại nhóm TRÙNG ở ngưỡng [maxHamming] (<= [PdqIndex.maxEdgeHamming]).
/// Cùng quy tắc với bước dựng nhóm lúc quét: nối cạnh có Hamming <= ngưỡng và ảnh
/// trùng SHA-256; ảnh lớn nhất/cũ nhất làm đại diện; chỉ giữ ảnh có Hamming TRỰC
/// TIẾP với đại diện <= ngưỡng (hoặc cùng SHA), không nối chuỗi qua ảnh khác.
List<DuplicateGroup> regroupDuplicates(PdqIndex idx, int maxHamming) {
  final n = idx.assets.length;
  final limit = maxHamming > idx.maxEdgeHamming ? idx.maxEdgeHamming : maxHamming;
  bool alive(int i) => !idx.removed.contains(idx.assets[i].id);

  final uf = UnionFind(n);
  final bySha = <String, int>{};
  for (var i = 0; i < n; i++) {
    final s = idx.shas[i];
    if (s == null || !alive(i)) continue;
    final first = bySha[s];
    if (first == null) {
      bySha[s] = i;
    } else {
      uf.union(first, i);
    }
  }
  for (final e in idx.edges) {
    if (e.distance <= limit && alive(e.a) && alive(e.b)) uf.union(e.a, e.b);
  }

  final byRoot = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    if (!alive(i)) continue;
    (byRoot[uf.find(i)] ??= <int>[]).add(i);
  }

  int? ham(int i, int j) => idx.has[i] == 1 && idx.has[j] == 1
      ? hammingFlat(idx.flat, i, j)
      : null;

  final groups = <DuplicateGroup>[];
  for (final members in byRoot.values) {
    if (members.length < 2) continue;
    members.sort((a, b) {
      final pa = idx.assets[a].width * idx.assets[a].height;
      final pb = idx.assets[b].width * idx.assets[b].height;
      if (pa != pb) return pb.compareTo(pa);
      return idx.assets[a].createDateTime.compareTo(idx.assets[b].createDateTime);
    });
    final rep = members.first;
    final items = <DuplicateItem>[];
    for (final m in members) {
      final exact = m != rep && idx.shas[m] != null && idx.shas[m] == idx.shas[rep];
      final h = m == rep ? 0 : ham(m, rep);
      if (m != rep && !exact && (h == null || h > limit)) continue;
      items.add(DuplicateItem(idx.assets[m],
          exact: exact, similarity: m == rep ? 100 : (h == null ? null : pdqSimilarity(h))));
    }
    if (items.length >= 2) groups.add(DuplicateGroup(items));
  }
  groups.sort((a, b) => b.items.length.compareTo(a.items.length));
  return groups;
}

/// Độ giống (%) <-> Hamming trên 256 bit của PDQ.
int hammingForSimilarity(double percent) => (256 * (1 - percent / 100)).floor();
double similarityForHamming(int h) => pdqSimilarity(h);
