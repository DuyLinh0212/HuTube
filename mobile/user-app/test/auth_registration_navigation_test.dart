import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/core/localization/app_strings.dart';
import 'package:user_app/main.dart';
import 'auth_test.dart' show MemoryStore, jsonResponse, session;
import 'auth_widget_helpers.dart';

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    AppStrings.currentLang.value = 'vi';
  });
  for (final exit in ['button', 'system-back']) {
    testWidgets('sign-in returns home by $exit without closing app', (
      tester,
    ) async {
      final client = MockClient((_) async => jsonResponse({'items': []}));
      final auth = AuthController(ApiClient(client: client), MemoryStore());
      await tester.pumpWidget(HuTubeApp(auth: auth));
      await tester.pumpAndSettle();
      await openSignInFromHome(tester);
      expect(
        find.widgetWithText(TextButton, AppStrings.t('auth.backHome')),
        findsNothing,
      );
      if (exit == 'button') {
        await tapVisible(
          tester,
          find.byTooltip(AppStrings.t('auth.backHome')),
        );
      } else {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey('Email')), findsNothing);
      expect(find.byTooltip(AppStrings.t('common.signIn')), findsOneWidget);
      expect(auth.authenticated, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      client.close();
    });
  }
  testWidgets(
    'registration explains duplicate username then verifies email and signs in',
    (tester) async {
      var verified = false, registerCalls = 0;
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/auth/register')) {
          registerCalls++;
          final data = jsonDecode(request.body) as Map;
          if (data['username'] == 'taken') {
            return jsonResponse({'code': 'USERNAME_ALREADY_EXISTS'}, 409);
          }
          expect(data['username'], 'available_name');
          return jsonResponse({'message': 'Created'}, 201);
        }
        if (path.endsWith('/auth/verify-email')) {
          expect(
            (jsonDecode(request.body) as Map)['token'],
            'test-verification-token',
          );
          verified = true;
          return jsonResponse({'message': 'Verified'});
        }
        if (path.endsWith('/auth/login')) {
          expect(verified, isTrue);
          final result = session();
          (result['user'] as Map)['email'] = 'new@example.test';
          return jsonResponse(result);
        }
        return jsonResponse({'items': []});
      });
      final auth = AuthController(ApiClient(client: client), MemoryStore());
      await tester.pumpWidget(HuTubeApp(auth: auth));
      await tester.pumpAndSettle();
      await openSignInFromHome(tester);
      await tapVisible(tester, find.text('Chưa có tài khoản? Đăng ký'));
      for (final pair in [
        ('Tên hiển thị', 'New User'),
        ('Tên người dùng', 'taken'),
        ('Email', 'new@example.test'),
        ('Mật khẩu', 'ValidPassword123!'),
        ('Nhập lại mật khẩu', 'ValidPassword123!'),
      ]) {
        final field = find.byKey(ValueKey(pair.$1));
        await tester.ensureVisible(field);
        await tester.enterText(field, pair.$2);
      }
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, AppStrings.t('auth.createAccount')),
      );
      expect(find.text(AppStrings.t('auth.usernameTaken')), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('Email')))
            .controller!
            .text,
        'new@example.test',
      );
      await tester.enterText(
        find.byKey(const ValueKey('Tên người dùng')),
        'available_name',
      );
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, AppStrings.t('auth.createAccount')),
      );
      expect(find.text(AppStrings.t('auth.checkEmailTitle')), findsOneWidget);
      expect(registerCalls, 2);
      final link = find.byKey(const ValueKey('verification-link'));
      await tester.ensureVisible(link);
      await tester.enterText(
        link,
        'http://localhost:4200/verify-email?token=test-verification-token',
      );
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, AppStrings.t('auth.verifyTitle')),
      );
      expect(find.text(AppStrings.t('auth.verifySuccess')), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('Email')))
            .controller!
            .text,
        'new@example.test',
      );
      await tester.enterText(
        find.byKey(const ValueKey('Mật khẩu')),
        'ValidPassword123!',
      );
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, AppStrings.t('auth.loginTitle')),
      );
      expect(auth.authenticated, isTrue);
      expect(verified, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      client.close();
    },
  );
  test(
    'verification input accepts only trusted origins and exactly one token',
    () {
      expect(
        AuthLink.parseVerificationInput(
          'http://localhost:4200/verify-email?token=test',
        )?.token,
        'test',
      );
      expect(
        AuthLink.parseVerificationInput(
          'hutube://auth/verify-email?token=test',
        )?.token,
        'test',
      );
      for (final input in [
        'https://attacker.test/verify-email?token=test',
        'http://localhost:4200/verify-email',
        'http://localhost:4200/verify-email?token=a&token=b',
        'http://evil@localhost:4200/verify-email?token=a',
        'http://localhost:4200/reset-password?token=a',
      ]) {
        expect(AuthLink.parseVerificationInput(input), isNull, reason: input);
      }
    },
  );
  for (final entry in {
    'EMAIL_ALREADY_EXISTS': 'auth.emailTaken',
    'USERNAME_ALREADY_EXISTS': 'auth.usernameTaken',
    'EMAIL_DELIVERY_UNAVAILABLE': 'auth.emailDeliveryUnavailable',
    'INVALID_OR_EXPIRED_TOKEN': 'auth.invalidVerificationLink',
  }.entries) {
    test('actionable auth error ${entry.key}', () {
      expect(
        ApiFailure.fromResponse(409, {'code': entry.key}).message,
        AppStrings.t(entry.value),
      );
    });
  }
}
