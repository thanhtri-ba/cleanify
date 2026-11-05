import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

/// Bộ embedding cho bước AI: hiện là MobileNetV3-Large (torchvision, ImageNet),
/// ảnh 224x224 -> vector 960 chiều (sau global average pooling, bỏ classifier).
/// Xuất bằng tool/export_mobilenet_onnx.py; tiền xử lý phải khớp script đó:
/// RGB, chia 255, trừ mean [0.485, 0.456, 0.406], chia std [0.229, 0.224, 0.225].
/// Đổi sang MobileNetV2 thì đặt dinoDim = 1280 (script in ra số chiều).
/// Muốn quay lại DINO (chậm hơn nhiều): dinoDim = 384 và
/// dinoAsset = 'assets/models/dino.onnx'.
/// Tên `dino*` được giữ nguyên để không phá tool/calibrate, score_pairs và test.
const int dinoSize = 224;
const int dinoDim = 960;
const String dinoAsset = 'assets/models/mobilenet.onnx';

const _mean = [0.485, 0.456, 0.406];
const _std = [0.229, 0.224, 0.225];

final List<Float32List> _lut = [
  for (var c = 0; c < 3; c++)
    Float32List.fromList(
        [for (var v = 0; v < 256; v++) (v / 255.0 - _mean[c]) / _std[c]]),
];

/// Ảnh JPEG/PNG bytes -> tensor NCHW (3*224*224) hoặc null nếu không giải mã được.
Float32List? dinoPreprocess(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final rgb = decoded.numChannels == 3 ? decoded : decoded.convert(numChannels: 3);
  final small = (rgb.width == dinoSize && rgb.height == dinoSize)
      ? rgb
      : img.copyResize(
          rgb,
          width: dinoSize,
          height: dinoSize,
          interpolation: img.Interpolation.average,
        );
  const plane = dinoSize * dinoSize;
  final out = Float32List(3 * plane);
  // Đọc thẳng buffer byte RGB (không tạo Pixel cho từng điểm ảnh) + bảng tra
  // chuẩn hóa 256 giá trị/kênh: nhanh hơn nhiều so với getPixel + chia từng điểm.
  final rgbBytes = small.format == img.Format.uint8
      ? small.getBytes(order: img.ChannelOrder.rgb)
      : null;
  if (rgbBytes != null && rgbBytes.length == 3 * plane) {
    final lut = _lut;
    for (var i = 0, j = 0; i < plane; i++, j += 3) {
      out[i] = lut[0][rgbBytes[j]];
      out[plane + i] = lut[1][rgbBytes[j + 1]];
      out[2 * plane + i] = lut[2][rgbBytes[j + 2]];
    }
    return out;
  }
  for (var y = 0; y < dinoSize; y++) {
    for (var x = 0; x < dinoSize; x++) {
      final p = small.getPixel(x, y);
      final i = y * dinoSize + x;
      out[i] = (p.r / 255.0 - _mean[0]) / _std[0];
      out[plane + i] = (p.g / 255.0 - _mean[1]) / _std[1];
      out[2 * plane + i] = (p.b / 255.0 - _mean[2]) / _std[2];
    }
  }
  return out;
}

/// Tiền xử lý cả batch trong isolate riêng; phần tử null nếu ảnh lỗi/thiếu.
Future<List<Float32List?>> dinoPreprocessBatch(List<Uint8List?> thumbs) =>
    Isolate.run(() => [
          for (final t in thumbs)
            if (t == null) null else _safePreprocess(t)
        ]);

Float32List? _safePreprocess(Uint8List t) {
  try {
    return dinoPreprocess(t);
  } catch (_) {
    return null;
  }
}

class DinoEmbedder {
  OrtSession? _session;
  String _inName = '';
  String _outName = '';

  bool get loaded => _session != null;

  /// Ném lỗi nếu thiếu file model hoặc không khởi tạo được ONNX Runtime.
  Future<void> load() async {
    final ort = OnnxRuntime();
    final s = await ort.createSessionFromAsset(dinoAsset);
    _session = s;
    _inName = s.inputNames.first;
    _outName = s.outputNames.first;
  }

  /// Embedding đã L2-normalize cho từng ảnh trong [inputs] (mỗi phần tử là
  /// tensor 3*224*224 từ [dinoPreprocess]).
  Future<List<Float32List>> embed(List<Float32List> inputs) async {
    final s = _session;
    if (s == null) throw StateError('DinoEmbedder chưa load()');
    final b = inputs.length;
    const per = 3 * dinoSize * dinoSize;
    final flat = Float32List(b * per);
    for (var i = 0; i < b; i++) {
      flat.setRange(i * per, (i + 1) * per, inputs[i]);
    }
    final tensor =
        await OrtValue.fromList(flat, [b, 3, dinoSize, dinoSize]);
    Map<String, OrtValue>? outs;
    try {
      outs = await s.run({_inName: tensor});
      final raw = await outs[_outName]!.asList();
      final values = <double>[];
      _flatten(raw, values);
      if (values.length != b * dinoDim) {
        throw StateError('Đầu ra DINO có ${values.length} giá trị, '
            'kỳ vọng ${b * dinoDim} (batch $b x $dinoDim)');
      }
      return [
        for (var i = 0; i < b; i++)
          _l2(Float32List.fromList(values.sublist(i * dinoDim, (i + 1) * dinoDim)))
      ];
    } finally {
      await tensor.dispose();
      if (outs != null) {
        for (final o in outs.values) {
          await o.dispose();
        }
      }
    }
  }

  Future<void> close() async {
    final s = _session;
    _session = null;
    if (s != null) await s.close();
  }
}

void _flatten(dynamic x, List<double> out) {
  if (x is List) {
    for (final e in x) {
      _flatten(e, out);
    }
  } else if (x is num) {
    out.add(x.toDouble());
  }
}

Float32List _l2(Float32List v) {
  var s = 0.0;
  for (final x in v) {
    s += x * x;
  }
  final n = math.sqrt(s);
  if (n == 0) return v;
  for (var i = 0; i < v.length; i++) {
    v[i] = v[i] / n;
  }
  return v;
}
