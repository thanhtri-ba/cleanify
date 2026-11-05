import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cleanify/features/home/home_page.dart';
import 'package:cleanify/features/scan/scan_controller.dart';

void main() {
  testWidgets('Home hiển thị các thẻ theo Figma khi chưa quét', (tester) async {
    final c = ScanController();
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(home: HomePage(controller: c)));
    expect(find.text('Cleanify'), findsOneWidget);
    expect(find.text('Quét ảnh & video'), findsOneWidget);
    expect(find.text('Ảnh trùng'), findsOneWidget);
    expect(find.text('Ảnh nghi trùng'), findsOneWidget);
    // ListView chỉ build phần đang hiển thị: cuộn tới ô cuối rồi mới kiểm tra.
    await tester.scrollUntilVisible(find.text('Quản lý ứng dụng'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Quản lý ứng dụng'), findsOneWidget);
  });

  testWidgets('Thẻ chưa hỗ trợ báo "sắp có"', (tester) async {
    final c = ScanController();
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(home: HomePage(controller: c)));
    final tile = find.text('Quản lý ứng dụng');
    await tester.scrollUntilVisible(tile, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pump();
    expect(find.text('Tính năng này sắp có.'), findsOneWidget);
  });
}
