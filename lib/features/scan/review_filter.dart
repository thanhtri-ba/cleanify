import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/scanner/scan_session.dart';
import '../home/home_kit.dart';

enum SizeBand { all, two, threeFour, fivePlus }

enum PhotoKindFilter { all, screenshot, live }

enum DateBand { all, last30, thisYear, older }

/// Bộ lọc chỉ để ẩn/hiện nhóm trong màn xem; không đổi kết quả quét và chỉ ảnh đang hiển
/// thị mới được tính khi xóa.
class ReviewFilter {
  const ReviewFilter({
    this.size = SizeBand.all,
    this.kind = PhotoKindFilter.all,
    this.date = DateBand.all,
    this.hideFavorites = false,
    this.hideEdited = false,
  });

  final SizeBand size;
  final PhotoKindFilter kind;
  final DateBand date;
  final bool hideFavorites;
  final bool hideEdited;

  int get activeCount =>
      (size != SizeBand.all ? 1 : 0) +
      (kind != PhotoKindFilter.all ? 1 : 0) +
      (date != DateBand.all ? 1 : 0) +
      (hideFavorites ? 1 : 0) +
      (hideEdited ? 1 : 0);

  bool get isActive => activeCount > 0;

  /// Nhãn ngắn của các bộ lọc đang bật, hiện thành chip cạnh nút Bộ lọc.
  List<String> get labels => [
        if (size != SizeBand.all)
          const {SizeBand.two: '2 ảnh', SizeBand.threeFour: '3–4 ảnh', SizeBand.fivePlus: 'Từ 5 ảnh'}[size]!,
        if (kind != PhotoKindFilter.all)
          kind == PhotoKindFilter.screenshot ? 'Màn hình' : 'Live Photo',
        if (date != DateBand.all)
          const {DateBand.last30: '30 ngày', DateBand.thisYear: 'Năm nay', DateBand.older: 'Cũ hơn 1 năm'}[date]!,
        if (hideFavorites) 'Ẩn yêu thích',
        if (hideEdited) 'Ẩn đã chỉnh',
      ];

  ReviewFilter copyWith({
    SizeBand? size,
    PhotoKindFilter? kind,
    DateBand? date,
    bool? hideFavorites,
    bool? hideEdited,
  }) =>
      ReviewFilter(
        size: size ?? this.size,
        kind: kind ?? this.kind,
        date: date ?? this.date,
        hideFavorites: hideFavorites ?? this.hideFavorites,
        hideEdited: hideEdited ?? this.hideEdited,
      );

  static bool isScreenshot(AssetEntity a) =>
      (a.subtype & 4) != 0 || (a.relativePath ?? '').toLowerCase().contains('screenshot');

  bool passes(DuplicateGroup g, Set<String> edited, {DateTime? now}) {
    final n = g.items.length;
    switch (size) {
      case SizeBand.all:
        break;
      case SizeBand.two:
        if (n != 2) return false;
      case SizeBand.threeFour:
        if (n < 3 || n > 4) return false;
      case SizeBand.fivePlus:
        if (n < 5) return false;
    }
    final assets = [for (final e in g.items) e.asset];
    if (hideFavorites && assets.any((a) => a.isFavorite)) return false;
    if (hideEdited && assets.any((a) => edited.contains(a.id))) return false;
    switch (kind) {
      case PhotoKindFilter.all:
        break;
      case PhotoKindFilter.screenshot:
        if (!assets.any(isScreenshot)) return false;
      case PhotoKindFilter.live:
        if (!assets.any((a) => a.isLivePhoto)) return false;
    }
    if (date != DateBand.all) {
      final t = now ?? DateTime.now();
      final newest = assets.map((a) => a.createDateTime).reduce((a, b) => a.isAfter(b) ? a : b);
      switch (date) {
        case DateBand.last30:
          if (newest.isBefore(t.subtract(const Duration(days: 30)))) return false;
        case DateBand.thisYear:
          if (newest.year != t.year) return false;
        case DateBand.older:
          if (!newest.isBefore(t.subtract(const Duration(days: 365)))) return false;
        case DateBand.all:
          break;
      }
    }
    return true;
  }
}

class ReviewFilterResult {
  const ReviewFilterResult(this.filter, this.tab, this.sim);
  final ReviewFilter filter;
  final GroupKind tab;
  final double sim;
}

