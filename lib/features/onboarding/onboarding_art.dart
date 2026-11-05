import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Hình minh họa động cho 3 trang onboarding. Ảnh nền là asset tĩnh, hiệu ứng
/// (sóng, tia quét, chấm quỹ đạo, sao, bộ đếm) vẽ bằng CustomPainter lên trên.
/// Toàn bộ hiệu ứng suy ra từ một đồng hồ duy nhất (giây), nên không cần nhiều
/// controller. Bật "giảm chuyển động" thì đứng yên ở một khung hình đẹp.
class OnboardingArt extends StatefulWidget {
  const OnboardingArt({super.key, required this.index});

  /// 0: điện thoại, 1: so sánh A/B, 2: két bảo mật.
  final int index;

  @override
  State<OnboardingArt> createState() => _OnboardingArtState();
}

const int _kClockSecs = 3600;

class _ArtSpec {
  const _ArtSpec(this.asset, this.w, this.h, this.radius, this.imgW, this.imgH);
  final String asset;
  final double w, h, radius;

  /// Hệ tọa độ của ảnh gốc, dùng để đặt hiệu ứng đúng chỗ.
  final double imgW, imgH;
}

const _specs = <_ArtSpec>[
  _ArtSpec('assets/onboarding/ill1.png', 296, 291, 52, 484, 476),
  _ArtSpec('assets/onboarding/ill2.png', 310, 315, 0, 460, 468),
  _ArtSpec('assets/onboarding/ill3.png', 296, 295, 52, 400, 398),
];

