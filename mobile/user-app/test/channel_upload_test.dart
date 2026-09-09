import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/features/channel/models/channel_models.dart';
import 'package:user_app/features/channel/screens/channel_settings_screen.dart';
import 'package:user_app/features/channel/services/channel_service.dart';

import 'auth_test.dart' show MemoryStore, jsonResponse, session;

Map<String, dynamic> channelJson({String? avatarUrl, String? bannerUrl}) => {
  'channelId': 'channel-1',
  'ownerUserId': 'user-1',
  'name': 'HuTube Test',
  'handle': 'hutube-test',
  'description': 'Kênh kiểm thử',
  'avatarUrl': avatarUrl,
  'bannerUrl': bannerUrl,
  'settings': '{}',
  'status': 'active',
  'subscriberCount': 0,
  'videoCount': 0,
  'isOwner': true,
  'myRole': 'owner',
  'permissions': ['channel.edit_branding', 'channel.delete'],
  'createdAt': '2026-09-09T00:00:00Z',
};

Future<AuthController> authenticatedController(
  Future<http.Response> Function(http.Request request) handler,
) async {
  final auth = AuthController(
    ApiClient(client: MockClient(handler)),
    MemoryStore(),
  );
  await auth.login('owner@example.test', 'GoodPassword1');
  return auth;
}

void main() {
  test('channel avatar upload sends authenticated multipart image', () async {
    var uploadCalls = 0;
    final auth = await authenticatedController((request) async {
      if (request.url.path.endsWith('/auth/login')) {
        return jsonResponse(session());
      }
      uploadCalls++;
      expect(request.url.path, '/api/v1/channels/channel-1/avatar');
      expect(request.headers['authorization'], 'Bearer access-1');
      expect(
        request.headers['content-type'],
        startsWith('multipart/form-data'),
      );
      expect(
        utf8.decode(request.bodyBytes, allowMalformed: true),
        contains('name="file"'),
      );
      return jsonResponse(
        channelJson(avatarUrl: 'https://res.cloudinary.com/demo/avatar.png'),
      );
    });
    final file = XFile.fromData(
      Uint8List.fromList(const [137, 80, 78, 71]),
      name: 'avatar.png',
      mimeType: 'image/png',
    );

    final channel = await ChannelService(auth).uploadAvatar('channel-1', file);

    expect(uploadCalls, 1);
    expect(channel.avatarUrl, contains('cloudinary.com'));
  });

  test('channel banner rejects GIF before making a network request', () async {
    var uploadCalls = 0;
    final auth = await authenticatedController((request) async {
      if (request.url.path.endsWith('/auth/login')) {
        return jsonResponse(session());
      }
      uploadCalls++;
      return jsonResponse(channelJson());
    });
    final file = XFile.fromData(
      Uint8List.fromList(const [71, 73, 70]),
      name: 'banner.gif',
      mimeType: 'image/gif',
    );

    await expectLater(
      ChannelService(auth).uploadBanner('channel-1', file),
      throwsA(
        isA<ApiFailure>().having(
          (failure) => failure.code,
          'code',
          'INVALID_FILE_TYPE',
        ),
      ),
    );
    expect(uploadCalls, 0);
  });

  testWidgets('owner can choose and upload both channel images', (
    tester,
  ) async {
    final uploadedPaths = <String>[];
    final auth = await authenticatedController((request) async {
      if (request.url.path.endsWith('/auth/login')) {
        return jsonResponse(session());
      }
      if (request.url.path.endsWith('/channels/roles')) {
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      uploadedPaths.add(request.url.path);
      return jsonResponse(channelJson());
    });
    final channel = ChannelDetail.fromJson(channelJson());
    var picks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ChannelSettingsScreen(
          auth: auth,
          channel: channel,
          imagePicker: (avatar) async {
            picks++;
            return XFile.fromData(
              Uint8List.fromList(const [137, 80, 78, 71]),
              name: avatar ? 'avatar.png' : 'banner.png',
              mimeType: 'image/png',
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final avatarButton = find.byKey(const ValueKey('upload-channel-avatar'));
    await tester.ensureVisible(avatarButton);
    await tester.tap(avatarButton);
    await tester.pumpAndSettle();
    expect(find.text('Đã cập nhật ảnh đại diện kênh.'), findsOneWidget);

    final bannerButton = find.byKey(const ValueKey('upload-channel-banner'));
    await tester.ensureVisible(bannerButton);
    await tester.tap(bannerButton);
    await tester.pumpAndSettle();
    expect(picks, 2);
    expect(uploadedPaths, [
      '/api/v1/channels/channel-1/avatar',
      '/api/v1/channels/channel-1/banner',
    ]);
  });
}
