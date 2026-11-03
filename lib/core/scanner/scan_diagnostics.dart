import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'scan_session.dart';

const _diagDefine = bool.fromEnvironment('SCAN_DIAG');

/// Chẩn đoán chỉ bật khi chạy debug hoặc build với --dart-define=SCAN_DIAG=true.
bool scanDiagEnabled({bool debug = kDebugMode, bool define = _diagDefine}) =>
    debug || define;

enum DiagVerdict { yes, no, unsure }

extension DiagVerdictSymbol on DiagVerdict {
  String get symbol => switch (this) {
        DiagVerdict.yes => '✓',
        DiagVerdict.no => '✗',
        DiagVerdict.unsure => '?',
      };
}

/// Số liệu của một ảnh so với ảnh đại diện (anchor) của cùng nhóm.
class DiagRow {
  const DiagRow({
    required this.assetId,
    required this.anchorId,
    required this.threshold,
    required this.reason,
    this.hamming,
    this.pdqPercent,
    this.cosDino,
    this.cosReid,
  });

  final String assetId;
  final String anchorId;

  /// Khoảng cách Hamming PDQ (0–256). Null nếu một trong hai ảnh không có hash.
  final int? hamming;
  final double? pdqPercent;

  /// cosine DINO. Chỉ có ở tab "tương tự".
  final double? cosDino;

  /// cosine Re-ID toàn thân. Chỉ có ở tab "người".
  final double? cosReid;

  /// Ngưỡng đang áp dụng cho tab này, dạng văn bản.
  final String threshold;

  /// Lý do ảnh được gom vào nhóm.
  final String reason;
}

class TabStats {
  const TabStats({required this.graded, required this.yes, required this.no});
  final int graded;
  final int yes;
  final int no;

  /// ✓ / (✓ + ✗). Null nếu chưa có nhóm nào được chấm ✓ hoặc ✗.
  double? get precision => yes + no == 0 ? null : yes / (yes + no);
}

/// Ghi lại số liệu từng ảnh trong nhóm và nhãn chấm tay, chỉ nằm trong RAM.
/// Khóa là đối tượng nhóm (so sánh theo danh tính).
class ScanDiagnostics {
  final Map<DuplicateGroup, List<DiagRow>> _rows = {};
  final Map<DuplicateGroup, DiagVerdict> _verdicts = {};

  void attach(DuplicateGroup group, List<DiagRow> rows) => _rows[group] = rows;

  List<DiagRow> rowsOf(DuplicateGroup group) => _rows[group] ?? const [];

  DiagVerdict? verdictOf(DuplicateGroup group) => _verdicts[group];

  void setVerdict(DuplicateGroup group, DiagVerdict? verdict) {
    if (verdict == null) {
      _verdicts.remove(group);
    } else {
      _verdicts[group] = verdict;
    }
  }

  void clear() {
    _rows.clear();
    _verdicts.clear();
  }

  TabStats statsFor(List<DuplicateGroup> groups) {
    var yes = 0, no = 0, graded = 0;
    for (final g in groups) {
      final v = _verdicts[g];
      if (v == null) continue;
      graded++;
      if (v == DiagVerdict.yes) yes++;
      if (v == DiagVerdict.no) no++;
    }
    return TabStats(graded: graded, yes: yes, no: no);
  }

  /// [tabs]: tên tab -> danh sách nhóm của tab đó (theo thứ tự hiển thị).
  String toCsv(Map<String, List<DuplicateGroup>> tabs) {
    final buf = StringBuffer()
      ..write(
          'tab,group_id,asset_id,anchor_id,hamming,pdq_percent,cos_dino,'
          'cos_reid,threshold,reason,verdict\r\n');
    tabs.forEach((tab, groups) {
      for (var i = 0; i < groups.length; i++) {
        final g = groups[i];
        final verdict = _verdicts[g]?.symbol ?? '';
        final groupId = '$tab-${i + 1}';
        for (final r in rowsOf(g)) {
          buf.write([
            tab,
            groupId,
            r.assetId,
            r.anchorId,
            r.hamming,
            _fmt(r.pdqPercent, 2),
            _fmt(r.cosDino, 4),
            _fmt(r.cosReid, 4),
            r.threshold,
            r.reason,
            verdict,
          ].map(csvEscape).join(','));
          buf.write('\r\n');
        }
      }
    });
    return buf.toString();
  }

  /// Ghi CSV vào thư mục documents của app (lấy ra qua Files/AirDrop).
  Future<File> writeCsv(Map<String, List<DuplicateGroup>> tabs) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
        '${dir.path}/cleanify_diag_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(toCsv(tabs));
    return file;
  }
}

/// Escape theo RFC 4180: bọc bằng nháy kép nếu có dấu phẩy, nháy kép hoặc xuống dòng.
String csvEscape(Object? value) {
  if (value == null) return '';
  final s = value.toString();
  if (s.contains(RegExp(r'[",\r\n]'))) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String _fmt(double? v, int digits) => v == null ? '' : v.toStringAsFixed(digits);
