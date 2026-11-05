import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../core/platform/photo_edits.dart';
import '../home/home_kit.dart';
import '../scan/cleaning_page.dart';
import '../scan/scan_controller.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_icon.dart';

/// Video dung lượng lớn: liệt kê video theo dung lượng giảm dần, lọc theo ngưỡng,
/// người dùng TỰ chọn video cần xóa (không có gì được chọn sẵn). Dung lượng đọc từ
/// metadata iOS nên không tải video từ iCloud. Xóa đi qua [CleaningPage].
class LargeVideosPage extends StatefulWidget {
  const LargeVideosPage({super.key, required this.controller});
  final ScanController controller;
  @override
  State<LargeVideosPage> createState() => _LargeVideosPageState();
}

class _Vid {
  _Vid(this.asset, this.bytes);
  final AssetEntity asset;
  final int bytes;
}

class _LargeVideosPageState extends State<LargeVideosPage> {
  static const _thresholdsMb = [50, 150, 500];

  bool _loading = true;
  String? _error;
  int _done = 0;
  int _total = 0;
  int _minMb = 150;
  final List<_Vid> _all = [];
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
      final paths =
          await PhotoManager.getAssetPathList(onlyAll: true, type: RequestType.video);
      if (paths.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      final path = paths.first;
      final total = await path.assetCountAsync;
      if (mounted) setState(() => _total = total);
      const chunk = 200;
      for (var s = 0; s < total; s += chunk) {
        if (!mounted) return;
        final list = await path.getAssetListRange(
            start: s, end: s + chunk > total ? total : s + chunk);
        final sizes = await edits.fileSizes([for (final a in list) a.id]);
        for (final a in list) {
          _all.add(_Vid(a, sizes[a.id] ?? 0));
        }
        _done = _all.length;
        if (mounted) setState(() {});
      }
      _all.sort((a, b) => b.bytes.compareTo(a.bytes));
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Không đọc được danh sách video: $e';
        });
      }
    }
  }

  List<_Vid> get _shown =>
      [for (final v in _all) if (v.bytes >= _minMb * 1000 * 1000) v];

  List<_Vid> get _selected => [for (final v in _all) if (_sel.contains(v.asset.id)) v];

  static String _size(int b) => b >= 1000 * 1000 * 1000
      ? '${(b / 1e9).toStringAsFixed(2)} GB'
      : '${(b / 1e6).round()} MB';

  static String _dur(int sec) {
    final m = (sec ~/ 60).toString();
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

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
        title: const Text('Xóa video đã chọn?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kInk)),
        content: Text(
            'Sẽ xóa ${sel.length} video (${_size(bytes)}). '
            'iOS sẽ hỏi xác nhận lần nữa; video vào mục Đã xóa gần đây 30 ngày.',
            style: const TextStyle(fontSize: 14, height: 1.5, color: kInk2)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Xóa ${sel.length} video'),
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
    final shown = _shown;
    final sel = _selected;
    final selBytes = sel.fold<int>(0, (n, v) => n + v.bytes);
    final totalBytes = shown.fold<int>(0, (n, v) => n + v.bytes);
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(children: [
          HTopBar(title: 'Video dung lượng lớn', onBack: () => Navigator.of(context).pop()),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(children: [
              for (final t in _thresholdsMb) ...[
                _chip('>$t MB', _minMb == t, () => setState(() => _minMb = t)),
                const SizedBox(width: 8),
              ],
            ]),
          ),
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${shown.length} video · tổng ${_size(totalBytes)}',
                    style: const TextStyle(fontSize: 12, color: kInk3)),
              ),
            ),
          Expanded(child: _body(shown)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: SlateButton(
              label: sel.isEmpty
                  ? 'Chọn video để xóa'
                  : 'Xóa ${sel.length} video (${_size(selBytes)})',
              icon: AppIcons.deleteOutline,
              onPressed: sel.isEmpty ? null : _delete,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _body(List<_Vid> shown) {
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
          Text('Đang đọc dung lượng video… $_done/$_total',
              style: const TextStyle(fontSize: 13, color: kInk3)),
        ]),
      );
    }
    if (shown.isEmpty) {
      return Center(
          child: Text('Không có video nào lớn hơn $_minMb MB.',
              style: const TextStyle(color: kInk3)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      itemCount: shown.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _row(shown[i]),
      ),
    );
  }

  Widget _row(_Vid v) {
    final on = _sel.contains(v.asset.id);
    final d = v.asset.createDateTime;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => on ? _sel.remove(v.asset.id) : _sel.add(v.asset.id)),
      child: HCard(
        padding: 12,
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 76,
              height: 76,
              child: Stack(fit: StackFit.expand, children: [
                AssetEntityImage(v.asset,
                    isOriginal: false,
                    fit: BoxFit.cover,
                    thumbnailSize: const ThumbnailSize.square(240)),
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                        color: const Color(0xCC2A343F), borderRadius: BorderRadius.circular(6)),
                    child: Text(_dur(v.asset.duration),
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_size(v.bytes),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700, color: kInk)),
              const SizedBox(height: 2),
              Text('${d.day}/${d.month}/${d.year} · ${v.asset.width}×${v.asset.height}',
                  style: const TextStyle(fontSize: 12, color: kInk3)),
            ]),
          ),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
                color: on ? kInk : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: kInk)),
            child: on ? const AppIcon(AppIcons.check, size: 14, color: Colors.white) : null,
          ),
        ]),
      ),
    );
  }

  Widget _chip(String t, bool on, VoidCallback f) => GestureDetector(
        onTap: f,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
              color: on ? kInk : kChip, borderRadius: BorderRadius.circular(99)),
          child: Text(t,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: on ? Colors.white : kInk2)),
        ),
      );
}
