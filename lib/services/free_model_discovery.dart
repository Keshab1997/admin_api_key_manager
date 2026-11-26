import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:admin_api_key_manager/models/free_model.dart';

/// Fetches the public model catalog from OpenRouter and filters for free models.
///
/// No API key is needed for `GET /api/v1/models`. The same shape is documented at
/// https://openrouter.ai/docs/api-reference/list-available-models
class FreeModelDiscovery {
  FreeModelDiscovery({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _openRouterModelsUrl = 'https://openrouter.ai/api/v1/models';

  /// Returns all models, with `isFree` set per entry.
  ///
  /// 30 s, not 15: OpenRouter's catalog is ~900 kB of JSON, and on a weak
  /// mobile connection a 15 s ceiling expired mid-download — the screen then
  /// showed its error state for a fetch that would have finished. A timeout is
  /// for a hung server, not for a big body.
  Future<List<FreeModel>> fetchAll(
      {Duration timeout = const Duration(seconds: 30)}) async {
    final res = await _client.get(Uri.parse(_openRouterModelsUrl),
        headers: {'Accept': 'application/json'}).timeout(timeout);
    if (res.statusCode != 200) {
      throw FreeModelFetchException(
          'OpenRouter returned HTTP ${res.statusCode}', res.statusCode);
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = body['data'] as List<dynamic>? ?? [];
    return data
        .map((e) => FreeModel.fromOpenRouter(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) {
        // Free first, then by provider+id
        if (a.isFree != b.isFree) return a.isFree ? -1 : 1;
        final p = a.provider.compareTo(b.provider);
        if (p != 0) return p;
        return a.id.compareTo(b.id);
      });
  }

  /// Returns only the free models (pricing 0,0 or :free suffix).
  Future<List<FreeModel>> fetchFree(
      {Duration timeout = const Duration(seconds: 30)}) async {
    final all = await fetchAll(timeout: timeout);
    return all.where((m) => m.isFree).toList();
  }

  /// Known key-provisioning URLs per provider (for the "Get API key" button).
  static const Map<String, String> providerKeyUrls = {
    'openai': 'https://platform.openai.com/api-keys',
    'anthropic': 'https://console.anthropic.com/settings/keys',
    'google': 'https://aistudio.google.com/app/apikey',
    'openrouter': 'https://openrouter.ai/keys',
    'groq': 'https://console.groq.com/keys',
    'together': 'https://api.together.xyz/settings/api-keys',
    'huggingface': 'https://huggingface.co/settings/tokens',
  };

  void close() => _client.close();
}

class FreeModelFetchException implements Exception {
  FreeModelFetchException(this.message, this.statusCode);
  final String message;
  final int statusCode;

  @override
  String toString() => 'FreeModelFetchException($statusCode): $message';
}

/// Simple in-memory filter — keeps the widget stateless and testable.
List<FreeModel> filterModels(
  List<FreeModel> models, {
  String query = '',
  String provider = 'all',
  bool freeOnly = false,
}) {
  final q = query.trim().toLowerCase();
  return models.where((m) {
    if (freeOnly && !m.isFree) return false;
    if (provider != 'all' && m.provider != provider) return false;
    if (q.isEmpty) return true;
    return m.id.toLowerCase().contains(q) ||
        m.name.toLowerCase().contains(q) ||
        m.provider.toLowerCase().contains(q) ||
        (m.description?.toLowerCase().contains(q) ?? false);
  }).toList();
}
