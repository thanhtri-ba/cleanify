import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_icons.dart';
import 'app_theme.dart';

/// Vẽ một [AppIconData]. Dùng như [Icon]: [size] và [color] mặc định lấy từ
/// [IconTheme] (nút Material tự đặt màu chữ cho icon bên trong). Chi tiết nhấn lime
/// lấy từ theme: lime đậm trên nền sáng, lime sáng khi icon có màu sáng (đặt trên nền đậm).
/// [accent] ghi đè màu nhấn; truyền cùng màu với [color] để có icon một màu.
class AppIcon extends StatelessWidget {
  const AppIcon(this.data, {super.key, this.size, this.color, this.accent});
  final AppIconData data;
  final double? size;
  final Color? color;
  final Color? accent;

  static final Map<String, String> _cache = {};

  static String _hex(Color c) =>
      '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24.0;
    final base = color ?? theme.color ?? const Color(0xFF2A343F);
    final x = context.appColors;
    final acc = accent ?? (base.computeLuminance() > 0.5 ? x.accentSoft : x.accent1);
    // Icon nhỏ cần nét dày hơn một chút để không bị mảnh.
    final sw = s <= 20 ? 1.9 : 1.75;
    final key = '${data.name}|${base.value}|${acc.value}|$sw';
    final svg = _cache.putIfAbsent(key, () {
      final body = data.body.replaceAll('class="a"', 'stroke="${_hex(acc)}" stroke-opacity="${acc.opacity.toStringAsFixed(3)}"');
      return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
          'stroke="${_hex(base)}" stroke-opacity="${base.opacity.toStringAsFixed(3)}" '
          'stroke-width="$sw" stroke-linecap="round" stroke-linejoin="round">$body</svg>';
    });
    return SvgPicture.string(svg,
        width: s, height: s, excludeFromSemantics: true);
  }
}