class _OnboardingArtState extends State<OnboardingArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: _kClockSecs),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
      _c.value = 4.2 / _kClockSecs; // khung hình giữa chu kỳ
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = _specs[widget.index];
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final s = _c.value * _kClockSecs;
          final lift = -6 * (0.5 - 0.5 * math.cos(2 * math.pi * s / 6));
          final r = BorderRadius.circular(spec.radius);
          return Transform.translate(
            offset: Offset(0, lift),
            child: SizedBox(
              width: spec.w,
              height: spec.h,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (spec.radius > 0)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: r,
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33557800),
                              blurRadius: 40,
                              offset: Offset(0, 18),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: r,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset(
                            spec.asset,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const ColoredBox(color: Color(0xFFE6F2BE)),
                          ),
                          CustomPaint(
                            painter: _ArtPainter(
                              index: widget.index,
                              seconds: s,
                              imgW: spec.imgW,
                              imgH: spec.imgH,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.index == 1) _CountPill(seconds: s),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Nhãn "+x,y GB có thể dọn": đếm từ 0 lên 4,8 trong mỗi chu kỳ 6 giây.
class _CountPill extends StatelessWidget {
  const _CountPill({required this.seconds});
  final double seconds;

  @override
  Widget build(BuildContext context) {
    final t = (seconds % 6) / 6;
    final tenths =
        t < 0.1 ? 0 : (t < 0.6 ? ((t - 0.1) / 0.5 * 48).round() : 48);
    final pulse = 1 + 0.06 * (0.5 - 0.5 * math.cos(2 * math.pi * seconds / 3));
    return Positioned(
      right: 6,
      bottom: 14,
      child: Transform.scale(
        scale: pulse,
        child: Container(
          width: 214,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(99),
            boxShadow: const [
              BoxShadow(
                color: Color(0x38557800),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                    color: Color(0xFFA3D133), shape: BoxShape.circle),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '+${tenths ~/ 10},${tenths % 10} GB có thể dọn',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2A343F),
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

const _accent = Color(0xFFA3D133);
const _accentDeep = Color(0xFF557800);
const _accentLight = Color(0xFFC9E36B);

double _frac(double v) => v - v.floorToDouble();

Color _al(Color c, double a) =>
    c.withAlpha((a * 255).round().clamp(0, 255).toInt());

class _ArtPainter extends CustomPainter {
  _ArtPainter({
    required this.index,
    required this.seconds,
    required this.imgW,
    required this.imgH,
  });

  final int index;
  final double seconds;
  final double imgW, imgH;

  double get s => seconds;

  @override
  void paint(Canvas canvas, Size size) {
    if (index != 1) _shine(canvas, size);
    canvas.save();
    canvas.scale(size.width / imgW, size.height / imgH);
    switch (index) {
      case 0:
        _phone(canvas);
      case 1:
        _compare(canvas);
      default:
        _vault(canvas);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ArtPainter old) => old.seconds != seconds;

  // ---- hiệu ứng dùng chung ----

  /// Vệt sáng lướt ngang cả ảnh mỗi 7 giây.
  void _shine(Canvas canvas, Size size) {
    final ph = _frac(s / 7);
    if (ph < 0.3 || ph > 0.6) return;
    final p = (ph - 0.3) / 0.3;
    final x = ui.lerpDouble(-96, size.width + 60, p)!;
    canvas.save();
    canvas.translate(x, 0);
    canvas.skew(-0.32, 0);
    final rect = Rect.fromLTWH(0, 0, 60, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(colors: [
          Color(0x00FFFFFF),
          Color(0x73FFFFFF),
          Color(0x00FFFFFF),
        ]).createShader(rect),
    );
    canvas.restore();
  }

  void _star(Canvas canvas, double x, double y, double delay, double r,
      [Color c = Colors.white]) {
    final ph = _frac((s - delay) / 2.6);
    final k = 0.5 - 0.5 * math.cos(2 * math.pi * ph);
    final op = 0.25 + 0.75 * k;
    final sc = 0.7 + 0.4 * k;
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + i * math.pi / 4;
      final rr = (i.isEven ? r : r * 0.34) * sc;
      final p = Offset(x + rr * math.cos(a), y + rr * math.sin(a));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = _al(c, op));
  }

  void _halo(Canvas canvas, double x, double y, double r, double delay,
      [Color c = _accent]) {
    final ph = _frac((s - delay) / 3.4);
    final sc = 0.35 + 1.35 * ph;
    canvas.drawCircle(
      Offset(x, y),
      r * sc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _al(c, 0.8 * (1 - ph)),
    );
  }

  void _lit(Canvas canvas, double x, double y, double r, double delay) {
    final ph = _frac((s - delay) / 4.8);
    double op, sc;
    if (ph < 0.3) {
      final k = ph / 0.3;
      op = 0.85 * k;
      sc = 0.6 + 0.55 * k;
    } else if (ph < 0.6) {
      final k = (ph - 0.3) / 0.3;
      op = 0.85 * (1 - k);
      sc = 1.15 - 0.2 * k;
    } else {
      return;
    }
    final rr = r * sc;
    canvas.drawCircle(
      Offset(x, y),
      rr,
      Paint()
        ..shader = ui.Gradient.radial(Offset(x, y), rr, [
          _al(Colors.white, 0.95 * op),
          _al(const Color(0xFFD2EC82), 0),
        ]),
    );
  }

  void _bokeh(Canvas canvas, List<List<double>> items) {
    for (final it in items) {
      final x = it[0], y = it[1], r = it[2], d = it[3], dx = it[4];
      final ph = _frac((s - d) / 5);
      final op = ph < 0.15 ? 0.8 * ph / 0.15 : 0.8 * (1 - (ph - 0.15) / 0.85);
      canvas.drawCircle(
        Offset(x + dx * ph, y - 90 * ph),
        r,
        Paint()..color = _al(Colors.white, op.clamp(0.0, 1.0).toDouble()),
      );
    }
  }

  void _dot(Canvas canvas, Offset p, double r, Color glow) {
    canvas.drawCircle(
      p,
      r,
      Paint()
        ..color = glow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(p, r * 0.45, Paint()..color = Colors.white);
  }

  /// Vệt sáng quét qua [clip] theo kiểu keyframes: nghỉ, lướt, nghỉ.
  void _glint(Canvas canvas, RRect clip, double period, double w, double x0,
      double x1) {
    final ph = _frac(s / period);
    if (ph < 0.35 || ph > 0.7) return;
    final p = (ph - 0.35) / 0.35;
    final x = ui.lerpDouble(x0, x1, p)!;
    canvas.save();
    canvas.clipRRect(clip);
    final rect = Rect.fromLTWH(x, clip.top - 20, w, clip.height + 40);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(colors: [
          Color(0x00FFFFFF),
          Color(0xF2FFFFFF),
          Color(0x00FFFFFF),
        ]).createShader(rect),
    );
    canvas.restore();
  }

  // ---- 1: điện thoại ----
  void _phone(Canvas canvas) {
    // Quỹ đạo elip nét đứt quanh điện thoại + 2 chấm chạy theo.
    const cx = 243.0, cy = 255.0, rx = 222.0, ry = 105.0;
    final rot = -8 * math.pi / 180;
    Offset onOrbit(double t) {
      final x = rx * math.cos(t), y = ry * math.sin(t);
      return Offset(cx + x * math.cos(rot) - y * math.sin(rot),
          cy + x * math.sin(rot) + y * math.cos(rot));
    }

    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = _al(_accentLight, 0.7);
    const n = 200;
    for (var i = 0; i < n; i++) {
      if (i % 10 >= 3) continue;
      canvas.drawLine(onOrbit(2 * math.pi * i / n),
          onOrbit(2 * math.pi * (i + 1) / n), dash);
    }
    _dot(canvas, onOrbit(2 * math.pi * (s / 9)), 5, const Color(0xFFA3D133));
    _dot(canvas, onOrbit(2 * math.pi * ((s - 3) / 13)), 4,
        const Color(0xFF7FC4FF));

    _halo(canvas, 172, 118, 34, 0);
    _halo(canvas, 125, 200, 32, 0.7);
    _halo(canvas, 372, 236, 30, 1.4);
    _halo(canvas, 355, 315, 34, 2.1);

    _glint(
        canvas,
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(321, 156, 60, 34), const Radius.circular(17)),
        3.6,
        30,
        261,
        400);

    // Thanh tiến độ trên thẻ "Premium": ánh sáng chạy ngang.
    canvas.save();
    canvas.translate(248, 162);
    canvas.rotate(-5 * math.pi / 180);
    canvas.translate(-248, -162);
    _glint(
        canvas,
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(219, 157, 58, 9), const Radius.circular(4)),
        2.8,
        22,
        200,
        290);
    canvas.restore();

    _lit(canvas, 240, 320, 34, 0.5);
    _star(canvas, 380, 134, 0, 12, const Color(0xFFC9E36B));
    _star(canvas, 112, 143, 0.7, 8);
    _star(canvas, 82, 256, 1.3, 9, const Color(0xFFE1EFA8));
    _star(canvas, 308, 368, 0.4, 12, const Color(0xFFC9E36B));
    _star(canvas, 440, 120, 1.6, 6);
    _bokeh(canvas, const [
      [70, 380, 4, 0, 14],
      [150, 400, 3, 1.3, -8],
      [300, 410, 5, 0.7, 10],
      [420, 360, 3, 2.1, -12],
      [240, 420, 4, 2.8, 6],
    ]);
  }

  // ---- 2: so sánh A/B ----
  void _compare(Canvas canvas) {
    final ph = _frac(s / 6);

    // Tia quét đi qua hai ảnh.
    final beamTx = 320.0 * math.min(ph / 0.55, 1.0);
    final beamOp = ph < 0.08
        ? ph / 0.08
        : (ph < 0.55 ? 1.0 : (ph < 0.62 ? 1 - (ph - 0.55) / 0.07 : 0.0));
    if (beamOp > 0) {
      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(
          const Rect.fromLTWH(60, 120, 340, 190), const Radius.circular(14)));
      final rect = Rect.fromLTWH(60 + beamTx, 120, 40, 190);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(colors: [
            _al(Colors.white, 0),
            _al(Colors.white, 0.9 * beamOp),
            _al(Colors.white, 0),
          ]).createShader(rect),
      );
      canvas.restore();
    }

    // Viền cam quanh ảnh B sau khi quét: đánh dấu trùng.
    double edge;
    if (ph < 0.45) {
      edge = 0;
    } else if (ph < 0.58) {
      edge = (ph - 0.45) / 0.13;
    } else if (ph < 0.85) {
      edge = 1;
    } else {
      edge = 1 - (ph - 0.85) / 0.15;
    }
    if (edge > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(253, 137, 125, 155), const Radius.circular(12)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _al(const Color(0xFFFF7A45), edge),
      );
    }

    // Mũi tên nét đứt chạy từ A sang B.
    final shift = _frac(s / 0.9) * 12;
    final arrow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = _accent;
    for (var k = -2; k < 6; k++) {
      final a = 213 - 12 + k * 6 + shift;
      final x0 = a.clamp(213.0, 239.0).toDouble();
      final x1 = (a + 3).clamp(213.0, 239.0).toDouble();
      if (x1 > x0) canvas.drawLine(Offset(x0, 214), Offset(x1, 214), arrow);
    }

    _halo(canvas, 104, 167, 14, 0);
    _halo(canvas, 274, 167, 14, 0.8);
    _halo(canvas, 323, 305, 26, 1.6, _accentDeep);
    _star(canvas, 60, 90, 0, 10);
    _star(canvas, 400, 100, 0.9, 12, const Color(0xFFC9E36B));
    _star(canvas, 430, 250, 1.5, 8);
    _star(canvas, 40, 300, 0.5, 8);
    _bokeh(canvas, const [
      [120, 330, 4, 0, 10],
      [220, 350, 5, 1.2, -10],
      [330, 340, 4, 0.6, 12],
      [400, 320, 3, 2, -6],
      [70, 360, 3, 2.6, 8],
    ]);
  }

  // ---- 3: két bảo mật ----
  void _vault(Canvas canvas) {
    const c = Offset(205, 205);
    // Vòng chấm xoay chậm.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..color = _al(const Color(0xFFD2EC82), 0.8);
    final spin = 2 * math.pi * (s / 40);
    const nd = 80;
    for (var i = 0; i < nd; i++) {
      final a0 = spin + 2 * math.pi * i / nd;
      canvas.drawArc(Rect.fromCircle(center: c, radius: 131), a0,
          2 * math.pi / nd * 0.2, false, ring);
    }
    // 3 chấm sáng chạy quanh vòng icon.
    Offset onRing(double t) => c + Offset(131 * math.cos(t), 131 * math.sin(t));
    _dot(canvas, onRing(2 * math.pi * (s / 10)), 5, const Color(0xFFA3D133));
    _dot(canvas, onRing(2 * math.pi * ((s - 3.3) / 10)), 4,
        const Color(0xFF7FC4FF));
    _dot(canvas, onRing(2 * math.pi * ((s - 6.6) / 10)), 4, Colors.white);

    // Vệt sáng xoay trên vòng cung chính.
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: 94),
      2 * math.pi * (s / 4.5),
      60 / 591 * 2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..color = _al(Colors.white, 0.9)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    _halo(canvas, 205, 205, 60, 0);
    _halo(canvas, 205, 205, 60, 1.6);
    _lit(canvas, 205, 190, 34, 0);
    const pts = <Offset>[
      Offset(200, 75),
      Offset(268, 92),
      Offset(322, 135),
      Offset(322, 195),
      Offset(305, 255),
      Offset(270, 300),
      Offset(205, 320),
      Offset(140, 300),
      Offset(95, 255),
      Offset(80, 195),
      Offset(95, 142),
      Offset(135, 92),
    ];
    for (var i = 0; i < pts.length; i++) {
      _lit(canvas, pts[i].dx, pts[i].dy, 30, i * 0.4);
    }
    _star(canvas, 190, 30, 0, 10);
    _star(canvas, 340, 70, 0.9, 8);
    _star(canvas, 60, 60, 1.4, 8);
    _star(canvas, 350, 330, 0.5, 9);
    _star(canvas, 50, 300, 1.8, 7);
  }
}
