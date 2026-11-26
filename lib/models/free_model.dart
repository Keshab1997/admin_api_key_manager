/// A model entry discovered from a provider's public catalog (e.g. OpenRouter).
/// Used only for discovery — never written to Firestore as a key.
class FreeModel {
  const FreeModel({
    required this.id,
    required this.name,
    required this.provider,
    this.contextLength,
    this.description,
    required this.isFree,
    this.pricingPrompt,
    this.pricingCompletion,
  });

  /// Full model id as the provider addresses it, e.g. `openai/gpt-4o-mini:free`
  /// or `meta-llama/llama-3.1-8b-instruct:free`.
  final String id;

  /// Human readable name, e.g. `GPT-4o Mini`.
  final String name;

  /// Provider slug derived from the id prefix, e.g. `openai`, `google`, `meta-llama`.
  final String provider;

  final int? contextLength;
  final String? description;
  final bool isFree;
  final String? pricingPrompt;
  final String? pricingCompletion;

  /// URL where a user can create an API key for this provider.
  String get apiKeyUrl {
    switch (provider) {
      case 'openai':
        return 'https://platform.openai.com/api-keys';
      case 'anthropic':
        return 'https://console.anthropic.com/settings/keys';
      case 'google':
        return 'https://aistudio.google.com/app/apikey';
      case 'meta-llama':
      case 'meta':
        return 'https://openrouter.ai/keys';
      case 'qwen':
      case 'mistralai':
      case 'deepseek':
      case 'cohere':
      case 'x-ai':
      case 'microsoft':
      case 'ibm-granite':
        return 'https://openrouter.ai/keys';
      default:
        return 'https://openrouter.ai/keys';
    }
  }

  /// Short provider display name.
  String get providerDisplay {
    switch (provider) {
      case 'openai':
        return 'OpenAI';
      case 'anthropic':
        return 'Anthropic';
      case 'google':
        return 'Google';
      case 'meta-llama':
        return 'Meta';
      case 'qwen':
        return 'Qwen';
      case 'mistralai':
        return 'Mistral';
      case 'deepseek':
        return 'DeepSeek';
      case 'cohere':
        return 'Cohere';
      case 'x-ai':
        return 'xAI';
      default:
        return provider;
    }
  }

  factory FreeModel.fromOpenRouter(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final pricing = json['pricing'] as Map<String, dynamic>?;
    final prompt = pricing?['prompt']?.toString() ?? '';
    final completion = pricing?['completion']?.toString() ?? '';
    final isFree = prompt == '0' && completion == '0';
    // Fallback: some free models are marked :free suffix
    final freeBySuffix = id.endsWith(':free');
    return FreeModel(
      id: id,
      name: json['name'] as String? ?? id,
      provider: id.contains('/') ? id.split('/').first : 'unknown',
      contextLength: json['context_length'] as int?,
      description: json['description'] as String?,
      isFree: isFree || freeBySuffix,
      pricingPrompt: prompt,
      pricingCompletion: completion,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'provider': provider,
        'contextLength': contextLength,
        'description': description,
        'isFree': isFree,
      };
}
