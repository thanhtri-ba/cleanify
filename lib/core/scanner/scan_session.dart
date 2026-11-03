import 'dart:async';

import 'package:photo_manager/photo_manager.dart';

import 'scan_diagnostics.dart';

class DuplicateItem {
  DuplicateItem(this.asset,
      {required this.exact, this.similarity, this.byModel = false});
  final AssetEntity asset;

  /// Trùng SHA-256 với ảnh đại diện của nhóm.
  final bool exact;

  /// Độ giống so với ảnh đại diện (0–100): bit-hash PDQ, hoặc cosine DINO x 100
  /// khi [byModel]. Null nếu không tính được.
  final double? similarity;

  /// Được nhóm bởi mô hình AI (DINO), không phải bởi SHA-256/PDQ.
  final bool byModel;
}

enum GroupKind { duplicate }

class DuplicateGroup {
  DuplicateGroup(this.items, {this.kind = GroupKind.duplicate});

  /// duplicate: trùng hoặc gần trùng (SHA-256/PDQ).
  final GroupKind kind;

  /// items.first là ảnh đề xuất giữ lại (độ phân giải cao nhất, cũ nhất).
  final List<DuplicateItem> items;

  bool get allExact => items.every((e) => e.exact);

  double? get minSimilarity {
    double? m;
    for (final e in items) {
      final s = e.exact ? 100.0 : e.similarity;
      if (s != null && (m == null || s < m)) m = s;
    }
    return m;
  }
}

class ScanCancelled implements Exception {
  const ScanCancelled();
}

class PermissionDeniedException implements Exception {
  const PermissionDeniedException();
}

/// Toàn bộ kết quả quét chỉ sống trong RAM của session này.
/// Không ghi database/file. [dispose] xóa mọi tham chiếu.
class ScanSession {
  ScanSession({this.diag});

  /// Chẩn đoán (chỉ khi bật). Null nghĩa là không ghi gì thêm.
  final ScanDiagnostics? diag;

  bool cancelled = false;
  bool _paused = false;
  Completer<void>? _resumeSignal;

  final List<DuplicateGroup> groups = [];

  /// Thời gian từng giai đoạn của lần quét này (hiện trên màn hình kết quả).
  final List<String> timings = [];
  int scanned = 0;
  int hashFailures = 0;
  Duration elapsed = Duration.zero;

  bool get paused => _paused;

  void pause() {
    if (_paused) return;
    _paused = true;
    _resumeSignal = Completer<void>();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    _resumeSignal?.complete();
    _resumeSignal = null;
  }

  /// Dừng tại ranh giới batch khi đang pause.
  Future<void> waitIfPaused() async {
    final signal = _resumeSignal;
    if (_paused && signal != null) await signal.future;
  }

  int get reclaimable =>
      groups.fold(0, (sum, g) => sum + (g.items.length - 1));

  void removeAssets(Set<String> ids) {
    for (final g in groups) {
      g.items.removeWhere((e) => ids.contains(e.asset.id));
    }
    groups.removeWhere((g) => g.items.length < 2);
  }

  Future<void> dispose() async {
    cancelled = true;
    resume();
    groups.clear();
    diag?.clear();
  }
}
