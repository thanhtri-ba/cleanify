import 'package:flutter/material.dart';

import '../../core/scanner/bulk_cleanup.dart';
import '../../core/scanner/scan_progress.dart';
import '../../core/scanner/scan_session.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../theme/widgets.dart';
import '../home/home_kit.dart';
import 'review_page.dart';
import 'scan_controller.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_icon.dart';

/// Màn "Quét xong — sẵn sàng xem lại" (Figma 1:520). Số liệu và kế hoạch xóa
/// lấy từ [planBulkCleanup]: mỗi nhóm giữ 1 ảnh, không xóa gì trước khi xác nhận.
class ScanCompletePage extends StatefulWidget {
  const ScanCompletePage({super.key, required this.controller});
  final ScanController controller;
  @override
  State<ScanCompletePage> createState() => _ScanCompletePageState();
}

class _ScanCompletePageState extends State<ScanCompletePage> {
  late final Set<GroupKind> _kinds = {
    if (widget.controller.shown.duplicates) GroupKind.duplicate,
    if (widget.controller.shown.similar) GroupKind.similar,
  };

  ScanController get c => widget.controller;

  BulkCleanupPlan get _plan => planBulkCleanup(c.session?.groups ?? const [],
      minSimilarity: kBulkCleanupDefaultSimilarity);

  /// Số nhóm (>= 2 ảnh) và số ảnh thật của một loại, kể cả loại không tự chọn xóa.
  /// Nhóm thật (>= 2 ảnh) của một loại; nhóm tương tự đã bỏ ảnh nằm trong nhóm trùng.
  List<DuplicateGroup> _groupList(GroupKind k) {
    final raw = c.session?.groups ?? const <DuplicateGroup>[];
    if (k == GroupKind.similar) {
      final dup = c.shown.duplicates
          ? raw.where((g) => g.kind == GroupKind.duplicate)
          : const <DuplicateGroup>[];
      return similarExcludingDuplicates(
          [...dup, ...raw.where((g) => g.kind == GroupKind.similar)]);
    }
    return [for (final g in raw) if (g.kind == k && g.items.length > 1) g];
  }

  int _groupsOf(GroupKind k) => _groupList(k).length;
  int _itemsOf(GroupKind k) => _groupList(k).fold(0, (n, g) => n + g.items.length);

  /// Mở trang xem ảnh để người dùng tự chọn giữ/xóa; không xóa gì ở đây.
  void _review() {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ReviewPage(controller: c, kinds: {..._kinds})));
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final total = plan.assetsFor(_kinds).length;
    return Scaffold(
      backgroundColor: kBg,
      body: Stack(children: [
        const Positioned(top: 0, left: 0, right: 0, child: Aura()),
        SafeArea(
        child: Column(children: [
          HTopBar(title: 'Kết quả quét', onBack: () => Navigator.of(context).popUntil((r) => r.isFirst)),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 12), children: [
              const Reveal(
                index: 0,
                child: Text('Quét xong — sẵn sàng xem lại',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: kInk)),
              ),
              const SizedBox(height: 8),
              const Text(
                  'Có những mục nên xem lại trước khi dọn. Không có gì bị xóa cho đến khi bạn xác nhận.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, height: 1.5, color: kInk3)),
              const SizedBox(height: 20),
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (r) => context.appColors.gradient.createShader(r),
                child: CountUp(
                  value: total.toDouble(),
                  builder: (t) => Text('$t ảnh',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 52,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1.5,
                          color: Colors.white)),
                ),
              ),
              const Text('Có thể dọn để giải phóng dung lượng',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: kInk3)),
              const SizedBox(height: 16),
              Reveal(
                index: 2,
                child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: kChip, borderRadius: BorderRadius.circular(14)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Đã chọn để xem lại',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
                  HPill('$total ảnh', fg: Colors.white, bg: kInk2, size: 12),
                ]),
              )),
              const SizedBox(height: 14),
              Reveal(
                index: 3,
                child: HCard(
                padding: 0,
                child: Column(children: [
                  if (c.shown.duplicates)
                    _row(GroupKind.duplicate, AppIcons.copyOutlined, 'Ảnh trùng', plan, true),
                  if (c.shown.similar)
                    _row(GroupKind.similar, AppIcons.photoOutlined, 'Ảnh tương tự', plan,
                        !c.shown.duplicates),
                ]),
              )),
              const SizedBox(height: 14),
              // Thời gian từng khâu (kể cả bước AI chạy nền) để biết chỗ nào chậm.
              ListenableBuilder(
                listenable: c,
                builder: (context, _) {
                  final t = c.session?.timings ?? const <String>[];
                  if (t.isEmpty) return const SizedBox.shrink();
                  return HCard(
                    padding: 0,
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                        title: const Text('Chi tiết thời gian quét',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
                        subtitle: Text(
                            'Tổng ${formatElapsed(c.elapsed)}${c.refining ? ' · AI đang chạy nền…' : ''}',
                            style: const TextStyle(fontSize: 12, color: kInk3)),
                        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        expandedAlignment: Alignment.centerLeft,
                        children: [
                          SelectableText('Tổng thời gian quét: ${formatElapsed(c.elapsed)}\n${t.join('\n')}',
                              style: const TextStyle(
                                  fontSize: 12, height: 1.5, color: kInk2)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(children: [
              const Text('Không có gì bị xóa cho đến khi bạn xác nhận.',
                  style: TextStyle(fontSize: 12, color: kInk3)),
              const SizedBox(height: 10),
              SlateButton(
                label: total > 0
                    ? 'Xem ảnh ($total ảnh)'
                    : 'Xem ${_kinds.fold(0, (n, k) => n + _itemsOf(k))} ảnh',
                icon: AppIcons.photoLibraryOutlined,
                // Nhóm tương tự không tự chọn xóa (total = 0) nhưng vẫn phải xem được.
                onPressed: _kinds.any((k) => _groupsOf(k) > 0) ? _review : null,
              ),
              TextButton(
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('Về trang chủ',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kInk)),
              ),
            ]),
          ),
        ]),
      ),
      ]),
    );
  }

  Widget _row(GroupKind k, AppIconData i, String t, BulkCleanupPlan plan, bool first) {
    final on = _kinds.contains(k);
    final n = plan.countFor(k);
    return InkWell(
      onTap: () => setState(() => on ? _kinds.remove(k) : _kinds.add(k)),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            border: first ? null : const Border(top: BorderSide(color: kBorder))),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(12)),
            child: AppIcon(i, size: 18, color: kInk2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kInk)),
              Text(
                  k == GroupKind.similar
                      ? '${_itemsOf(k)} ảnh để xem lại'
                      : '$n ảnh có thể dọn · ${_itemsOf(k)} ảnh nghi trùng',
                  style: const TextStyle(fontSize: 12, color: kInk3)),
            ]),
          ),
          AnimatedContainer(
            duration: kMotionFast,
            width: 24,
            height: 24,
            decoration: BoxDecoration(
                color: on ? kInk : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: kInk)),
            child: AnimatedScale(
              scale: on ? 1 : 0,
              duration: kMotionFast,
              curve: Curves.easeOutBack,
              child: const AppIcon(AppIcons.check, size: 14, color: Colors.white),
            ),
          ),
        ]),
      ),
    );
  }
}
