import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../core/scanner/scan_diagnostics.dart';
import '../../core/scanner/scan_session.dart';
import '../scan/home_page.dart' show TimingsCard;
import '../scan/scan_controller.dart';
import 'bulk_cleanup_dialog.dart';
import 'group_page.dart';

class ResultsPage extends StatelessWidget {
  const ResultsPage({super.key, required this.controller});
  final ScanController controller;

  /// Mở dialog Dọn nhanh; chỉ xóa khi người dùng bấm Xóa trong dialog.
  Future<void> _bulkClean(
      BuildContext context, List<DuplicateGroup> groups) async {
    final messenger = ScaffoldMessenger.of(context);
    final toDelete = await showDialog<List<AssetEntity>>(
      context: context,
      builder: (_) => BulkCleanupDialog(groups: groups),
    );
    if (toDelete == null || toDelete.isEmpty) return;
    final count = await controller.deleteAssets(toDelete);
    messenger.showSnackBar(
        SnackBar(content: Text('Đã xóa $count/${toDelete.length} ảnh')));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final dupes = controller.session?.groups ?? const <DuplicateGroup>[];
        final diag = controller.diag;
        return Scaffold(
            appBar: AppBar(
              title: const Text('Kết quả quét'),
              actions: [
                if (controller.session?.timings.isNotEmpty ?? false)
                  IconButton(
                    tooltip: 'Thời gian xử lý',
                    icon: const Icon(Icons.timer_outlined),
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => SafeArea(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: TimingsCard(
                              timings: controller.session!.timings),
                        ),
                      ),
                    ),
                  ),
                if (dupes.isNotEmpty)
                  IconButton(
                    tooltip: 'Dọn nhanh',
                    icon: const Icon(Icons.cleaning_services_outlined),
                    onPressed: () =>
                        _bulkClean(context, dupes),
                  ),
                if (diag != null)
                  IconButton(
                    tooltip: 'Xuất CSV chẩn đoán',
                    icon: const Icon(Icons.file_download_outlined),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final file = await controller.exportDiagCsv();
                      messenger.showSnackBar(SnackBar(
                          content: Text(file == null
                              ? 'Không có dữ liệu chẩn đoán'
                              : 'Đã ghi ${file.path}')));
                    },
                  ),
              ],
            ),
            body: _GroupList(
              controller: controller,
              groups: dupes,
              diag: diag,
              empty: 'Không còn nhóm ảnh trùng nào.',
            ),
        );
      },
    );
  }
}

class _GroupList extends StatelessWidget {
  const _GroupList({
    required this.controller,
    required this.groups,
    required this.empty,
    this.diag,
  });
  final ScanController controller;
  final List<DuplicateGroup> groups;
  final String empty;
  final ScanDiagnostics? diag;

  @override
  Widget build(BuildContext context) {
    final list = _list(context);
    if (diag == null) return list;
    final st = diag!.statsFor(groups);
    final p = st.precision;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Text('Đã chấm ${st.graded}/${groups.length} nhóm · precision '
            '${p == null ? '—' : '${(p * 100).toStringAsFixed(1)}%'} '
            '(✓ ${st.yes} / ✗ ${st.no})'),
      ),
      Expanded(child: list),
    ]);
  }

  Widget _list(BuildContext context) {
    if (groups.isEmpty) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24), child: Text(empty)));
    }
    return ListView.separated(
      itemCount: groups.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) => _GroupTile(
        index: i,
        group: groups[i],
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => GroupPage(
            controller: controller,
            group: groups[i],
            title: 'Nhóm ${i + 1}',
          ),
        )),
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.index, required this.group, required this.onTap});
  final int index;
  final DuplicateGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sim = group.minSimilarity;
    final String subtitle;
    if (group.allExact) {
      subtitle = 'Giống hệt nhau (SHA-256)';
    } else {
      subtitle =
          'Gần giống · độ giống bit-hash thấp nhất ${sim?.toStringAsFixed(1) ?? '—'}%';
    }
    return ListTile(
      onTap: onTap,
      title: Text('Nhóm ${index + 1} · ${group.items.length} ảnh'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle),
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: group.items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, k) => ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: AssetEntityImage(
                  group.items[k].asset,
                  isOriginal: false,
                  thumbnailSize: const ThumbnailSize.square(160),
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}
