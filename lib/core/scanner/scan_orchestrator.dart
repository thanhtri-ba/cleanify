import 'dart:io' show ProcessInfo;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, kProfileMode, kReleaseMode;
import 'package:photo_manager/photo_manager.dart';

import '../../engines/dino/dino_engine.dart';
import '../../engines/dino/dino_matcher.dart';
import '../../engines/lsh/candidate_index.dart';
import '../../engines/pdq/pdq_engine.dart';
import 'hash_worker.dart';
import 'scan_diagnostics.dart';
import 'scan_progress.dart';
import 'scan_session.dart';

class ScanConfig {
  const ScanConfig({
    this.batchSize = 128,
    this.ioConcurrency = 8,
    this.shaBatch = 32,
    this.fileConcurrency = 4,
    this.maxHamming = 40,
    this.useModel = true,
    this.modelBatch = 16,
    this.modelMinCosine = 0.84,
    this.modelExactBelow = 8000,
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
  /// 40 -> độ giống bit-hash >= 84,4% (100 * (1 - 40/256)).
  final int maxHamming;

  /// Bước AI (DINOv2) chạy SAU PDQ/SHA, chỉ cho ảnh chưa vào nhóm nào.
  final bool useModel;
  final int modelBatch;

  /// Hai ảnh là trùng theo mô hình khi cosine embedding >= ngưỡng này.
  /// CHƯA calibrate trên ảnh thật: chỉnh bằng tool/calibrate.py (xem tool/EVAL.md).
  final double modelMinCosine;

  /// Số ảnh tối đa để so mọi cặp; lớn hơn thì dùng LSH (recall xấp xỉ).
  final int modelExactBelow;
}

class ScanOrchestrator {
  ScanOrchestrator({this.config = const ScanConfig()});

  final ScanConfig config;

  /// Điền kết quả vào [session]. Dữ liệu trung gian (hash, index) chỉ là biến
  /// cục bộ nên được giải phóng khi hàm kết thúc.
  Future<void> run(
    ScanSession session,
    void Function(ScanProgress) onProgress,
  ) async {
    final sw = Stopwatch()..start();
    // Ghi thời gian từng giai đoạn để hiện trên màn hình kết quả.
    void mark(String tag) {
      _log(tag, sw);
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
          return _Batch(list, await _thumbs(list));
        } catch (_) {
          return null;
        }
      }

      var nextStart = config.batchSize;
      var next = fetch(0);
      while (true) {
        if (session.cancelled) throw const ScanCancelled();
        await session.waitIfPaused();
        if (session.cancelled) throw const ScanCancelled();

        final cur = await next;
        if (cur == null) break;
        next = fetch(nextStart);
        nextStart += config.batchSize;

        final base = assets.length;
        assets.addAll(cur.assets);
        final outputs = await hashBatch(cur.inputs);
        for (final o in outputs) {
          final p = o.pdq;
          if (p != null) {
            final gi = base + o.index;
            flat.setRange(gi * 4, gi * 4 + 4, p);
            has[gi] = 1;
          }
        }
        session.scanned = assets.length;
        onProgress(ScanProgress(ScanPhase.reading, assets.length, total,
            paused: session.paused));
        if ((assets.length ~/ config.batchSize) % 10 == 0) {
          mark('đọc ${assets.length}/$total');
        }
      }

      final n = assets.length;
      mark('xong PDQ n=$n');
      onProgress(ScanProgress(ScanPhase.matching, n, n));

      // Giai đoạn 2: ứng viên LSH + Hamming (chỉ cần PDQ).
      final edges = findNearEdges(
        flat: flat,
        has: has,
        n: n,
        maxHamming: config.maxHamming,
      );

      // SHA-256 chỉ cần cho ảnh nghi trùng: hai file giống hệt nhau luôn có
      // thumbnail và PDQ giống hệt nhau, nên ảnh không nằm trong cặp ứng viên
      // nào thì không thể là bản sao y hệt của ảnh khác.
      final needSha = Uint8List(n);
      for (final e in edges) {
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
          if (needSha[i] == 1) i
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
        onProgress(ScanProgress(
            ScanPhase.exact, math.min(s0 + config.shaBatch, shaIdx.length),
            shaIdx.length,
            paused: session.paused));
      }
      for (var i = 0; i < n; i++) {
        if (has[i] == 0 && shas[i] == null) session.hashFailures++;
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

      for (final e in edges) {
        uf.union(e.a, e.b);
      }

      // Giai đoạn 3: mô hình AI cho các ảnh còn lại chưa vào nhóm nào.
      final emb = config.useModel
          ? await _modelStage(session, assets, uf, onProgress, mark)
          : <int, Float32List>{};

      // Giai đoạn 5: dựng nhóm.
      final byRoot = <int, List<int>>{};
      for (var i = 0; i < n; i++) {
        (byRoot[uf.find(i)] ??= <int>[]).add(i);
      }
      final groups = <DuplicateGroup>[];
      for (final members in byRoot.values) {
        if (members.length < 2) continue;
        members.sort((a, b) {
          final pa = assets[a].width * assets[a].height;
          final pb = assets[b].width * assets[b].height;
          if (pa != pb) return pb.compareTo(pa);
          return assets[a].createDateTime.compareTo(assets[b].createDateTime);
        });
        final rep = members.first;
        final items = <DuplicateItem>[];
        final rows = <DiagRow>[];
        for (final m in members) {
          final exact = shas[m] != null && shas[m] == shas[rep];
          final h = _hamming(flat, has, m, rep);
          final c = m == rep ? null : cosineOf(emb[m], emb[rep]);
          // Nhóm do mô hình: hai ảnh không gần nhau theo PDQ nhưng có cosine.
          final byModel =
              !exact && c != null && !(h != null && h <= config.maxHamming);
          double? sim;
          if (m == rep) {
            sim = 100;
          } else if (byModel) {
            sim = c! * 100;
          } else if (h != null) {
            sim = pdqSimilarity(h);
          }
          items.add(DuplicateItem(assets[m],
              exact: exact, similarity: sim, byModel: byModel));
          if (session.diag != null) {
            rows.add(_dupRow(assets[m], assets[rep],
                isAnchor: m == rep,
                exact: exact,
                hamming: h,
                cosine: c,
                byModel: byModel));
          }
        }
        final group = DuplicateGroup(items);
        groups.add(group);
        session.diag?.attach(group, rows);
      }
      groups.sort((a, b) => b.items.length.compareTo(a.items.length));
      session.groups
        ..clear()
        ..addAll(groups);

      mark('xong nhóm ảnh trùng');
    } finally {
      session.elapsed = sw.elapsed;
      // Xóa file tạm mà photo_manager có thể đã tạo (vd. iOS export file gốc).
      try {
        await PhotoManager.clearFileCache();
      } catch (_) {}
    }
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
  }) {
    final String reason;
    if (isAnchor) {
      reason = 'anchor';
    } else if (exact) {
      reason = 'sha256';
    } else if (byModel) {
      reason = 'dino-cosine>=${config.modelMinCosine}';
    } else if (hamming != null && hamming <= config.maxHamming) {
      reason = 'hamming<=max';
    } else {
      reason = 'bắc cầu (union-find)';
    }
    return DiagRow(
      assetId: asset.id,
      anchorId: anchor.id,
      hamming: hamming,
      pdqPercent: hamming == null ? null : pdqSimilarity(hamming),
      cosDino: cosine,
      threshold: byModel
          ? 'cos>=${config.modelMinCosine}'
          : 'max<=${config.maxHamming}',
      reason: reason,
    );
  }

