import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import 'onboarding_art.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_icon.dart';

Future<PermissionState> _defaultRequest() =>
    PhotoManager.requestPermissionExtend();
Future<void> _defaultOpenSettings() => PhotoManager.openSetting();

enum _Perm { initial, requesting, denied }

// Bảng màu "nhẹ": nền sáng, nút xanh xám, điểm nhấn tím nhạt.
const Color _ink = Color(0xFF2A343F);
const Color _mute = Color(0xFF6B7686);
const Color _btn = Color(0xFF2A343F);
const Color _line = Color(0xFFE8E9EF);
const Color _accent = Color(0xFF557800);
const Color _accentSoft = Color(0xFFE6F2BE);
const Color _chip = Color(0xFFF1F2F6);

const _bgGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFFFDFDFF), Color(0xFFF3F3F8)],
);

TextStyle _t(double size, double line, FontWeight w, Color c,
        {double spacing = 0}) =>
    TextStyle(
      fontSize: size,
      height: line / size,
      fontWeight: w,
      color: c,
      letterSpacing: spacing,
    );

/// Onboarding 3 trang + trang xin quyền Ảnh. Không lưu cờ "đã xem" xuống đĩa
/// (app stateless): nơi gọi quyết định có hiển thị hay không.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    super.key,
    required this.onFinished,
    this.requestPermission = _defaultRequest,
    this.openSettings = _defaultOpenSettings,
  });

  final VoidCallback onFinished;
  final Future<PermissionState> Function() requestPermission;
  final Future<void> Function() openSettings;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  static const int _permStep = 3;
  int _step = 0;
  _Perm _perm = _Perm.initial;

  void _go(int step) => setState(() => _step = step);

  Future<void> _allow() async {
    if (_perm == _Perm.requesting) return;
    setState(() => _perm = _Perm.requesting);
    PermissionState result;
    try {
      result = await widget.requestPermission();
    } catch (_) {
      result = PermissionState.denied;
    }
    if (!mounted) return;
    if (result.hasAccess) {
      widget.onFinished();
    } else {
      setState(() => _perm = _Perm.denied);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FB),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: _bgGradient),
        child: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: KeyedSubtree(
              key: ValueKey(_step),
              child: _step == _permStep ? _permissionPage() : _introPage(),
            ),
          ),
        ),
      ),
    );
  }

  // ---- 3 trang giới thiệu ----
  static const _intro = <_IntroData>[
    _IntroData(
      title: 'Dọn ảnh trùng,\nnhẹ máy ngay',
      body: 'Giải phóng dung lượng bằng cách tìm\n'
          'những ảnh giống nhau trong thư viện.',
      cta: 'Bắt đầu',
    ),
    _IntroData(
      title: 'Giữ bản đẹp nhất,\nbỏ bản trùng',
      body: 'Ảnh giống nhau được gom thành nhóm.\n'
          'Bạn chọn, chỉ xóa khi xác nhận.',
      cta: 'Tiếp tục',
    ),
    _IntroData(
      title: 'Ảnh của bạn ở lại\ntrên máy',
      body: 'Quét và so sánh ngay trên điện thoại.\n'
          'Mọi thao tác xóa đều hỏi bạn trước.',
      cta: 'Tiếp tục',
    ),
  ];

  Widget _introPage() {
    final d = _intro[_step];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: const _Logo(),
                  ),
                ),
                _SkipPill(onPressed: () => _go(_permStep)),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: OnboardingArt(index: _step),
                ),
              ),
            ),
          ),
          Text(
            d.title,
            textAlign: TextAlign.center,
            style: _t(25, 31, FontWeight.w700, _ink, spacing: -0.5),
          ),
          const SizedBox(height: 10),
          Text(
            d.body,
            textAlign: TextAlign.center,
            style: _t(14, 22, FontWeight.w400, _mute),
          ),
          const SizedBox(height: 30),
          _Dots(step: _step),
          const SizedBox(height: 20),
          _PrimaryButton(
            label: d.cta,
            trailing: _step == 0 ? null : AppIcons.arrowForwardRounded,
            onPressed: () => _go(_step + 1),
          ),
          SizedBox(height: 44, child: _footer()),
        ],
      ),
    );
  }

  Widget _footer() {
    switch (_step) {
      case 0:
        return Center(
          child: Text('Không cần tài khoản',
              style: _t(13, 18, FontWeight.w500, _ink)),
        );
      case 1:
        return TextButton(
          onPressed: () => _go(0),
          style: TextButton.styleFrom(
            foregroundColor: _ink,
            textStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          child: const Text('Quay lại'),
        );
      default:
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Không tải ảnh lên',
                  style: _t(12, 16, FontWeight.w400, _ink)),
              const SizedBox(width: 10),
              Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                    color: Color(0xFFB8BCC8), shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Text('Không lưu lịch sử',
                  style: _t(12, 16, FontWeight.w400, _ink)),
            ],
          ),
        );
    }
  }

  // ---- trang xin quyền ----
  Widget _permissionPage() {
    final denied = _perm == _Perm.denied;
    final requesting = _perm == _Perm.requesting;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 44,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Semantics(
                            button: true,
                            label: 'Quay lại',
                            child: InkResponse(
                              onTap: requesting ? null : () => _go(2),
                              radius: 22,
                              child: Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: const BoxDecoration(
                                      color: _chip, shape: BoxShape.circle),
                                  child: const AppIcon(AppIcons.chevronLeftRounded,
                                      size: 20, color: _ink),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Text('Quyền truy cập ảnh',
                          style: _t(15, 22, FontWeight.w600, _ink)),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 1, color: _line),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Cleanify cần đọc thư viện ảnh để tìm ảnh trùng và gợi '
                        'ý bản nên giữ.',
                        style: _t(14, 21, FontWeight.w400, _ink),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Quyền này chỉ dùng để quét và so sánh. Bạn vẫn dùng '
                        'được các phần khác của app khi chưa cấp quyền.',
                        style: _t(12, 17, FontWeight.w400, _mute),
                      ),
                      const SizedBox(height: 16),
                      const _PermissionArt(),
                      const SizedBox(height: 12),
                      _StatusRow(denied: denied),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F5F8),
                          border: Border.all(color: _line),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Nếu chỉ chọn một số ảnh, chỉ những ảnh đó được quét. '
                          'Bạn có thể đổi lại trong Cài đặt.',
                          style: _t(12, 17, FontWeight.w400, _mute),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PrimaryButton(
                        label: denied ? 'Mở Cài đặt' : 'Cho phép truy cập ảnh',
                        busy: requesting,
                        onPressed: denied ? widget.openSettings : _allow,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: requesting ? null : widget.onFinished,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _mute,
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: _line),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            textStyle: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                          child: const Text('Để sau'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IntroData {
  const _IntroData(
      {required this.title, required this.body, required this.cta});
  final String title;
  final String body;
  final String cta;
}

// ---------------------------------------------------------------------------
// Thành phần nhỏ
// ---------------------------------------------------------------------------

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x332A343F),
                  blurRadius: 10,
                  offset: Offset(0, 2)),
            ],
          ),
          child:
              const AppIcon(AppIcons.autoAwesomeOutlined, size: 20, color: _accent),
        ),
        const SizedBox(width: 10),
        Text('Cleanify', style: _t(17, 22, FontWeight.w700, _ink)),
      ],
    );
  }
}

