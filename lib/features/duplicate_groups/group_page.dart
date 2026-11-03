import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../core/scanner/scan_diagnostics.dart';
import '../../core/scanner/scan_session.dart';
import '../scan/scan_controller.dart';

class GroupPage extends StatefulWidget {
  const GroupPage({
    super.key,
    required this.controller,
    required this.group,
    required this.title,
  });

  final ScanController controller;
  final DuplicateGroup group;
  final String title;

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  /// Mặc định giữ ảnh đầu tiên, chọn các ảnh còn lại để xóa.
  late final Set<String> _selected = {
    for (final e in widget.group.items.skip(1)) e.asset.id
  };

  List<DuplicateItem> get _items => widget.group.items;

  bool get _wouldDeleteAll =>
      _items.isNotEmpty && _selected.length >= _items.length;

  Future<void> _delete() async {
    final toDelete =
        _items.where((e) => _selected.contains(e.asset.id)).map((e) => e.asset).toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa ảnh đã chọn?'),
        content: Text(
            'Sẽ xóa ${toDelete.length} ảnh khỏi thiết bị. Hệ điều hành có thể '
            'hỏi xác nhận thêm. Thao tác này có thể không hoàn tác được.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Xóa')),
        ],
      ),
    );
    if (ok != true) return;

    final count = await widget.controller.deleteAssets(toDelete);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Đã xóa $count ảnh')));
    if (_items.length < 2) {
      Navigator.of(context).pop();
    } else {
      setState(() => _selected.removeWhere((id) => !_items.any((e) => e.asset.id == id)));
    }
  }

  /// Số liệu chẩn đoán của một ảnh trong nhóm (chỉ khi bật chẩn đoán).
  String _diagText(DiagRow? r) => r == null
      ? ''
      : 'H=${r.hamming ?? '—'}';

  Widget _verdictBar(ScanDiagnostics diag) {
    final current = diag.verdictOf(widget.group);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SegmentedButton<DiagVerdict>(
        emptySelectionAllowed: true,
        segments: const [
          ButtonSegment(value: DiagVerdict.yes, label: Text('✓ đúng')),
          ButtonSegment(value: DiagVerdict.no, label: Text('✗ sai')),
          ButtonSegment(value: DiagVerdict.unsure, label: Text('? chưa rõ')),
        ],
        selected: current == null ? <DiagVerdict>{} : {current},
        onSelectionChanged: (s) => setState(
            () => diag.setVerdict(widget.group, s.isEmpty ? null : s.first)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final diag = widget.controller.diag;
    final rowById = {
      for (final r in diag?.rowsOf(widget.group) ?? const <DiagRow>[])
        r.assetId: r,
    };
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final item = _items[i];
          final selected = _selected.contains(item.asset.id);
          final label = item.exact
              ? (i == 0 ? 'Giữ lại (đề xuất)' : 'Giống hệt')
              : '${item.similarity?.toStringAsFixed(1) ?? '—'}%${item.byModel ? ' · AI' : ''}';
          return GestureDetector(
            onTap: () => setState(() {
              selected ? _selected.remove(item.asset.id) : _selected.add(item.asset.id);
            }),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AssetEntityImage(
                    item.asset,
                    isOriginal: false,
                    thumbnailSize: const ThumbnailSize.square(400),
                    fit: BoxFit.cover,
                  ),
                ),
                if (selected)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.black38,
                      border: Border.all(
                          color: Theme.of(context).colorScheme.error, width: 3),
                    ),
                  ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    color: selected ? Theme.of(context).colorScheme.error : Colors.white,
                  ),
                ),
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$label · ${item.asset.width}×${item.asset.height}',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
                if (diag != null)
                  Positioned(
                    left: 6,
                    right: 6,
                    bottom: 30,
                    child: Text(
                      _diagText(rowById[item.asset.id]),
                      style: const TextStyle(color: Colors.amber, fontSize: 10),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (diag != null) _verdictBar(diag),
              if (_wouldDeleteAll)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Hãy giữ lại ít nhất một ảnh.',
                      style: TextStyle(fontSize: 12)),
                ),
              FilledButton.icon(
                onPressed: _selected.isEmpty || _wouldDeleteAll ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                label: Text('Xóa ${_selected.length} ảnh đã chọn'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
