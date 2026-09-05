import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/main.dart';

import 'auth_test.dart' show MemoryStore, jsonResponse;

void main() {
  testWidgets(
    'register and email verification use API contract without showing token',
    (tester) async {
      final links = StreamController<Uri>();
      final calls = <String>[];
      final auth = AuthController(
        ApiClient(
          client: MockClient((request) async {
            calls.add(request.url.path);
            final body = jsonDecode(request.body) as Map;
            if (request.url.path.endsWith('/register')) {
              expect(body['username'], 'linh_01');
              expect(body['email'], 'linh@example.com');
              expect(body['displayName'], 'Linh');
              expect(body['password'], 'GoodPassword1');
            } else {
              expect(body, {'token': 'secret-verification'});
            }
            return jsonResponse({'message': 'OK'});
          }),
        ),
        MemoryStore(),
      );
      await tester.pumpWidget(HuTubeApp(auth: auth, links: links.stream));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chưa có tài khoản? Đăng ký'));
      await tester.pumpAndSettle();
      for (final entry in {
        'Tên hiển thị': 'Linh',
        'Tên người dùng': 'linh_01',
        'Email': 'linh@example.com',
        'Mật khẩu': 'GoodPassword1',
        'Nhập lại mật khẩu': 'GoodPassword1',
      }.entries) {
        await tester.ensureVisible(find.byKey(ValueKey(entry.key)));
        await tester.enterText(find.byKey(ValueKey(entry.key)), entry.value);
      }
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Tạo tài khoản'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Tạo tài khoản'));
      await tester.pumpAndSettle();
      expect(auth.authenticated, isFalse);
      expect(find.textContaining('Tài khoản đã được tạo'), findsOneWidget);
      links.add(
        Uri.parse('hutube://auth/verify-email?token=secret-verification'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('secret-verification'), findsNothing);
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Xác minh email'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Xác minh email'));
      await tester.pumpAndSettle();
      expect(calls, ['/api/v1/auth/register', '/api/v1/auth/verify-email']);
      expect(find.textContaining('Email đã được xác minh'), findsOneWidget);
      await links.close();
    },
  );

  testWidgets(
    'forgot password and reset submit correct token and clear old credentials',
    (tester) async {
      final links = StreamController<Uri>();
      final calls = <String>[];
      final store = MemoryStore();
      final auth = AuthController(
        ApiClient(
          client: MockClient((request) async {
            calls.add(request.url.path);
            final body = jsonDecode(request.body) as Map;
            if (request.url.path.endsWith('/forgot-password')) {
              expect(body, {'email': 'linh@example.com'});
            } else {
              expect(body, {
                'token': 'secret-reset',
                'password': 'NewPassword123',
              });
            }
            return jsonResponse({'message': 'OK'});
          }),
        ),
        store,
      );
      await tester.pumpWidget(HuTubeApp(auth: auth, links: links.stream));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quên mật khẩu?'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('Email')),
        'linh@example.com',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Gửi email'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nếu email thuộc tài khoản'), findsOneWidget);
      links.add(Uri.parse('hutube://auth/reset-password?token=secret-reset'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('Mật khẩu mới')),
        'NewPassword123',
      );
      await tester.enterText(
        find.byKey(const ValueKey('Nhập lại mật khẩu')),
        'NewPassword123',
      );
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Lưu mật khẩu mới'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu mật khẩu mới'));
      await tester.pumpAndSettle();
      expect(calls, [
        '/api/v1/auth/forgot-password',
        '/api/v1/auth/reset-password',
      ]);
      expect(store.token, isNull);
      expect(find.textContaining('Mật khẩu đã được đổi'), findsOneWidget);
      await links.close();
    },
  );
}
