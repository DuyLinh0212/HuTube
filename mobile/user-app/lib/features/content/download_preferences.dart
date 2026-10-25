import '../../core/storage/app_preferences.dart';
import 'content_models.dart';

class DownloadPreferences {
  const DownloadPreferences({
    this.wifiOnly = true,
    this.recommendations = true,
    this.quality = 'ask',
  });
  final bool wifiOnly, recommendations;
  final String quality;

  static Future<DownloadPreferences> load(AppPreferencesStore store) async {
    final values = await Future.wait<Object>([
      store.readDownloadWifiOnly(),
      store.readDownloadRecommendations(),
      store.readDownloadQuality(),
    ]);
    return DownloadPreferences(
      wifiOnly: values[0] as bool,
      recommendations: values[1] as bool,
      quality: values[2] as String,
    );
  }
}

/// A configured quality is a ceiling, never a request to upscale or download
/// a larger file. Ask each time leaves the quality selection to the user.
Rendition? selectDownloadRendition(List<Rendition> options, String preference) {
  if (options.isEmpty || preference == 'ask') return null;
  int height(Rendition r) => r.height > 0
      ? r.height
      : int.tryParse(r.quality.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  final cap = int.tryParse(preference.replaceAll('p', '')) ?? 480;
  final sorted = [...options]..sort((a, b) => height(a).compareTo(height(b)));
  final fitting = sorted.where((r) => height(r) <= cap).toList();
  return fitting.isNotEmpty ? fitting.last : null;
}
