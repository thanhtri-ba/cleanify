import 'dart:math' as math;
import 'dart:typed_data';

import '../lsh/candidate_index.dart';

class CosEdge {
  const CosEdge(this.a, this.b, this.cos);
  final int a;
  final int b;
  final double cos;
}

/// Tích vô hướng hai vector con dài [dim] trong mảng phẳng [emb] (đã L2-normalize
/// nên bằng cosine).
double dotRows(Float32List emb, int i, int j, int dim) {
  var s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0;
  final bi = i * dim;
  final bj = j * dim;
  var k = 0;
  for (; k + 3 < dim; k += 4) {
    s0 += emb[bi + k] * emb[bj + k];
    s1 += emb[bi + k + 1] * emb[bj + k + 1];
    s2 += emb[bi + k + 2] * emb[bj + k + 2];
    s3 += emb[bi + k + 3] * emb[bj + k + 3];
  }
  for (; k < dim; k++) {
    s0 += emb[bi + k] * emb[bj + k];
  }
  return s0 + s1 + s2 + s3;
}

/// Cosine giữa hai embedding đã L2-normalize; null nếu thiếu một trong hai.
double? cosineOf(Float32List? a, Float32List? b) {
  if (a == null || b == null || a.length != b.length) return null;
  var s = 0.0;
  for (var k = 0; k < a.length; k++) {
    s += a[k] * b[k];
  }
  return s;
}

/// Trừ vector trung bình của [emb] khỏi từng embedding rồi L2-normalize lại.
/// Đặc trưng sau pooling (vd. MobileNet) đều dương nên cosine giữa hai ảnh bất
/// kỳ đã cao; trừ trung bình của một mẫu đủ rộng loại bỏ thành phần chung đó.
/// Cần mẫu đủ lớn: với 2 vector, trung bình nằm giữa chúng và cosine thành -1.
Map<int, Float32List> centerEmbeddings(Map<int, Float32List> emb) {
  if (emb.isEmpty) return {};
  final dim = emb.values.first.length;
  final mean = Float64List(dim);
  for (final v in emb.values) {
    for (var k = 0; k < dim; k++) {
      mean[k] += v[k];
    }
  }
  final inv = 1.0 / emb.length;
  for (var k = 0; k < dim; k++) {
    mean[k] *= inv;
  }
  final out = <int, Float32List>{};
  emb.forEach((i, v) {
    final c = Float32List(dim);
    var s = 0.0;
    for (var k = 0; k < dim; k++) {
      final x = v[k] - mean[k];
      c[k] = x;
      s += x * x;
    }
    final norm = math.sqrt(s);
    if (norm > 0) {
      for (var k = 0; k < dim; k++) {
        c[k] = c[k] / norm;
      }
    }
    out[i] = c;
  });
  return out;
}

/// Tìm mọi cặp có cosine >= [minCos] trong [n] embedding (mảng phẳng [n*dim],
/// đã L2-normalize).
///
/// n <= [exactBelow]: so mọi cặp, không bỏ sót. Lớn hơn: lấy ứng viên bằng
/// random-hyperplane LSH (256 bit, dùng lại [findNearEdges]) rồi kiểm lại bằng
/// cosine thật, nên recall chỉ là xác suất (kết quả không có cặp sai thêm).
List<CosEdge> findDinoEdges({
  required Float32List emb,
  required int n,
  required int dim,
  required double minCos,
  int exactBelow = 8000,
}) {
  final edges = <CosEdge>[];
  if (n < 2) return edges;
  if (n <= exactBelow) {
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final c = dotRows(emb, i, j, dim);
        if (c >= minCos) edges.add(CosEdge(i, j, c));
      }
    }
    return edges;
  }

  // Chiếu ngẫu nhiên (seed cố định để kết quả lặp lại được) -> 256 bit dấu.
  final rnd = math.Random(0xC1EA);
  final proj = Float32List(256 * dim);
  for (var i = 0; i < proj.length; i += 2) {
    final u1 = 1.0 - rnd.nextDouble();
    final u2 = rnd.nextDouble();
    final r = math.sqrt(-2.0 * math.log(u1));
    proj[i] = r * math.cos(2 * math.pi * u2);
    if (i + 1 < proj.length) proj[i + 1] = r * math.sin(2 * math.pi * u2);
  }
  final flat = Uint64List(n * 4);
  for (var i = 0; i < n; i++) {
    for (var b = 0; b < 256; b++) {
      var s = 0.0;
      final pb = b * dim;
      final ei = i * dim;
      for (var k = 0; k < dim; k++) {
        s += proj[pb + k] * emb[ei + k];
      }
      if (s > 0) flat[i * 4 + (b >> 6)] |= (1 << (b & 63));
    }
  }
  // cos = minCos ứng với góc θ; mỗi bit khác nhau với xác suất θ/π.
  // Lấy ứng viên rộng (trung bình + ~6 độ lệch chuẩn), rồi lọc bằng cosine thật.
  final theta = math.acos(minCos.clamp(-1.0, 1.0));
  final p = theta / math.pi;
  final maxHamming =
      (256 * p + 6 * math.sqrt(256 * p * (1 - p))).ceil().clamp(1, 256).toInt();
  final cand = findNearEdges(
    flat: flat,
    has: Uint8List(n)..fillRange(0, n, 1),
    n: n,
    maxHamming: maxHamming,
    exactBelow: 0,
  );
  for (final e in cand) {
    final c = dotRows(emb, e.a, e.b, dim);
    if (c >= minCos) edges.add(CosEdge(e.a, e.b, c));
  }
  return edges;
}

