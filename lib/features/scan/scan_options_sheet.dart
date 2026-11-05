import 'package:flutter/material.dart';

import '../../core/scanner/scan_mode.dart';
import '../../theme/app_theme.dart';
import '../home/home_kit.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_icon.dart';

/// Hộp chọn kiểu quét trước khi bắt đầu. Trả về null nếu người dùng đóng hộp.
/// [photos] là số ảnh trong thư viện, dùng để ước tính thời gian (0 = không biết).
Future<ScanMode?> showScanOptions(BuildContext context, {required int photos}) {
  return showModalBottomSheet<ScanMode>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ScanOptions(photos: photos),
  );
}

class _ScanOptions extends StatefulWidget {
  const _ScanOptions({required this.photos});
  final int photos;
  @override
  State<_ScanOptions> createState() => _ScanOptionsState();
}

class _ScanOptionsState extends State<_ScanOptions> {
  bool _dup = true;
  bool _sim = false;

  ScanMode get _mode => ScanMode(duplicates: _dup, similar: _sim);

  String _about(Duration d) =>
      widget.photos <= 0 ? '' : ' · ~${_fmt(d)}';

  /// "~45 giây", "~2 phút", dễ đọc hơn mm:ss cho phần ước tính.
  String _fmt(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds < 5 ? 5 : d.inSeconds} giây';
    final m = (d.inSeconds / 60).round();
    return '$m phút';
  }

  @override
  Widget build(BuildContext context) {
    final x = context.appColors;
    final est = estimateScan(widget.photos, _mode);
    return Container(
      decoration: const BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 16 + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: x.stroke, borderRadius: BorderRadius.circular(99)),
        ),
        const SizedBox(height: 16),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Chọn kiểu quét',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: kInk)),
        ),
        const SizedBox(height: 4),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Chỉ phần bạn chọn mới được chạy.',
              style: TextStyle(fontSize: 14, color: kInk3)),
        ),
        const SizedBox(height: 16),
        _option(
          on: _dup,
          icon: AppIcons.copyOutlined,
          title: 'Ảnh trùng',
          sub: 'Bản sao giống hệt hoặc gần như y hệt · PDQ + SHA-256'
              '${_about(estimateDuplicates(widget.photos))}',
          onTap: () => setState(() => _dup = !_dup),
        ),
        const SizedBox(height: 10),
        _option(
          on: _sim,
          icon: AppIcons.autoAwesomeOutlined,
          title: 'Ảnh tương tự',
          sub: 'Cùng cảnh nhưng khác lần chụp · AI MobileNetV3'
              '${_about(estimateSimilar(widget.photos))} (chậm hơn)',
          onTap: () => setState(() => _sim = !_sim),
        ),
        const SizedBox(height: 16),
        if (widget.photos > 0 && _mode.any)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
                'Dự kiến cho ${widget.photos} ảnh: ~${_fmt(est)}. '
                'Đây là ước tính, thời gian thật có thể khác.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, height: 1.4, color: kInk3)),
          ),
        SlateButton(
          label: 'Bắt đầu quét',
          icon: AppIcons.search,
          onPressed: _mode.any ? () => Navigator.pop(context, _mode) : null,
        ),
      ]),
    );
  }

  Widget _option({
    required bool on,
    required AppIconData icon,
    required String title,
    required String sub,
    required VoidCallback onTap,
  }) {
    final x = context.appColors;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: on ? kInk : kBorder, width: on ? 1.5 : 1),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: on ? x.gradient : null,
                  color: on ? null : x.surfaceAlt),
              child: AppIcon(icon, size: 20, color: on ? kInk : kInk2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600, color: kInk)),
                const SizedBox(height: 2),
                Text(sub,
                    style: const TextStyle(fontSize: 12, height: 1.4, color: kInk3)),
              ]),
            ),
            const SizedBox(width: 8),
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
      ),
    );
  }
}
