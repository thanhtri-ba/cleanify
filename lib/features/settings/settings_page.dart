import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../home/home_kit.dart';
import '../scan/scan_controller.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_icon.dart';

/// Cài đặt: trạng thái quyền ảnh (+ lối tắt sửa), xóa kết quả quét đang giữ trong
/// bộ nhớ, và cam kết riêng tư. App không lưu dữ liệu nên không có cài đặt tài khoản.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});
  final ScanController controller;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with WidgetsBindingObserver {
  PermissionState? _perm;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final p = await PhotoManager.getPermissionState(
        requestOption: const PermissionRequestOption());
    if (mounted) setState(() => _perm = p);
  }

  String get _permText {
    switch (_perm) {
      case null:
        return 'Đang kiểm tra…';
      case PermissionState.authorized:
        return 'Đã cho phép truy cập tất cả ảnh';
      case PermissionState.limited:
        return 'Chỉ truy cập một phần ảnh — kết quả quét sẽ thiếu';
      default:
        return 'Chưa được cấp quyền truy cập ảnh';
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa kết quả quét?'),
        content: const Text(
            'Chỉ xóa danh sách kết quả trong app. Ảnh trong thư viện không bị ảnh hưởng.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          TextButton(
              onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.controller.clearResults();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Đã xóa kết quả quét.')));
  }

  @override
  Widget build(BuildContext context) {
    final limited = _perm == PermissionState.limited;
    final denied = _perm != null && !(_perm!.hasAccess);
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(children: [
          HTopBar(title: 'Cài đặt', onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
              HCard(
                padding: 4,
                child: Column(children: [
                  ListTile(
                    leading: AppIcon(
                        limited || denied ? AppIcons.warningAmberRounded : AppIcons.lockOpen,
                        color: limited || denied ? Colors.orange : kInk),
                    title: const Text('Quyền truy cập ảnh'),
                    subtitle: Text(_permText),
                  ),
                  if (limited)
                    ListTile(
                      leading: const AppIcon(AppIcons.photoLibraryOutlined, color: kInk),
                      title: const Text('Chọn thêm ảnh được phép'),
                      onTap: () => PhotoManager.presentLimited(),
                    ),
                  if (limited || denied)
                    ListTile(
                      leading: const AppIcon(AppIcons.settingsOutlined, color: kInk),
                      title: const Text('Mở Cài đặt để cho phép tất cả ảnh'),
                      trailing: const AppIcon(AppIcons.chevronRight),
                      onTap: () => PhotoManager.openSetting(),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              HCard(
                padding: 4,
                child: ListenableBuilder(
                  listenable: widget.controller,
                  builder: (_, __) => ListTile(
                    leading: const AppIcon(AppIcons.deleteSweepOutlined, color: kInk),
                    title: const Text('Xóa kết quả quét'),
                    subtitle: const Text('Làm mới danh sách trùng/tương tự trong app'),
                    enabled: !widget.controller.busy,
                    onTap: _clear,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const HCard(
                padding: 16,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Riêng tư',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
                  SizedBox(height: 8),
                  Text(
                      '• Quét hoàn toàn trên máy, không tải ảnh lên mạng.\n'
                      '• Không lưu cơ sở dữ liệu; kết quả mất khi đóng app.\n'
                      '• Chỉ xóa ảnh sau khi bạn xác nhận. Ảnh đã xóa nằm trong '
                      '"Đã xóa gần đây" của iOS 30 ngày.',
                      style: TextStyle(fontSize: 13, height: 1.5, color: kInk2)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
