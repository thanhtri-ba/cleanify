import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cleanify/engines/lsh/candidate_index.dart';
import 'package:cleanify/engines/pdq/pdq_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _jpg(int w, int h, int Function(int x, int y) f) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = f(x, y).clamp(0, 255);
      im.setPixelRgb(x, y, v, v, v);
    }
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 85));
}

void main() {
  test('popcount64', () {
    expect(popcount64(0), 0);
    expect(popcount64(-1), 64); // toàn bit 1
    expect(popcount64(0xF0F0), 8);
  });

  test('PDQ: ảnh resize/nén gần giống, ảnh khác hẳn thì xa', () {
    Uint8List base(int w, int h) =>
        _jpg(w, h, (x, y) => ((x / w) * 200 + math.sin(y / h * 9) * 40 + 30).round());
    final a = pdqHash(base(256, 256))!;
    final b = pdqHash(base(128, 128))!; // cùng nội dung, nhỏ hơn
    final c = pdqHash(_jpg(256, 256, (x, y) => ((x ~/ 16 + y ~/ 16) % 2) * 220))!; // bàn cờ

    final flat = Uint64List(12)
      ..setRange(0, 4, a)
      ..setRange(4, 8, b)
      ..setRange(8, 12, c);
    final dAB = hammingFlat(flat, 0, 1);
    final dAC = hammingFlat(flat, 0, 2);
    expect(dAB, lessThan(32));
    expect(dAC, greaterThan(dAB));
  });

  test('LSH tìm đúng cặp gần nhau và bỏ qua cặp xa', () {
    final rnd = math.Random(7);
    const n = 200;
    final flat = Uint64List(n * 4);
    for (var i = 0; i < flat.length; i++) {
      flat[i] = (rnd.nextInt(1 << 32) << 32) | rnd.nextInt(1 << 32);
    }
    // ảnh 1 = ảnh 0 lật 5 bit
    for (var k = 0; k < 4; k++) {
      flat[4 + k] = flat[k];
    }
    flat[4] ^= 0x1F;
    final has = Uint8List(n)..fillRange(0, n, 1);

    final edges = findNearEdges(flat: flat, has: has, n: n, maxHamming: 24);
    expect(edges.any((e) => e.a == 0 && e.b == 1 && e.distance == 5), isTrue);
    expect(edges.where((e) => e.a > 1 || e.b > 1).isEmpty, isTrue);
  });

  test('ngưỡng 84%: cặp Hamming 40 được bắt, Hamming 41 thì không', () {
    final rnd = math.Random(11);
    const n = 100;
    final flat = Uint64List(n * 4);
    for (var i = 0; i < flat.length; i++) {
      flat[i] = (rnd.nextInt(1 << 32) << 32) | rnd.nextInt(1 << 32);
    }
    // ảnh 1 = ảnh 0 lật đúng 40 bit; ảnh 3 = ảnh 2 lật đúng 41 bit
    void flip(int src, int dst, int bits) {
      for (var k = 0; k < 4; k++) {
        flat[dst * 4 + k] = flat[src * 4 + k];
      }
      for (var b = 0; b < bits; b++) {
        flat[dst * 4 + (b >> 6)] ^= (1 << (b & 63));
      }
    }

    flip(0, 1, 40);
    flip(2, 3, 41);
    final has = Uint8List(n)..fillRange(0, n, 1);
    final edges = findNearEdges(flat: flat, has: has, n: n, maxHamming: 40);
    expect(edges.any((e) => e.a == 0 && e.b == 1 && e.distance == 40), isTrue);
    expect(edges.any((e) => e.a == 2 && e.b == 3), isFalse);
    expect(pdqSimilarity(40), closeTo(84.375, 1e-9));
  });

  test('UnionFind', () {
    final uf = UnionFind(5)..union(0, 1)..union(1, 2);
    expect(uf.find(0), uf.find(2));
    expect(uf.find(3), isNot(uf.find(0)));
  });
}
