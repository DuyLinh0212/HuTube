import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/core/localization/app_strings.dart';
import 'package:user_app/core/storage/app_preferences.dart';
import 'package:user_app/core/theme/app_theme.dart';
import 'package:user_app/features/account/playback_settings_screen.dart';
import 'package:user_app/features/account/background_download_settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final directory = Platform.environment['MOBILE_AUDIT_FONT_DIR'];
    if (directory == null) return;
    for (final family in ['Plus Jakarta Sans', 'Roboto', 'MaterialIcons']) {
      final loader = FontLoader(family);
      final name = family == 'MaterialIcons'
          ? 'materialicons-regular.otf'
          : 'roboto-regular.ttf';
      loader.addFont(
        File('$directory/$name').readAsBytes().then(ByteData.sublistView),
      );
      await loader.load();
    }
  });
  const store = AppPreferencesStore();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    AppStrings.currentLang.value = 'vi';
  });
  for (final value in ['-10', '0', '9999', 'broken', '15']) {
    test('seek setting validates stored value $value', () async {
      FlutterSecureStorage.setMockInitialValues({
        AppPreferencesStore.playbackDoubleTapSeekKey: value,
      });
      expect(await store.readDoubleTapSeek(), value == '15' ? 15 : 10);
    });
  }
  test('unsupported background mode falls back to disabled', () async {
    FlutterSecureStorage.setMockInitialValues({
      AppPreferencesStore.backgroundPlaybackModeKey: 'broken',
    });
    expect(await store.readBackgroundPlaybackMode(), 'off');
  });
  for (final value in ['Chất lượng cao (1080p)', 'broken', '720p']) {
    test('download quality restores legacy and invalid value $value', () async {
      FlutterSecureStorage.setMockInitialValues({
        AppPreferencesStore.downloadQualityKey: value,
      });
      expect(
        await store.readDownloadQuality(),
        value.startsWith('Chất')
            ? '1080p'
            : value == '720p'
            ? '720p'
            : 'ask',
      );
    });
  }
  for (final background in [false, true]) {
    final screen = background
        ? const BackgroundDownloadSettingsScreen()
        : const PlaybackSettingsScreen();
    final title = AppStrings.t(
      background ? 'bgDownload.wifiOnly' : 'playback.autoplayNext',
    );
    for (final dark in [false, true]) {
      Widget app() => MaterialApp(
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: screen,
        ),
      );
      testWidgets(
        'settings persist toggles and restore, background=$background dark=$dark',
        (tester) async {
          tester.view.physicalSize = const Size(375, 812);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(app());
          await tester.pumpAndSettle();
          if (Platform.environment['CAPTURE_MOBILE_AUDIT'] == 'true') {
            final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
              find.byType(RepaintBoundary),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory = Directory('../../.work/mobile-audit');
              await directory.create(recursive: true);
              await File(
                '${directory.path}/settings-${background ? "downloads" : "playback"}-${dark ? "dark" : "light"}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          final tile = find.widgetWithText(SwitchListTile, title);
          final before = tester.widget<SwitchListTile>(tile).value;
          await tester.ensureVisible(tile);
          await tester.pumpAndSettle();
          final toggle = find.descendant(
            of: tile,
            matching: find.byType(Switch),
          );
          await tester.ensureVisible(toggle);
          await tester.pumpAndSettle();
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(tester.widget<SwitchListTile>(tile).value, !before);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(app());
          await tester.pumpAndSettle();
          expect(tester.widget<SwitchListTile>(tile).value, !before);
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'settings recover from storage read failure, background=$background',
      (tester) async {
        final preferences = FailingPreferences()..failRead = true;
        final failingScreen = background
            ? BackgroundDownloadSettingsScreen(preferences: preferences)
            : PlaybackSettingsScreen(preferences: preferences);
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.lightTheme, home: failingScreen),
        );
        await tester.pumpAndSettle();
        expect(find.text(AppStrings.t('prefs.loadError')), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        preferences.failRead = false;
        await tester.tap(find.text(AppStrings.t('common.retry')));
        await tester.pumpAndSettle();
        expect(find.text(AppStrings.t('prefs.loadError')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'failed settings write retains previous toggle, background=$background',
      (tester) async {
        final preferences = FailingPreferences()..failWrite = true;
        final failingScreen = background
            ? BackgroundDownloadSettingsScreen(preferences: preferences)
            : PlaybackSettingsScreen(preferences: preferences);
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.lightTheme, home: failingScreen),
        );
        await tester.pumpAndSettle();
        final tile = find.widgetWithText(SwitchListTile, title);
        final before = tester.widget<SwitchListTile>(tile).value;
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(tile).value, before);
        expect(find.text(AppStrings.t('prefs.saveError')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class FailingPreferences extends AppPreferencesStore {
  bool failRead = false;
  bool failWrite = false;
  @override
  Future<bool> readAutoplayNext() async {
    if (failRead) throw PlatformException(code: 'LOCKED');
    return super.readAutoplayNext();
  }

  @override
  Future<String> readBackgroundPlaybackMode() async {
    if (failRead) throw PlatformException(code: 'LOCKED');
    return super.readBackgroundPlaybackMode();
  }

  @override
  Future<void> writeAutoplayNext(bool value) async {
    if (failWrite) throw PlatformException(code: 'DISK_FULL');
    await super.writeAutoplayNext(value);
  }

  @override
  Future<void> writeDownloadWifiOnly(bool value) async {
    if (failWrite) throw PlatformException(code: 'DISK_FULL');
    await super.writeDownloadWifiOnly(value);
  }
}