class _SkipPill extends StatelessWidget {
  const _SkipPill({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Vùng chạm 44px, hình pill nhìn thấy 30px.
    return Semantics(
      button: true,
      label: 'Bỏ qua',
      child: InkResponse(
        onTap: onPressed,
        radius: 28,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Center(
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFE8ECF3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Bỏ qua',
                  style: _t(13, 18, FontWeight.w600, const Color(0xFF2A343F))),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 3; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == step ? 22 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == step ? _btn : const Color(0xFFD6D9E2),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.trailing,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final AppIconData? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1F2A343F), blurRadius: 14, offset: Offset(0, 6)),
        ],
      ),
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFE8ECF3),
          foregroundColor: _btn,
          disabledBackgroundColor: const Color(0xFFE8ECF3),
          disabledForegroundColor: _btn,
          side: const BorderSide(color: Color(0xFFD3D9E4)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _btn),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(label,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    AppIcon(trailing!, size: 18),
                  ],
                ],
              ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.denied});
  final bool denied;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const AppIcon(AppIcons.imageOutlined, size: 22, color: _ink),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Quyền truy cập ảnh',
                    style: _t(14, 20, FontWeight.w600, _ink)),
                Text('Cần để quét và gợi ý ảnh nên dọn.',
                    style: _t(12, 16, FontWeight.w400, _mute)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: denied ? const Color(0xFFFFE9E1) : _chip,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              denied ? 'Bị từ chối' : 'Chưa cấp',
              style: _t(11, 14, FontWeight.w600,
                  denied ? const Color(0xFFB23A12) : _ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// Khung icon ảnh lơ lửng với sóng lan, đặt trong thẻ trắng 196px.
class _PermissionArt extends StatefulWidget {
  const _PermissionArt();

  @override
  State<_PermissionArt> createState() => _PermissionArtState();
}

class _PermissionArtState extends State<_PermissionArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
      _c.value = 0.3;
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
    return Container(
      height: 196,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final s = _c.value * 6;
          final lift = -6 * (0.5 - 0.5 * math.cos(2 * math.pi * s / 6));
          return Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.infinite,
                painter: _RipplePainter(s),
              ),
              Transform.translate(
                offset: Offset(0, lift),
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x38557800),
                          blurRadius: 28,
                          offset: Offset(0, 12)),
                    ],
                  ),
                  child: const AppIcon(AppIcons.imageOutlined,
                      size: 40, color: _accent),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  _RipplePainter(this.s);
  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    // Quầng sáng mờ.
    final glow = 0.5 + 0.5 * math.sin(2 * math.pi * s / 4);
    canvas.drawCircle(
      c,
      75 * (1 + 0.1 * glow),
      Paint()
        ..shader = RadialGradient(colors: [
          _accentSoft.withAlpha((120 + 40 * glow).round()),
          _accentSoft.withAlpha(0),
        ]).createShader(Rect.fromCircle(center: c, radius: 80)),
    );
    // Hai vòng sóng lệch pha.
    for (final delay in const [0.0, 1.5]) {
      var ph = ((s - delay) / 3) % 1;
      if (ph < 0) ph += 1;
      canvas.drawCircle(
        c,
        50 * (0.55 + 0.95 * ph),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _accent.withAlpha((140 * (1 - ph)).round()),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter old) => old.s != s;
}
