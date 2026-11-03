import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/scanner/scan_diagnostics.dart';
import '../../core/scanner/scan_orchestrator.dart';
import '../../core/scanner/scan_progress.dart';
import '../../core/scanner/scan_session.dart';

enum ScanStatus { idle, scanning, done, error }

/// Giữ ScanSession trong RAM. Không lưu gì xuống đĩa.
/// Session bị dispose khi người dùng bấm xóa kết quả hoặc app bị detach.
class ScanController extends ChangeNotifier with WidgetsBindingObserver {
  ScanController({ScanOrchestrator? orchestrator})
      : _orchestrator = orchestrator ?? ScanOrchestrator() {
    WidgetsBinding.instance.addObserver(this);
  }

  final ScanOrchestrator _orchestrator;

  ScanStatus status = ScanStatus.idle;
  ScanProgress? progress;
  ScanSession? session;
  String? error;

  final Stopwatch _stopwatch = Stopwatch();

  /// Thời gian quét đã trôi qua, không tính lúc tạm dừng.
  Duration get elapsed => _stopwatch.elapsed;

  Future<void> start() async {
    if (status == ScanStatus.scanning) return;
    await session?.dispose();
    final s = ScanSession(
        diag: scanDiagEnabled() ? ScanDiagnostics() : null);
    session = s;
    status = ScanStatus.scanning;
    error = null;
    progress = null;
    _stopwatch
      ..reset()
      ..start();
    notifyListeners();

    try {
      await _orchestrator.run(
        s,
        (p) {
          progress = p;
          notifyListeners();
        },
      );
      _stopwatch.stop();
      s.elapsed = _stopwatch.elapsed;
      status = ScanStatus.done;
    } on ScanCancelled {
      await s.dispose();
      session = null;
      status = ScanStatus.idle;
    } on PermissionDeniedException {
      session = null;
      status = ScanStatus.error;
      error = 'Cần cấp quyền truy cập thư viện ảnh để quét.';
    } catch (e) {
      session = null;
      status = ScanStatus.error;
      error = 'Quét thất bại: $e';
    }
    _stopwatch.stop();
    if (status != ScanStatus.done) _stopwatch.reset();
    notifyListeners();
  }

  /// Đang tạm dừng hay không. Trạng thái thật nằm ở ScanSession.
  bool get paused => session?.paused ?? false;

  void pause() {
    session?.pause();
    if (status == ScanStatus.scanning) _stopwatch.stop();
    notifyListeners();
  }

  void resume() {
    session?.resume();
    if (status == ScanStatus.scanning) _stopwatch.start();
    notifyListeners();
  }

  void cancel() {
    session?.cancelled = true;
    session?.resume();
  }

  /// Chẩn đoán của phiên hiện tại; null khi không bật chẩn đoán.
  ScanDiagnostics? get diag => session?.diag;

  /// Ghi CSV chẩn đoán (mọi tab) vào thư mục documents của app.
  Future<File?> exportDiagCsv() async {
    final s = session;
    final d = s?.diag;
    if (s == null || d == null) return null;
    return d.writeCsv({
      'dup': s.groups,
    });
  }

  /// Xóa toàn bộ kết quả khỏi RAM.
  Future<void> clearResults() async {
    await session?.dispose();
    session = null;
    progress = null;
    _stopwatch
      ..stop()
      ..reset();
    status = ScanStatus.idle;
    notifyListeners();
  }

  /// Xóa ảnh thật khỏi thiết bị. Chỉ gọi sau khi người dùng đã xác nhận.
  Future<int> deleteAssets(List<AssetEntity> assets) async {
    final deleted =
        await PhotoManager.editor.deleteWithIds(assets.map((a) => a.id).toList());
    session?.removeAssets(deleted.toSet());
    notifyListeners();
    return deleted.length;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      clearResults();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    session?.dispose();
    super.dispose();
  }
}
