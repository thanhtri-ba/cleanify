import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/scanner/scan_progress.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../theme/widgets.dart';
import '../home/home_kit.dart';
import 'scan_complete_page.dart';
import 'scan_controller.dart';
import 'scan_error_page.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_icon.dart';

/// Màn "Đang quét ảnh của bạn". Tiến độ lấy từ [ScanController].
class SmartScanPage extends StatefulWidget {
  const SmartScanPage({super.key, required this.controller});
  final ScanController controller;
  @override
  State<SmartScanPage> createState() => _SmartScanPageState();
}

class _SmartScanPageState extends State<SmartScanPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beam =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  Timer? _tick;
  bool _left = false;

  /// Thời điểm (theo đồng hồ quét) mỗi giai đoạn bắt đầu, để tính thời gian từng mốc.
  final Map<int, Duration> _phaseStart = {};
  int _lastPhase = -1;

  void _trackPhase(ScanProgress? p) {
    final i = p?.phase.index ?? 0;
    if (i == _lastPhase) return;
    _lastPhase = i;
    _phaseStart.putIfAbsent(i, () => c.elapsed);
  }

  /// Giai đoạn kế tiếp đã bắt đầu sớm nhất sau [i] (giai đoạn bị bỏ qua không có mốc).
  Duration? _nextStart(int i) {
    Duration? best;
    _phaseStart.forEach((k, v) {
      if (k > i && (best == null || v < best!)) best = v;
    });
    return best;
  }

  ScanController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    // Đồng hồ chỉ đổi khi controller notify (theo batch); ticker này để thời gian
    // chạy mượt và cho thấy rõ quét đang chậm hay đã kẹt.
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _beam.stop();
    } else if (!_beam.isAnimating) {
      _beam.repeat();
    }
  }

  void _onChange() {
    if (_left || !mounted) return;
    if (c.status == ScanStatus.done) {
      _left = true;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ScanCompletePage(controller: c)));
    } else if (c.status == ScanStatus.error) {
      _left = true;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ScanErrorPage(controller: c)));
    } else if (c.status == ScanStatus.idle && c.session == null) {
      _leave(); // đã hủy xong
    }
  }

  /// Rời màn ngay. Dùng pop() trực tiếp: maybePop() bị PopScope(canPop: false) chặn.
  void _leave() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pop();
  }

  /// Hủy quét và thoát ngay, không chờ batch đang chạy kết thúc.
  void _cancel() {
    c.cancel();
    _leave();
  }

  @override
  void dispose() {
    _tick?.cancel();
    c.removeListener(_onChange);
    _beam.dispose();
    super.dispose();
  }

  /// Tiến độ tổng do controller tính (đơn điệu, chỉ đạt 100% khi quét xong).
  double get _fraction => c.overall.clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final x = context.appColors;
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: kBg,
        body: Stack(children: [
          const Positioned(top: 0, left: 0, right: 0, child: Aura()),
          SafeArea(
            child: ListenableBuilder(
              listenable: c,
              builder: (context, _) {
                final p = c.progress;
                final s = c.session;
                final found = s == null
                    ? 0
                    : (s.groups.isNotEmpty ? s.groups.length : s.liveGroups);
                _trackPhase(p);
                final cur = p?.phase.index ?? 0;
                return Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SectionLabel('Quét nhanh'),
                      const SizedBox(height: 6),
                      Text(c.paused ? 'Đã tạm dừng' : 'Đang quét ảnh của bạn',
                          style: const TextStyle(
                              fontSize: 26,
                              height: 32 / 26,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.6,
                              color: kInk)),
                      const SizedBox(height: 12),
                      FlowTracker(
                        labels: const ['Quét', 'Xem lại', 'Dọn', 'Xong'],
                        index: 0,
                        current: _fraction,
                      ),
                    ]),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      children: [
                        HCard(
                          padding: 20,
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              CountUp(
                                value: _fraction * 100,
                                duration: const Duration(milliseconds: 300),
                                builder: (t) => Text(t,
                                    style: const TextStyle(
                                        fontSize: 64,
                                        height: 1,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -2,
                                        color: kInk)),
                              ),
                              const Padding(
                                padding: EdgeInsets.only(left: 2, bottom: 6),
                                child: Text('%',
                                    style: TextStyle(
                                        fontSize: 20, fontWeight: FontWeight.w600, color: kInk2)),
                              ),
                              const Spacer(),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Row(mainAxisSize: MainAxisSize.min, children: [
                                  CircleAvatar(radius: 4, backgroundColor: x.accent1),
                                  const SizedBox(width: 6),
                                  CountUp(
                                    value: found.toDouble(),
                                    duration: const Duration(milliseconds: 300),
                                    builder: (t) => Text('$t nhóm',
                                        style: const TextStyle(
                                            fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
                                  ),
                                ]),
                                const Text('đã tìm thấy',
                                    style: TextStyle(fontSize: 12, color: kInk3)),
                              ]),
                            ]),
                            const SizedBox(height: 16),
                            _grid(x),
                            const SizedBox(height: 16),
                            _scanBar(x),
                            const SizedBox(height: 8),
                            Text(
                                '${p?.label ?? 'Đang chuẩn bị…'} · ${formatElapsed(c.elapsed)}',
                                style: const TextStyle(fontSize: 12, color: kInk3)),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        _notifyCard(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
                          child: Row(children: [
                            const SectionLabel('Mốc thời gian'),
                            const Spacer(),
                            Text(
                                'Tổng ${formatElapsed(c.elapsed)}'
                                '${c.estimated > Duration.zero ? ' · dự kiến ~${formatElapsed(c.estimated)}' : ''}',
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600, color: kInk2)),
                          ]),
                        ),
                        HCard(
                          padding: 0,
                          child: Column(children: [
                            _phaseRow(0, cur, p, AppIcons.photoLibraryOutlined,
                                c.mode.duplicates ? 'Đọc & băm ảnh' : 'Đọc thư viện ảnh',
                                c.mode.duplicates
                                    ? 'Lấy thumbnail, tạo dấu vân tay'
                                    : 'Liệt kê ảnh cần phân tích'),
                            if (c.mode.duplicates) ...[
                              _phaseRow(1, cur, p, AppIcons.search, 'So khớp ứng viên',
                                  'Tìm các cặp ảnh gần giống'),
                              _phaseRow(2, cur, p, AppIcons.fingerprint, 'Đối chiếu file gốc',
                                  'SHA-256 cho ảnh nghi trùng'),
                            ],
                            if (c.mode.similar)
                              _phaseRow(3, cur, p, AppIcons.autoAwesomeOutlined,
                                  'Phân tích AI', 'Embedding MobileNetV3 cho từng ảnh'),
                          ]),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Column(children: [
                      const Text('Bạn vẫn dùng iPhone bình thường. Không có gì bị xóa.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: kInk3)),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: OutlineBtn(
                            label: c.paused ? 'Tiếp tục' : 'Tạm dừng',
                            icon: c.paused ? AppIcons.playArrowRounded : AppIcons.pauseRounded,
                            onPressed: c.paused ? c.resume : c.pause,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: OutlineBtn(label: 'Hủy quét', onPressed: _cancel)),
                      ]),
                    ]),
                  ),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }

  /// Thẻ "thoát app được" + công tắc báo khi quét xong.
  Widget _notifyCard() {
    final ios = Platform.isIOS;
    final on = c.notifyWhenDone;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: HCard(
        padding: 16,
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(12)),
              child: const Center(
                  child: AppIcon(AppIcons.notificationsOutlined,
                      size: 22, color: Colors.white, accent: Color(0xFFA3D133))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ios ? 'Giữ app mở để quét nhanh nhất' : 'Bạn có thể thoát app',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: kInk)),
                const SizedBox(height: 2),
                Text(
                    ios
                        ? 'Nếu thoát, iOS sẽ dừng quét. Cleanify nhắc bạn mở lại để quét tiếp.'
                        : 'Cleanify quét tiếp ở nền và gửi thông báo khi xong.',
                    style: const TextStyle(fontSize: 13, height: 1.45, color: kInk2)),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => c.setNotifyWhenDone(!on),
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFDFE3EC)))),
              child: Row(children: [
                const Expanded(
                  child: Text('Báo khi quét xong',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 46,
                  height: 28,
                  padding: const EdgeInsets.all(3),
                  alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                  decoration: BoxDecoration(
                      color: on ? const Color(0xFFA3D133) : const Color(0xFFE6E9F0),
                      borderRadius: BorderRadius.circular(14)),
                  child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                          color: on ? kInk : Colors.white, shape: BoxShape.circle)),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  /// Lưới 2×6 với tia quét chạy ngang. Chỉ là hiệu ứng minh họa, không biểu diễn
  /// ảnh cụ thể nào.
  static const int _cols = 8;
  static const int _rows = 2;

  /// Lưới ô chạy theo tiến độ thật: ô thứ i đầy dần khi tiến độ đi qua nó, ô đang
  /// xử lý nhấp nháy nhẹ. Không có tia quét giả.
  Widget _grid(AppColors x) {
    const cells = _cols * _rows;
    final f = _fraction * cells;
    final live = !c.paused && !MediaQuery.disableAnimationsOf(context);

    Widget cell(int i) {
      final fill = (f - i).clamp(0.0, 1.0);
      final active = fill > 0 && fill < 1;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: AspectRatio(
            aspectRatio: 1,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: fill),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              builder: (_, v, __) => AnimatedBuilder(
                animation: _beam,
                builder: (_, __) {
                  final pulse = active && live
                      ? 0.75 + 0.25 * math.sin(2 * math.pi * _beam.value * 2)
                      : 1.0;
                  return Transform.scale(
                    scale: 0.88 + 0.12 * v,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        color: x.stroke,
                      ),
                      child: Opacity(
                        opacity: (v * pulse).clamp(0.0, 1.0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(7),
                            gradient: x.gradient,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration:
          BoxDecoration(color: x.surfaceAlt, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        for (var r = 0; r < _rows; r++)
          Row(children: [for (var i = r * _cols; i < (r + 1) * _cols; i++) cell(i)]),
      ]),
    );
  }

  /// Thanh tiến độ có vệt sáng chạy trong phần đã đầy khi đang quét.
  Widget _scanBar(AppColors x) {
    final live = !c.paused && !MediaQuery.disableAnimationsOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 8,
        color: x.line,
        alignment: Alignment.centerLeft,
        child: AnimatedFractionallySizedBox(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          widthFactor: _fraction.clamp(0.0, 1.0),
          child: Stack(fit: StackFit.expand, children: [
            DecoratedBox(decoration: BoxDecoration(gradient: x.gradient)),
            if (live)
              AnimatedBuilder(
                animation: _beam,
                builder: (_, __) => Align(
                  alignment: Alignment(-1.5 + 3 * _beam.value, 0),
                  child: const FractionallySizedBox(
                    widthFactor: 0.35,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          Color(0x00FFFFFF),
                          Color(0x66FFFFFF),
                          Color(0x00FFFFFF),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _phaseRow(
      int i, int cur, ScanProgress? p, AppIconData icon, String title, String sub) {
    final x = context.appColors;
    final done = i < cur;
    final running = i == cur;
    final start = _phaseStart[i];

    Duration? took;
    if (done && start != null) {
      final next = _nextStart(i);
      if (next != null) took = next - start;
    }

    String detail = sub;
    if (done && took != null) {
      detail = 'Xong trong ${formatElapsed(took)}';
    } else if (running) {
      final inPhase = start == null ? Duration.zero : c.elapsed - start;
      final frac = p?.fraction ?? 0;
      detail = 'Đã chạy ${formatElapsed(inPhase)}';
      if (frac >= 0.03 && inPhase.inSeconds >= 3) {
        final eta = Duration(
            milliseconds: (inPhase.inMilliseconds * (1 - frac) / frac).round());
        detail += ' · còn ~${formatElapsed(eta)}';
      }
    }

    // Giai đoạn đang chạy chưa xong thì không hiện 100%; "so khớp" không có phần trăm.
    final pct = math.min(99, ((p?.fraction ?? 0) * 100).round());
    Widget trailing;
    if (done) {
      trailing = Text(took == null ? 'Xong' : formatElapsed(took),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk2));
    } else if (running) {
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(99)),
        child: Text(
            c.paused ? 'Tạm dừng' : (p?.phase == ScanPhase.matching ? 'Đang chạy' : '$pct%'),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
      );
    } else {
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            border: Border.all(color: x.stroke), borderRadius: BorderRadius.circular(99)),
        child: const Text('CHỜ',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .4, color: kInk3)),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          border: i == 0 ? null : Border(top: BorderSide(color: x.line))),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: running ? null : x.surfaceAlt,
            gradient: running ? x.gradient : null,
          ),
          child: AppIcon(done ? AppIcons.check : (running ? icon : AppIcons.schedule),
              size: 18, color: running ? kInk : kInk2),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
            Text(detail, style: const TextStyle(fontSize: 12, color: kInk3)),
          ]),
        ),
        const SizedBox(width: 8),
        trailing,
      ]),
    );
  }
}
