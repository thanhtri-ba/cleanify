import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cleanify/engines/dino/dino_engine.dart';
import 'package:cleanify/engines/dino/dino_matcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// n vector ngẫu nhiên L2-normalize; các cặp trong [planted] được ghi đè bằng
/// bản gần giống (nhiễu rất nhỏ) của vector đầu cặp.
Float32List _make(int n, int dim, Map<int, int> planted, {int seed = 7}) {
  final rnd = math.Random(seed);
  final v = Float32List(n * dim);
  for (var i = 0; i < n * dim; i++) {
    // xấp xỉ Gaussian: tổng 4 giá trị đều
    v[i] = (rnd.nextDouble() + rnd.nextDouble() + rnd.nextDouble() +
            rnd.nextDouble() - 2) *
        1.7;
  }
  planted.forEach((a, b) {
    for (var k = 0; k < dim; k++) {
      v[b * dim + k] = v[a * dim + k] + (rnd.nextDouble() - 0.5) * 0.02;
    }
  });
  for (var i = 0; i < n; i++) {
    var s = 0.0;
    for (var k = 0; k < dim; k++) {
      s += v[i * dim + k] * v[i * dim + k];
    }
    final norm = math.sqrt(s);
    for (var k = 0; k < dim; k++) {
      v[i * dim + k] /= norm;
    }
  }
  return v;
}

void main() {
  topKTests();
  test('findDinoEdges (so mọi cặp) tìm đúng cặp gần giống', () {
    const dim = 64;
    final emb = _make(30, dim, {3: 1, 20: 10});
    final edges = findDinoEdges(emb: emb, n: 30, dim: dim, minCos: 0.95);
    final pairs = {for (final e in edges) '${e.a}-${e.b}'};
    expect(pairs, {'1-3', '10-20'});
    for (final e in edges) {
      expect(e.cos, greaterThanOrEqualTo(0.95));
    }
  });

  test('nhánh LSH không có cặp sai và bắt được cặp rất giống', () {
    const dim = 384;
    const n = 300;
    final planted = {for (var i = 0; i < 20; i++) 100 + i: i};
    final emb = _make(n, dim, planted);
    final exact = findDinoEdges(
        emb: emb, n: n, dim: dim, minCos: 0.9, exactBelow: 100000);
    final lsh =
        findDinoEdges(emb: emb, n: n, dim: dim, minCos: 0.9, exactBelow: 0);
    final exactSet = {for (final e in exact) '${e.a}-${e.b}'};
    final lshSet = {for (final e in lsh) '${e.a}-${e.b}'};
    expect(lshSet.difference(exactSet), isEmpty);
    expect(lshSet.length, exactSet.length);
    expect(exactSet.length, 20);
  });

  test('cosineOf trả null khi thiếu embedding', () {
    final a = Float32List.fromList([1, 0]);
    expect(cosineOf(a, null), isNull);
    expect(cosineOf(a, Float32List.fromList([0, 1])), 0);
    expect(cosineOf(a, a), 1);
  });

  test('centerEmbeddings: bỏ thành phần chung, giữ độ giống của cặp thật', () {
    // Vector đều dương (như MobileNet sau pooling): ai cũng có cosine thô cao.
    const dim = 64;
    const n = 60;
    final rnd = math.Random(3);
    final raw = <int, Float32List>{};
    for (var i = 0; i < n; i++) {
      final v = Float32List(dim);
      var s = 0.0;
      for (var k = 0; k < dim; k++) {
        v[k] = 5.0 + rnd.nextDouble();
        s += v[k] * v[k];
      }
      final norm = math.sqrt(s);
      for (var k = 0; k < dim; k++) {
        v[k] /= norm;
      }
      raw[i] = v;
    }
    // Ảnh 1 là bản nhiễu rất nhỏ của ảnh 0.
    final dup = Float32List.fromList(
        [for (var k = 0; k < dim; k++) raw[0]![k] + (rnd.nextDouble() - 0.5) * 0.001]);
    raw[1] = dup;

    final rawUnrelated = cosineOf(raw[2], raw[3])!;
    expect(rawUnrelated, greaterThan(0.9)); // cosine thô: ảnh bất kỳ cũng cao

    final c = centerEmbeddings(raw);
    expect(cosineOf(c[0], c[1])!, greaterThan(0.9)); // cặp thật vẫn giống
    expect(cosineOf(c[2], c[3])!.abs(), lessThan(0.6)); // cặp lạ bị tách ra
    for (final v in c.values) {
      expect(cosineOf(v, v)!, closeTo(1, 1e-4)); // vẫn L2-normalize
    }
    expect(centerEmbeddings({}), isEmpty);
  });

  test('dinoPreprocess ra tensor NCHW 3x224x224 đã chuẩn hóa', () {
    final bytes = Uint8List.fromList(
        img.encodeJpg(img.Image(width: dinoSize, height: dinoSize)));
    final t = dinoPreprocess(bytes)!;
    expect(t.length, 3 * dinoSize * dinoSize);
    // ảnh đen: (0 - mean) / std
    expect(t[0], closeTo(-0.485 / 0.229, 0.1));
    expect(t[dinoSize * dinoSize], closeTo(-0.456 / 0.224, 0.1));
    expect(dinoPreprocess(Uint8List.fromList([1, 2, 3])), isNull);
  });
}

void topKTests() {
  group('findTopKEdges', () {
    test('mỗi ảnh nối với hàng xóm gần nhất, bỏ cạnh dưới ngưỡng', () {
      // 4 vector 2 chiều đã chuẩn hóa: 0~1 gần nhau, 2~3 gần nhau, hai cụm vuông góc.
      final v = [
        [1.0, 0.0],
        [0.98, 0.199],
        [0.0, 1.0],
        [0.199, 0.98],
      ];
      final emb = Float32List.fromList([for (final r in v) ...r]);
      final edges = findTopKEdges(emb: emb, n: 4, dim: 2, k: 1, minCos: 0.5);
      final keys = edges.map((e) => '${e.a}-${e.b}').toSet();
      expect(keys, {'0-1', '2-3'});
    });

    test('k giới hạn số cạnh mỗi ảnh', () {
      final emb = Float32List.fromList(List.filled(10 * 2, 0.7071));
      final edges = findTopKEdges(emb: emb, n: 10, dim: 2, k: 2, minCos: 0.5);
      expect(edges.length, lessThanOrEqualTo(10 * 2));
    });
  });
}
