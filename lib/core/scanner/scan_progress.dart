import 'scan_mode.dart';

enum ScanPhase { reading, matching, exact, embedding, features }

class ScanProgress {
  const ScanProgress(this.phase, this.done, this.total, {this.paused = false});
  final ScanPhase phase;
  final int done;
  final int total;
  final bool paused;

  double? get fraction => total == 0 ? null : done / total;

  String get label {
    switch (phase) {
      case ScanPhase.reading:
        return 'Đang băm ảnh $done/$total';
      case ScanPhase.matching:
        return 'Đang so khớp ứng viên…';
      case ScanPhase.exact:
        return 'Đang đối chiếu file gốc $done/$total';
      case ScanPhase.embedding:
        return 'Đang phân tích AI $done/$total';
      case ScanPhase.features:
        return 'Đang so khớp điểm đặc trưng $done/$total';
    }
  }
}

/// "03:25" khi dưới 1 giờ, "1:02:03" khi từ 1 giờ trở lên.
String formatElapsed(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Thứ tự các giai đoạn THEO THỜI GIAN trong một lần quét (khác thứ tự enum).
const List<ScanPhase> _phaseOrder = [
  ScanPhase.reading,
  ScanPhase.matching,
  ScanPhase.exact,
  ScanPhase.features,
  ScanPhase.embedding,
];

/// Tỉ trọng thời gian của từng giai đoạn SẼ CHẠY theo [mode], cộng lại bằng 1.
/// Giai đoạn không chạy có trọng số 0 nên không chiếm phần nào của thanh tiến độ.
/// Con số lấy từ hệ số ước tính trong scan_mode.dart (đọc+băm ~6 ms/ảnh, AI ~30 ms/ảnh).
Map<ScanPhase, double> phaseWeights(ScanMode mode) {
  if (mode.duplicates && mode.similar) {
    return {
      ScanPhase.reading: .15,
      ScanPhase.matching: .05,
      ScanPhase.exact: .10,
      ScanPhase.features: 0,
      ScanPhase.embedding: .70,
    };
  }
  if (mode.similar) {
    return {
      ScanPhase.reading: .20,
      ScanPhase.matching: .02,
      ScanPhase.exact: 0,
      ScanPhase.features: 0,
      ScanPhase.embedding: .78,
    };
  }
  return {
    ScanPhase.reading: .60,
    ScanPhase.matching: .15,
    ScanPhase.exact: .25,
    ScanPhase.features: 0,
    ScanPhase.embedding: 0,
  };
}

/// Tiến độ TỔNG (0..1) của lần quét. Chỉ tăng theo giai đoạn đã xong cộng phần đang
/// chạy; giai đoạn "so khớp" không có tiến độ con nên coi là 0 cho tới khi giai đoạn
/// sau bắt đầu. Không bao giờ trả về 1: 100% chỉ có khi quét thật sự xong.
double overallProgress(ScanMode mode, ScanProgress p) {
  final w = phaseWeights(mode);
  var before = 0.0;
  for (final ph in _phaseOrder) {
    if (ph == p.phase) break;
    before += w[ph] ?? 0;
  }
  final inPhase = p.phase == ScanPhase.matching ? 0.0 : (p.fraction ?? 0.0).clamp(0.0, 1.0);
  return (before + (w[p.phase] ?? 0) * inPhase).clamp(0.0, 0.99);
}
