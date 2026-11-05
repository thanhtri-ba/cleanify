import 'dart:io' show ProcessInfo;
import 'dart:isolate' show Isolate;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, kProfileMode, kReleaseMode;
import 'package:photo_manager/photo_manager.dart';

import '../../engines/dino/dino_engine.dart';
import '../../engines/dino/dino_matcher.dart';
import '../../engines/features/local_matcher.dart';
import '../../engines/lsh/candidate_index.dart';
import '../../engines/pdq/pdq_engine.dart';
import '../platform/photo_edits.dart';
import 'active_clock.dart';
import 'hash_worker.dart';
import 'regroup.dart';
import 'scan_diagnostics.dart';
import 'scan_mode.dart';
import 'scan_progress.dart';
import 'scan_session.dart';

class ScanConfig {
  const ScanConfig({
    this.batchSize = 128,
    this.ioConcurrency = 16,
    this.shaBatch = 32,
    this.fileConcurrency = 4,
    this.maxHamming = 32,
    this.exactPairsBelow = 30000,
    this.similarMaxHamming = 60,
    this.useModel = false,
    this.useSimilarModel = true,
    this.similarModelK = 3,
    this.similarModelFloor = 0.55,
    this.modelBatch = 16,
    this.modelMinCosine = 0.80,
    this.modelMeanSample = 256,
    this.modelMinMeanCount = 32,
    this.useOriginalVersion = true,
    this.useLocalFeatures = false,
    this.localMinInliers = 45,
    this.localNeighbors = 6,
    this.localWindowMinutes = 5,
    this.localMaxPairs = 3000,
    this.localThumbSide = 640,
  });

  /// Số ảnh mỗi batch khi đọc thumbnail + băm PDQ.
  final int batchSize;

  /// Số thumbnail đọc song song (nhỏ, nhẹ).
  final int ioConcurrency;

  /// SHA-256 chỉ tính cho ảnh nghi trùng: số ảnh mỗi lượt và số file gốc
  /// được export song song (export file gốc nặng nên giữ thấp).
  final int shaBatch;
  final int fileConcurrency;

  /// Hai ảnh là trùng khi Hamming PDQ <= maxHamming trên 256 bit.
  /// 32 -> độ giống bit-hash >= 87,5% (100 * (1 - 32/256)); gần mức 31 mà PDQ gốc
  /// của Meta khuyến nghị. Trước đây là 40 (84,4%) nhưng bản PDQ ở đây đã đơn giản
  /// hóa (không có Jarosz filter, không lọc ảnh ít chi tiết) nên kém phân biệt hơn
  /// bản gốc, và người dùng báo ảnh khác nhau bị gom chung. Cặp Hamming 33-70 vẫn
  /// hiện ở nhóm "tương tự" (chỉ để xem, không tự xóa).
  final int maxHamming;

  /// Số ảnh tối đa để so mọi cặp PDQ (chính xác). Lớn hơn thì LSH 16 band
  /// bỏ sót nhiều cặp: đo trên 1500 ảnh, recall cháy x2 = 84% (exact 97%).
  /// 30000 ảnh ~ 450 triệu cặp, khoảng 5 giây trên máy đo.
  final int exactPairsBelow;

  /// Ngưỡng Hamming cho nhóm "tương tự" (gần giống, chỉ để xem, không tự xóa).
  /// Lớn hơn maxHamming. 60 -> độ giống >= 76,6%.
  final int similarMaxHamming;

  /// Bước AI (embedding ONNX) chạy SAU PDQ/SHA: chỉ xác minh cặp PDQ có
  /// maxHamming < Hamming <= similarMaxHamming của ảnh chưa vào nhóm nào.
  /// ĐANG TẮT (false) cho tới khi calibrate ngưỡng cho model đang dùng (DINO hoặc MobileNet).
  final bool useModel;

  /// Dùng embedding để tìm thêm ảnh "tương tự" (cùng cảnh/chủ thể) mà PDQ bỏ sót.
  /// Mỗi ảnh nối với [similarModelK] hàng xóm gần nhất có cosine (đã trừ trung bình)
  /// >= [similarModelFloor]; mức cao hơn do người dùng chọn lúc xem. Không bao giờ
  /// tự xóa. Lỗi/thiếu mô hình thì bỏ qua, không ảnh hưởng kết quả PDQ.
  final bool useSimilarModel;

  final int similarModelK;
  final double similarModelFloor;
  final int modelBatch;

  /// Cặp được nâng thành "trùng" khi cosine của embedding ĐÃ TRỪ TRUNG BÌNH
  /// (rồi L2-normalize) >= ngưỡng này. 0.80 chỉ là giá trị tạm, CHƯA calibrate:
  /// chạy tool/calibrate.py (xem tool/EVAL.md) trên tập có cặp khó rồi mới bật
  /// [useModel]. Thang cosine sau khi trừ trung bình khác thang cosine thô.
  final double modelMinCosine;

  /// Số ảnh mẫu rải đều thư viện để tính vector trung bình, và số embedding tối
  /// thiểu để trung bình có nghĩa (ít hơn thì bỏ qua bước AI).
  final int modelMeanSample;
  final int modelMinMeanCount;

  /// iOS: với ảnh đã chỉnh sửa trong ứng dụng Ảnh, hash thêm BẢN GỐC và nối ảnh đó
  /// với ảnh khác khi hash gốc gần hash hiện tại của ảnh kia (Hamming <= maxHamming).
  /// Cặp này chỉ vào nhóm "tương tự", không bao giờ tự xóa. Android: bỏ qua.
  final bool useOriginalVersion;

  /// So khớp điểm đặc trưng cục bộ (ORB + RANSAC) cho các cặp chụp gần nhau về thời
  /// gian mà PDQ không nối được (crop, chụp lệch khung, nét vẽ). Chỉ chạy khi
  /// [ScanOrchestrator.localMatcher] khác null. Cặp đạt [localMinInliers] chỉ vào nhóm
  /// "tương tự", không bao giờ tự xóa.
  /// [localMinInliers]=45 CHƯA calibrate: đo trên 50 ảnh thật, cặp khác nội dung
  /// thường <= 20 điểm, nhưng trang chữ dày có thể tới ~40 điểm dù khác trang.
  final bool useLocalFeatures;
  final int localMinInliers;

