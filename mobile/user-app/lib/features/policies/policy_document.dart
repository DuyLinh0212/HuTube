import 'dart:io';
import 'package:flutter/services.dart';

String policyDocumentText(
  List<Map<String, dynamic>> policies, {
  required String fallback,
}) {
  if (policies.isEmpty) return fallback;
  return policies
      .map(
        (policy) => [
          '${policy['name'] ?? policy['title'] ?? ''}',
          if (policy['version'] != null)
            '${policy['code'] ?? ''} · ${policy['version']}',
          if (policy['effectiveAt'] != null) '${policy['effectiveAt']}',
          '${policy['description'] ?? policy['content'] ?? ''}',
        ].join('\n'),
      )
      .join('\n\n');
}

Future<String> exportPolicyDocument(
  String title,
  String body, {
  bool print = false,
}) async {
  if (!Platform.isAndroid) throw UnsupportedError('Android policy export');
  final path = await const MethodChannel('hutube/media_tools')
      .invokeMethod<String>(print ? 'printPolicy' : 'exportPolicy', {
        'title': title,
        'body': body,
      });
  if (path == null) throw const FormatException('PDF was not generated');
  return path;
}
