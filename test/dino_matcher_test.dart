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
