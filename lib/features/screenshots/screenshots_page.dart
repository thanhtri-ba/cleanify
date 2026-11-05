import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../core/platform/photo_edits.dart';
import '../home/home_kit.dart';
import '../scan/cleaning_page.dart';
import '../scan/scan_controller.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_icon.dart';

/// Ảnh chụp màn hình: iOS tự gắn nhãn screenshot nên không cần model. Người dùng
/// TỰ chọn ảnh cần xóa (không chọn sẵn), có "Chọn tất cả". Xóa đi qua [CleaningPage].
class ScreenshotsPage extends StatefulWidget {
  const ScreenshotsPage({super.key, required this.controller});
  final ScanController controller;
  @override
  State<ScreenshotsPage> createState() => _ScreenshotsPageState();
}

class _Shot {
  _Shot(this.asset, this.bytes);
  final AssetEntity asset;
  final int bytes;
}

class _ScreenshotsPageState extends State<ScreenshotsPage> {
  bool _loading = true;
  String? _error;
  int _done = 0;
  int _total = 0;
  final List<_Shot> _all = [];
  final Set<String> _sel = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final edits = PhotoEdits();
    if (!edits.supported) {
      setState(() {
        _loading = false;
        _error = 'Tính năng này hiện chỉ hỗ trợ iPhone.';
      });
      return;
    }
    try {
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.hasAccess) {
        setState(() {
          _loading = false;
          _error = 'Cần cấp quyền truy cập thư viện ảnh.';
        });
        return;
      }
      final ids = await edits.screenshotIds();
      if (mounted) setState(() => _total = ids.length);
      const chunk = 100;
      for (var s = 0; s < ids.length; s += chunk) {
        if (!mounted) return;
        final part = ids.sublist(s, s + chunk > ids.length ? ids.length : s + chunk);
        final assets = await Future.wait([for (final id in part) AssetEntity.fromId(id)]);
        final sizes = await edits.fileSizes(part);
        for (final a in assets) {
          if (a != null) _all.add(_Shot(a, sizes[a.id] ?? 0));
        }
        _done = _all.length;
        if (mounted) setState(() {});
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Không đọc được ảnh chụp màn hình: $e';
        });
      }
    }
  }

  List<_Shot> get _selected => [for (final v in _all) if (_sel.contains(v.asset.id)) v];

  static String _size(int b) => b >= 1000 * 1000 * 1000
      ? '${(b / 1e9).toStringAsFixed(2)} GB'
      : '${(b / 1e6).toStringAsFixed(b >= 10 * 1000 * 1000 ? 0 : 1)} MB';

  Future<void> _delete() async {
    final sel = _selected;
    if (sel.isEmpty) return;
    final bytes = sel.fold<int>(0, (n, v) => n + v.bytes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Xóa ảnh chụp màn hình?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kInk)),
        content: Text(
            'Sẽ xóa ${sel.length} ảnh (${_size(bytes)}). '
            'iOS sẽ hỏi xác nhận lần nữa; ảnh vào mục Đã xóa gần đây 30 ngày.',
            style: const TextStyle(fontSize: 14, height: 1.5, color: kInk2)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Xóa ${sel.length} ảnh'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CleaningPage(
            controller: widget.controller, assets: [for (final v in sel) v.asset])));
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    final selBytes = sel.fold<int>(0, (n, v) => n + v.bytes);
    final totalBytes = _all.fold<int>(0, (n, v) => n + v.bytes);
    final allOn = _all.isNotEmpty && _sel.length == _all.length;
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(children: [
          HTopBar(title: 'Ảnh chụp màn hình', onBack: () => Navigator.of(context).pop()),
          if (!_loading && _error == null && _all.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 12, 4),
              child: Row(children: [
                Text('${_all.length} ảnh · tổng ${_size(totalBytes)}',
                    style: const TextStyle(fontSize: 12, color: kInk3)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    if (allOn) {
                      _sel.clear();
                    } else {
                      _sel
                        ..clear()
                        ..addAll(_all.map((v) => v.asset.id));
                    }
                  }),
                  child: Text(allOn ? 'Bỏ chọn' : 'Chọn tất cả',
                      style: const TextStyle(fontSize: 13, color: kInk)),
                ),
              ]),
            ),
          Expanded(child: _body()),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: SlateButton(
              label: sel.isEmpty
                  ? 'Chọn ảnh để xóa'
                  : 'Xóa ${sel.length} ảnh (${_size(selBytes)})',
              icon: AppIcons.deleteOutline,
              onPressed: sel.isEmpty ? null : _delete,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(_error!,
            textAlign: TextAlign.center, style: const TextStyle(color: kInk3, height: 1.5)),
      ));
    }
    if (_loading) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text('Đang đọc ảnh chụp màn hình… $_done/$_total',
              style: const TextStyle(fontSize: 13, color: kInk3)),
        ]),
      );
    }
    if (_all.isEmpty) {
      return const Center(
          child: Text('Không có ảnh chụp màn hình nào.', style: TextStyle(color: kInk3)));
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.62),
      itemCount: _all.length,
      itemBuilder: (_, i) => _tile(_all[i]),
    );
  }

  Widget _tile(_Shot v) {
    final on = _sel.contains(v.asset.id);
    return GestureDetector(
      onTap: () => setState(() => on ? _sel.remove(v.asset.id) : _sel.add(v.asset.id)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(fit: StackFit.expand, children: [
          AssetEntityImage(v.asset,
              isOriginal: false,
              fit: BoxFit.cover,
              thumbnailSize: const ThumbnailSize(300, 480)),
          if (on) Container(color: const Color(0x662A343F)),
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                  color: on ? kInk : const Color(0x80FFFFFF),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5)),
              child: on ? const AppIcon(AppIcons.check, size: 14, color: Colors.white) : null,
            ),
          ),
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: const Color(0xCC2A343F), borderRadius: BorderRadius.circular(8)),
              child: Text(_size(v.bytes),
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }
}