  /// Mỗi ảnh chỉ so với tối đa [localNeighbors] ảnh kế tiếp theo thời gian chụp và
  /// cách nhau không quá [localWindowMinutes] phút; tối đa [localMaxPairs] cặp mỗi
  /// lần quét; ảnh thu nhỏ về cạnh [localThumbSide] px.
  final int localNeighbors;
  final int localWindowMinutes;
  final int localMaxPairs;
  final int localThumbSide;
}

class ScanOrchestrator {
  ScanOrchestrator({this.config = const ScanConfig(), this.localMatcher});

  final ScanConfig config;

  /// Bộ so khớp điểm đặc trưng (OpenCV). Null thì bước này bị bỏ qua.
  final LocalFeatureMatcher? localMatcher;

  /// Trạng thái giữa hai giai đoạn để [refineSimilar] dựng lại nhóm tương tự.
  _Pending? _pending;

  /// Còn bước AI chưa chạy cho kết quả vừa quét.
  bool get canRefine => _pending != null;

  /// Điền kết quả vào [session]. Dữ liệu trung gian (hash, index) chỉ là biến
  /// cục bộ nên được giải phóng khi hàm kết thúc.
  Future<void> run(
    ScanSession session,
    void Function(ScanProgress) onProgress, {
    ActiveClock? clock,
    ScanMode mode = const ScanMode(),
  }) async {
    // Luôn chạy bước trùng (PDQ/SHA) để ảnh trùng không lọt vào "tương tự";
    // nhóm trùng chỉ được GIỮ LẠI trong kết quả nếu người dùng chọn.
    final wantDup = mode.duplicates;
    mode = ScanMode(duplicates: true, similar: mode.similar);
    // Đồng hồ không tính lúc tạm dừng/ra nền nếu controller truyền vào.
    final sw = clock ?? (ActiveClock()..start());
    // Ghi thời gian từng giai đoạn để hiện trên màn hình kết quả.
    void mark(String tag) {
      _log(tag, sw.elapsed);
      session.timings.add('${sw.elapsed.inSeconds}s · $tag');
    }

    session.timings.add(kReleaseMode
        ? 'build: release'
        : kProfileMode
            ? 'build: profile'
            : 'build: DEBUG (Dart chạy chậm hơn nhiều)');
    try {
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.hasAccess) throw const PermissionDeniedException();

      final paths = await PhotoManager.getAssetPathList(
        onlyAll: true,
        type: RequestType.image,
      );
      if (paths.isEmpty) return;
      final all = paths.first;
      final total = await all.assetCountAsync;

      final assets = <AssetEntity>[];
      final shas = List<String?>.filled(total, null);
      final flat = Uint64List(total * 4);
      final has = Uint8List(total);

      // Giai đoạn 1: thumbnail + PDQ theo batch. KHÔNG đụng tới file gốc.
      // Trong lúc isolate băm batch hiện tại, batch kế tiếp đã được đọc trước.
      Future<_Batch?> fetch(int start) async {
        if (start >= total) return null;
        try {
          final end = math.min(start + config.batchSize, total);
          final list = await all.getAssetListRange(start: start, end: end);
          if (list.isEmpty) return null;
          // Chỉ quét ảnh tương tự thì không cần thumbnail 128px/PDQ.
          return _Batch(list, mode.duplicates ? await _thumbs(list) : const []);
        } catch (_) {
          return null;
        }
      }

      var nextStart = config.batchSize;
      var next = fetch(0);
      // Chờ thumbnail (đọc ảnh) so với băm: khâu nào lớn hơn là khâu nghẽn.
      final waitSw = Stopwatch();
      final hashSw = Stopwatch();
      while (true) {
        if (session.cancelled) throw const ScanCancelled();
        await session.waitIfPaused();
        if (session.cancelled) throw const ScanCancelled();

        waitSw.start();
        final cur = await next;
        waitSw.stop();
        if (cur == null) break;
        next = fetch(nextStart);
        nextStart += config.batchSize;

        final base = assets.length;
        assets.addAll(cur.assets);
        hashSw.start();
        final outputs =
            mode.duplicates ? await hashBatch(cur.inputs) : const <HashOutput>[];
        hashSw.stop();
        for (final o in outputs) {
          final p = o.pdq;
          if (p != null) {
            final gi = base + o.index;
            flat.setRange(gi * 4, gi * 4 + 4, p);
            has[gi] = 1;
          }
        }
        session.scanned = assets.length;
        session.assets = assets;
        onProgress(ScanProgress(ScanPhase.reading, assets.length, total,
            paused: session.paused));
        if ((assets.length ~/ config.batchSize) % 10 == 0) {
          mark('đọc ${assets.length}/$total');
        }
      }

      final n = assets.length;
      mark('xong PDQ n=$n · chờ thumbnail ${waitSw.elapsed.inSeconds}s, '
          'băm ${hashSw.elapsed.inSeconds}s');

      // Giai đoạn 1b (iOS): hash bản gốc của ảnh đã chỉnh sửa trong ứng dụng Ảnh.
      final orig = config.useOriginalVersion && mode.duplicates
          ? await _originalHashes(session, assets, mark)
          : const _OrigHashes([], null);
      onProgress(ScanProgress(ScanPhase.matching, n, n));

      // Giai đoạn 2: ứng viên LSH + Hamming (chỉ cần PDQ).
      // Chạy ngoài isolate chính: so mọi cặp là vài triệu phép so, không được chặn UI.
      final maxH = config.similarMaxHamming;
      final exactBelow = config.exactPairsBelow;
      final edges = !mode.duplicates
          ? <MatchEdge>[]
          : await Isolate.run(() => findNearEdges(
                flat: flat,
                has: has,
                n: n,
                maxHamming: maxH,
                exactBelow: exactBelow,
              ));
      mark('so khớp PDQ xong: ${edges.length} cạnh');

      // SHA-256 chỉ cần cho ảnh nghi trùng: hai file giống hệt nhau luôn có
      // thumbnail và PDQ giống hệt nhau, nên ảnh không nằm trong cặp ứng viên
      // nào thì không thể là bản sao y hệt của ảnh khác.
      final needSha = Uint8List(n);
      // Hai file giống hệt nhau luôn có PDQ giống hệt (khoảng cách 0), nên chỉ cạnh
      // khoảng cách 0 cần SHA để xác nhận. Cạnh xa hơn đã chắc chắn là KHÁC file;
      // bỏ qua chúng tránh export file gốc hàng nghìn ảnh (rất chậm trên iOS).
      for (final e in edges) {
        if (e.distance != 0) continue;
        needSha[e.a] = 1;
        needSha[e.b] = 1;
      }
      // PDQ trùng khít (kể cả bucket lớn mà LSH bỏ qua) và ảnh không có PDQ.
      final firstByPdq = <String, int>{};
      for (var i = 0; i < n; i++) {
        if (has[i] == 0) {
          needSha[i] = 1;
          continue;
        }
        final k = '${flat[i * 4]}_${flat[i * 4 + 1]}_'
            '${flat[i * 4 + 2]}_${flat[i * 4 + 3]}';
        final first = firstByPdq[k];
        if (first == null) {
          firstByPdq[k] = i;
        } else {
          needSha[first] = 1;
          needSha[i] = 1;
        }
      }
      final shaIdx = [
        for (var i = 0; i < n; i++)
          if (mode.duplicates && needSha[i] == 1) i
      ];
      mark('cần SHA ${shaIdx.length}/$n ảnh, cạnh LSH=${edges.length}');

      for (var s0 = 0; s0 < shaIdx.length; s0 += config.shaBatch) {
        if (session.cancelled) throw const ScanCancelled();
        await session.waitIfPaused();
        if (session.cancelled) throw const ScanCancelled();
        final part =
            shaIdx.sublist(s0, math.min(s0 + config.shaBatch, shaIdx.length));
        final outs = await hashBatch(await _files(part, assets));
        for (final o in outs) {
          shas[part[o.index]] = o.sha256Hex;
        }
        // Xóa bản export file gốc ngay, không để dồn tới cuối phiên.
        try {
          await PhotoManager.clearFileCache();
        } catch (_) {}
        onProgress(ScanProgress(ScanPhase.exact,
            math.min(s0 + config.shaBatch, shaIdx.length), shaIdx.length,
            paused: session.paused));
      }
      for (var i = 0; i < n; i++) {
        if (mode.duplicates && has[i] == 0 && shas[i] == null) {
          session.hashFailures++;
        }
      }
      mark('xong SHA');

      // Nhóm exact theo SHA-256.
      final uf = UnionFind(n);
      final bySha = <String, int>{};
      for (var i = 0; i < n; i++) {
        final s = shas[i];
        if (s == null) continue;
        final first = bySha[s];
        if (first == null) {
          bySha[s] = i;
        } else {
          uf.union(first, i);
        }
      }

      // Nhóm "tương tự" chỉ dựa vào AI (ufSim), độc lập với nhóm trùng, để kết quả
      // giống hệt dù quét riêng hay quét cùng ảnh trùng.
      final ufSim = UnionFind(n);
      for (final e in edges) {
        if (e.distance <= config.maxHamming) uf.union(e.a, e.b);
      }
      if (mode.duplicates) {
        final sizes = <int, int>{};
        for (var i = 0; i < n; i++) {
          final r = uf.find(i);
          sizes[r] = (sizes[r] ?? 0) + 1;
        }
        session.liveGroups = sizes.values.where((v) => v > 1).length;
        onProgress(ScanProgress(ScanPhase.exact, n, n, paused: session.paused));
      }

      // Liên kết "bản đã chỉnh <-> ảnh khác" qua hash BẢN GỐC; chỉ cho nhóm tương tự.
      final links = _originalLinks(orig, flat, has, n);
      if (orig.owners.isNotEmpty) {
        mark('bản gốc: ${links.length} liên kết ảnh đã chỉnh <-> ảnh khác');
      }

      // Liên kết theo điểm đặc trưng cục bộ (ORB + RANSAC); cũng chỉ cho tab tương tự.
      final localLinks = config.useLocalFeatures && localMatcher != null
          ? await _localFeatureStage(
              session, assets, uf, flat, has, onProgress, mark)
          : <int, int>{};

      // Giai đoạn 3: mô hình AI xác minh các cặp PDQ nằm giữa ngưỡng trùng và
      // ngưỡng tương tự (chỉ cho ảnh chưa vào nhóm nào).
      final emb = config.useModel
          ? await _modelStage(session, assets, uf, edges, onProgress, mark)
          : <int, Float32List>{};

      final simEmb = config.useSimilarModel && mode.similar
          ? await _similarModelStage(
              session, assets, ufSim, onProgress, mark)
          : <int, Float32List>{};

      // Giai đoạn 5: nhóm trùng (ngưỡng maxHamming), rồi nhóm tương tự
      // (ngưỡng similarMaxHamming) từ các ảnh chưa nằm trong nhóm trùng nào.
      final byRoot = <int, List<int>>{};
      for (var i = 0; i < n; i++) {
        (byRoot[uf.find(i)] ??= <int>[]).add(i);
      }
      final groups = <DuplicateGroup>[];
      final inDupIds = <String>{};
      for (final members in byRoot.values) {
        if (members.length < 2) continue;
        final g = _buildGroup(session, assets, members, shas, flat, has, emb,
            GroupKind.duplicate, config.maxHamming,
            links: links, localLinks: localLinks);
        if (g == null) continue;
        groups.add(g);
        inDupIds.addAll(g.items.map((e) => e.asset.id));
      }
      groups.sort((a, b) => b.items.length.compareTo(a.items.length));

      final pending = _Pending(
          assets: assets,
          shas: shas,
          flat: flat,
          has: has,
          uf: uf,
          ufSim: ufSim,
          links: links,
          localLinks: localLinks,
          emb: emb,
          inDupIds: inDupIds,
          dupGroups: List.of(groups));
      // Không chọn "tương tự": chưa dựng nhóm tương tự; người dùng có thể chạy AI sau.
      final similar = mode.similar
          ? _buildSimilarGroups(session, pending, simEmb)
          : <DuplicateGroup>[];
      _pending = config.useSimilarModel && !mode.similar && wantDup
          ? pending
          : null;
      if (!wantDup) groups.clear();
      groups.addAll(similar);
      session.groups
        ..clear()
        ..addAll(groups);
      session.pdqIndex = wantDup
          ? PdqIndex(
              assets: assets,
              shas: shas,
              flat: flat,
              has: has,
              edges: edges,
              maxEdgeHamming: maxH)
          : null;

      mark('xong nhóm ảnh trùng');
    } finally {
      session.elapsed = sw.elapsed;
      // Xóa file tạm mà photo_manager có thể đã tạo (vd. iOS export file gốc).
      try {
        await PhotoManager.clearFileCache();
      } catch (_) {}
    }
  }

  /// Nhóm "tương tự" từ ảnh chưa vào nhóm trùng, theo [_Pending.ufSim] (+ embedding
  /// [simEmb] nếu có).
  List<DuplicateGroup> _buildSimilarGroups(
      ScanSession session, _Pending p, Map<int, Float32List> simEmb) {
    final n = p.assets.length;
    final bySim = <int, List<int>>{};
    for (var i = 0; i < n; i++) {
      (bySim[p.ufSim.find(i)] ??= <int>[]).add(i);
    }
    final similar = <DuplicateGroup>[];
    for (final all in bySim.values) {
      // Ảnh đã thuộc nhóm trùng thì không đưa vào nhóm tương tự.
      final members = [
        for (final i in all)
          if (!p.inDupIds.contains(p.assets[i].id)) i
      ];
      if (members.length < 2) continue;
      final g = _buildGroup(session, p.assets, members, p.shas, p.flat, p.has,
          p.emb, GroupKind.similar, config.similarMaxHamming,
          simEmb: simEmb);
      if (g != null) similar.add(g);
    }
    similar.sort((a, b) => b.items.length.compareTo(a.items.length));
    return similar;
  }

  /// Giai đoạn 2 (chạy nền sau [run]): embedding AI cho mọi ảnh rồi dựng lại các
  /// nhóm "tương tự". Nhóm trùng không đổi. Lỗi/hủy: giữ nguyên kết quả hiện có.
  Future<void> refineSimilar(
      ScanSession session, void Function(ScanProgress) onProgress) async {
    final p = _pending;
    if (p == null) return;
    _pending = null;
    final sw = ActiveClock()..start();
    void mark(String tag) {
      _log('AI nền: $tag', sw.elapsed);
      session.timings.add('AI nền ${sw.elapsed.inSeconds}s · $tag');
    }

    try {
      final simEmb = await _similarModelStage(
          session, p.assets, p.ufSim, onProgress, mark);
      if (session.cancelled || simEmb.isEmpty) return;
      final similar = _buildSimilarGroups(session, p, simEmb);
      // Ảnh có thể đã bị xóa trong lúc AI chạy.
      final live = {for (final a in session.assets) a.id};
      for (final g in similar) {
        g.items.removeWhere((e) => !live.contains(e.asset.id));
      }
      similar.removeWhere((g) => g.items.length < 2);
      session.groups
        ..clear()
        ..addAll(p.dupGroups.where((g) => g.items.length > 1))
        ..addAll(similar);
      mark('xong nhóm tương tự: ${similar.length} nhóm');
    } finally {
      sw.stop();
    }
  }

  /// Dựng một nhóm: ảnh lớn nhất/cũ nhất làm đại diện. Chỉ giữ ảnh có độ giống
  /// trực tiếp với đại diện <= [limit] (hoặc SHA trùng). KHÔNG nối qua ảnh khác,
  /// để tránh chuỗi gom ảnh rất khác nhau. Trả về null nếu còn dưới 2 ảnh.
  DuplicateGroup? _buildGroup(
    ScanSession session,
    List<AssetEntity> assets,
    List<int> members,
    List<String?> shas,
    Uint64List flat,
    Uint8List has,
    Map<int, Float32List> emb,
    GroupKind kind,
    int limit, {
    Map<int, int> links = const {},
    Map<int, int> localLinks = const {},
    Map<int, Float32List> simEmb = const {},
  }) {
    final n = assets.length;
    double? simCos(int m) =>
        kind == GroupKind.similar ? cosineOf(simEmb[m], simEmb[members.first]) : null;
    bool linked(int a, int b) => links.containsKey(_linkKey(a, b, n));
    bool linkedLocal(int a, int b) =>
        localLinks.containsKey(_linkKey(a, b, n));
    members.sort((a, b) {
      final pa = assets[a].width * assets[a].height;
      final pb = assets[b].width * assets[b].height;
      if (pa != pb) return pb.compareTo(pa);
      return assets[a].createDateTime.compareTo(assets[b].createDateTime);
    });
    final rep = members.first;
    // Nhóm tương tự chỉ xét embedding AI; nhóm trùng chỉ xét SHA/PDQ.
    final isSim = kind == GroupKind.similar;
    final kept = [
      for (final m in members)
        if (m == rep ||
            (isSim
                ? (simCos(m) ?? -1) >= config.similarModelFloor
                : ((shas[m] != null && shas[m] == shas[rep]) ||
                    (_hamming(flat, has, m, rep) ?? limit + 1) <= limit ||
                    (cosineOf(emb[m], emb[rep]) ?? -1) >= config.modelMinCosine)))
          m,
    ];
    if (kept.length < 2) return null;
    final items = <DuplicateItem>[];
    final rows = <DiagRow>[];
    for (final m in kept) {
      final exact = !isSim && shas[m] != null && shas[m] == shas[rep];
      final h = isSim ? null : _hamming(flat, has, m, rep);
      final c = m == rep ? null : cosineOf(emb[m], emb[rep]);
      // Nhóm do mô hình: hai ảnh không gần nhau theo PDQ nhưng có cosine.
      final byModel = !exact && c != null && !(h != null && h <= limit);
      final viaOriginal = m != rep &&
          !exact &&
          !byModel &&
          !(h != null && h <= limit) &&
          linked(m, rep);
      final localInl = m != rep &&
              !exact &&
              !byModel &&
              !viaOriginal &&
              !(h != null && h <= limit) &&
              linkedLocal(m, rep)
          ? localLinks[_linkKey(m, rep, n)]
          : null;
      final cs = m == rep ? null : simCos(m);
      final modelOnly = kind == GroupKind.similar &&
          m != rep &&
          !exact &&
          !byModel &&
          !viaOriginal &&
          localInl == null &&
          !(h != null && h <= limit) &&
          cs != null &&
          cs >= config.similarModelFloor;
      double? sim;
      if (m == rep) {
        sim = 100;
      } else if (viaOriginal || localInl != null || modelOnly) {
        sim = null; // ảnh khác ảnh đại diện (đã chỉnh): không tự xóa
      } else if (byModel) {
        sim = c * 100;
      } else if (h != null) {
        sim = pdqSimilarity(h);
      }
      items.add(DuplicateItem(assets[m],
          exact: exact,
          similarity: sim,
          byModel: byModel,
          viaOriginal: viaOriginal,
          localInliers: localInl,
          modelCosine: modelOnly ? cs : null));
      if (session.diag != null) {
        rows.add(_dupRow(assets[m], assets[rep],
            isAnchor: m == rep,
            exact: exact,
            hamming: h,
            cosine: c ?? cs,
            byModel: byModel,
            modelOnly: modelOnly,
            limit: limit,
            origDistance: viaOriginal ? links[_linkKey(m, rep, n)] : null,
            localInliers: localInl));
      }
    }
    final group = DuplicateGroup(items, kind: kind);
    session.diag?.attach(group, rows);
    return group;
  }

  /// Hamming PDQ giữa hai ảnh theo chỉ số; null nếu một trong hai không có hash.
  int? _hamming(Uint64List flat, Uint8List has, int i, int j) =>
      has[i] == 1 && has[j] == 1 ? hammingFlat(flat, i, j) : null;

  DiagRow _dupRow(
    AssetEntity asset,
    AssetEntity anchor, {
    required bool isAnchor,
    required bool exact,
    required int? hamming,
    double? cosine,
    bool byModel = false,
    bool modelOnly = false,
    required int limit,
    int? origDistance,
    int? localInliers,
  }) {
    final String reason;
    if (isAnchor) {
      reason = 'anchor';
    } else if (exact) {
      reason = 'sha256';
    } else if (localInliers != null) {
      reason = 'điểm đặc trưng (inlier=$localInliers)';
    } else if (origDistance != null) {
      reason = 'bản gốc đã chỉnh (Hamming gốc=$origDistance)';
    } else if (modelOnly) {
      reason = 'ai-tương-tự cosine>=${config.similarModelFloor}';
    } else if (byModel) {
      reason = 'dino-cosine>=${config.modelMinCosine}';
    } else if (hamming != null && hamming <= limit) {
      reason = 'hamming<=$limit';
    } else {
      reason = 'bắc cầu (union-find)';
    }
    return DiagRow(
      assetId: asset.id,
      anchorId: anchor.id,
      hamming: hamming,
      pdqPercent: hamming == null ? null : pdqSimilarity(hamming),
      cosDino: cosine,
      threshold: byModel ? 'cos>=${config.modelMinCosine}' : 'max<=$limit',
      reason: reason,
    );
  }

  /// Khóa không phân biệt thứ tự cho cặp ảnh (a, b) trong thư viện n ảnh.
  static int _linkKey(int a, int b, int n) => a < b ? a * n + b : b * n + a;

  /// iOS: hash thumbnail BẢN GỐC của các ảnh đã chỉnh sửa trong ứng dụng Ảnh.
  /// Mọi lỗi (kênh nền tảng thiếu, ảnh trên iCloud...) chỉ ghi vào timings.
  Future<_OrigHashes> _originalHashes(
    ScanSession session,
    List<AssetEntity> assets,
    void Function(String) mark,
  ) async {
    final edits = PhotoEdits();
    if (!edits.supported) return const _OrigHashes([], null);
    try {
      final idToIdx = {for (var i = 0; i < assets.length; i++) assets[i].id: i};
      final allIds = idToIdx.keys.toList();
      final edited = <int>[];
      for (var s = 0; s < allIds.length; s += 500) {
        if (session.cancelled) throw const ScanCancelled();
        final part = allIds.sublist(s, math.min(s + 500, allIds.length));
        for (final id in await edits.editedIds(part)) {
          final i = idToIdx[id];
          if (i != null) edited.add(i);
        }
      }
      edited.sort();
      final owners = <int>[];
      final words = <int>[];
      var missing = 0;
      for (var s = 0; s < edited.length; s += 32) {
        if (session.cancelled) throw const ScanCancelled();
        await session.waitIfPaused();
        final part = edited.sublist(s, math.min(s + 32, edited.length));
        final thumbs =
            await edits.originalThumbs([for (final i in part) assets[i].id]);
        final inputs = <HashInput>[];
        final idxs = <int>[];
        for (final i in part) {
          final t = thumbs[assets[i].id];
          if (t == null) {
            missing++;
            continue;
          }
          inputs.add(HashInput(index: idxs.length, thumb: t));
          idxs.add(i);
        }
        if (inputs.isEmpty) continue;
        for (final o in await hashBatch(inputs)) {
          final p = o.pdq;
          if (p == null) {
            missing++;
            continue;
          }
          owners.add(idxs[o.index]);
          words.addAll(p);
        }
      }
      mark('bản gốc: ${edited.length} ảnh đã chỉnh, ${owners.length} có hash gốc'
          '${missing > 0 ? ', $missing không lấy được (iCloud/lỗi)' : ''}');
      return _OrigHashes(owners, Uint64List.fromList(words));
    } on ScanCancelled {
      rethrow;
    } catch (e) {
      mark('bản gốc: BỎ QUA ($e)');
      return const _OrigHashes([], null);
    }
  }

  /// Cặp (ảnh đã chỉnh o, ảnh khác j): hash BẢN GỐC của o có Hamming <= maxHamming
  /// với hash hiện tại của j, và hash hiện tại của o thì không (cặp đó đã được
  /// tìm thấy ở bước PDQ thường). Giá trị là khoảng cách Hamming của hash gốc.
  Map<int, int> _originalLinks(
      _OrigHashes orig, Uint64List flat, Uint8List has, int n) {
    final out = <int, int>{};
    final of = orig.flat;
    if (of == null) return out;
    for (var k = 0; k < orig.owners.length; k++) {
      final o = orig.owners[k];
      for (var j = 0; j < n; j++) {
        if (j == o || has[j] == 0) continue;
        var d = 0;
        for (var w = 0; w < 4; w++) {
          d += popcount64(of[k * 4 + w] ^ flat[j * 4 + w]);
        }
        if (d > config.maxHamming) continue;
        if (has[o] == 1 && hammingFlat(flat, o, j) <= config.maxHamming) {
          continue;
        }
        final key = _linkKey(o, j, n);
        final prev = out[key];
        if (prev == null || d < prev) out[key] = d;
      }
    }
    return out;
  }

  /// So khớp điểm đặc trưng cục bộ cho các cặp chụp gần nhau về thời gian mà PDQ
  /// chưa nối (Hamming > similarMaxHamming) và chưa cùng nhóm Trùng. Trả về
  /// khóa cặp -> số inlier, chỉ gồm cặp >= localMinInliers. Lỗi chỉ ghi vào timings.
  Future<Map<int, int>> _localFeatureStage(
    ScanSession session,
    List<AssetEntity> assets,
    UnionFind uf,
    Uint64List flat,
    Uint8List has,
    void Function(ScanProgress) onProgress,
    void Function(String) mark,
  ) async {
    final matcher = localMatcher!;
    final n = assets.length;
    final batches = planLocalBatches(
      times: [for (final a in assets) a.createDateTime],
      neighbors: config.localNeighbors,
      window: Duration(minutes: config.localWindowMinutes),
      skip: (a, b) =>
          uf.find(a) == uf.find(b) ||
          (has[a] == 1 &&
              has[b] == 1 &&
              hammingFlat(flat, a, b) <= config.similarMaxHamming),
    );
    var total = 0;
    for (final b in batches) {
      total += b.pairs.length;
    }
    if (total == 0) {
      mark('điểm đặc trưng: không có cặp ứng viên');
      return {};
    }
    final out = <int, int>{};
    var done = 0;
    var checked = 0;
    var failed = 0;
    String? lastErr;
    for (final b in batches) {
      if (session.cancelled) throw const ScanCancelled();
      await session.waitIfPaused();
      if (session.cancelled) throw const ScanCancelled();
      if (checked >= config.localMaxPairs) {
        mark('điểm đặc trưng: DỪNG ở giới hạn ${config.localMaxPairs} cặp '
            '(còn ${total - done} cặp chưa so)');
        break;
      }
      try {
        final thumbs = await _thumbBytes(
            [for (final i in b.photos) assets[i]], config.localThumbSide);
        final newIdx = List<int>.filled(thumbs.length, -1);
        final photos = <Uint8List>[];
        for (var k = 0; k < thumbs.length; k++) {
          final t = thumbs[k];
          if (t != null) {
            newIdx[k] = photos.length;
            photos.add(t);
          }
        }
        final pairs = <LocalPair>[];
        final origPairs = <LocalPair>[];
        for (final p in b.pairs) {
          final x = newIdx[p.a];
          final y = newIdx[p.b];
          if (x < 0 || y < 0) continue;
          pairs.add(LocalPair(x, y));
          origPairs.add(p);
        }
        if (pairs.isNotEmpty) {
          final inl = await matcher.matchPairs(photos, pairs);
          for (var k = 0; k < pairs.length && k < inl.length; k++) {
            checked++;
            if (inl[k] < config.localMinInliers) continue;
            final key =
                _linkKey(b.photos[origPairs[k].a], b.photos[origPairs[k].b], n);
            final prev = out[key];
            if (prev == null || inl[k] > prev) out[key] = inl[k];
          }
        }
      } catch (e) {
        failed++;
        lastErr = '$e';
        if (failed >= 3) {
          mark('điểm đặc trưng: DỪNG sau 3 lô lỗi ($lastErr)');
          break;
        }
      }
      done += b.pairs.length;
      onProgress(ScanProgress(ScanPhase.features, done, total,
          paused: session.paused));
    }
    mark('điểm đặc trưng: so $checked/$total cặp, ${out.length} cặp >= '
        '${config.localMinInliers} điểm'
        '${failed > 0 ? ', $failed lô lỗi ($lastErr)' : ''}');
    return out;
  }

  /// Embedding (chưa trừ trung bình) cho các ảnh có chỉ số trong [todo]. Lỗi được
  /// ghi vào timings; trả về map rỗng/thiếu thay vì ném lỗi.
  Future<Map<int, Float32List>> _embedIndices(
    ScanSession session,
    List<AssetEntity> assets,
    List<int> todo,
    void Function(ScanProgress) onProgress,
    void Function(String) mark,
  ) async {
    final embedder = DinoEmbedder();
    try {
      await embedder.load();
    } catch (e) {
      mark('AI: BỎ QUA, không tải được mô hình ($e)');
      return {};
    }

    final raw = <int, Float32List>{};
    try {
      var thumbFail = 0;
      var batchFail = 0;
      var consecutiveFail = 0;
      String? lastErr;

      // Tổng thời gian (cộng dồn, các batch chạy chồng nhau nên có thể > thời gian thật).
      var thumbMs = 0;
      var prepMs = 0;
      Future<_EmbBatch> prep(int start) async {
        final idx = todo.sublist(
            start, math.min(start + config.modelBatch, todo.length));
        try {
          final sw = Stopwatch()..start();
          final bytes =
              await _thumbBytes([for (final i in idx) assets[i]], dinoSize);
          thumbMs += sw.elapsedMilliseconds;
          sw.reset();
          final inputs = await dinoPreprocessBatch(bytes);
          prepMs += sw.elapsedMilliseconds;
          return _EmbBatch(idx, inputs);
        } catch (e) {
          return _EmbBatch(idx, const [], error: '$e');
        }
      }

      // Chuẩn bị trước 2 batch (thumbnail + giải mã chạy song song với model).
      final queue = <Future<_EmbBatch>>[prep(0)];
      var nextStart = config.modelBatch;
      if (nextStart < todo.length) {
        queue.add(prep(nextStart));
        nextStart += config.modelBatch;
      }
      var done = 0;
      // Đo thời gian: waitSw = thời gian CHỜ batch kế tiếp chuẩn bị xong (thumbnail +
      // giải mã + chuẩn hóa); embedSw = thời gian chạy model. Chờ lâu => nghẽn ở
      // chuẩn bị ảnh, embed lâu => nghẽn ở model.
      final waitSw = Stopwatch();
      final embedSw = Stopwatch();
      while (true) {
        if (session.cancelled) throw const ScanCancelled();
        await session.waitIfPaused();
        if (session.cancelled) throw const ScanCancelled();

        waitSw.start();
        final cur = await queue.removeAt(0);
        waitSw.stop();
        if (nextStart < todo.length) {
          queue.add(prep(nextStart));
          nextStart += config.modelBatch;
        }

        if (cur.error != null) {
          batchFail += cur.idx.length;
          lastErr = cur.error;
        } else {
          final ok = <int>[];
          final inputs = <Float32List>[];
          for (var k = 0; k < cur.idx.length; k++) {
            final t = cur.inputs[k];
            if (t == null) {
              thumbFail++;
            } else {
              ok.add(cur.idx[k]);
              inputs.add(t);
            }
          }
          if (inputs.isNotEmpty) {
            try {
              embedSw.start();
              final e = await embedder.embed(inputs);
              embedSw.stop();
              for (var k = 0; k < ok.length; k++) {
                raw[ok[k]] = e[k];
              }
              consecutiveFail = 0;
            } catch (e) {
              embedSw.stop();
              batchFail += ok.length;
              lastErr = '$e';
              consecutiveFail++;
            }
          }
        }
        done += cur.idx.length;
        onProgress(ScanProgress(ScanPhase.embedding, done, todo.length,
            paused: session.paused));
        if (done >= todo.length) break;
        if (consecutiveFail >= 3) {
          mark('AI: DỪNG sớm sau 3 batch lỗi liên tiếp');
          break;
        }
      }
      mark('AI: lấy thumbnail ${(thumbMs / 1000).round()}s, giải mã+chuẩn hóa '
          '${(prepMs / 1000).round()}s (cộng dồn); '
          'thời gian chờ chuẩn bị ảnh ${waitSw.elapsed.inSeconds}s, '
          'chạy model ${embedSw.elapsed.inSeconds}s '
          '(${todo.length} ảnh, batch ${config.modelBatch})');
      mark('AI: ${raw.length}/${todo.length} ảnh có embedding'
          '${thumbFail > 0 ? ', $thumbFail ảnh không đọc được thumbnail' : ''}'
          '${batchFail > 0 ? ', $batchFail ảnh lỗi ($lastErr)' : ''}');
    } finally {
      await embedder.close();
    }

    return raw;
  }

  /// Bước AI cho tab "Tương tự": embedding mọi ảnh chưa vào nhóm trùng, trừ trung
  /// bình toàn thư viện, rồi nối mỗi ảnh với [ScanConfig.similarModelK] hàng xóm gần
  /// nhất (cosine >= [ScanConfig.similarModelFloor]) vào [ufSim]. Ngưỡng cuối do
  /// người dùng chỉnh lúc xem (thanh "Độ nhạy"), nên không cần bộ dữ liệu cố định.
  /// Trả về embedding đã trừ trung bình; rỗng nếu bỏ qua.
  Future<Map<int, Float32List>> _similarModelStage(
    ScanSession session,
    List<AssetEntity> assets,
    UnionFind ufSim,
    void Function(ScanProgress) onProgress,
    void Function(String) mark,
  ) async {
    final n = assets.length;
    // Mọi ảnh đều được embedding: kết quả tương tự không phụ thuộc việc có quét
    // ảnh trùng hay không.
    final todo = [for (var i = 0; i < n; i++) i];
    if (todo.length < config.modelMinMeanCount) {
      mark('AI tương tự: BỎ QUA, chỉ ${todo.length} ảnh cần so');
      return {};
    }
    final raw = await _embedIndices(session, assets, todo, onProgress, mark);
    if (raw.length < config.modelMinMeanCount) {
      mark('AI tương tự: BỎ QUA, chỉ ${raw.length} embedding hợp lệ');
      return {};
    }
    final out = centerEmbeddings(raw);
    onProgress(const ScanProgress(ScanPhase.matching, 0, 1));
    final ids = out.keys.toList()..sort();
    final dim = out[ids.first]!.length;
    final flat = Float32List(ids.length * dim);
    for (var r = 0; r < ids.length; r++) {
      flat.setRange(r * dim, (r + 1) * dim, out[ids[r]]!);
    }
    final k = config.similarModelK;
    final floor = config.similarModelFloor;
    final edges = await Isolate.run(
        () => findTopKEdges(emb: flat, n: ids.length, dim: dim, k: k, minCos: floor));
    for (final e in edges) {
      ufSim.union(ids[e.a], ids[e.b]);
    }
    session.embeddings
      ..clear()
      ..addAll({for (final i in ids) assets[i].id: out[i]!});
    mark('AI tương tự: ${ids.length} ảnh, ${edges.length} cạnh top-$k '
        'cosine>=$floor');
    return out;
  }

  /// Bước AI: xác minh các cặp ứng viên PDQ có Hamming nằm giữa [ScanConfig.maxHamming]
  /// và [ScanConfig.similarMaxHamming] (hash lệch một chút, ví dụ ảnh cháy sáng).
  /// Chỉ ảnh thuộc các cặp đó (và chưa vào nhóm nào) được embedding, cộng một mẫu
  /// nhỏ rải đều thư viện để tính vector trung bình. Embedding được trừ trung bình
  /// rồi L2-normalize lại (đặc trưng MobileNet đều dương nên cosine thô giữa ảnh
  /// bất kỳ đã cao). Cặp có cosine >= [ScanConfig.modelMinCosine] được nối vào [uf].
  /// Mọi lỗi đều được ghi vào timings. Trả về embedding (đã trừ trung bình) theo
  /// chỉ số ảnh; rỗng nếu không có cặp nào cần xác minh hoặc không đủ mẫu.
  Future<Map<int, Float32List>> _modelStage(
    ScanSession session,
    List<AssetEntity> assets,
    UnionFind uf,
    List<MatchEdge> edges,
    void Function(ScanProgress) onProgress,
    void Function(String) mark,
  ) async {
    final n = assets.length;
    final groupSize = List<int>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      groupSize[uf.find(i)]++;
    }
    final pairs = <MatchEdge>[
      for (final e in edges)
        if (e.distance > config.maxHamming &&
            groupSize[uf.find(e.a)] == 1 &&
            groupSize[uf.find(e.b)] == 1)
          e,
    ];
    if (pairs.isEmpty) {
      mark('AI: bỏ qua, không có cặp PDQ nào cần xác minh');
      return {};
    }

    // Ảnh cần embedding = ảnh trong các cặp + mẫu rải đều để lấy trung bình.
    final need = <int>{
      for (final e in pairs) ...[e.a, e.b],
    };
    final sampleStep = math.max(1, n ~/ config.modelMeanSample);
    for (var i = 0; i < n; i += sampleStep) {
      need.add(i);
    }
    final todo = need.toList()..sort();
    if (todo.length < config.modelMinMeanCount) {
      mark('AI: BỎ QUA, chỉ ${todo.length} ảnh (< ${config.modelMinMeanCount}) '
          'nên không đủ mẫu để trừ trung bình');
      return {};
    }

    final raw = await _embedIndices(session, assets, todo, onProgress, mark);
    if (raw.length < config.modelMinMeanCount) {
      mark('AI: BỎ QUA xác minh, chỉ ${raw.length} embedding hợp lệ');
      return {};
    }
    final out = centerEmbeddings(raw);
    onProgress(ScanProgress(ScanPhase.matching, pairs.length, pairs.length));
    var checked = 0;
    var merged = 0;
    for (final e in pairs) {
      final c = cosineOf(out[e.a], out[e.b]);
      if (c == null) continue;
      checked++;
      if (c >= config.modelMinCosine) {
        uf.union(e.a, e.b);
        merged++;
      }
    }
    mark('AI: $merged/$checked cặp PDQ (${config.maxHamming}<Hamming<='
        '${config.similarMaxHamming}) có cosine>=${config.modelMinCosine}');
    return out;
  }

  /// Thumbnail vuông [side]px cho từng ảnh; null nếu không đọc được.
  Future<List<Uint8List?>> _thumbBytes(
      List<AssetEntity> batch, int side) async {
    final res = <Uint8List?>[];
    final c = config.ioConcurrency;
    for (var i = 0; i < batch.length; i += c) {
      final slice = batch.sublist(i, math.min(i + c, batch.length));
      res.addAll(await Future.wait([
        for (final a in slice)
          () async {
            try {
              return await a.thumbnailDataWithSize(ThumbnailSize(side, side),
                  quality: 85);
            } catch (_) {
              return null;
            }
          }()
      ]));
    }
    return res;
  }

  /// Chỉ thumbnail 128px; chỉ số là chỉ số trong batch.
  Future<List<HashInput>> _thumbs(List<AssetEntity> batch) async {
    final inputs = <HashInput>[];
    final c = config.ioConcurrency;
    for (var i = 0; i < batch.length; i += c) {
      final slice = batch.sublist(i, math.min(i + c, batch.length));
      inputs.addAll(await Future.wait(List.generate(slice.length, (k) async {
        Uint8List? thumb;
        try {
          // Ảnh nằm trên iCloud chưa tải có thể làm lời gọi này treo vô hạn:
          // quá hạn thì coi như không đọc được, quét tiếp ảnh sau.
          thumb = await slice[k]
              .thumbnailDataWithSize(
                const ThumbnailSize(128, 128),
                quality: 70,
              )
              .timeout(const Duration(seconds: 10));
        } catch (_) {}
        return HashInput(index: i + k, thumb: thumb);
      })));
    }
    return inputs;
  }

  /// Export file gốc cho các ảnh nghi trùng; chỉ số là chỉ số trong [idx].
  Future<List<HashInput>> _files(
      List<int> idx, List<AssetEntity> assets) async {
    final inputs = <HashInput>[];
    final c = config.fileConcurrency;
    for (var i = 0; i < idx.length; i += c) {
      final end = math.min(i + c, idx.length);
      inputs.addAll(await Future.wait([
        for (var k = i; k < end; k++)
          () async {
            String? path;
            try {
              path = (await assets[idx[k]]
                      .originFile
                      .timeout(const Duration(seconds: 30)))
                  ?.path;
            } catch (_) {}
            return HashInput(index: k, filePath: path);
          }()
      ]));
    }
    return inputs;
  }
}