/// Với mỗi ảnh, lấy [k] hàng xóm có cosine cao nhất và >= [minCos]; trả về cạnh
/// (a < b) xuất hiện ở top-k của ít nhất một đầu. Giới hạn bậc nên không bùng nổ số
/// cạnh trên thư viện lớn (khác ngưỡng toàn cục). Exact O(n^2*dim) khi n <=
/// [exactBelow]; lớn hơn thì lấy ứng viên bằng [findDinoEdges] ở ngưỡng cao hơn
/// (>= 0.5) rồi cắt top-k (recall thấp hơn nhưng chạy được).
List<CosEdge> findTopKEdges({
  required Float32List emb,
  required int n,
  required int dim,
  required int k,
  required double minCos,
  int exactBelow = 6000,
  bool mutual = true,
}) {
  if (n < 2 || k < 1) return [];
  final bestCos = List<Float64List>.generate(n, (_) {
    final f = Float64List(k);
    f.fillRange(0, k, -2.0);
    return f;
  });
  final bestIdx = List<Int32List>.generate(n, (_) => Int32List(k)..fillRange(0, k, -1));

  void push(int i, int j, double c) {
    final cs = bestCos[i];
    if (c <= cs[k - 1]) return;
    final ix = bestIdx[i];
    var p = k - 1;
    while (p > 0 && cs[p - 1] < c) {
      cs[p] = cs[p - 1];
      ix[p] = ix[p - 1];
      p--;
    }
    cs[p] = c;
    ix[p] = j;
  }

  if (n <= exactBelow) {
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final c = dotRows(emb, i, j, dim);
        push(i, j, c);
        push(j, i, c);
      }
    }
  } else {
    final cand = findDinoEdges(
        emb: emb, n: n, dim: dim, minCos: math.max(minCos, 0.5), exactBelow: 0);
    for (final e in cand) {
      push(e.a, e.b, e.cos);
      push(e.b, e.a, e.cos);
    }
  }

  // Đếm số đầu có cạnh trong top-k của mình; mutual => cần cả hai đầu (tránh chuỗi
  // A~B~C~D gom cả cụm ảnh cùng "loại cảnh" nhưng khác nhau).
  final votes = <int, int>{};
  final cosOf = <int, double>{};
  for (var i = 0; i < n; i++) {
    for (var p = 0; p < k; p++) {
      final j = bestIdx[i][p];
      final c = bestCos[i][p];
      if (j < 0 || c < minCos) continue;
      final int key = i < j ? i * n + j : j * n + i;
      votes[key] = (votes[key] ?? 0) + 1;
      cosOf[key] = c;
    }
  }
  final need = mutual ? 2 : 1;
  return [
    for (final e in votes.entries)
      if (e.value >= need) CosEdge(e.key ~/ n, e.key % n, cosOf[e.key]!),
  ];
}
