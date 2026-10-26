import 'dart:io';
import 'policy_catalog.dart';
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
          '${policy['content'] ?? policy['description'] ?? ''}',
          if ((policy['rules'] as List? ?? []).isNotEmpty)
            policyLabel('policies.mandatoryRules'),
          for (final rule in policy['rules'] as List? ?? []) '• $rule',
          if ((policy['exceptions'] as List? ?? []).isNotEmpty)
            policyLabel('policies.exceptionsEdsa'),
          for (final exception in policy['exceptions'] as List? ?? [])
            '• $exception',
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
