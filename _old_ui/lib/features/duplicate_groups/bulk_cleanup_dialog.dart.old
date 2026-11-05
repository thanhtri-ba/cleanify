import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/scanner/bulk_cleanup.dart';
import '../../core/scanner/scan_session.dart';

/// Dialog tổng kết "Dọn nhanh": thanh trượt ngưỡng, số ảnh sẽ
/// xóa. Trả về danh sách ảnh cần xóa khi người dùng bấm Xóa, null nếu hủy.
/// Dialog này CHỈ lập kế hoạch; việc xóa thật do nơi gọi thực hiện.
class BulkCleanupDialog extends StatefulWidget {
  const BulkCleanupDialog({super.key, required this.groups});
  final List<DuplicateGroup> groups;

  @override
  State<BulkCleanupDialog> createState() => _BulkCleanupDialogState();
}

class _BulkCleanupDialogState extends State<BulkCleanupDialog> {
  double _min = kBulkCleanupDefaultSimilarity;

  @override
  Widget build(BuildContext context) {
    final plan = planBulkCleanup(widget.groups, minSimilarity: _min);
    final chosen = plan.assetsFor({GroupKind.duplicate});
    return AlertDialog(
      title: const Text('Dọn nhanh'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mỗi nhóm giữ lại 1 ảnh đại diện. Xóa các ảnh còn lại có độ '
                'giống từ ${_min.round()}% trở lên.'),
            Row(children: [
              Expanded(
                child: Slider(
                  value: _min,
                  min: kBulkCleanupMinSimilarity,
                  max: 100,
                  divisions: (100 - kBulkCleanupMinSimilarity).round(),
                  label: '${_min.round()}%',
                  onChanged: (v) => setState(() => _min = v.roundToDouble()),
                ),
              ),
              SizedBox(
                  width: 44,
                  child: Text('${_min.round()}%', textAlign: TextAlign.end)),
            ]),
            Text('Ảnh trùng · ${plan.countFor(GroupKind.duplicate)} ảnh '
                '(${plan.groupsFor(GroupKind.duplicate)} nhóm)'),
            const SizedBox(height: 8),
            Text('Sẽ xóa ${chosen.length} ảnh khỏi thiết bị. Hệ điều hành có '
                'thể hỏi xác nhận thêm. Thao tác này có thể không hoàn tác được.'),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy')),
        FilledButton(
          onPressed: chosen.isEmpty
              ? null
              : () => Navigator.pop<List<AssetEntity>>(context, chosen),
          child: Text('Xóa ${chosen.length} ảnh'),
        ),
      ],
    );
  }
}
