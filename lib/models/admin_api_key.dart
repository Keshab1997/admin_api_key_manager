import 'package:cloud_firestore/cloud_firestore.dart';

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