class _Pending {
  _Pending({
    required this.assets,
    required this.shas,
    required this.flat,
    required this.has,
    required this.uf,
    required this.ufSim,
    required this.links,
    required this.localLinks,
    required this.emb,
    required this.inDupIds,
    required this.dupGroups,
  });
  final List<AssetEntity> assets;
  final List<String?> shas;
  final Uint64List flat;
  final Uint8List has;
  final UnionFind uf;
  final UnionFind ufSim;
  final Map<int, int> links;
  final Map<int, int> localLinks;
  final Map<int, Float32List> emb;
  final Set<String> inDupIds;
  final List<DuplicateGroup> dupGroups;
}

class _OrigHashes {
  const _OrigHashes(this.owners, this.flat);

  /// owners[k] = chỉ số ảnh (đã chỉnh) mà hash gốc thứ k thuộc về.
  final List<int> owners;

  /// 4 word 64-bit cho mỗi hash gốc; null nếu không có.
  final Uint64List? flat;
}

class _EmbBatch {
  const _EmbBatch(this.idx, this.inputs, {this.error});
  final List<int> idx;
  final List<Float32List?> inputs;
  final String? error;
}

class _Batch {
  const _Batch(this.assets, this.inputs);
  final List<AssetEntity> assets;
  final List<HashInput> inputs;
}

void _log(String tag, Duration elapsed) {
  if (!kDebugMode) return;
  const mb = 1024 * 1024;
  debugPrint('[scan] ${elapsed.inSeconds}s $tag '
      'rss=${ProcessInfo.currentRss ~/ mb}MB max=${ProcessInfo.maxRss ~/ mb}MB');
}
