import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/platform/scan_notifier.dart';
import '../../core/scanner/active_clock.dart';
import '../../core/scanner/scan_diagnostics.dart';
import '../../core/scanner/scan_mode.dart';
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

  /// Tiến độ tổng (0..1) của lần quét: chỉ tăng, không bao giờ lùi, và chỉ đạt 1 khi xong.
  double overall = 0;
  ScanSession? session;
  String? error;

  final ActiveClock _stopwatch = ActiveClock();

  /// Thời gian quét đã trôi qua, không tính lúc tạm dừng và lúc app ra nền.
  Duration get elapsed => _stopwatch.elapsed;

  int _runId = 0;

  /// Báo khi quét xong lúc app ở nền. Chỉ giữ trong RAM (app không lưu cài đặt).
  bool notifyWhenDone = true;
  AppLifecycleState _life = AppLifecycleState.resumed;
  int _lastPct = -1;
  final ScanNotifier _notif = ScanNotifier.instance;

  void setNotifyWhenDone(bool v) {
    notifyWhenDone = v;
    if (v) _notif.requestPermission();
    notifyListeners();
  }

  /// Bước AI cho tab "Tương tự" đang chạy nền sau khi đã có kết quả ảnh trùng.
  bool refining = false;
  ScanProgress? refineProgress;

  /// Còn bước AI chưa chạy (người dùng chủ động bấm ở tab "Tương tự").
  bool get canRefine =>
      status == ScanStatus.done && !refining && _orchestrator.canRefine;

  /// Chạy bước AI tìm ảnh tương tự cho kết quả hiện tại.
  Future<void> startRefine() async {
    final s = session;
    if (s == null || !canRefine) return;
    shown = ScanMode(duplicates: shown.duplicates, similar: true);
    await _refine(s, _runId);
  }

  Future<void> _refine(ScanSession s, int runId) async {
    if (!_orchestrator.canRefine) return;
    refining = true;
    refineProgress = null;
    notifyListeners();
    try {
      await _orchestrator.refineSimilar(s, (p) {
        if (runId != _runId) return;
        refineProgress = p;
        notifyListeners();
      });
    } catch (e) {
      s.timings.add('AI nền: dừng ($e)');
    }
    if (runId == _runId) {
      refining = false;
      refineProgress = null;
      notifyListeners();
    }
  }

  /// Đang quét thật sự (đã bấm hủy thì không còn tính là bận, dù lần chạy cũ
  /// có thể còn đang dừng nốt ở nền).
  bool get busy => status == ScanStatus.scanning && session?.cancelled != true;

  /// Kiểu quét của lần quét hiện tại và thời gian dự kiến (0 nếu không biết số ảnh).
  ScanMode mode = const ScanMode();

  /// Loại kết quả đang hiển thị (đã quét và còn dữ liệu). Quét lại loại nào thì loại
  /// đó bị bỏ khỏi đây NGAY, nên số ảnh về 0 rồi mới có số mới; loại khác giữ nguyên.
  ScanMode shown = const ScanMode(duplicates: false, similar: false);

  /// Nhóm của loại không quét lại, giữ để hiển thị trong lúc đang quét.
  List<DuplicateGroup> keptGroups = [];

  Duration estimated = Duration.zero;

  Future<void> start({ScanMode mode = const ScanMode(), int? photos}) async {
    if (busy) return;
    // Giữ kết quả loại KHÔNG quét lại (vd. quét trùng rồi quét tương tự: vẫn còn cả hai).
    final hadPrev = status == ScanStatus.done && session != null;
    final prevShown = hadPrev ? shown : const ScanMode(duplicates: false, similar: false);
    final prevGroups =
        hadPrev ? List<DuplicateGroup>.of(session!.groups) : <DuplicateGroup>[];
    this.mode = mode;
    shown = ScanMode(
        duplicates: prevShown.duplicates && !mode.duplicates,
        similar: prevShown.similar && !mode.similar);
    keptGroups = [
      for (final g in prevGroups)
        if (g.kind == GroupKind.duplicate ? !mode.duplicates : !mode.similar) g
    ];
    estimated = photos == null ? Duration.zero : estimateScan(photos, mode);
    final runId = ++_runId;
    await session?.dispose();
    // TẠM: luôn bật chẩn đoán để xuất CSV từ bản build hiện tại. Khôi phục
    // thành `scanDiagEnabled() ? ScanDiagnostics() : null` khi xong.
    final s = ScanSession(diag: ScanDiagnostics());
    session = s;
    status = ScanStatus.scanning;
    error = null;
    progress = null;
    overall = 0;
    _stopwatch
      ..reset()
      ..start();
    notifyListeners();
    _lastPct = -1;
    _notif.showProgress(0, 0); // Android: bật dịch vụ nền để quét tiếp khi thoát app

    try {
      await _orchestrator.run(
        s,
        (p) {
          if (runId != _runId) return;
          progress = p;
          overall = math.max(overall, overallProgress(mode, p));
          final pct = (overall * 100).floor();
          if (pct != _lastPct) {
            _lastPct = pct;
            _notif.showProgress(pct, s.liveGroups);
          }
          notifyListeners();
        },
        clock: _stopwatch,
        mode: mode,
      );
      if (runId != _runId) return; // đã có lần quét mới thay thế
      _stopwatch.stop();
      s.elapsed = _stopwatch.elapsed;
      final bg = _stopwatch.backgroundTime;
      if (bg.inSeconds > 0) {
        s.timings.add('app ở nền ${bg.inSeconds}s (không tính vào thời gian quét)');
      }
      if (hadPrev) {
        final live = {for (final a in s.assets) a.id};
        for (final g in prevGroups) {
          final rescanned =
              g.kind == GroupKind.duplicate ? mode.duplicates : mode.similar;
          if (rescanned) continue;
          g.items.removeWhere((e) => !live.contains(e.asset.id));
          if (g.items.length > 1) s.groups.add(g);
        }
      }
      shown = ScanMode(
          duplicates: shown.duplicates || mode.duplicates,
          similar: shown.similar || mode.similar);
      keptGroups = [];
      overall = 1;
      status = ScanStatus.done;
      await _notif.stopProgress();
      await _notif.clearResumeHint();
      if (notifyWhenDone && _life != AppLifecycleState.resumed) {
        await _notif.showDone(s.groups.length, s.groups.fold(0, (n, g) => n + g.items.length));
      }
    } on ScanCancelled {
      await s.dispose();
      if (runId != _runId) return;
      session = null;
      shown = const ScanMode(duplicates: false, similar: false);
      keptGroups = [];
      status = ScanStatus.idle;
    } on PermissionDeniedException {
      if (runId != _runId) return;
      session = null;
      shown = const ScanMode(duplicates: false, similar: false);
      keptGroups = [];
      status = ScanStatus.error;
      error = 'Cần cấp quyền truy cập thư viện ảnh để quét.';
    } catch (e) {
      if (runId != _runId) return;
      session = null;
      shown = const ScanMode(duplicates: false, similar: false);
      keptGroups = [];
      status = ScanStatus.error;
      error = 'Quét thất bại: $e';
    }
    _stopwatch.stop();
    if (status != ScanStatus.done) {
      _stopwatch.reset();
      await _notif.stopProgress();
      await _notif.clearResumeHint();
    }
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
  /// Chép CSV chẩn đoán vào clipboard để dán trực tiếp vào chat.
  /// Trả về số dòng, hoặc null nếu chưa có dữ liệu chẩn đoán.
  Future<int?> copyDiagCsv() async {
    final s = session;
    final d = s?.diag;
    if (s == null || d == null) return null;
    final csv = d.toCsv({'dup': s.groups});
    await Clipboard.setData(ClipboardData(text: csv));
    return '\n'.allMatches(csv).length;
  }

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
    refining = false;
    refineProgress = null;
    shown = const ScanMode(duplicates: false, similar: false);
    keptGroups = [];
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
    _life = state;
    if (status == ScanStatus.scanning && notifyWhenDone) {
      if (state == AppLifecycleState.paused) _notif.showResumeHint(); // chỉ iOS
      if (state == AppLifecycleState.resumed) _notif.clearResumeHint();
    }
    if (state == AppLifecycleState.detached) {
      clearResults();
      return;
    }
    // inactive chỉ là thoáng qua (kéo thông báo...), chỉ hidden/paused mới là ra nền.
    final background = state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden;
    _stopwatch.setForeground(!background);
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    session?.dispose();
    super.dispose();
  }
}
