import 'dart:math';

String normalizeChannelHandle(String value) =>
    value.trim().replaceFirst(RegExp(r'^@+'), '').trim().toLowerCase();

bool isValidChannelHandle(String value) =>
    RegExp(r'^[a-z0-9_.-]{3,50}$').hasMatch(normalizeChannelHandle(value));

String newHandleSuffix() =>
    Random.secure().nextInt(0x100000000).toRadixString(16).padLeft(8, '0');

String suggestChannelHandle(String name, String suffix) {
  var base = name.toLowerCase();
  const accents = {
    'a': 'àáạảãâầấậẩẫăằắặẳẵ',
    'e': 'èéẹẻẽêềếệểễ',
    'i': 'ìíịỉĩ',
    'o': 'òóọỏõôồốộổỗơờớợởỡ',
    'u': 'ùúụủũưừứựửữ',
    'y': 'ỳýỵỷỹ',
    'd': 'đ',
  };
  for (final entry in accents.entries) {
    base = base.replaceAll(RegExp('[${entry.value}]'), entry.key);
  }
  base = base
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (base.isEmpty) base = 'dalitu';
  if (base.length > 41) {
    base = base.substring(0, 41).replaceAll(RegExp(r'-+$'), '');
  }
  return '$base-$suffix';
}
