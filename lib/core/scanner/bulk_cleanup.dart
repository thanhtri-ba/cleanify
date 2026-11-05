import 'package:photo_manager/photo_manager.dart';

import 'scan_session.dart';

/// Ngưỡng độ giống (%) để TỰ CHỌN xóa sẵn. Cao hơn ngưỡng gom nhóm (87,5%) có chủ
/// ý: ảnh giống 87,5-94% vẫn nằm trong nhóm để xem nhưng mặc định ở trạng thái
/// giữ, người dùng tự quyết. 94,0 tương ứng Hamming <= 15; ảnh trùng SHA-256 là 100.
const double kBulkCleanupDefaultSimilarity = 94.0;

/// Ngưỡng thấp nhất người dùng được kéo thanh trượt xuống.
const double kBulkCleanupMinSimilarity = 80.0;

/// Độ giống hiệu dụng của một ảnh so với ảnh giữ lại: ảnh trùng SHA-256 là 100,
/// còn lại lấy [DuplicateItem.similarity]. null nghĩa là không biết, nên không xóa.
double? effectiveSimilarity(DuplicateItem item) =>
    item.exact ? 100.0 : item.similarity;

/// Chỉ số ảnh được giữ lại của nhóm: ảnh đầu tiên (độ phân giải cao nhất).
int keeperIndex(DuplicateGroup g) => 0;

/// Kết quả lập kế hoạch xóa hàng loạt. Chỉ là dữ liệu, chưa xóa gì.
class BulkCleanupPlan {
  const BulkCleanupPlan({required this.deletes, required this.groupCounts});

  /// Ảnh sẽ xóa, theo loại nhóm.
  final Map<GroupKind, List<AssetEntity>> deletes;

  /// Số nhóm có ít nhất một ảnh bị xóa, theo loại nhóm.
  final Map<GroupKind, int> groupCounts;

  int countFor(GroupKind kind) => deletes[kind]?.length ?? 0;

  int groupsFor(GroupKind kind) => groupCounts[kind] ?? 0;

  /// Ảnh sẽ xóa nếu chỉ lấy các loại nhóm trong [kinds].
  List<AssetEntity> assetsFor(Set<GroupKind> kinds) => [
        for (final k in GroupKind.values)
          if (kinds.contains(k)) ...?deletes[k],
      ];
}

/// Lập kế hoạch "Dọn nhanh": mỗi nhóm giữ lại 1 ảnh ([keeperIndex]), xóa các ảnh
/// còn lại có độ giống với ảnh giữ lại >= [minSimilarity] (%).
///
/// Bảo đảm:
/// - Không bao giờ xóa hết một nhóm (ảnh giữ lại luôn nằm ngoài danh sách xóa).
/// - Ảnh là "ảnh giữ lại" của bất kỳ nhóm nào thì không bị nhóm khác xóa.
/// - Ảnh không có độ giống (null và không phải trùng SHA-256) không bị xóa.
/// - Ảnh yêu thích và ảnh trong [protectedIds] (vd. ảnh đã chỉnh sửa) không bao giờ
///   được tự chọn xóa; người dùng vẫn tự chọn tay được.
/// - Mỗi ảnh chỉ xuất hiện một lần.
BulkCleanupPlan planBulkCleanup(
  List<DuplicateGroup> groups, {
  required double minSimilarity,
  Set<String> protectedIds = const {},
}) {
  final protected = <String>{};
  for (final g in groups) {
    if (g.items.isEmpty) continue;
    protected.add(g.items[keeperIndex(g)].asset.id);
  }

  final seen = <String>{};
  final deletes = {for (final k in GroupKind.values) k: <AssetEntity>[]};
  final groupCounts = {for (final k in GroupKind.values) k: 0};

  for (final g in groups) {
    if (g.items.length < 2) continue;
    final keep = keeperIndex(g);
    var any = false;
    for (var i = 0; i < g.items.length; i++) {
      if (i == keep) continue;
      final item = g.items[i];
      final s = effectiveSimilarity(item);
      // 1e-6: tránh lệch do số thực khi s đúng bằng ngưỡng.
      if (s == null || s + 1e-6 < minSimilarity) continue;
      final id = item.asset.id;
      if (item.asset.isFavorite || protectedIds.contains(id)) continue;
      if (protected.contains(id) || !seen.add(id)) continue;
      deletes[g.kind]!.add(item.asset);
      any = true;
    }
    if (any) groupCounts[g.kind] = groupCounts[g.kind]! + 1;
  }
  return BulkCleanupPlan(deletes: deletes, groupCounts: groupCounts);
}
