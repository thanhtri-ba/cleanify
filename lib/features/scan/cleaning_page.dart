import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:photo_manager/photo_manager.dart';

import '../../theme/app_theme.dart';
import '../../theme/widgets.dart';
import '../home/home_kit.dart';
import 'scan_controller.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_icon.dart';

/// Màn "Đang dọn dung lượng" (Figma 1:629). Chỉ được mở sau khi người dùng đã
/// xác nhận ở [ScanCompletePage]. Xóa theo lô để có thể tạm dừng giữa các lô;
/// mỗi lô iOS hiện một hộp thoại xác nhận của hệ thống.
class CleaningPage extends StatefulWidget {
  const CleaningPage({super.key, required this.controller, required this.assets});
  final ScanController controller;
  final List<AssetEntity> assets;
  @override
  State<CleaningPage> createState() => _CleaningPageState();
}

class _CleaningPageState extends State<CleaningPage> {
  static const _batch = 500;
  int _deleted = 0;
  bool _paused = false;
  bool _finished = false;
  bool _failed = false;

  int get _total => widget.assets.length;
  double get _frac => _total == 0 ? 1 : _deleted / _total;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      var i = _deleted;
      while (i < _total) {
        while (_paused && mounted) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        if (!mounted) return;
        final chunk = widget.assets.sublist(i, math.min(i + _batch, _total));
        final n = await widget.controller.deleteAssets(chunk);
        if (n == 0) {
          // Người dùng từ chối hộp thoại hệ thống: dừng, không thử lại ngầm.
          setState(() => _failed = true);
          return;
        }
        i += chunk.length;
        if (mounted) setState(() => _deleted += n);
      }
      if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() => _finished = true);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stopped = _finished || _failed;
    final pct = (_frac * 100).round();
    return PopScope(
      canPop: stopped,
      child: Scaffold(
        backgroundColor: kBg,
        body: Stack(children: [
          const Positioned(top: 0, left: 0, right: 0, child: Aura()),
          SafeArea(
          child: Column(children: [
            HTopBar(
                title: 'Đang dọn dung lượng',
                onBack: stopped ? () => Navigator.of(context).popUntil((r) => r.isFirst) : null),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 16), children: [
                Center(
                  child: SizedBox(
                    width: 220,
                    height: 220,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: _frac),
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut,
                      builder: (context, f, _) => Stack(alignment: Alignment.center, children: [
                      CustomPaint(size: const Size(220, 220), painter: _RingPainter(f, context.appColors)),
                      Container(
                        width: 150,
                        height: 150,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Color(0x2E676767), blurRadius: 36, offset: Offset(0, 12), spreadRadius: -6)
                          ],
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 350),
                            transitionBuilder: (child, a) => FadeTransition(
                              opacity: a,
                              child: ScaleTransition(
                                  scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
                                  child: child),
                            ),
                            child: _finished
                                ? const AppIcon(AppIcons.checkRounded,
                                    key: ValueKey('ok'), size: 52, color: kInk)
                                : Text('${(f * 100).round()}%',
                                    key: const ValueKey('pct'),
                                    style: const TextStyle(
                                        fontSize: 44, fontWeight: FontWeight.w700, color: kInk)),
                          ),
                          Text(_finished ? 'HOÀN TẤT' : (_failed ? 'ĐÃ DỪNG' : 'ĐANG DỌN'),
                              style: const TextStyle(
                                  fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w600, color: kInk3)),
                        ]),
                      ),
                    ])),
                  ),
                ),
                const SizedBox(height: 18),
                Text(_finished ? 'Đã dọn xong' : 'Dọn chỗ cho điều quan trọng',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: kInk)),
                const SizedBox(height: 6),
                Text(
                    _failed
                        ? 'Bạn đã từ chối xác nhận hoặc có lỗi. Ảnh còn lại vẫn được giữ nguyên.'
                        : (_finished ? 'Các ảnh đã chọn đã được xóa.' : 'Đang xử lý ảnh đã xác nhận'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: kInk2)),
                const SizedBox(height: 18),
                HStats([
                  ('$_deleted', 'Đã xóa'),
                  ('$_total', 'Ảnh đã chọn'),
                  ('${_total - _deleted}', 'Còn lại'),
                ]),
                const SizedBox(height: 18),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Tiến độ dọn dẹp',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
                  Text('$pct%',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
                ]),
                const SizedBox(height: 8),
                GradientBar(value: _frac),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: stopped
                  ? SlateButton(
                      label: 'Về trang chủ',
                      onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst))
                  : OutlineBtn(
                      label: _paused ? 'Tiếp tục dọn' : 'Tạm dừng dọn',
                      icon: _paused ? AppIcons.playArrowRounded : AppIcons.layersOutlined,
                      onPressed: () => setState(() => _paused = !_paused),
                    ),
            ),
          ]),
        ),
        ]),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.f, this.x);
  final double f;
  final AppColors x;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, size.width / 2, Paint()..color = x.line);
    final rect = Rect.fromCircle(center: c, radius: 94);
    if (f > 0) {
      canvas.drawArc(
          rect,
          -math.pi / 2,
          2 * math.pi * f.clamp(0.0, 1.0),
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 16
            ..strokeCap = StrokeCap.round
            ..shader = SweepGradient(
              startAngle: -math.pi / 2,
              endAngle: 3 * math.pi / 2,
              colors: [x.accent1, x.accent2],
            ).createShader(rect));
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) => o.f != f || o.x != x;
}
