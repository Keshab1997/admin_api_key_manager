import 'dart:convert';
import 'package:http/http.dart' as http;

/// OpenRouter serves models as `provider/model` ids (e.g. `openai/gpt-4o-mini`).
/// ChatAnywhere-style entries store bare names (e.g. `gpt-4o-mini`), which
/// OpenRouter rejects. Map a bare name to the right provider prefix when the
/// request targets OpenRouter; leave every other backend untouched.
String resolveOpenRouterModel(String baseUrl, String model) {
  if (!baseUrl.contains('openrouter')) return model;
  if (model.contains('/')) return model; // already provider-prefixed
  const providerByPrefix = <String, String>{
    'claude': 'anthropic/',
    'gemini': 'google/',
    'gemma': 'google/',
    'llama': 'meta-llama/',
    'mistral': 'mistralai/',
    'qwen': 'qwen/',
    'deepseek': 'deepseek/',
    'command': 'cohere/',
    'phi': 'microsoft/',
    'granite': 'ibm-granite/',
    'grok': 'x-ai/',
    'gpt-': 'openai/',
    'o1': 'openai/',
    'o3': 'openai/',
    'o4': 'openai/',
  };
  final lower = model.toLowerCase();
  for (final entry in providerByPrefix.entries) {
    if (lower.startsWith(entry.key)) return '${entry.value}$model';
  }
  return model;
}

/// Lightweight provider ping (a 5-token "Hi") that returns the raw HTTP status
/// code so callers can tell an auth error (401/403) from a transient
/// rate-limit (429), server (5xx) or network (0) problem. Used by the periodic
/// key health check and the admin "Test Connection" flow.
Future<int> pingKeyStatus({
  required String provider,
  required String baseUrl,
  required String apiKey,
  required String model,
}) async {
  try {
    if (provider == 'google') {
      final url =
          Uri.parse('$baseUrl/models/$model:generateContent?key=$apiKey');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': 'Hi'}
                  ]
                }
              ],
              'generationConfig': {'maxOutputTokens': 5},
            }),
          )
          .timeout(const Duration(seconds: 15));
      return response.statusCode;
    }
    final url = Uri.parse('$baseUrl/chat/completions');
    final response = await http
        .post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': resolveOpenRouterModel(baseUrl, model),
            'messages': [
              {'role': 'user', 'content': 'Hi'}
            ],
            'max_tokens': 5,
          }),
        )
        .timeout(const Duration(seconds: 15));
    return response.statusCode;
  } catch (_) {
    // Network / timeout / bad URL → 0, treated as "unknown, don't act".
    return 0;
  }
}
