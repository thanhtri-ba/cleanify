import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:cleanify/features/onboarding/onboarding_flow.dart';
import 'package:cleanify/theme/app_icons.dart';
import 'package:cleanify/theme/app_icon.dart';

/// Màn hình cỡ iPhone (390x844 logic) để mọi nút nằm trong khung nhìn.
void _phone(WidgetTester t) {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
}

/// Hình minh họa chạy hoạt ảnh lặp vô hạn nên không dùng pumpAndSettle.
Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _tap(WidgetTester t, String text) async {
  await t.tap(find.text(text));
  await _settle(t);
}

Future<void> _toPermission(WidgetTester t) async {
  await _tap(t, 'Bắt đầu');
  await _tap(t, 'Tiếp tục');
  await _tap(t, 'Tiếp tục');
}

Widget _app(OnboardingFlow flow) => MaterialApp(home: flow);

void main() {
  testWidgets('đi hết 3 trang rồi cấp quyền thì kết thúc onboarding',
      (t) async {
    _phone(t);
    var finished = false;
    await t.pumpWidget(_app(OnboardingFlow(
      onFinished: () => finished = true,
      requestPermission: () async => PermissionState.authorized,
    )));
    expect(find.textContaining('Dọn ảnh trùng'), findsOneWidget);
    await _toPermission(t);
    expect(find.text('Cho phép truy cập ảnh'), findsOneWidget);
    await _tap(t, 'Cho phép truy cập ảnh');
    expect(finished, isTrue);
  });

  testWidgets('quyền Limited vẫn được tính là có quyền', (t) async {
    _phone(t);
    var finished = false;
    await t.pumpWidget(_app(OnboardingFlow(
      onFinished: () => finished = true,
      requestPermission: () async => PermissionState.limited,
    )));
    await _toPermission(t);
    await _tap(t, 'Cho phép truy cập ảnh');
    expect(finished, isTrue);
  });

  testWidgets('bị từ chối thì hiện Mở Cài đặt và không kết thúc', (t) async {
    _phone(t);
    var finished = false;
    var opened = false;
    await t.pumpWidget(_app(OnboardingFlow(
      onFinished: () => finished = true,
      requestPermission: () async => PermissionState.denied,
      openSettings: () async => opened = true,
    )));
    await _toPermission(t);
    await _tap(t, 'Cho phép truy cập ảnh');
    expect(finished, isFalse);
    expect(find.text('Mở Cài đặt'), findsOneWidget);
    expect(find.text('Bị từ chối'), findsOneWidget);
    await _tap(t, 'Mở Cài đặt');
    expect(opened, isTrue);
    expect(finished, isFalse);
  });

  testWidgets('Bỏ qua nhảy thẳng tới trang quyền; Để sau thì kết thúc',
      (t) async {
    _phone(t);
    var finished = false;
    await t.pumpWidget(
        _app(OnboardingFlow(onFinished: () => finished = true)));
    await _tap(t, 'Bỏ qua');
    expect(find.text('Cho phép truy cập ảnh'), findsOneWidget);
    await _tap(t, 'Để sau');
    expect(finished, isTrue);
  });

  testWidgets('Quay lại ở trang 2 về trang 1; nút quay lại ở trang quyền về trang 3',
      (t) async {
    _phone(t);
    await t.pumpWidget(_app(OnboardingFlow(onFinished: () {})));
    await _tap(t, 'Bắt đầu');
    expect(find.textContaining('Giữ bản đẹp nhất'), findsOneWidget);
    await _tap(t, 'Quay lại');
    expect(find.textContaining('Dọn ảnh trùng'), findsOneWidget);
    await _toPermission(t);
    await t.tap(find.byWidgetPredicate((w) => w is AppIcon && w.data == AppIcons.chevronLeftRounded));
    await _settle(t);
    expect(find.textContaining('Ảnh của bạn ở lại'), findsOneWidget);
  });

  testWidgets('bật giảm chuyển động vẫn dựng được hình minh họa', (t) async {
    _phone(t);
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await t.pumpWidget(_app(OnboardingFlow(onFinished: () {})));
    await t.pumpAndSettle();
    expect(find.textContaining('Dọn ảnh trùng'), findsOneWidget);
  });
}
