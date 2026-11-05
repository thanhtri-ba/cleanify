import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../core/platform/photo_edits.dart';
import '../../core/scanner/bulk_cleanup.dart';
import '../../core/scanner/scan_session.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../theme/widgets.dart';
import '../scan/review_page.dart';
import '../screenshots/screenshots_page.dart';
import '../videos/large_videos_page.dart';
import '../scan/scan_options_sheet.dart';
import '../scan/scan_controller.dart';
import '../scan/smart_scan_page.dart';
import '../settings/settings_page.dart';
import '../storage/storage_page.dart';
import 'home_kit.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_icon.dart';

/// Màn chính: thẻ Bộ nhớ iPhone (tổng/còn trống từ iOS, dung lượng Ảnh/Video cộng
/// từ metadata từng asset, "Khác" là phần còn lại), nút quét, rồi kết quả và các
/// công cụ dọn dẹp. Số chưa đọc xong hiển thị "—" thay vì số giả.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});
  final ScanController controller;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  ScanController get c => widget.controller;

  int? _photos;
  int? _videos;

  /// Quyền thư viện ảnh hiện tại. iOS cho phép người dùng chỉ chọn một số ảnh
  /// (limited); khi đó app chỉ thấy các ảnh đó nên kết quả quét sẽ thiếu.
  PermissionState? _perm;

  // Bộ nhớ máy (byte); null = chưa đọc xong.
  int? _total;
  int? _free;
  int? _photoBytes;
  int? _videoBytes;
  bool _loadingStorage = false;
  ScanStatus? _lastStatus;
  int _lastAssets = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_onScan);
    _loadCounts();
    _loadStorage();
  }

  /// Người dùng có thể vừa đổi quyền trong Cài đặt: quay lại app thì đọc lại.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadCounts();
      _loadStorage();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_onScan);
    super.dispose();
  }

  /// Đọc lại số liệu khi quét xong/hủy hoặc sau khi xóa ảnh.
  void _onScan() {
    final n = c.session?.assets.length ?? 0;
    final statusChanged = c.status != _lastStatus &&
        (c.status == ScanStatus.done || c.status == ScanStatus.idle);
    final deleted = c.status == ScanStatus.done && n != _lastAssets;
    _lastStatus = c.status;
    _lastAssets = n;
    if (statusChanged || deleted) {
      _loadCounts();
      _loadStorage();
    }
  }

  Future<void> _loadCounts() async {
    try {
      final perm = await PhotoManager.getPermissionState(
          requestOption: const PermissionRequestOption());
      if (mounted) setState(() => _perm = perm);
      if (!perm.hasAccess) return;
      Future<int> count(RequestType t) async {
        final ps = await PhotoManager.getAssetPathList(onlyAll: true, type: t);
        return ps.isEmpty ? 0 : await ps.first.assetCountAsync;
      }

      final p = await count(RequestType.image);
      final v = await count(RequestType.video);
      if (mounted) {
        setState(() {
          _photos = p;
          _videos = v;
        });
      }
    } catch (_) {}
  }

  /// Đọc tổng/còn trống rồi cộng dung lượng Ảnh và Video theo lô (không tải iCloud).
  Future<void> _loadStorage() async {
    if (_loadingStorage) return;
    _loadingStorage = true;
    try {
      final edits = PhotoEdits();
      if (!edits.supported) return;
      final st = await edits.storage();
      if (mounted && st != null) {
        setState(() {
          _total = st.total;
          _free = st.free;
        });
      }
      final perm = await PhotoManager.getPermissionState(
          requestOption: const PermissionRequestOption());
      if (!perm.hasAccess) return;
      Future<int> sum(RequestType t) async {
        final ps = await PhotoManager.getAssetPathList(onlyAll: true, type: t);
        if (ps.isEmpty) return 0;
        final n = await ps.first.assetCountAsync;
        var bytes = 0;
        for (var s = 0; s < n; s += 500) {
          if (!mounted) return bytes;
          final list = await ps.first
              .getAssetListRange(start: s, end: s + 500 > n ? n : s + 500);
          final sizes = await edits.fileSizes([for (final a in list) a.id]);
          bytes += sizes.values.fold(0, (a, b) => a + b);
        }
        return bytes;
      }

      final p = await sum(RequestType.image);
      if (mounted) setState(() => _photoBytes = p);
      final v = await sum(RequestType.video);
      if (mounted) setState(() => _videoBytes = v);
    } catch (_) {
      // Giữ "—" nếu lỗi, không hiện số sai.
    } finally {
      _loadingStorage = false;
    }
  }

  Future<void> _scan() async {
    // Người dùng chọn quét ảnh trùng và/hoặc ảnh tương tự; chỉ phần đó được chạy.
    final mode = await showScanOptions(context, photos: _photos ?? 0);
    if (mode == null || !mounted) return;
    c.start(mode: mode, photos: _photos);
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SmartScanPage(controller: c)));
  }

  void _say(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  void _soon() => _say('Tính năng này sắp có.');

  /// Mở một trang công cụ; quay lại thì đọc lại số liệu vì có thể đã xóa.
  Future<void> _openTool(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    _loadCounts();
    _loadStorage();
  }

  void _openStorage() => _openTool(StoragePage(
        total: _total,
        free: _free,
        photoBytes: _photoBytes,
        videoBytes: _videoBytes,
        photos: _photos,
        videos: _videos,
        onLargeVideos: _openVideos,
        onScreenshots: _openScreenshots,
      ));

  void _openSettings() => _openTool(SettingsPage(controller: c));

  void _openScreenshots() => _openTool(ScreenshotsPage(controller: c));

  void _openVideos() => _openTool(LargeVideosPage(controller: c));

  void _openResults() {
    if (c.status == ScanStatus.done && c.session != null) {
      // Vào thẳng trang xem ảnh, không qua màn tổng kết.
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ReviewPage(controller: c)));
    } else {
      _say('Hãy quét trước để xem ảnh trùng.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.session;
        final done = c.status == ScanStatus.done && s != null;
        // Chỉ hiện loại đã chọn lúc quét.
        // Đang quét thì vẫn hiện loại KHÔNG quét lại; loại đang quét lại về 0 ngay.
        final scanning = c.status == ScanStatus.scanning;
        final src = done ? s!.groups : (scanning ? c.keptGroups : <DuplicateGroup>[]);
        final hasData = done || (scanning && (c.shown.duplicates || c.shown.similar));
        final groups = [
          for (final g in src)
            if (g.kind == GroupKind.duplicate && c.shown.duplicates) g
        ];
        // Ảnh đã là "trùng" thì không tính lại là "tương tự".
        final similar = c.shown.similar
            ? similarExcludingDuplicates([...groups, ...src.where((g) => g.kind == GroupKind.similar)])
            : <DuplicateGroup>[];
        // Cùng cách tính với màn xem ảnh: chỉ ảnh được CHỌN XÓA SẴN mới tính là dọn được.
        final reclaim = hasData && c.shown.duplicates
            ? planBulkCleanup(src, minSimilarity: kBulkCleanupDefaultSimilarity)
                .countFor(GroupKind.duplicate)
            : 0;
        // Gallery hiện cả nhóm trùng lẫn nhóm tương tự (nhóm lớn nhất trước), để
        // quét kiểu nào cũng thấy ảnh trên Home.
        int bySize(DuplicateGroup a, DuplicateGroup b) =>
            b.items.length.compareTo(a.items.length);
        final dd = [...groups]..sort(bySize);
        final ss = [...similar]..sort(bySize);
        final cap = ss.isEmpty ? 6 : 4;
        final nDup = dd.length < cap ? dd.length : cap;
        final nSim = ss.length < 6 - nDup ? ss.length : 6 - nDup;
        final shown = [...dd.take(nDup), ...ss.take(nSim)];
        // Kết quả hiển thị theo SỐ ẢNH (không phải số nhóm).
        int photosOf(List<DuplicateGroup> g) => g.fold(0, (n, x) => n + x.items.length);
        final dupPhotos = photosOf(groups);
        final simPhotos = photosOf(similar);
        return Scaffold(
          backgroundColor: kBg,
          body: Stack(children: [
            const Positioned(top: 0, left: 0, right: 0, child: Aura()),
            SafeArea(
              child: Column(children: [
                _header(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    children: [
                      _Reveal(
                          0,
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Padding(
                              padding: EdgeInsets.fromLTRB(4, 0, 4, 14),
                              child: Text('Gọn gàng hơn một chút',
                                  style: TextStyle(
                                      fontSize: 30,
                                      height: 1.15,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -1,
                                      color: kInk)),
                            ),
                            _accessBanner(),
                            _storageCard(_scanButton(done)),
                          ])),
                      const SizedBox(height: 10),
                      _Reveal(1, _statsRow(hasData, dupPhotos, reclaim)),
                      const SizedBox(height: 10),
                      _Reveal(
                          2,
                          _gallery(
                              dupPhotos + simPhotos,
                              [
                                for (final g in shown) (g.items.first.asset, g.items.length)
                              ],
                              title: similar.isEmpty ? 'Ảnh trùng' : 'Ảnh trùng & tương tự')),
                      const SizedBox(height: 20),
                      const Padding(
                        padding: EdgeInsets.only(left: 4, bottom: 10),
                        child: SectionLabel('Công cụ khác'),
                      ),
                      _Reveal(
                        3,
                        // Hai ô cao bằng nhau; trong ListView chiều cao không bị chặn nên
                        // cần IntrinsicHeight thì stretch mới hợp lệ.
                        Column(children: [
                          IntrinsicHeight(
                            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Expanded(
                                  child: _soonTile(AppIcons.videocamOutlined,
                                      'Video dung lượng lớn',
                                      _videos == null ? '>150 MB' : '$_videos video', true,
                                      onTap: _openVideos)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _soonTile(AppIcons.screenshotOutlined,
                                      'Ảnh chụp màn hình', 'Dọn nhanh', false,
                                      onTap: _openScreenshots)),
                            ]),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: _soonTile(AppIcons.layersOutlined, 'Quản lý ứng dụng',
                                'Sắp có', true),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      _Reveal(4, _analysis()),
                    ],
                  ),
                ),
                _tabs(),
              ]),
            ),
          ]),
        );
      },
    );
  }

  /// Nút quét màu lime nằm trong thẻ bộ nhớ.
  Widget _scanButton(bool done) {
    final off = c.busy;
    return GestureDetector(
      onTap: off ? null : _scan,
      child: PressScale(
        enabled: !off,
        child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: off ? const Color(0xFFC9D0DC) : const Color(0xFFA3D133),
            borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon(done ? AppIcons.refreshRounded : AppIcons.search,
              size: 20, color: off ? kInk3 : kInk),
          const SizedBox(width: 8),
          Text(off ? 'Đang quét…' : (done ? 'Quét lại' : 'Quét ảnh & video'),
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: off ? kInk3 : kInk)),
        ]),
      ),
      ),
    );
  }

  // ---- header ----
  Widget _header() {
    final x = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(children: [
        const BrandMark(size: 36),
        const SizedBox(width: 10),
        const Text('Cleanify',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: kInk)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
              color: x.tint1, borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(AppIcons.shieldOutlined, size: 14, color: x.accent1),
            const SizedBox(width: 6),
            const Text('Quét trên máy',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kInk2)),
          ]),
        ),
      ]),
    );
  }

  // ---- cảnh báo quyền truy cập ảnh ----
  /// Hiện khi chỉ được truy cập một số ảnh (limited) hoặc bị từ chối. App không thể
  /// tự nâng quyền: người dùng phải chọn "Cho phép truy cập tất cả ảnh" trong Cài đặt.
  Widget _accessBanner() {
    final perm = _perm;
    if (perm == null || perm == PermissionState.notDetermined) {
      return const SizedBox.shrink();
    }
    final limited = perm == PermissionState.limited;
    if (!limited && perm.hasAccess) return const SizedBox.shrink();
    final x = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: HCard(
        padding: 14,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AppIcon(AppIcons.lockOutline, size: 18, color: x.accent1),
            const SizedBox(width: 8),
            Expanded(
              child: Text(limited ? 'Đang cho phép một số ảnh' : 'Chưa có quyền truy cập ảnh',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: kInk)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
              limited
                  ? 'Cleanify chỉ thấy những ảnh bạn đã chọn nên kết quả quét sẽ thiếu. '
                      'Chọn "Cho phép truy cập tất cả ảnh" để quét đầy đủ.'
                  : 'Cần quyền truy cập thư viện ảnh để quét. Mở Cài đặt và chọn '
                      '"Cho phép truy cập tất cả ảnh".',
              style: const TextStyle(fontSize: 13, height: 1.4, color: kInk2)),
          const SizedBox(height: 10),
          Row(children: [
            FilledButton(
              onPressed: PhotoManager.openSetting,
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40)),
              child: Text(limited ? 'Cho phép tất cả ảnh' : 'Mở Cài đặt'),
            ),
            if (limited) ...[
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  await PhotoManager.presentLimited();
                  if (mounted) {
                    _loadCounts();
                    _loadStorage();
                  }
                },
                style: OutlinedButton.styleFrom(
                    foregroundColor: kInk,
                    side: const BorderSide(color: kBorder),
                    minimumSize: const Size(0, 40)),
                child: const Text('Chọn thêm ảnh'),
              ),
            ],
          ]),
        ]),
      ),
    );
  }

  // ---- thẻ Bộ nhớ iPhone ----
  static String _gb(int? b) =>
      b == null ? '—' : '${(b / 1e9).toStringAsFixed(1).replaceAll('.', ',')} GB';

  Widget _storageCard(Widget action) {
    final total = _total;
    final free = _free;
    final used = total != null && free != null ? total - free : null;
    final photos = _photoBytes;
    final videos = _videoBytes;
    final other = used != null && photos != null && videos != null
        ? (used - photos - videos).clamp(0, used).toInt()
        : null;
    const cPhotos = Color(0xFFA3D133); // lime (nhấn của app)
    const cVideos = Color(0xFF3B82F6); // xanh dương (thông tin)
    const cOther = Color(0xFFF59E0B); // cam (cảnh báo)
    const cFree = Color(0xFFC9D0DC); // trống, trên nền xám nhạt
    const sub = Color(0xFF5B6675);

    final ringParts = total == null || total == 0 || free == null || used == null
        ? <(double, Color)>[]
        : [
            ((photos ?? 0) / total, cPhotos),
            ((videos ?? 0) / total, cVideos),
            ((other ?? (used - (photos ?? 0) - (videos ?? 0)).clamp(0, used)) / total, cOther),
          ];
    final pct = total == null || total == 0 || used == null ? null : (used / total * 100).round();

    Widget legend(Color c, String name, int? v) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: sub)),
              ),
            ]),
            const SizedBox(height: 2),
            Text(_gb(v),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
          ]),
        );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: kChip, borderRadius: BorderRadius.circular(28)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(
            width: 112,
            height: 112,
            child: Stack(alignment: Alignment.center, children: [
              CustomPaint(
                  size: const Size(112, 112),
                  painter: _RingPainter(ringParts, cFree)),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(pct == null ? '—' : '$pct%',
                    style: const TextStyle(
                        fontSize: 26, height: 1, fontWeight: FontWeight.w700, color: kInk)),
                const SizedBox(height: 2),
                const Text('đã dùng', style: TextStyle(fontSize: 11, color: sub)),
              ]),
            ]),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('BỘ NHỚ IPHONE',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: sub)),
              const SizedBox(height: 4),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(
                    used == null
                        ? '—'
                        : (used / 1e9).toStringAsFixed(1).replaceAll('.', ','),
                    style: const TextStyle(
                        fontSize: 36,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1,
                        color: kInk)),
                const SizedBox(width: 6),
                const Padding(
                  padding: EdgeInsets.only(bottom: 3),
                  child: Text('GB', style: TextStyle(fontSize: 15, color: sub)),
                ),
              ]),
              const SizedBox(height: 4),
              Text(total == null ? '' : 'trên ${_gb(total)} · còn ${_gb(free)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: sub)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.only(top: 14),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFD3D9E4)))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            legend(cPhotos, 'Ảnh', photos),
            legend(cVideos, 'Video', videos),
            legend(cOther, 'Khác', other),
            legend(cFree, 'Trống', free),
          ]),
        ),
        const SizedBox(height: 16),
        action,
      ]),
    );
  }

  // ---- số liệu sau quét: một thẻ gọn, hai cột ----
  Widget _statsRow(bool done, int photos, int reclaim) {
    final x = context.appColors;
    Widget stat(AppIconData i, String label, String value, Color bg, Color fg) => Expanded(
          child: Row(children: [
            _tile(i, size: 36, bg: bg, fg: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 22,
                        height: 26 / 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                        color: kInk)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: kInk3)),
              ]),
            ),
          ]),
        );
    return Row(children: [
      Expanded(
        child: HCard(
          padding: 14,
          child: Row(children: [
            stat(AppIcons.layersOutlined, 'Ảnh nghi trùng', done ? '$photos' : '—', x.tint1,
                x.accent1),
          ]),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: HCard(
          padding: 14,
          child: Row(children: [
            stat(AppIcons.cleaningServicesOutlined, 'Ảnh có thể dọn', done ? '$reclaim' : '—',
                const Color(0xFFDBEAFE), const Color(0xFF2563EB)),
          ]),
        ),
      ),
    ]);
  }

  /// Ô icon: [gradient] true thì nền gradient lime, ngược lại nền nhạt.
  /// Icon thuần một màu than chì, không nền và không tô màu. Giữ tham số cũ để
  /// các chỗ gọi không phải đổi; [bg], [fg], [gradient] không còn tác dụng.
  Widget _tile(AppIconData i, {Color? bg, Color? fg, bool gradient = false, double size = 40}) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: AppIcon(i, size: size * 0.7, color: kInk, accent: kInk),
      ),
    );
  }

  // ---- ảnh trùng: lưới 3 cột, ảnh lớn để nhìn rõ (bấm để xem kết quả) ----
  Widget _gallery(int photos, List<(dynamic, int)> thumbs, {String title = 'Ảnh trùng'}) {
    final empty = thumbs.isEmpty;
    final shownPhotos = thumbs.fold<int>(0, (n, t) => n + t.$2);
    Widget tile(Widget child) => ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(aspectRatio: 1, child: child));
    final cells = <Widget>[
      if (empty)
        for (var i = 0; i < 6; i++)
          tile(ColoredBox(
              color: kChip,
              child: Center(
                  child: AppIcon(AppIcons.imageOutlined, color: kInk3, accent: kInk3))))
      else
        for (final t in thumbs)
          tile(Stack(fit: StackFit.expand, children: [
            AssetEntityImage(t.$1,
                isOriginal: false,
                fit: BoxFit.cover,
                thumbnailSize: const ThumbnailSize.square(400)),
            Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                      color: const Color(0xCC2A343F), borderRadius: BorderRadius.circular(8)),
                  child: Text('${t.$2} ảnh',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                )),
          ])),
    ];
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _openResults,
      child: HCard(
        child: Column(children: [
          Row(children: [
            _tile(AppIcons.photoOutlined, gradient: true, size: 36),
            const SizedBox(width: 10),
            Text(title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: kInk)),
            const Spacer(),
            HPill(empty ? 'Chưa có' : '$photos ảnh', fg: kInk2, bg: kChip, size: 12),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 116,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cells.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => SizedBox(width: 116, child: cells[i]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(children: [
              Text(!empty && photos > shownPhotos ? '+${photos - shownPhotos} ảnh nữa' : '',
                  style: const TextStyle(fontSize: 12, color: kInk3)),
              const Spacer(),
              const Text('Xem tất cả',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kInk)),
              const AppIcon(AppIcons.chevronRight, size: 16, color: kInk),
            ]),
          ),
        ]),
      ),
    );
  }

  // ---- ô công cụ chưa hỗ trợ ----
  Widget _soonTile(AppIconData i, String title, String chip, bool blue,
      {VoidCallback? onTap}) {
    final x = context.appColors;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap ?? _soon,
      child: HCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _tile(i,
              size: 40,
              bg: blue ? const Color(0xFFDBEAFE) : x.tint1,
              fg: blue ? const Color(0xFF2563EB) : x.accent1),
          const SizedBox(height: 14),
          Text(title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kInk)),
          const SizedBox(height: 8),
          HPill(chip,
              fg: kInk2, bg: kChip),
        ]),
      ),
    );
  }

  Widget _analysis() {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _soon,
      child: HCard(
        child: Row(children: [
          _tile(AppIcons.storageOutlined, bg: const Color(0xFFDBEAFE), fg: const Color(0xFF2563EB)),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Phân tích dung lượng',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kInk)),
              Text('Tổng quan & mức sử dụng',
                  style: TextStyle(fontSize: 13, color: kInk3)),
            ]),
          ),
          const HDisc(AppIcons.chevronRight, size: 32, bg: kChip),
        ]),
      ),
    );
  }

  // ---- tab bar ----
  Widget _tabs() {
    Widget t(AppIconData i, String l, bool on, VoidCallback? f) => InkWell(
          onTap: f,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              on
                  ? Container(
                      width: 28,
                      height: 3,
                      decoration: BoxDecoration(
                          gradient: context.appColors.gradient,
                          borderRadius: BorderRadius.circular(2)))
                  : const SizedBox(height: 3),
              const SizedBox(height: 6),
              AppIcon(i, size: 20, color: on ? kInk : kInk3),
              const SizedBox(height: 4),
              Text(l,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                      color: on ? kInk : kInk3)),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: context.appColors.line)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        t(AppIcons.homeOutlined, 'Trang chủ', true, null),
        t(AppIcons.search, 'Quét', false, c.busy ? null : _scan),
        t(AppIcons.storageOutlined, 'Bộ nhớ', false, _openStorage),
        t(AppIcons.settingsOutlined, 'Cài đặt', false, _openSettings),
      ]),
    );
  }
}

/// Hiện dần + trượt nhẹ từ dưới lên, so le theo [index]. Không dùng Timer
/// (một controller với Interval) và tắt khi người dùng bật giảm chuyển động.
class _Reveal extends StatefulWidget {
  const _Reveal(this.index, this.child);
  final int index;
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final int _total = 420 + 60 * widget.index;
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Duration(milliseconds: _total))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    final curve = CurvedAnimation(
      parent: _c,
      curve: Interval(60 * widget.index / _total, 1, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(curve),
        child: widget.child,
      ),
    );
  }
}

/// Vòng tròn dung lượng: các phần (tỷ lệ 0..1 so với tổng) nối nhau từ đỉnh, phần còn lại
/// là nền [track]. Đầu nét phẳng để các phần khít nhau.
class _RingPainter extends CustomPainter {
  _RingPainter(this.parts, this.track);
  final List<(double, Color)> parts;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, 6.283185307179586, false, base);
    var start = -1.5707963267948966; // đỉnh vòng
    for (final p in parts) {
      final sweep = 6.283185307179586 * p.$1.clamp(0.0, 1.0);
      if (sweep <= 0) continue;
      canvas.drawArc(rect, start, sweep, false, base..color = p.$2);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.parts != parts || old.track != track;
}
