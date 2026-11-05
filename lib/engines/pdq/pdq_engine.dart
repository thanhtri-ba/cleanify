import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Hash 256 bit kiểu PDQ: grayscale 64x64 -> DCT -> lấy 16x16 hệ số thấp
/// -> so với median -> 256 bit.
///
/// Lưu ý: đây là bản đơn giản hóa theo ý tưởng PDQ (không có Jarosz filter,
/// không có chuẩn hóa/quantize như bản gốc của Meta), nên KHÔNG tương thích
/// bit-by-bit với thư viện PDQ chính thức.
final List<Float64List> _cos = List.generate(
  16,
  (u) => Float64List.fromList(
    List.generate(64, (x) => math.cos(math.pi * (2 * x + 1) * u / 128)),
  ),
);

/// Trả về 4 word 64-bit, hoặc null nếu không giải mã được ảnh.
Uint64List? pdqHash(Uint8List imageBytes) {
  final decoded = img.decodeImage(imageBytes);
  if (decoded == null) return null;
  final small = img.copyResize(
    decoded,
    width: 64,
    height: 64,
    interpolation: img.Interpolation.average,
  );

  final lum = Float64List(64 * 64);
  // Đọc thẳng buffer byte (nhanh hơn nhiều so với getPixel từng điểm); giá trị
  // luminance giống hệt đường getPixel nên hash không đổi.
  final rgb = small.format == img.Format.uint8
      ? small.getBytes(order: img.ChannelOrder.rgb)
      : null;
  if (rgb != null && rgb.length == 3 * 64 * 64) {
    for (var i = 0, j = 0; i < 64 * 64; i++, j += 3) {
      lum[i] = 0.299 * rgb[j] + 0.587 * rgb[j + 1] + 0.114 * rgb[j + 2];
    }
  } else {
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        final p = small.getPixel(x, y);
        lum[y * 64 + x] = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      }
    }
  }

  // DCT tách hàng/cột, chỉ tính 16 tần số thấp.
  final tmp = Float64List(64 * 16);
  for (var y = 0; y < 64; y++) {
    for (var u = 0; u < 16; u++) {
      var s = 0.0;
      final c = _cos[u];
      for (var x = 0; x < 64; x++) {
        s += lum[y * 64 + x] * c[x];
      }
      tmp[y * 16 + u] = s;
    }
  }
  final coeff = Float64List(256);
  for (var v = 0; v < 16; v++) {
    final c = _cos[v];
    for (var u = 0; u < 16; u++) {
      var s = 0.0;
      for (var y = 0; y < 64; y++) {
        s += tmp[y * 16 + u] * c[y];
      }
      coeff[v * 16 + u] = s;
    }
  }

  final sorted = Float64List.fromList(coeff)..sort();
  final median = (sorted[127] + sorted[128]) / 2;
  final words = Uint64List(4);
  for (var i = 0; i < 256; i++) {
    if (coeff[i] > median) {
      words[i >> 6] |= (1 << (i & 63));
    }
  }
  return words;
}

int popcount64(int x) {
  x = x - ((x >>> 1) & 0x5555555555555555);
  x = (x & 0x3333333333333333) + ((x >>> 2) & 0x3333333333333333);
  x = (x + (x >>> 4)) & 0x0f0f0f0f0f0f0f0f;
  return (x * 0x0101010101010101) >>> 56;
}

/// Hamming distance giữa hash thứ [i] và [j] trong mảng phẳng (4 word/hash).
int hammingFlat(Uint64List flat, int i, int j) {
  var d = 0;
  for (var k = 0; k < 4; k++) {
    d += popcount64(flat[i * 4 + k] ^ flat[j * 4 + k]);
  }
  return d;
}

/// S_PDQ = 100 * (1 - D_H / 256). Là độ giống của bit hash, không phải % nội dung.
double pdqSimilarity(int hamming) => 100 * (1 - hamming / 256);