  /// Bước AI: embedding DINOv2 cho ảnh chưa vào nhóm, rồi nối các cặp có
  /// cosine >= [ScanConfig.modelMinCosine] vào [uf]. Mọi lỗi đều được ghi vào
  /// timings, không nuốt âm thầm. Trả về embedding theo chỉ số ảnh.
  Future<Map<int, Float32List>> _modelStage(
    ScanSession session,
    List<AssetEntity> assets,
    UnionFind uf,
    void Function(ScanProgress) onProgress,
    void Function(String) mark,
  ) async {
    final n = assets.length;
    final groupSize = List<int>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      groupSize[uf.find(i)]++;
    }
    final todo = [
      for (var i = 0; i < n; i++)
        if (groupSize[uf.find(i)] == 1) i
    ];
    if (todo.length < 2) {
      mark('AI: bỏ qua, còn ${todo.length} ảnh chưa nhóm');
      return {};
    }

    final embedder = DinoEmbedder();
    try {
      await embedder.load();
    } catch (e) {
      mark('AI: BỎ QUA, không tải được mô hình ($e)');
      return {};
    }

    final out = <int, Float32List>{};
    try {
      var thumbFail = 0;
      var batchFail = 0;
      var consecutiveFail = 0;
      String? lastErr;

      Future<_EmbBatch> prep(int start) async {
        final idx = todo.sublist(
            start, math.min(start + config.modelBatch, todo.length));
        try {
          final bytes =
              await _thumbBytes([for (final i in idx) assets[i]], dinoSize);
          return _EmbBatch(idx, await dinoPreprocessBatch(bytes));
        } catch (e) {
          return _EmbBatch(idx, const [], error: '$e');
        }
      }

      var nextStart = config.modelBatch;
      var next = prep(0);
      var done = 0;
      while (true) {
        if (session.cancelled) throw const ScanCancelled();
        await session.waitIfPaused();
        if (session.cancelled) throw const ScanCancelled();

        final cur = await next;
        if (nextStart < todo.length) {
          next = prep(nextStart);
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
              final e = await embedder.embed(inputs);
              for (var k = 0; k < ok.length; k++) {
                out[ok[k]] = e[k];
              }
              consecutiveFail = 0;
            } catch (e) {
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
      mark('AI: ${out.length}/${todo.length} ảnh có embedding'
          '${thumbFail > 0 ? ', $thumbFail ảnh không đọc được thumbnail' : ''}'
          '${batchFail > 0 ? ', $batchFail ảnh lỗi ($lastErr)' : ''}');

      if (out.length >= 2) {
        final ids = out.keys.toList()..sort();
        final cnt = ids.length;
        final flatEmb = Float32List(cnt * dinoDim);
        for (var k = 0; k < cnt; k++) {
          flatEmb.setRange(k * dinoDim, (k + 1) * dinoDim, out[ids[k]]!);
        }
        onProgress(ScanProgress(ScanPhase.matching, cnt, cnt));
        final minCos = config.modelMinCosine;
        final exactBelow = config.modelExactBelow;
        final edges = await Isolate.run(() => findDinoEdges(
              emb: flatEmb,
              n: cnt,
              dim: dinoDim,
              minCos: minCos,
              exactBelow: exactBelow,
            ));
        for (final e in edges) {
          uf.union(ids[e.a], ids[e.b]);
        }
        mark('AI: ${edges.length} cặp cosine>=$minCos trên $cnt ảnh'
            '${cnt > exactBelow ? ' (LSH, recall xấp xỉ)' : ''}');
      }
    } finally {
      await embedder.close();
    }
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
          thumb = await slice[k].thumbnailDataWithSize(
            const ThumbnailSize(128, 128),
            quality: 70,
          );
        } catch (_) {}
        return HashInput(index: i + k, thumb: thumb);
      })));
    }
    return inputs;
  }

  /// Export file gốc cho các ảnh nghi trùng; chỉ số là chỉ số trong [idx].
  Future<List<HashInput>> _files(List<int> idx, List<AssetEntity> assets) async {
    final inputs = <HashInput>[];
    final c = config.fileConcurrency;
    for (var i = 0; i < idx.length; i += c) {
      final end = math.min(i + c, idx.length);
      inputs.addAll(await Future.wait([
        for (var k = i; k < end; k++)
          () async {
            String? path;
            try {
              path = (await assets[idx[k]].originFile)?.path;
            } catch (_) {}
            return HashInput(index: k, filePath: path);
          }()
      ]));
    }
    return inputs;
  }
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

void _log(String tag, Stopwatch sw) {
  if (!kDebugMode) return;
  const mb = 1024 * 1024;
  debugPrint('[scan] ${sw.elapsed.inSeconds}s $tag '
      'rss=${ProcessInfo.currentRss ~/ mb}MB max=${ProcessInfo.maxRss ~/ mb}MB');
}
