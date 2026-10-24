import '../../core/storage/app_preferences.dart';
import 'content_models.dart';

class DownloadPreferences {
  const DownloadPreferences({
    this.smart = false,
    this.wifiOnly = true,
    this.recommendations = true,
    this.quality = 'ask',
    this.limitMb = 256,
  });
  final bool smart, wifiOnly, recommendations;
  final String quality;
  final int limitMb;
  int get limitBytes => limitMb * 1024 * 1024;

  static Future<DownloadPreferences> load(AppPreferencesStore store) async {
    final values = await Future.wait<Object>([
      store.readSmartDownload(),
      store.readDownloadWifiOnly(),
      store.readDownloadRecommendations(),
      store.readDownloadQuality(),
      store.readSmartDownloadLimitMb(),
    ]);
    return DownloadPreferences(
      smart: values[0] as bool,
      wifiOnly: values[1] as bool,
      recommendations: values[2] as bool,
      quality: values[3] as String,
      limitMb: values[4] as int,
    );
  }
}

/// A configured quality is a ceiling, never a request to upscale or download
/// a larger file. Smart downloads use 480p when manual downloads ask each time.
Rendition? selectDownloadRendition(
  List<Rendition> options,
  String preference, {
  bool automatic = false,
}) {
  if (options.isEmpty || (preference == 'ask' && !automatic)) return null;
  int height(Rendition r) => r.height > 0
      ? r.height
      : int.tryParse(r.quality.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  final cap = int.tryParse(preference.replaceAll('p', '')) ?? 480;
  final sorted = [...options]..sort((a, b) => height(a).compareTo(height(b)));
  final fitting = sorted.where((r) => height(r) <= cap).toList();
  return fitting.isNotEmpty ? fitting.last : null;
}