/// Mở bảng lọc. [count] trả về (số nhóm, số ảnh) khớp bộ lọc và loại nhóm đang chỉnh.
/// [showSim] = false thì ẩn thanh độ giống (chỉ áp dụng cho nhóm trùng khi còn dữ liệu PDQ).
Future<ReviewFilterResult?> showReviewFilterSheet(
  BuildContext context, {
  required ReviewFilter initial,
  required GroupKind tab,
  required List<GroupKind> kinds,
  required double sim,
  required bool showSim,
  required (int, int) Function(ReviewFilter, GroupKind) count,
}) {
  return showModalBottomSheet<ReviewFilterResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kBg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => _FilterSheet(
        initial: initial, tab: tab, kinds: kinds, sim: sim, showSim: showSim, count: count),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.initial,
    required this.tab,
    required this.kinds,
    required this.sim,
    required this.showSim,
    required this.count,
  });
  final ReviewFilter initial;
  final GroupKind tab;
  final List<GroupKind> kinds;
  final double sim;
  final bool showSim;
  final (int, int) Function(ReviewFilter, GroupKind) count;
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  static const _line = Color(0xFFDFE3EC);
  static const _lime = Color(0xFFA3D133);
  late ReviewFilter f = widget.initial;
  late GroupKind tab = widget.tab;
  late double sim = widget.sim;

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(t,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kInk2)),
      );

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        width: double.infinity,
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _line),
        ),
        child: child,
      );

  Widget _segmented() => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: const Color(0xFFE6E9F0), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          for (final k in widget.kinds)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => tab = k),
                child: Container(
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: tab == k ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(11)),
                  child: Text(k == GroupKind.duplicate ? 'Trùng khớp' : 'Giống nhau',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: tab == k ? FontWeight.w700 : FontWeight.w600,
                          color: tab == k ? kInk : kInk2)),
                ),
              ),
            ),
        ]),
      );

  Widget _simCard() {
    final loose = sim < 84.0;
    return _card(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          const Expanded(
            child: Text('Độ giống tối thiểu',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
          ),
          Text('${sim.toStringAsFixed(1).replaceAll('.', ',')}%',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF557800))),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: _lime,
            inactiveTrackColor: const Color(0xFFE6E9F0),
            thumbColor: kInk,
            overlayColor: kInk.withOpacity(0.08),
            tickMarkShape: SliderTickMarkShape.noTickMark,
          ),
          child: Slider(
            value: sim,
            min: 73,
            max: 95,
            divisions: 44,
            onChanged: (v) => setState(() => sim = v),
          ),
        ),
        const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('73% · nhiều ảnh', style: TextStyle(fontSize: 12, color: kInk2)),
          Text('95% · chính xác', style: TextStyle(fontSize: 12, color: kInk2)),
        ]),
        if (loose)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Dễ gom nhầm ảnh khác nhau',
                style: TextStyle(fontSize: 12, color: Color(0xFFD13438))),
          ),
      ]),
    );
  }

  Widget _chips<T>(List<(T, String)> opts, T value, ValueChanged<T> onPick) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in opts)
            GestureDetector(
              onTap: () => onPick(o.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  color: o.$1 == value ? kInk : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: o.$1 == value ? kInk : _line),
                ),
                child: Text(o.$2,
                    style: TextStyle(
                        fontSize: 14,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: o.$1 == value ? Colors.white : kInk)),
              ),
            ),
        ],
      );

  Widget _switch(String t, bool v, ValueChanged<bool> on, {bool last = false}) => InkWell(
        onTap: () => on(!v),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          decoration: BoxDecoration(
              border: last ? null : const Border(bottom: BorderSide(color: _line))),
          child: Row(children: [
            Expanded(
              child: Text(t,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 46,
              height: 28,
              padding: const EdgeInsets.all(3),
              alignment: v ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                  color: v ? _lime : const Color(0xFFE6E9F0),
                  borderRadius: BorderRadius.circular(14)),
              child: Container(
                  width: 22,
                  height: 22,
                  decoration:
                      BoxDecoration(color: v ? kInk : Colors.white, shape: BoxShape.circle)),
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final (groups, photos) = widget.count(f, tab);
    final simChanged = widget.showSim && (sim - widget.sim).abs() > 0.01;
    final dirty = f.isActive || simChanged || tab != widget.tab;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40,
            height: 5,
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            decoration: BoxDecoration(
                color: const Color(0xFFC3CAD6), borderRadius: BorderRadius.circular(3)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
            child: Row(children: [
              const Expanded(
                child: Text('Bộ lọc',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kInk)),
              ),
              TextButton(
                onPressed: dirty
                    ? () => setState(() {
                          f = const ReviewFilter();
                          sim = 87.5;
                        })
                    : null,
                child: const Text('Đặt lại',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF557800))),
              ),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (widget.kinds.length > 1) ...[
                  _label('Loại nhóm'),
                  _segmented(),
                  const SizedBox(height: 2),
                ],
                if (widget.showSim && tab == GroupKind.duplicate) ...[
                  const SizedBox(height: 14),
                  _simCard(),
                ],
                _label('Số ảnh trong nhóm'),
                _chips(const [
                  (SizeBand.all, 'Tất cả'),
                  (SizeBand.two, '2'),
                  (SizeBand.threeFour, '3–4'),
                  (SizeBand.fivePlus, '5+'),
                ], f.size, (v) => setState(() => f = f.copyWith(size: v))),
                _label('Loại ảnh'),
                _chips(const [
                  (PhotoKindFilter.all, 'Tất cả'),
                  (PhotoKindFilter.screenshot, 'Ảnh chụp màn hình'),
                  (PhotoKindFilter.live, 'Live Photo'),
                ], f.kind, (v) => setState(() => f = f.copyWith(kind: v))),
                _label('Thời gian chụp'),
                _chips(const [
                  (DateBand.all, 'Mọi lúc'),
                  (DateBand.last30, '30 ngày'),
                  (DateBand.thisYear, 'Năm nay'),
                  (DateBand.older, 'Cũ hơn 1 năm'),
                ], f.date, (v) => setState(() => f = f.copyWith(date: v))),
                const SizedBox(height: 18),
                _card(
                  child: Column(children: [
                    _switch('Ẩn ảnh yêu thích', f.hideFavorites,
                        (v) => setState(() => f = f.copyWith(hideFavorites: v))),
                    _switch('Ẩn ảnh đã chỉnh sửa', f.hideEdited,
                        (v) => setState(() => f = f.copyWith(hideEdited: v)),
                        last: true),
                  ]),
                ),
                const SizedBox(height: 16),
              ]),
            ),
          ),
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, ReviewFilterResult(f, tab, sim)),
                style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: Text(simChanged ? 'Áp dụng' : 'Xem $groups nhóm · $photos ảnh',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
