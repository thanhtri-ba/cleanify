import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'app_icons.dart';
import 'app_icon.dart';

/// Card của bản thiết kế: nền surface, viền 1px, bo 20, padding 20.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.appColors.line),
      ),
      child: child,
    );
  }
}

/// Nhãn nhỏ viết hoa (11px, letter-spacing .06em).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        height: 14 / 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.66,
        color: context.appColors.text3,
      ),
    );
  }
}

/// Thanh tiến trình 8px với gradient nhấn. value == null: đang chuẩn bị.
class GradientBar extends StatelessWidget {
  const GradientBar({super.key, this.value, this.tintedTrack = false});
  final double? value;

  /// Nền thanh là gradient nhạt thay vì xám (cho thanh đang trống vẫn có màu).
  final bool tintedTrack;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final v = value;
    if (v == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          minHeight: 8,
          color: c.accent1,
          backgroundColor: c.line,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 8,
        decoration: tintedTrack
            ? BoxDecoration(gradient: LinearGradient(colors: [c.tint1, c.tint2]))
            : BoxDecoration(color: c.line),
        alignment: Alignment.centerLeft,
        child: AnimatedFractionallySizedBox(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          widthFactor: v.clamp(0.0, 1.0),
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: c.gradient),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// Logo Cleanify (assets/brand/mark.png), bo góc theo [size].
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Image.asset(
        'assets/brand/mark.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(gradient: context.appColors.gradient),
          child: AppIcon(AppIcons.photoLibraryOutlined, size: size * 0.6, color: Colors.white),
        ),
      ),
    );
  }
}

/// Hai vệt màu mờ ở đầu trang (teal trái, blue phải). Đặt trong Stack, dưới nội dung.
class Aura extends StatelessWidget {
  const Aura({super.key});

  @override
  Widget build(BuildContext context) {
    final x = context.appColors;
    Widget blob(Alignment center, double radius, Color color) => Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: center,
                radius: radius,
                colors: [color, const Color(0x00000000)],
              ),
            ),
          ),
        );
    return IgnorePointer(
      child: SizedBox(
        height: 460,
        child: Stack(children: [
          blob(const Alignment(-0.7, -1.0), 0.9, x.tint1),
          blob(const Alignment(1.0, -0.8), 0.8, x.tint2),
        ]),
      ),
    );
  }
}

/// Thanh các bước: bước đã xong tô đầy gradient, bước hiện tại tô theo [current].
class FlowTracker extends StatelessWidget {
  const FlowTracker({
    super.key,
    required this.labels,
    required this.index,
    required this.current,
  });
  final List<String> labels;
  final int index; // bước đang chạy
  final double current; // 0..1 của bước đang chạy

  @override
  Widget build(BuildContext context) {
    final x = context.appColors;
    final ink = Theme.of(context).colorScheme.onSurface;
    return Row(children: [
      for (var i = 0; i < labels.length; i++)
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Container(
                  height: 4,
                  color: x.line,
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: i < index ? 1.0 : (i == index ? current.clamp(0.0, 1.0) : 0.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(gradient: x.gradient),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(labels[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      height: 14 / 11,
                      fontWeight: FontWeight.w600,
                      color: i <= index ? ink : x.text3)),
            ]),
          ),
        ),
    ]);
  }
}
