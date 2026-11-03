import 'dart:async';
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import 'scan_diagnostics.dart';

class DuplicateItem {
  DuplicateItem(this.asset,
      {required this.exact,
      this.similarity,
      this.byModel = false,
      this.viaOriginal = false,
      this.localInliers,
      this.modelCosine});
  final AssetEntity asset;

  /// Trùng SHA-256 với ảnh đại diện của nhóm.
  final bool exact;

  /// Độ giống so với ảnh đại diện (0–100): bit-hash PDQ, hoặc cosine DINO x 100
  /// khi [byModel]. Null nếu không tính được.
  final double? similarity;

  /// Được nhóm bởi mô hình AI (DINO), không phải bởi SHA-256/PDQ.
  final bool byModel;

  /// Ảnh đã chỉnh sửa (iOS): hash của BẢN GỐC khớp ảnh đại diện. Ảnh đang hiển thị
  /// khác ảnh đại diện (có thể có nét vẽ, crop), nên [similarity] là null và
  /// "Dọn nhanh" không tự xóa.
  final bool viaOriginal;

  /// Chỉ cho nhóm tương tự: cosine embedding (đã trừ trung bình) với ảnh đại diện,
  /// khi ảnh được nhóm CHỈ nhờ mô hình. [similarity] là null nên không bị tự xóa.
  /// Giao diện lọc theo giá trị này (thanh "Độ nhạy").
  final double? modelCosine;

  /// Số điểm đặc trưng khớp (ORB + RANSAC) với ảnh đại diện khi ảnh được nhóm
  /// theo cách này (crop, chụp lệch, nét vẽ). [similarity] là null, "Dọn nhanh"
  /// không tự xóa.
  final int? localInliers;
}

enum GroupKind { duplicate, similar }

/// Nhãn mức giống theo cosine embedding. Cosine KHÔNG phải xác suất/%: các mốc này
/// chỉ là quy ước thô, chưa calibrate, dùng để người xem nhìn nhanh.
String cosineBand(double c) {
  if (c >= 0.80) return 'Rất giống';
  if (c >= 0.65) return 'Giống';
  if (c >= 0.55) return 'Hơi giống';
  return 'Khác biệt';
}

class DuplicateGroup {
  DuplicateGroup(this.items, {this.kind = GroupKind.duplicate});

  /// duplicate: trùng hoặc gần trùng (SHA-256/PDQ).
  final GroupKind kind;

  /// items.first là ảnh đề xuất giữ lại (độ phân giải cao nhất, cũ nhất).
  final List<DuplicateItem> items;

  bool get allExact => items.every((e) => e.exact);

  /// Bản lọc theo độ nhạy: bỏ ảnh chỉ được nhóm nhờ mô hình mà cosine < [t].
  /// Trả về chính nhóm này nếu không ảnh nào bị bỏ, null nếu còn dưới 2 ảnh.
  DuplicateGroup? withMinModelCosine(double t) {
    bool ok(DuplicateItem e) => e.modelCosine == null || e.modelCosine! >= t;
    if (items.every(ok)) return this;
    final kept = [for (final e in items) if (ok(e)) e];
    return kept.length < 2 ? null : DuplicateGroup(kept, kind: kind);
  }

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

  /// Mọi ảnh đã quét (đúng thứ tự quét) để màn hình "Xem ảnh" duyệt.
  List<AssetEntity> assets = const [];

  /// Embedding (đã trừ trung bình, L2-normalize) theo asset id; chỉ trong RAM.
  /// Rỗng nếu bước AI bị bỏ qua. Dùng cho [neighborsOf].
  final Map<String, Float32List> embeddings = {};

  /// [k] ảnh giống [id] nhất theo cosine embedding, giảm dần. Rỗng nếu thiếu embedding.
  List<({AssetEntity asset, double cosine})> neighborsOf(String id, {int k = 30}) {
    final q = embeddings[id];
    if (q == null) return const [];
    final byId = {for (final a in assets) a.id: a};
    final res = <({AssetEntity asset, double cosine})>[];
    embeddings.forEach((other, v) {
      final a = byId[other];
      if (other == id || a == null || v.length != q.length) return;
      var c = 0.0;
      for (var i = 0; i < q.length; i++) {
        c += q[i] * v[i];
      }
      res.add((asset: a, cosine: c));
    });
    res.sort((x, y) => y.cosine.compareTo(x.cosine));
    return res.length > k ? res.sublist(0, k) : res;
  }

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

  List<DuplicateGroup> get duplicateGroups =>
      groups.where((g) => g.kind == GroupKind.duplicate).toList();

  List<DuplicateGroup> get similarGroups =>
      groups.where((g) => g.kind == GroupKind.similar).toList();

  int get reclaimable =>
      duplicateGroups.fold(0, (sum, g) => sum + (g.items.length - 1));

  void removeAssets(Set<String> ids) {
    assets = [for (final a in assets) if (!ids.contains(a.id)) a];
    for (final id in ids) {
      embeddings.remove(id);
    }
    for (final g in groups) {
      g.items.removeWhere((e) => ids.contains(e.asset.id));
    }
    groups.removeWhere((g) => g.items.length < 2);
  }

  Future<void> dispose() async {
    cancelled = true;
    resume();
    groups.clear();
    embeddings.clear();
    assets = const [];
    diag?.clear();
  }
}
