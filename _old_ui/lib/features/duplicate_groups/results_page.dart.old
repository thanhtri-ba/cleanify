import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../core/scanner/scan_diagnostics.dart';
import '../../core/scanner/scan_session.dart';
import '../scan/home_page.dart' show TimingsCard;
import '../scan/scan_controller.dart';
import 'bulk_cleanup_dialog.dart';
import 'browse_page.dart';
import 'group_page.dart';

class ResultsPage extends StatefulWidget {
  const ResultsPage({super.key, required this.controller});
  final ScanController controller;

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  ScanController get controller => widget.controller;

  /// Độ nhạy tab Tương tự: cosine tối thiểu của ảnh chỉ được nhóm nhờ AI.
  /// Thấp = nhiều ảnh hơn nhưng dễ lẫn ảnh khác cảnh. Người dùng tự chỉnh bằng mắt.
  static const _sensMin = 0.55, _sensMax = 0.90;
  double _sens = 0.70;

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
        final dupes =
            controller.session?.duplicateGroups ?? const <DuplicateGroup>[];
        final similarAll =
            controller.session?.similarGroups ?? const <DuplicateGroup>[];
        final hasModelItems =
            similarAll.any((g) => g.items.any((e) => e.modelCosine != null));
        final similar = similarAll
            .map((g) => g.withMinModelCosine(_sens))
            .whereType<DuplicateGroup>()
            .toList();
        final diag = controller.diag;
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Kết quả quét'),
              bottom: const TabBar(
                tabs: [Tab(text: 'Trùng'), Tab(text: 'Tương tự')],
              ),
              actions: [
                if (controller.session?.assets.isNotEmpty ?? false)
                  IconButton(
                    tooltip: 'Xem ảnh',
                    icon: const Icon(Icons.grid_view_outlined),
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                BrowsePage(controller: controller))),
                  ),
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
                          child:
                              TimingsCard(timings: controller.session!.timings),
                        ),
                      ),
                    ),
                  ),
                if (dupes.isNotEmpty)
                  IconButton(
                    tooltip: 'Dọn nhanh',
                    icon: const Icon(Icons.cleaning_services_outlined),
                    onPressed: () => _bulkClean(context, dupes),
                  ),
                if (diag != null)
                  IconButton(
                    tooltip: 'Chép CSV chẩn đoán',
                    icon: const Icon(Icons.copy_all_outlined),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final rows = await controller.copyDiagCsv();
                      messenger.showSnackBar(SnackBar(
                          content: Text(rows == null
                              ? 'Không có dữ liệu chẩn đoán'
                              : 'Đã chép $rows dòng CSV, hãy dán vào chat')));
                    },
                  ),
              ],
            ),
            body: TabBarView(
              children: [
                _GroupList(
                  controller: controller,
                  groups: dupes,
                  diag: diag,
                  empty: 'Không còn nhóm ảnh trùng nào.',
                ),
                Column(children: [
                  if (hasModelItems)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(children: [
                        const Text('Độ nhạy'),
                        Expanded(
                          child: Slider(
                            // Phải = chặt hơn (ít nhóm, chính xác hơn).
                            value: _sens,
                            min: _sensMin,
                            max: _sensMax,
                            divisions: 35,
                            label: _sens.toStringAsFixed(2),
                            onChanged: (v) => setState(() => _sens = v),
                          ),
                        ),
                        Text('${similar.length} nhóm'),
                      ]),
                    ),
                  Expanded(
                    child: _GroupList(
                      controller: controller,
                      groups: similar,
                      diag: diag,
                      empty: 'Không có nhóm ảnh tương tự nào.',
                    ),
                  ),
                ]),
              ],
            ),
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
          child:
              Padding(padding: const EdgeInsets.all(24), child: Text(empty)));
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
  const _GroupTile(
      {required this.index, required this.group, required this.onTap});
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
      subtitle = group.kind == GroupKind.similar
          ? 'Gần giống · Hamming cao nhất ${sim == null ? '—' : ((100 - sim) * 2.56).round()}/256'
          : 'Gần giống · độ giống bit-hash thấp nhất ${sim?.toStringAsFixed(1) ?? '—'}%';
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
