import 'package:cloud_firestore/cloud_firestore.dart';

/// The endpoint and model that go together for a given provider.
class ProviderDefaults {
  final String baseUrl;
  final String model;

  const ProviderDefaults({required this.baseUrl, required this.model});
}

/// A single admin-managed API key (Gemini / OpenRouter / any OpenAI-compatible
/// /chat/completions endpoint). Stored in Firestore `admin_api_keys`.
class AdminApiKey {
  final String id;
  final String name;
  final String key;
  final String baseUrl;
  final String model;

  /// Provider/backend for this key: `google` (Gemini API), `openrouter`, or
  /// `custom` (any OpenAI-compatible /chat/completions endpoint).
  final String provider;

  final bool isActive;
  final int priority;
  final int usageCount;
  final int errorCount;
  final DateTime? lastErrorAt;
  final DateTime? lastUsedAt;
  final String addedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AdminApiKey({
    required this.id,
    required this.name,
    required this.key,
    this.baseUrl = 'https://openrouter.ai/api/v1',
    this.model = 'gpt-4o-mini',
    this.provider = 'custom',
    this.isActive = true,
    this.priority = 1,
    this.usageCount = 0,
    this.errorCount = 0,
    this.lastErrorAt,
    this.lastUsedAt,
    this.addedBy = '',
    required this.createdAt,
    required this.updatedAt,
  });

  /// The endpoint and model a provider is normally used with.
  ///
  /// Lives next to [inferProvider] on purpose: one maps a URL to a provider,
  /// the other a provider to a URL, and keeping them apart is how they drift.
  ///
  /// `custom` is deliberately absent — the whole point of that option is an
  /// endpoint only the admin knows.
  static const Map<String, ProviderDefaults> providerDefaults = {
    'openrouter': ProviderDefaults(
      baseUrl: 'https://openrouter.ai/api/v1',
      // OpenRouter addresses models as `provider/model`. Spelling it out keeps
      // the field identical to what the OpenRouter dashboard shows.
      model: 'openai/gpt-4o-mini',
    ),
    'google': ProviderDefaults(
      // Must include the API version: callers build
      // `$baseUrl/models/$model:generateContent`.
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      model: 'gemini-2.0-flash',
    ),
  };

  /// Defaults for [provider], or null for `custom`.
  static ProviderDefaults? defaultsFor(String provider) =>
      providerDefaults[provider];

  /// True when [baseUrl] is one of the known provider defaults.
  ///
  /// Used to decide whether a URL was filled in automatically or typed by the
  /// admin — an admin's own proxy URL must never be silently replaced.
  static bool isDefaultBaseUrl(String baseUrl) {
    final normalised = _normaliseUrl(baseUrl);
    if (normalised.isEmpty) return true; // nothing to protect
    return providerDefaults.values
        .any((d) => _normaliseUrl(d.baseUrl) == normalised);
  }

  /// True when [model] is one of the known provider defaults.
  static bool isDefaultModel(String model) {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return true;
    return providerDefaults.values.any((d) => d.model == trimmed) ||
        // The pre-1.2 default, still sitting in plenty of forms.
        trimmed == 'gpt-4o-mini';
  }

  static String _normaliseUrl(String url) {
    var value = url.trim().toLowerCase();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// Infers the provider from a base URL for keys stored before the provider
  /// field existed (zero-migration backfill).
  static String inferProvider(String baseUrl) {
    final b = baseUrl.toLowerCase();
    if (b.contains('generativelanguage')) return 'google';
    if (b.contains('openrouter')) return 'openrouter';
    return 'custom';
  }

  static String providerName(String provider) {
    switch (provider) {
      case 'google':
        return 'Google AI Studio';
      case 'openrouter':
        return 'OpenRouter';
      default:
        return 'Custom';
    }
  }

  factory AdminApiKey.fromMap(Map<String, dynamic> map, String docId) {
    final baseUrl = map['baseUrl'] as String? ?? 'https://openrouter.ai/api/v1';
    return AdminApiKey(
      id: docId,
      name: map['name'] as String? ?? '',
      key: map['key'] as String? ?? '',
      baseUrl: baseUrl,
      model: map['model'] as String? ?? 'gpt-4o-mini',
      provider: map['provider'] as String? ?? inferProvider(baseUrl),
      isActive: map['isActive'] as bool? ?? true,
      priority: map['priority'] as int? ?? 1,
      usageCount: map['usageCount'] as int? ?? 0,
      errorCount: map['errorCount'] as int? ?? 0,
      lastErrorAt: (map['lastErrorAt'] as Timestamp?)?.toDate(),
      lastUsedAt: (map['lastUsedAt'] as Timestamp?)?.toDate(),
      addedBy: map['addedBy'] as String? ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'key': key,
      'baseUrl': baseUrl,
      'model': model,
      'provider': provider,
      'isActive': isActive,
      'priority': priority,
      'usageCount': usageCount,
      'errorCount': errorCount,
      'lastErrorAt': lastErrorAt != null ? Timestamp.fromDate(lastErrorAt!) : null,
      'lastUsedAt': lastUsedAt != null ? Timestamp.fromDate(lastUsedAt!) : null,
      'addedBy': addedBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  AdminApiKey copyWith({
    String? id,
    String? name,
    String? key,
    String? baseUrl,
    String? model,
    String? provider,
    bool? isActive,
    int? priority,
    int? usageCount,
    int? errorCount,
    DateTime? lastErrorAt,
    DateTime? lastUsedAt,
    String? addedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AdminApiKey(
      id: id ?? this.id,
      name: name ?? this.name,
      key: key ?? this.key,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      provider: provider ?? this.provider,
      isActive: isActive ?? this.isActive,
      priority: priority ?? this.priority,
      usageCount: usageCount ?? this.usageCount,
      errorCount: errorCount ?? this.errorCount,
      lastErrorAt: lastErrorAt ?? this.lastErrorAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      addedBy: addedBy ?? this.addedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'AdminApiKey(id: $id, name: $name, isActive: $isActive)';
}
