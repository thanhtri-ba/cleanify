import 'package:cleanify/core/scanner/bulk_cleanup.dart';
import 'package:cleanify/core/scanner/scan_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

AssetEntity _a(String id) =>
    AssetEntity(id: id, typeInt: 1, width: 100, height: 100);

DuplicateItem _i(String id, {double? sim, bool exact = false}) =>
    DuplicateItem(_a(id), exact: exact, similarity: sim);

DuplicateGroup _g(List<DuplicateItem> items,
        {GroupKind kind = GroupKind.duplicate}) =>
    DuplicateGroup(items, kind: kind);

List<String> _ids(BulkCleanupPlan p, GroupKind k) =>
    p.deletes[k]!.map((e) => e.id).toList();

void main() {
  group('planBulkCleanup', () {
    test('giữ ảnh đầu, xóa ảnh còn lại đạt ngưỡng', () {
      final plan = planBulkCleanup([
        _g([_i('a', sim: 100), _i('b', sim: 95), _i('c', sim: 90)]),
      ], minSimilarity: 88);
      expect(_ids(plan, GroupKind.duplicate), ['b', 'c']);
      expect(plan.groupsFor(GroupKind.duplicate), 1);
    });

    test('ảnh dưới ngưỡng được giữ lại', () {
      final plan = planBulkCleanup([
        _g([_i('a', sim: 100), _i('b', sim: 95), _i('c', sim: 80)]),
      ], minSimilarity: 88);
      expect(_ids(plan, GroupKind.duplicate), ['b']);
    });

    test('biên 88%: Hamming 30 (88,28%) được xóa, Hamming 31 (87,89%) thì không',
        () {
      double pdq(int h) => 100 * (1 - h / 256);
      final plan = planBulkCleanup([
        _g([_i('a', sim: 100), _i('h30', sim: pdq(30)), _i('h31', sim: pdq(31))]),
      ], minSimilarity: 88);
      expect(_ids(plan, GroupKind.duplicate), ['h30']);
    });

    test('ngưỡng đúng bằng độ giống thì được xóa', () {
      final plan = planBulkCleanup([
        _g([_i('a', sim: 100), _i('b', sim: 90)]),
      ], minSimilarity: 90);
      expect(_ids(plan, GroupKind.duplicate), ['b']);
    });

    test('không có độ giống (null) thì không xóa, nhưng trùng SHA-256 thì xóa',
        () {
      final plan = planBulkCleanup([
        _g([
          _i('a', sim: 100),
          _i('n'),
          _i('e', exact: true),
        ]),
      ], minSimilarity: 88);
      expect(_ids(plan, GroupKind.duplicate), ['e']);
    });

    test('không bao giờ xóa hết nhóm: nhóm 2 ảnh với ảnh dưới ngưỡng thì rỗng',
        () {
      final plan = planBulkCleanup([
        _g([_i('a', sim: 100), _i('b', sim: 70)]),
      ], minSimilarity: 88);
      expect(plan.countFor(GroupKind.duplicate), 0);
      expect(plan.groupsFor(GroupKind.duplicate), 0);
    });

    test('ngưỡng 100 chỉ xóa bản trùng giống hệt', () {
      final plan = planBulkCleanup([
        _g([_i('a', sim: 100), _i('b', sim: 99.6), _i('e', exact: true)]),
      ], minSimilarity: 100);
      expect(_ids(plan, GroupKind.duplicate), ['e']);
    });

    test('mỗi ảnh chỉ xuất hiện một lần trong kế hoạch', () {
      final plan = planBulkCleanup([
        _g([_i('a', sim: 100), _i('dup', sim: 95)]),
        _g([_i('b', sim: 100), _i('dup', sim: 95)]),
      ], minSimilarity: 88);
      expect(plan.assetsFor(GroupKind.values.toSet()).map((e) => e.id).toList(),
          ['dup']);
    });

    test('ảnh giữ lại của nhóm này không bị nhóm khác xóa', () {
      final plan = planBulkCleanup([
        _g([_i('keep', sim: 100), _i('d1', sim: 95)]),
        _g([_i('other', sim: 100), _i('keep', sim: 96)]),
      ], minSimilarity: 88);
      expect(_ids(plan, GroupKind.duplicate), ['d1']);
    });

    test('nhóm rỗng hoặc 1 ảnh không gây lỗi và không xóa gì', () {
      final plan = planBulkCleanup([
        _g([]),
        _g([_i('solo', sim: 100)]),
      ], minSimilarity: 88);
      expect(plan.assetsFor(GroupKind.values.toSet()), isEmpty);
    });
  });

  group('withMinModelCosine', () {
    DuplicateItem m(String id, double c) =>
        DuplicateItem(_a(id), exact: false, modelCosine: c);
    final g = DuplicateGroup(
        [_i('a', sim: 100), m('b', 0.5), m('c', 0.7)],
        kind: GroupKind.similar);

    test('ngưỡng thấp giữ nguyên nhóm', () {
      expect(identical(g.withMinModelCosine(0.4), g), isTrue);
    });
    test('ngưỡng cao bỏ ảnh yếu', () {
      expect(g.withMinModelCosine(0.6)!.items.map((e) => e.asset.id), ['a', 'c']);
    });
    test('còn dưới 2 ảnh thì bỏ nhóm', () {
      expect(g.withMinModelCosine(0.9), isNull);
    });
    test('ảnh chỉ nhờ AI không bao giờ bị Dọn nhanh xóa', () {
      final plan = planBulkCleanup([g], minSimilarity: 80);
      expect(plan.deletes[GroupKind.similar] ?? const [], isEmpty);
    });
  });

  group('planBulkCleanup bảo vệ ảnh', () {
    DuplicateItem fav(String id, double sim) => DuplicateItem(
        AssetEntity(id: id, typeInt: 1, width: 100, height: 100, isFavorite: true),
        exact: false,
        similarity: sim);

    test('ảnh yêu thích không tự chọn xóa', () {
      final plan = planBulkCleanup([
        _g([_i('a', sim: 100), fav('b', 99), _i('c', sim: 95)]),
      ], minSimilarity: 88);
      expect(_ids(plan, GroupKind.duplicate), ['c']);
    });

    test('ảnh trong protectedIds (đã chỉnh sửa) không tự chọn xóa', () {
      final plan = planBulkCleanup([
        _g([_i('a', sim: 100), _i('b', sim: 99), _i('c', sim: 95)]),
      ], minSimilarity: 88, protectedIds: {'b'});
      expect(_ids(plan, GroupKind.duplicate), ['c']);
    });
  });
}
