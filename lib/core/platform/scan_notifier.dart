import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thông báo cho lần quét. Android: dịch vụ nền (foreground service) giữ tiến trình sống
/// khi thoát app và hiện thanh tiến độ. iOS không cho quét lâu ở nền, nên chỉ nhắc mở lại
/// app. Mọi lỗi đều bị nuốt: thông báo hỏng không được làm hỏng việc quét.
class ScanNotifier {
  ScanNotifier._();
  static final ScanNotifier instance = ScanNotifier._();

  static const _idProgress = 1;
  static const _idDone = 2;
  static const _idResume = 3;
  static const _channel = 'scan';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _service = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ));
      _ready = true;
    } catch (_) {}
  }

  /// Hỏi quyền thông báo (Android 13+ và iOS). Trả về true nếu được cấp.
  Future<bool> requestPermission() async {
    await init();
    try {
      if (Platform.isAndroid) {
        return await _android?.requestNotificationsPermission() ?? false;
      }
      if (Platform.isIOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, sound: true) ??
            false;
      }
    } catch (_) {}
    return false;
  }

  /// Bắt đầu hoặc cập nhật thông báo đang quét. Android: lần đầu bật dịch vụ nền.
  Future<void> showProgress(int percent, int groups) async {
    if (!Platform.isAndroid) return;
    await init();
    final body = groups > 0 ? 'Đã tìm thấy $groups nhóm ảnh trùng' : 'Đang đọc thư viện ảnh';
    final details = AndroidNotificationDetails(
      _channel,
      'Tiến độ quét',
      channelDescription: 'Tiến độ quét ảnh trùng',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: percent.clamp(0, 100),
    );
    try {
      if (!_service) {
        await _android?.startForegroundService(
          _idProgress,
          'Đang quét ảnh · $percent%',
          body,
          notificationDetails: details,
          foregroundServiceTypes: {AndroidServiceForegroundType.foregroundServiceTypeDataSync},
        );
        _service = true;
      } else {
        await _plugin.show(_idProgress, 'Đang quét ảnh · $percent%', body,
            NotificationDetails(android: details));
      }
    } catch (_) {}
  }

  /// Tắt dịch vụ nền và gỡ thông báo tiến độ.
  Future<void> stopProgress() async {
    try {
      if (_service) {
        await _android?.stopForegroundService();
        _service = false;
      }
      await _plugin.cancel(_idProgress);
    } catch (_) {}
  }

  Future<void> showDone(int groups, int photos) async {
    await init();
    final title = groups == 0 ? 'Quét xong, không có ảnh trùng' : 'Quét xong, tìm thấy $groups nhóm';
    final body = groups == 0
        ? 'Thư viện ảnh của bạn đã gọn.'
        : '$photos ảnh trùng. Bấm để xem lại và chọn ảnh xóa.';
    try {
      await _plugin.show(
        _idDone,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails('scan_done', 'Quét xong',
              channelDescription: 'Báo khi quét ảnh xong',
              importance: Importance.high,
              priority: Priority.high),
          iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
        ),
      );
    } catch (_) {}
  }

  /// iOS: app ra nền thì việc quét dừng; nhắc người dùng mở lại để quét tiếp.
  Future<void> showResumeHint() async {
    if (!Platform.isIOS) return;
    await init();
    try {
      await _plugin.show(
        _idResume,
        'Cleanify đang chờ bạn',
        'Mở lại app để quét tiếp, thông báo sẽ hiện khi xong.',
        const NotificationDetails(iOS: DarwinNotificationDetails(presentAlert: true)),
      );
    } catch (_) {}
  }

  Future<void> clearResumeHint() async {
    try {
      await _plugin.cancel(_idResume);
    } catch (_) {}
  }
}
