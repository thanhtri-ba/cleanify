import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../core/platform/photo_edits.dart';
import '../../core/scanner/bulk_cleanup.dart';
import '../../core/scanner/regroup.dart';
import '../../core/scanner/scan_session.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../home/home_kit.dart';
import 'cleaning_page.dart';
import 'photo_detail_page.dart';
import 'review_filter.dart';
import 'scan_controller.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_icon.dart';

/// Xem từng nhóm ảnh trùng/tương tự và tự chọn ảnh giữ/xóa. Chọn sẵn theo
/// [planBulkCleanup] (mỗi nhóm giữ ảnh đầu) nhưng người dùng sửa được. Chỉ khi bấm
/// nút xóa và xác nhận mới sang [CleaningPage]; một nhóm luôn còn ít nhất 1 ảnh.
class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.controller, this.kinds});
  final ScanController controller;

  /// Loại nhóm được chọn sẵn để xóa; null = tất cả.
  final Set<GroupKind>? kinds;
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  ScanController get c => widget.controller;
  late GroupKind _tab;
  Set<String> _del = {}; // id ảnh sẽ xóa

  /// Độ giống tối thiểu (%) để gom nhóm trùng. Mặc định = ngưỡng lúc quét (Hamming 32).
  static const double _defaultSim = 87.5;
  static const int _bigBatch = 200; // xóa nhiều hơn số này cần tick xác nhận
  double _sim = _defaultSim;

  /// Nhóm trùng gom lại theo [_sim]; null = dùng kết quả quét gốc.
  List<DuplicateGroup>? _regrouped;

  /// Bộ lọc hiển thị (chỉ ẩn/hiện nhóm, không đổi kết quả quét).
  ReviewFilter _filter = const ReviewFilter();

  bool _visible(DuplicateGroup g) => _filter.passes(g, _edited);

  /// Tăng mỗi lần gom lại để danh sách chuyển mờ dần thay vì nhảy.
  int _ver = 0;

  /// Ảnh đã chỉnh sửa trong ứng dụng Ảnh (iOS). Không tự chọn xóa để khỏi mất bản chỉnh.
  Set<String> _edited = {};
  bool _touched = false; // người dùng đã tự đổi lựa chọn: không ghi đè khi _edited tải xong

  /// Chỉ nhóm thuộc loại đã chọn lúc quét.
  List<DuplicateGroup> get _all {
    final raw = c.session?.groups ?? const <DuplicateGroup>[];
    final gone = _index?.removed ?? const <String>{};
    final dup = <DuplicateGroup>[];
    for (final g in _regrouped ?? raw) {
      if (g.kind != GroupKind.duplicate || !c.shown.duplicates) continue;
      // Nhóm gom lại là bản sao trong UI: bỏ ảnh đã xóa sau lúc gom.
      final items = _regrouped != null
          ? [for (final e in g.items) if (!gone.contains(e.asset.id)) e]
          : g.items;
      if (items.length > 1) {
        dup.add(items.length == g.items.length ? g : DuplicateGroup(items));
      }
    }
    // Ảnh đã nằm trong nhóm trùng thì không lặp lại ở tab Tương tự.
    final sim = c.shown.similar
        ? similarExcludingDuplicates([...dup, ...raw.where((g) => g.kind == GroupKind.similar)])
        : <DuplicateGroup>[];
    return [...dup, ...sim];
  }

  @override
  void initState() {
    super.initState();
    _applyDefault();
    _loadEdited();
    _tab = c.shown.duplicates &&
            (_all.any((g) => g.kind == GroupKind.duplicate && g.items.length > 1) ||
                !c.shown.similar)
        ? GroupKind.duplicate
        : GroupKind.similar;
  }

  Future<void> _loadEdited() async {
    try {
      final ids = {
        for (final g in c.session?.groups ?? const <DuplicateGroup>[])
          for (final e in g.items) e.asset.id
      }.toList();
      final edited = await PhotoEdits().editedIds(ids);
      if (!mounted || edited.isEmpty) return;
      setState(() {
        _edited = edited;
        if (!_touched) _applyDefault();
      });
    } catch (_) {
      // Không đọc được thì chỉ mất nhãn "Đã chỉnh", không ảnh hưởng xóa.
    }
  }

  bool _isProtected(AssetEntity a) => a.isFavorite || _edited.contains(a.id);

  void _applyDefault() {
    final plan = planBulkCleanup(_all,
        minSimilarity: kBulkCleanupDefaultSimilarity, protectedIds: _edited);
    _del = {
      for (final a in plan.assetsFor(widget.kinds ?? {...GroupKind.values})) a.id,
    };
  }

  PdqIndex? get _index => c.session?.pdqIndex;

  /// Gom lại nhóm trùng theo [_sim] mà không quét lại (dữ liệu PDQ nằm trong RAM).
  void _regroup() {
    final idx = _index;
    if (idx == null) return;
    final h = hammingForSimilarity(_sim);
    setState(() {
      _ver++;
      _regrouped = (_sim - _defaultSim).abs() < 0.05
          ? null
          : regroupDuplicates(idx, h);
      _applyDefault();
    });
  }

  /// Chọn xóa mọi ảnh trừ ảnh giữ của từng nhóm trong tab đang xem.
  void _selectAllButKeeper() {
    _touched = true;
    setState(() {
      for (final g in _all) {
        if (g.kind != _tab || g.items.length < 2 || !_visible(g)) continue;
        for (var i = 0; i < g.items.length; i++) {
          final id = g.items[i].asset.id;
          if (i == keeperIndex(g) || _isProtected(g.items[i].asset)) {
            _del.remove(id);
          } else {
            _del.add(id);
          }
        }
      }
    });
  }

  void _clearSelection() {
    _touched = true;
    setState(_del.clear);
  }

  void _openDetail(DuplicateGroup g, int index) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PhotoDetailPage(group: g, initialIndex: index)));
  }

  void _toggle(DuplicateGroup g, DuplicateItem it) {
    final id = it.asset.id;
    HapticFeedback.selectionClick();
    _touched = true;
    setState(() {
      if (_del.contains(id)) {
        _del.remove(id);
      } else {
        final left = g.items.where((e) => e.asset.id != id && !_del.contains(e.asset.id));
        if (left.isEmpty) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(const SnackBar(content: Text('Mỗi nhóm phải giữ lại ít nhất 1 ảnh.')));
          return;
        }
        _del.add(id);
      }
    });
  }

  List<AssetEntity> get _selected => [
        for (final g in _all)
          if (_visible(g))
            for (final it in g.items)
              if (_del.contains(it.asset.id)) it.asset,
      ];

  Future<void> _delete() async {
    final assets = _selected;
    if (assets.isEmpty) return;
    final nFav = assets.where((a) => a.isFavorite).length;
    final nEdited = assets.where((a) => _edited.contains(a.id)).length;
    // Cần tick xác nhận thêm khi xóa nhiều ảnh hoặc có ảnh yêu thích/đã chỉnh.
    final needTick = assets.length > _bigBatch || nFav > 0 || nEdited > 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        var ticked = !needTick;
        return StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text(
                assets.length > _bigBatch ? 'Xóa nhiều ảnh?' : 'Xóa ảnh đã chọn?',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kInk)),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Xóa ${assets.length} ảnh. Mỗi nhóm giữ lại ít nhất 1 ảnh.'
                  '${Platform.isIOS ? ' Ảnh vào "Đã xóa gần đây" 30 ngày.' : ''}',
                  style: const TextStyle(fontSize: 14, height: 1.5, color: kInk2)),
              if (nFav > 0 || nEdited > 0) ...[
                const SizedBox(height: 10),
                Text(
                    '${[
                      if (nFav > 0) '$nFav ảnh yêu thích',
                      if (nEdited > 0) '$nEdited ảnh đã chỉnh sửa',
                    ].join(' · ')} nằm trong lựa chọn.',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFD13438))),
              ],
              if (needTick)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  value: ticked,
                  onChanged: (v) => setD(() => ticked = v ?? false),
                  title: const Text('Tôi đã xem lại các ảnh này',
                      style: TextStyle(fontSize: 13, color: kInk)),
                ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
              FilledButton(
                onPressed: ticked ? () => Navigator.pop(ctx, true) : null,
                child: Text('Xóa ${assets.length} ảnh'),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true || !mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CleaningPage(controller: c, assets: assets)));
  }

  @override
  Widget build(BuildContext context) {
    final x = context.appColors;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final groups = [
          for (final g in _all)
            if (g.items.length > 1 && g.kind == _tab && _visible(g)) g
        ];
        // Đếm theo số ảnh trong các nhóm.
        int photosOf(GroupKind k) => _all
            .where((g) => g.items.length > 1 && g.kind == k && _visible(g))
            .fold(0, (n, g) => n + g.items.length);
        final nDup = photosOf(GroupKind.duplicate);
        final nSim = photosOf(GroupKind.similar);
        final n = _selected.length;
        return Scaffold(
          backgroundColor: kBg,
          body: SafeArea(
            child: Column(children: [
              HTopBar(title: 'Xem ảnh trùng', onBack: () => Navigator.of(context).pop()),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(children: [
                  // Hai tab chia đều chiều rộng, không bị cắt; "Chọn tự động" nằm hàng dưới.
                  if (c.shown.duplicates)
                    Expanded(
                      child: _chip('Trùng · $nDup', _tab == GroupKind.duplicate,
                          () => setState(() => _tab = GroupKind.duplicate)),
                    ),
                  if (c.shown.duplicates &&
                      (c.shown.similar || c.canRefine || c.refining))
                    const SizedBox(width: 8),
                  if (c.shown.similar || c.canRefine || c.refining)
                    Expanded(
                      child: _chip('Tương tự · $nSim', _tab == GroupKind.similar,
                          () => setState(() => _tab = GroupKind.similar)),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 12, 4),
                child: Row(children: [
                  _filterButton(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final l in _filter.labels)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(color: const Color(0xFFDFE3EC))),
                            child: Text(l,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600, color: kInk)),
                          ),
                      ]),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(_applyDefault),
                    child: const Text('Chọn tự động',
                        style: TextStyle(fontSize: 13, color: kInk)),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _selectAllButKeeper,
                      child: const Text('Chọn hết',
                          style: TextStyle(fontSize: 12, color: kInk)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: n == 0 ? null : _clearSelection,
                    child: const Text('Bỏ chọn',
                        style: TextStyle(fontSize: 12, color: kInk)),
                  ),
                ]),
              ),
              if (_tab == GroupKind.similar && c.canRefine)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: HCard(
                    padding: 12,
                    child: Row(children: [
                      const Expanded(
                        child: Text(
                            'Dùng AI tìm thêm ảnh cùng cảnh',
                            style: TextStyle(fontSize: 12, color: kInk2)),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: c.startRefine,
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 40)),
                        child: const Text('Chạy AI'),
                      ),
                    ]),
                  ),
                ),
              if (c.refining)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: HCard(
                    padding: 12,
                    child: Row(children: [
                      const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                            'Đang phân tích AI'
                            '${c.refineProgress?.fraction == null ? '' : ' · ${(c.refineProgress!.fraction! * 100).round()}%'}',
                            style: const TextStyle(fontSize: 12, color: kInk2)),
                      ),
                    ]),
                  ),
                ),
              Expanded(
                child: groups.isEmpty
                    ? Center(
                        child: Text(
                            _filter.isActive ? 'Không có nhóm nào khớp bộ lọc.' : 'Không có nhóm nào.',
                            style: const TextStyle(color: kInk3)))
                    : AnimatedSwitcher(
                        duration: kMotionMed,
                        child: ListView.builder(
                          key: ValueKey('$_tab-$_ver'),
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                          itemCount: groups.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Reveal(index: i, child: _group(groups[i], i + 1, x)),
                          ),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: SlateButton(
                  label: n == 0 ? 'Chưa chọn ảnh nào để xóa' : 'Xóa $n ảnh đã chọn',
                  icon: AppIcons.deleteOutline,
                  onPressed: n == 0 ? null : _delete,
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Future<void> _openFilter() async {
    final r = await showReviewFilterSheet(
      context,
      initial: _filter,
      tab: _tab,
      kinds: [
        if (c.shown.duplicates) GroupKind.duplicate,
        if (c.shown.similar) GroupKind.similar,
      ],
      sim: _sim,
      showSim: _index != null,
      count: (f, tab) {
        var g = 0, p = 0;
        for (final e in _all) {
          if (e.items.length > 1 && e.kind == tab && f.passes(e, _edited)) {
            g++;
            p += e.items.length;
          }
        }
        return (g, p);
      },
    );
    if (r == null || !mounted) return;
    final simChanged = (r.sim - _sim).abs() > 0.01;
    setState(() {
      _filter = r.filter;
      _tab = r.tab;
      _sim = r.sim;
      _ver++;
    });
    if (simChanged) _regroup();
  }

  Widget _filterButton() {
    final n = _filter.activeCount;
    return Material(
      color: kInk,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _openFilter,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(AppIcons.filter, size: 20, color: Colors.white, accent: const Color(0xFFA3D133)),
            const SizedBox(width: 6),
            Text('Bộ lọc',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
            if (n > 0) ...[
              const SizedBox(width: 6),
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: Color(0xFFA3D133), shape: BoxShape.circle),
                child: Text('$n',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: kInk)),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _chip(String t, bool on, VoidCallback f) => GestureDetector(
        onTap: f,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
              color: on ? kInk : kChip, borderRadius: BorderRadius.circular(99)),
          child: Text(t,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: on ? Colors.white : kInk2)),
        ),
      );

  Widget _group(DuplicateGroup g, int no, AppColors x) {
    final del = g.items.where((e) => _del.contains(e.asset.id)).length;
    return HCard(
      padding: 12,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
          child: Row(children: [
            Text(
                'Nhóm $no · ${g.items.length} ảnh',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
            const Spacer(),
            Text('Xóa $del · Giữ ${g.items.length - del}',
                style: const TextStyle(fontSize: 12, color: kInk3)),
            const SizedBox(width: 4),
            InkWell(
              onTap: () => _openDetail(g, 0),
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: AppIcon(AppIcons.infoOutline, size: 18, color: kInk2),
              ),
            ),
          ]),
        ),
        LayoutBuilder(builder: (context, cons) {
          final w = (cons.maxWidth - 16) / 3;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final it in g.items) SizedBox(width: w, height: w, child: _tileFor(g, it, x)),
          ]);
        }),
      ]),
    );
  }

  Widget _tileFor(DuplicateGroup g, DuplicateItem it, AppColors x) {
    final del = _del.contains(it.asset.id);
    return GestureDetector(
      onTap: () => _toggle(g, it),
      onLongPress: () => _openDetail(g, g.items.indexOf(it)),
      child: AnimatedScale(
        scale: del ? 0.94 : 1,
        duration: kMotionFast,
        curve: kMotionCurve,
        child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(fit: StackFit.expand, children: [
          Hero(
            tag: 'photo_${it.asset.id}',
            child: AssetEntityImage(it.asset,
                isOriginal: false,
                fit: BoxFit.cover,
                thumbnailSize: const ThumbnailSize.square(400)),
          ),
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: del ? 1 : 0,
              duration: kMotionFast,
              child: Container(color: const Color(0x992A343F)),
            ),
          ),
          Positioned(
            left: 6,
            top: 6,
            child: AnimatedContainer(
              duration: kMotionFast,
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                  color: del ? const Color(0xFFD13438) : x.accentSoft,
                  borderRadius: BorderRadius.circular(8)),
              child: AnimatedSwitcher(
                duration: kMotionFast,
                child: Row(key: ValueKey(del), mainAxisSize: MainAxisSize.min, children: [
                  AppIcon(del ? AppIcons.deleteOutline : AppIcons.check,
                      size: 12, color: del ? Colors.white : kInk),
                  const SizedBox(width: 3),
                  Text(del ? 'Xóa' : 'Giữ',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: del ? Colors.white : kInk)),
                ]),
              ),
            ),
          ),
          if (it.asset.isFavorite || _edited.contains(it.asset.id))
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                    color: const Color(0xCC2A343F), borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (it.asset.isFavorite)
                    const AppIcon(AppIcons.heart, size: 11, color: Colors.white),
                  if (it.asset.isFavorite && _edited.contains(it.asset.id))
                    const SizedBox(width: 3),
                  if (_edited.contains(it.asset.id))
                    const Text('Đã chỉnh',
                        style: TextStyle(
                            fontSize: 9.5, fontWeight: FontWeight.w600, color: Colors.white)),
                ]),
              ),
            ),
          if (it.exact || it.similarity != null || it.modelCosine != null)
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: const Color(0xCC2A343F), borderRadius: BorderRadius.circular(8)),
                child: Text(
                    it.exact
                        ? 'Giống hệt'
                        : (it.similarity != null
                            ? '${it.similarity!.round()}%'
                            : cosineBand(it.modelCosine!)),
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
        ]),
      )),
    );
  }
}
