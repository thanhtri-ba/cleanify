import 'package:flutter/material.dart';

import '../../theme/motion.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_icon.dart';

/// Token và widget nhỏ dùng chung cho luồng Home → Quét → Kết quả → Dọn.
/// Theo logo Cleanify (nền #F2F4FA, chữ/nút chính xám than #2A343F, nhấn lime).
const kInk = Color(0xFF2A343F);
const kInk2 = Color(0xFF4A5666);
const kInk3 = Color(0xFF6B7686);
const kBg = Color(0xFFF2F4FA);
const kSurface = Color(0xFFEBEEF4);
const kChip = Color(0xFFE8ECF3);
const kBorder = Color(0xFFDFE3EC);
const kSlate = Color(0xFF2A343F);
const kBlue = Color(0xFF3E4A5A);

class HCard extends StatelessWidget {
  const HCard({super.key, required this.child, this.radius = 20, this.padding = 16});
  final Widget child;
  final double radius;
  final double padding;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: kBorder),
          boxShadow: const [
            BoxShadow(color: Color(0x0A2A343F), blurRadius: 24, offset: Offset(0, 8), spreadRadius: -4),
          ],
        ),
        child: child,
      );
}

class HDisc extends StatelessWidget {
  const HDisc(this.icon, {super.key, this.size = 36, this.bg = kSurface});
  final AppIconData icon;
  final double size;
  final Color bg;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: AppIcon(icon, size: size * 0.45, color: kInk2),
      );
}

class HPill extends StatelessWidget {
  const HPill(this.text, {super.key, this.fg = kInk3, this.bg = kChip, this.size = 11});
  final String text;
  final Color fg;
  final Color bg;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(text,
            style: TextStyle(fontSize: size, fontWeight: FontWeight.w600, color: fg)),
      );
}

class SlateButton extends StatelessWidget {
  const SlateButton({super.key, required this.label, required this.onPressed, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final AppIconData? icon;
  @override
  Widget build(BuildContext context) => PressScale(
        enabled: onPressed != null,
        child: SizedBox(
        height: 56,
        width: double.infinity,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE8ECF3),
            foregroundColor: kInk,
            disabledBackgroundColor: const Color(0xFFF0F2F6),
            disabledForegroundColor: kInk3,
            side: const BorderSide(color: Color(0xFFD3D9E4)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[AppIcon(icon!, size: 17), const SizedBox(width: 10)],
            AnimatedSwitcher(
              duration: kMotionFast,
              child: Text(label, key: ValueKey(label)),
            ),
          ]),
        ),
      ));
}

class OutlineBtn extends StatelessWidget {
  const OutlineBtn({super.key, required this.label, required this.onPressed, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final AppIconData? icon;
  @override
  Widget build(BuildContext context) => PressScale(
        enabled: onPressed != null,
        child: SizedBox(
        height: 52,
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: kInk,
            backgroundColor: Colors.white,
            side: const BorderSide(color: kInk),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[AppIcon(icon!, size: 16), const SizedBox(width: 10)],
            Text(label),
          ]),
        ),
      ));
}

/// Thanh trên: nút tròn trái/phải + tiêu đề giữa.
class HTopBar extends StatelessWidget {
  const HTopBar({super.key, required this.title, this.onBack, this.showMore = false});
  final String title;
  final VoidCallback? onBack;
  final bool showMore;
  Widget _b(AppIconData i, VoidCallback? f) => Material(
        color: Colors.white,
        shape: const CircleBorder(side: BorderSide(color: Color(0x66C6C6C6))),
        child: InkWell(
            customBorder: const CircleBorder(),
            onTap: f,
            child: SizedBox(width: 40, height: 40, child: AppIcon(i, size: 18, color: kInk))),
      );
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          onBack == null ? const SizedBox(width: 40) : _b(AppIcons.arrowBackIosNewRounded, onBack),
          Text(title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: kInk)),
          showMore ? _b(AppIcons.moreHoriz, null) : const SizedBox(width: 40),
        ]),
      );
}

/// Ba ô thống kê có đường kẻ dọc.
class HStats extends StatelessWidget {
  const HStats(this.items, {super.key});
  final List<(String, String)> items;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 17),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x66C6C6C6)),
          boxShadow: const [
            BoxShadow(color: Color(0x14676767), blurRadius: 30, offset: Offset(0, 10), spreadRadius: -4)
          ],
        ),
        child: IntrinsicHeight(
          child: Row(children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const VerticalDivider(width: 1, color: Color(0x4DC6C6C6)),
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(items[i].$1,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600, color: kInk)),
                  const SizedBox(height: 2),
                  Text(items[i].$2,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600, color: kInk2)),
                ]),
              ),
            ],
          ]),
        ),
      );
}

String gb(num n) => n.toStringAsFixed(1).replaceAll('.', ',');
