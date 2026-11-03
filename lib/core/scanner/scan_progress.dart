enum ScanPhase { reading, matching, exact, embedding }

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
