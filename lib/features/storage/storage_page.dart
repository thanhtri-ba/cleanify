import 'package:flutter/material.dart';

import '../home/home_kit.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_icon.dart';

/// Màn "Bộ nhớ": số liệu dung lượng iPhone (do Home đọc từ iOS) và lối tắt tới các
/// công cụ dọn dẹp. Không tự đọc dữ liệu nên không tốn thêm quyền hay thời gian.
class StoragePage extends StatelessWidget {
  const StoragePage({
    super.key,
    required this.total,
    required this.free,
    required this.photoBytes,
    required this.videoBytes,
    required this.photos,
    required this.videos,
    required this.onLargeVideos,
    required this.onScreenshots,
  });

  final int? total, free, photoBytes, videoBytes, photos, videos;
  final VoidCallback onLargeVideos, onScreenshots;

  static String _gb(int? b) =>
      b == null ? '—' : '${(b / 1e9).toStringAsFixed(1).replaceAll('.', ',')} GB';

  @override
  Widget build(BuildContext context) {
    final used = total != null && free != null ? total! - free! : null;
    final other = used != null && photoBytes != null && videoBytes != null
        ? (used - photoBytes! - videoBytes!).clamp(0, used).toInt()
        : null;

    Widget row(Color? dot, AppIconData? icon, String name, String value, [String? sub]) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            if (dot != null)
              Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle))
            else if (icon != null)
              AppIcon(icon, size: 18, color: kInk3),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontSize: 14, color: kInk)),
                if (sub != null)
                  Text(sub, style: const TextStyle(fontSize: 12, color: kInk3)),
              ]),
            ),
            Text(value,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
          ]),
        );

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(children: [
          HTopBar(title: 'Bộ nhớ', onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
              HCard(
                padding: 16,
                child: Column(children: [
                  row(null, AppIcons.phoneIphone, 'Tổng dung lượng', _gb(total)),
                  row(null, AppIcons.checkCircleOutline, 'Còn trống', _gb(free)),
                  row(null, AppIcons.pieChartOutline, 'Đã dùng', _gb(used)),
                ]),
              ),
              const SizedBox(height: 12),
              HCard(
                padding: 16,
                child: Column(children: [
                  row(const Color(0xFFA3D133), null, 'Ảnh', _gb(photoBytes),
                      photos == null ? null : '$photos ảnh'),
                  row(const Color(0xFF3B82F6), null, 'Video', _gb(videoBytes),
                      videos == null ? null : '$videos video'),
                  row(const Color(0xFFF59E0B), null, 'Khác (app, hệ thống)', _gb(other)),
                ]),
              ),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 8, 4, 12),
                child: Text(
                    'Dung lượng Ảnh/Video là tổng kích thước file gốc trong thư viện, '
                    'có thể lệch nhẹ so với mục Cài đặt > Cài đặt chung > Dung lượng iPhone.',
                    style: TextStyle(fontSize: 12, height: 1.4, color: kInk3)),
              ),
              HCard(
                padding: 4,
                child: Column(children: [
                  ListTile(
                    leading: const AppIcon(AppIcons.videocamOutlined, color: kInk),
                    title: const Text('Video dung lượng lớn'),
                    subtitle: const Text('Tìm video nặng để giải phóng nhanh'),
                    trailing: const AppIcon(AppIcons.chevronRight),
                    onTap: onLargeVideos,
                  ),
                  ListTile(
                    leading: const AppIcon(AppIcons.screenshotOutlined, color: kInk),
                    title: const Text('Ảnh chụp màn hình'),
                    subtitle: const Text('Dọn ảnh chụp màn hình cũ'),
                    trailing: const AppIcon(AppIcons.chevronRight),
                    onTap: onScreenshots,
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
