import 'package:cleanify/core/scanner/scan_diagnostics.dart';
import 'package:cleanify/core/scanner/scan_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

AssetEntity _asset(String id) =>
    AssetEntity(id: id, typeInt: 1, width: 100, height: 100);

DuplicateGroup _group(List<String> ids, {GroupKind kind = GroupKind.duplicate}) =>
    DuplicateGroup([for (final id in ids) DuplicateItem(_asset(id), exact: false)],
        kind: kind);

DiagRow _row(String asset, String anchor, {int? hamming, String reason = 'x'}) =>
    DiagRow(
      assetId: asset,
      anchorId: anchor,
      hamming: hamming,
      pdqPercent: hamming == null ? null : 100 * (1 - hamming / 256),
      threshold: 'certain<=12, max<=24',
      reason: reason,
    );

void main() {
  group('csvEscape', () {
    test('giữ nguyên giá trị đơn giản và null thành chuỗi rỗng', () {
      expect(csvEscape('abc'), 'abc');
      expect(csvEscape(12), '12');
      expect(csvEscape(null), '');
    });

    test('bọc nháy kép khi có dấu phẩy, nháy kép hoặc xuống dòng', () {
      expect(csvEscape('a,b'), '"a,b"');
      expect(csvEscape('say "hi"'), '"say ""hi"""');
      expect(csvEscape('line1\nline2'), '"line1\nline2"');
    });
  });

  group('toCsv', () {
    test('header đúng thứ tự cột và mỗi thành viên một dòng kèm verdict', () {
      final diag = ScanDiagnostics();
      final g = _group(['a1', 'a2']);
      diag.attach(g, [
        _row('a1', 'a1', reason: 'anchor'),
        _row('a2', 'a1', hamming: 6, reason: 'hamming<=certain'),
      ]);
      diag.setVerdict(g, DiagVerdict.yes);

      final lines = diag.toCsv({'dup': [g]}).split('\r\n')
        ..removeWhere((l) => l.isEmpty);
      expect(lines.first,
          'tab,group_id,asset_id,anchor_id,hamming,pdq_percent,cos_dino,'
          'cos_reid,threshold,reason,verdict');
      expect(lines.length, 3);
      expect(lines[2],
          startsWith('dup,dup-1,a2,a1,6,'));
      expect(lines[2], endsWith(',hamming<=certain,✓'));
    });

    test('nhóm chưa chấm thì cột verdict để trống', () {
      final diag = ScanDiagnostics();
      final g = _group(['b1', 'b2']);
      diag.attach(g, [_row('b1', 'b1', reason: 'anchor')]);
      final line = diag.toCsv({'similar': [g]}).split('\r\n')[1];
      expect(line.endsWith(','), isTrue);
    });
  });

  group('precision', () {
    test('precision = ✓ / (✓ + ✗), ? không tính vào mẫu số', () {
      final diag = ScanDiagnostics();
      final g1 = _group(['a', 'b']);
      final g2 = _group(['c', 'd']);
      final g3 = _group(['e', 'f']);
      final g4 = _group(['g', 'h']);
      diag.setVerdict(g1, DiagVerdict.yes);
      diag.setVerdict(g2, DiagVerdict.yes);
      diag.setVerdict(g3, DiagVerdict.no);
      diag.setVerdict(g4, DiagVerdict.unsure);

      final st = diag.statsFor([g1, g2, g3, g4, _group(['x', 'y'])]);
      expect(st.graded, 4);
      expect(st.yes, 2);
      expect(st.no, 1);
      expect(st.precision, closeTo(2 / 3, 1e-9));
    });

    test('chưa có ✓ hoặc ✗ thì precision là null', () {
      final diag = ScanDiagnostics();
      final g = _group(['a', 'b']);
      diag.setVerdict(g, DiagVerdict.unsure);
      expect(diag.statsFor([g]).precision, isNull);
    });

    test('bỏ chấm (null) thì nhóm không còn được tính', () {
      final diag = ScanDiagnostics();
      final g = _group(['a', 'b']);
      diag.setVerdict(g, DiagVerdict.yes);
      diag.setVerdict(g, null);
      expect(diag.statsFor([g]).graded, 0);
    });
  });

  group('diag tắt', () {
    test('scanDiagEnabled chỉ true khi debug hoặc có cờ define', () {
      expect(scanDiagEnabled(debug: false, define: false), isFalse);
      expect(scanDiagEnabled(debug: true, define: false), isTrue);
      expect(scanDiagEnabled(debug: false, define: true), isTrue);
    });

    test('phiên không có diag thì không có gì để ghi', () {
      final s = ScanSession();
      expect(s.diag, isNull);
      expect(s.groups, isEmpty);
    });
  });
}
