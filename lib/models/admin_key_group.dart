import 'admin_api_key.dart';

/// Per-provider group configuration stored in Firestore `admin_key_groups`
/// (docId = provider). Lets the admin enable/disable a whole provider at once,
/// rank providers so the fast group is tried before slower fallbacks, and
/// override the built-in cooldown durations (null = built-in default).
class AdminKeyGroup {
  /// Provider id this group applies to: `google` | `openrouter` | `custom`.
  final String provider;

  final String name;
  final bool enabled;

  /// Lower = tried first. Keys are ordered by (group priority, key priority).
  final int priority;

  /// Cooldown after a rate-limit (429) failure, in seconds. Null = built-in.
  final int? rateLimitCooldownSeconds;

  /// Cooldown after a provider server error (5xx), in seconds. Null = built-in.
  final int? serverErrorCooldownSeconds;

  /// Cooldown for any other failure, in seconds. Null = built-in.
  final int? defaultCooldownSeconds;

  const AdminKeyGroup({
    required this.provider,
    required this.name,
    this.enabled = true,
    this.priority = 100,
    this.rateLimitCooldownSeconds,
    this.serverErrorCooldownSeconds,
    this.defaultCooldownSeconds,
  });

  factory AdminKeyGroup.fromMap(Map<String, dynamic> map, String provider) {
    return AdminKeyGroup(
      provider: provider,
      name: map['name'] as String? ?? AdminApiKey.providerName(provider),
      enabled: map['enabled'] as bool? ?? true,
      priority: map['priority'] as int? ?? 100,
      rateLimitCooldownSeconds: map['rateLimitCooldownSeconds'] as int?,
      serverErrorCooldownSeconds: map['serverErrorCooldownSeconds'] as int?,
      defaultCooldownSeconds: map['defaultCooldownSeconds'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'enabled': enabled,
      'priority': priority,
      if (rateLimitCooldownSeconds != null)
        'rateLimitCooldownSeconds': rateLimitCooldownSeconds,
      if (serverErrorCooldownSeconds != null)
        'serverErrorCooldownSeconds': serverErrorCooldownSeconds,
      if (defaultCooldownSeconds != null)
        'defaultCooldownSeconds': defaultCooldownSeconds,
    };
  }

  AdminKeyGroup copyWith({
    String? name,
    bool? enabled,
    int? priority,
    int? rateLimitCooldownSeconds,
    int? serverErrorCooldownSeconds,
    int? defaultCooldownSeconds,
  }) {
    return AdminKeyGroup(
      provider: provider,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      priority: priority ?? this.priority,
      rateLimitCooldownSeconds:
          rateLimitCooldownSeconds ?? this.rateLimitCooldownSeconds,
      serverErrorCooldownSeconds:
          serverErrorCooldownSeconds ?? this.serverErrorCooldownSeconds,
      defaultCooldownSeconds:
          defaultCooldownSeconds ?? this.defaultCooldownSeconds,
    );
  }
}
