import 'dart:math' as math;

/// Kiểu quét người dùng chọn trước khi bắt đầu. Chỉ phần được chọn mới chạy.
class ScanMode {
  const ScanMode({this.duplicates = true, this.similar = false});

  /// Ảnh trùng / gần trùng: PDQ + SHA-256 (nhanh, là phần có chức năng xóa).
  final bool duplicates;

  /// Ảnh tương tự (cùng cảnh): embedding AI MobileNetV3 (chậm hơn nhiều).
  final bool similar;

  bool get any => duplicates || similar;
}

// Hệ số ước tính thời gian. Phần ảnh trùng đo từ lần quét 2880 ảnh trên bản DEBUG:
// đọc+băm ~6,3 ms/ảnh, so khớp mọi cặp ~6 µs/cặp. Phần AI (~30 ms/ảnh) là ƯỚC
// ĐOÁN, CHƯA đo. Bản profile/release thường nhanh hơn nên số hiển thị chỉ là mốc
// tham khảo; màn quét tự cập nhật ETA thật theo tiến độ.
const double _readMsPerPhoto = 6.3;
const double _pairUs = 6.0;
const double _shaFraction = 0.10; // tỷ lệ ảnh nghi trùng khít cần export file gốc
const double _shaMsPerPhoto = 15.0;
const double _aiMsPerPhoto = 30.0;
const int _exactPairsBelow = 30000;

/// Thời gian quét dự kiến cho [photos] ảnh theo [mode].
Duration estimateScan(int photos, ScanMode mode) {
  if (photos <= 0 || !mode.any) return Duration.zero;
  var ms = 0.0;
  // Quét tương tự vẫn phải chạy bước trùng để loại ảnh trùng khỏi kết quả.
  if (mode.any) {
    final m = math.min(photos, _exactPairsBelow);
    final pairs = m * (m - 1) / 2;
    ms += photos * _readMsPerPhoto +
        pairs * _pairUs / 1000 +
        photos * _shaFraction * _shaMsPerPhoto;
  }
  if (mode.similar) ms += photos * _aiMsPerPhoto;
  return Duration(milliseconds: ms.round());
}

/// Dự kiến riêng từng phần, để hiện cạnh mỗi lựa chọn.
Duration estimateDuplicates(int photos) =>
    estimateScan(photos, const ScanMode(duplicates: true, similar: false));
Duration estimateSimilar(int photos) =>
    estimateScan(photos, const ScanMode(duplicates: false, similar: true));
