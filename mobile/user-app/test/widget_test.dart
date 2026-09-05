import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/main.dart';
import 'auth_test.dart' show MemoryStore, jsonResponse, session;

void main() {
  testWidgets('empty login validates locally without network', (tester) async {
    var requests = 0;
    final auth = AuthController(
      ApiClient(
        client: MockClient((_) async {
          requests++;
          return jsonResponse({});
        }),
      ),
      MemoryStore(),
    );
    await tester.pumpWidget(HuTubeApp(auth: auth));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập địa chỉ email hợp lệ.'), findsOneWidget);
    expect(find.text('Nhập mật khẩu của bạn.'), findsOneWidget);
    expect(requests, 0);
  });
  testWidgets(
    'account deep link goes through login and loads session endpoint',
    (tester) async {
      final links = StreamController<Uri>();
      final calls = <String>[];
      final auth = AuthController(
        ApiClient(
          client: MockClient((request) async {
            calls.add(request.url.path);
            if (request.url.path.endsWith('/login')) {
              expect((jsonDecode(request.body) as Map)['platform'], 'mobile');
              return jsonResponse(session());
            }
            return jsonResponse({'items': []});
          }),
        ),
        MemoryStore(),
      );
      await tester.pumpWidget(HuTubeApp(auth: auth, links: links.stream));
      await tester.pumpAndSettle();
      links.add(Uri.parse('hutube://auth/account'));
      await tester.pumpAndSettle();
      expect(
        find.text('Đăng nhập để tiếp tục đến tài khoản của bạn.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('Email')),
        'linh@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('Mật khẩu')),
        'GoodPassword1',
      );
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Đăng nhập'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pumpAndSettle();
      expect(find.text('Tài khoản của bạn'), findsOneWidget);
      expect(find.text('linh@example.com'), findsOneWidget);
      expect(calls, contains('/api/v1/auth/sessions'));
      await links.close();
    },
  );
  testWidgets('invalid reset link offers recovery and no token input', (
    tester,
  ) async {
    final links = StreamController<Uri>();
    final auth = AuthController(
      ApiClient(client: MockClient((_) async => jsonResponse({}))),
      MemoryStore(),
    );
    await tester.pumpWidget(HuTubeApp(auth: auth, links: links.stream));
    await tester.pumpAndSettle();
    links.add(Uri.parse('hutube://auth/reset-password'));
    await tester.pumpAndSettle();
    expect(find.text('Yêu cầu liên kết mới'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    await links.close();
  });
  testWidgets('suspended login shows actionable error', (tester) async {
    final auth = AuthController(
      ApiClient(
        client: MockClient(
          (_) async => jsonResponse({'code': 'ACCOUNT_SUSPENDED'}, 403),
        ),
      ),
      MemoryStore(),
    );
    await tester.pumpWidget(HuTubeApp(auth: auth));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('Email')),
      'linh@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('Mật khẩu')),
      'GoodPassword1',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    expect(
      find.text('Tài khoản đang bị tạm khóa. Vui lòng liên hệ hỗ trợ.'),
      findsOneWidget,
    );
    expect(auth.authenticated, isFalse);
  });
  testWidgets('register stays scrollable with keyboard on small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = AuthController(
      ApiClient(client: MockClient((_) async => jsonResponse({}))),
      MemoryStore(),
    );
    await tester.pumpWidget(HuTubeApp(auth: auth));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Chưa có tài khoản? Đăng ký'));
    await tester.tap(find.text('Chưa có tài khoản? Đăng ký'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('Nhập lại mật khẩu')));
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
