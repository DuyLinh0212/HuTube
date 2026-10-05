import 'dart:convert';
import 'dart:math';

import 'package:image_picker/image_picker.dart';

import '../../auth.dart';
import '../../core/localization/app_strings.dart';
import '../content/content_models.dart';

class UploadPreflight {
  const UploadPreflight({
    required this.allowed,
    required this.maxUploadSize,
    required this.maxDuration,
    required this.storageLimit,
    required this.storageUsed,
  });

  final bool allowed;
  final int maxUploadSize;
  final int maxDuration;
  final int storageLimit;
  final int storageUsed;

  factory UploadPreflight.fromJson(Map<String, dynamic> json) =>
      UploadPreflight(
        allowed: json['allowed'] == true,
        maxUploadSize: asInt(json['maxUploadSize']),
        maxDuration: asInt(json['maxDuration']),
        storageLimit: asInt(json['storageLimit']),
        storageUsed: asInt(json['storageUsed']),
      );
}

class CreatorService {
  CreatorService(this.auth);
  final AuthController auth;

  String _path(String path, Map<String, Object?> query) {
    final pairs = query.entries
        .where((entry) => entry.value != null && '${entry.value}'.isNotEmpty)
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent('${entry.value}')}',
        )
        .join('&');
    return pairs.isEmpty ? path : '$path?$pairs';
  }

  Future<UploadPreflight> preflight({
    required String channelId,
    required int fileSize,
    required int duration,
    required String contentType,
    required String quality,
  }) async {
    final json = await auth.protected(
      'POST',
      '/videos/upload-preflight',
      body: {
        'channelId': channelId,
        'fileSize': fileSize,
        'duration': duration,
        'contentType': contentType,
        'sourceQuality': quality,
      },
    );
    return UploadPreflight.fromJson(json);
  }

  Future<VideoDetail> upload({
    required String channelId,
    required String title,
    required String description,
    required String? categoryId,
    required String visibility,
    required bool ageRestricted,
    required int duration,
    required String quality,
    required List<String> tags,
    List<Map<String, dynamic>> chapters = const [],
    List<Map<String, dynamic>> videoCards = const [],
    bool promotionEnabled = false,
    required MultipartFilePayload video,
    MultipartFilePayload? thumbnail,
  }) async {
    final idempotencyKey =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    final fields = <String, String>{
      'ChannelId': channelId,
      'Title': title.trim(),
      'Description': description.trim(),
      if (categoryId != null && categoryId.isNotEmpty) 'CategoryId': categoryId,
      'LanguageCode': 'vi',
      'Visibility': visibility,
      'AgeRestricted': '$ageRestricted',
      'Duration': '$duration',
      'SourceQuality': quality,
      'PromotionEnabled': '$promotionEnabled',
      if (videoCards.isNotEmpty) 'VideoCardsJson': jsonEncode(videoCards),
    };
    for (var index = 0; index < tags.length; index++) {
      fields['Tags[$index]'] = tags[index];
    }
    for (var index = 0; index < chapters.length; index++) {
      fields['Chapters[$index].StartSeconds'] =
          '${chapters[index]['startSeconds']}';
      fields['Chapters[$index].Title'] = '${chapters[index]['title']}';
    }
    final json = await auth.protectedMultipart(
      '/videos',
      fields: fields,
      files: [video, ?thumbnail],
      headers: {'Idempotency-Key': idempotencyKey},
    );
    return VideoDetail.fromJson(json);
  }

  Future<PageResult<VideoDetail>> managedVideos(
    String channelId, {
    int page = 1,
    String? status,
    String? visibility,
    String? search,
  }) async {
    final json = await auth.protected(
      'GET',
      _path('/videos/manage', {
        'channelId': channelId,
        'status': status,
        'visibility': visibility,
        'search': search,
        'page': page,
        'pageSize': 50,
      }),
    );
    return PageResult(
      items: (json['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => VideoDetail.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      page: asInt(json['page']) == 0 ? 1 : asInt(json['page']),
      pageSize: asInt(json['pageSize']) == 0 ? 50 : asInt(json['pageSize']),
      total: asInt(json['total']),
    );
  }

  Future<VideoDetail> updateVideo(
    String videoId, {
    String? visibility,
    String? title,
    String? description,
    String? categoryId,
    bool clearCategory = false,
    List<String>? tags,
    List<Map<String, dynamic>>? chapters,
    List<Map<String, dynamic>>? videoCards,
    bool? promotionEnabled,
  }) async {
    final json = await auth.protected(
      'PATCH',
      '/videos/${Uri.encodeComponent(videoId)}',
      body: {
        'title': title,
        'description': description,
        'categoryId': categoryId,
        'clearCategory': clearCategory,
        'languageCode': null,
        'visibility': visibility,
        'ageRestricted': null,
        'thumbnailUrl': null,
        'tags': tags,
        'chapters': chapters,
        'videoCards': videoCards,
        'promotionEnabled': promotionEnabled,
      },
    );
    return VideoDetail.fromJson(json);
  }

  Future<void> deleteVideo(String videoId) async {
    await auth.protected('DELETE', '/videos/${Uri.encodeComponent(videoId)}');
  }

  Future<VideoDetail> submitModeration(String videoId) async {
    final json = await auth.protected(
      'POST',
      '/videos/${Uri.encodeComponent(videoId)}/submit-moderation',
    );
    return VideoDetail.fromJson(json);
  }

  Future<VideoDetail> publish(String videoId) async {
    final json = await auth.protected(
      'POST',
      '/videos/${Uri.encodeComponent(videoId)}/publish',
    );
    return VideoDetail.fromJson(json);
  }

  Future<void> cancelUpload(String videoId) async {
    await auth.protected(
      'POST',
      '/videos/${Uri.encodeComponent(videoId)}/cancel-upload',
    );
  }

  Future<VideoDetail> retryProcessing(String videoId) async =>
      VideoDetail.fromJson(
        await auth.protected(
          'POST',
          '/videos/${Uri.encodeComponent(videoId)}/retry-processing',
        ),
      );

  Future<VideoDetail> updateThumbnail(
    String videoId, {
    XFile? image,
    bool generate = false,
  }) async {
    final mime = image?.mimeType ?? (image == null ? null : _mime(image.name));
    if (image != null &&
        !(const {'image/jpeg', 'image/png', 'image/webp'}.contains(mime))) {
      throw ApiFailure(
        400,
        'INVALID_FILE_TYPE',
        AppStrings.t('creator.thumbnailTypes'),
      );
    }
    if (image != null && (await image.length()) > 5 * 1024 * 1024) {
      throw ApiFailure(
        400,
        'FILE_TOO_LARGE',
        AppStrings.format('creator.thumbnailSize', {'size': 5}),
      );
    }
    final response = await auth.protectedMultipart(
      '/videos/${Uri.encodeComponent(videoId)}/thumbnail',
      fields: {'Generate': '$generate'},
      files: [
        if (image != null)
          MultipartFilePayload(
            field: 'Thumbnail',
            path: image.path,
            fileName: image.name,
            contentType: mime!,
          ),
      ],
    );
    return VideoDetail.fromJson(response);
  }

  String _mime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'application/octet-stream';
  }

  Future<PageResult<CommentItem>> managedComments(
    String channelId, {
    int page = 1,
    String? status,
    String sort = 'newest',
  }) async {
    final json = await auth.protected(
      'GET',
      _path('/channels/${Uri.encodeComponent(channelId)}/comments/manage', {
        'status': status,
        'sort': sort,
        'page': page,
        'pageSize': 50,
      }),
    );
    return PageResult(
      items: (json['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => CommentItem.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      page: asInt(json['page']) == 0 ? 1 : asInt(json['page']),
      pageSize: asInt(json['pageSize']) == 0 ? 50 : asInt(json['pageSize']),
      total: asInt(json['total']),
    );
  }

  Future<void> setCommentHidden(String id, bool hidden) async {
    await auth.protected(
      'PATCH',
      '/comments/${Uri.encodeComponent(id)}/visibility',
      body: {'hidden': hidden, 'reason': null},
    );
  }

  Future<void> deleteComment(String id) async {
    await auth.protected('DELETE', '/comments/${Uri.encodeComponent(id)}');
  }
}
