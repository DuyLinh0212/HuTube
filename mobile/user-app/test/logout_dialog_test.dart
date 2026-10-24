import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/core/localization/app_strings.dart';
import 'package:user_app/core/theme/app_theme.dart';
import 'package:user_app/core/widgets/logout_confirmation_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final directory = Platform.environment['MOBILE_AUDIT_FONT_DIR'];
    if (directory == null) return;
    for (final family in ['Plus Jakarta Sans', 'Roboto', 'MaterialIcons']) {
      final loader = FontLoader(family);
      final file = family == 'MaterialIcons'
          ? 'materialicons-regular.otf'
          : 'roboto-regular.ttf';
      loader.addFont(
        File('$directory/$file').readAsBytes().then(ByteData.sublistView),
      );
      await loader.load();
    }
  });
  for (final dark in [false, true]) {
    for (final width in [320.0, 375.0, 640.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'logout fits and returns user choice dark=$dark width=$width scale=$scale',
          (tester) async {
            AppStrings.currentLang.value = 'vi';
            tester.view.physicalSize = Size(width, width == 640 ? 360 : 812);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            bool? result;
            final key = GlobalKey();
            await tester.pumpWidget(
              RepaintBoundary(
                key: key,
                child: MaterialApp(
                  theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: Scaffold(
                    body: Builder(
                      builder: (context) => Center(
                        child: TextButton(
                          onPressed: () async {
                            result = await showLogoutConfirmation(context);
                          },
                          child: const Text('Open'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('Open'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final cancel = find.widgetWithText(
              OutlinedButton,
              AppStrings.t('common.cancel'),
            );
            final confirm = find.widgetWithText(
              FilledButton,
              AppStrings.t('auth.logout'),
            );
            if (scale == 1 && width == 375) {
              expect(tester.getCenter(cancel).dy, tester.getCenter(confirm).dy);
              expect(tester.getSize(confirm).height, greaterThanOrEqualTo(48));
              if (Platform.environment['CAPTURE_MOBILE_AUDIT'] == 'true') {
                await tester.runAsync(() async {
                  final boundary =
                      key.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary;
                  final image = await boundary.toImage();
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  final dir = Directory('../../.work/mobile-audit');
                  await dir.create(recursive: true);
                  await File(
                    '${dir.path}/logout-${dark ? "dark" : "light"}.png',
                  ).writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }
            }
            await tester.ensureVisible(cancel);
            await tester.tap(cancel);
            await tester.pumpAndSettle();
            expect(result, isFalse);
            await tester.tap(find.text('Open'));
            await tester.pumpAndSettle();
            await tester.ensureVisible(confirm);
            await tester.tap(confirm);
            await tester.pumpAndSettle();
            expect(result, isTrue);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
