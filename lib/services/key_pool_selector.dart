import 'package:admin_api_key_manager/models/admin_api_key.dart';
import 'package:admin_api_key_manager/models/admin_key_group.dart';

/// A key on cooldown until [until] (set after a failed API call).
class KeyCooldown {
  final String keyId;
  final DateTime until;
  KeyCooldown({required this.keyId, required this.until});
}

/// Pure key-selection logic, extracted from ApiKeyManager so it can be unit
/// tested without Firebase. Lower group priority (and lower key priority)
/// wins; within the top-priority group keys rotate round-robin.
class KeyPoolSelector {
  KeyPoolSelector({
    required this.keys,
    required this.groups,
    required this.cooldowns,
  });

  final List<AdminApiKey> keys;
  final Map<String, AdminKeyGroup> groups;
  final List<KeyCooldown> cooldowns;

  /// Active keys in enabled groups that aren't on cooldown, sorted by
  /// (group priority, key priority) — lower first.
  List<AdminApiKey> getHealthyKeys() {
    final now = DateTime.now();
    return keys.where((k) {
      final isOnCooldown =
          cooldowns.any((c) => c.keyId == k.id && c.until.isAfter(now));
      final groupEnabled = groups[k.provider]?.enabled ?? true;
      return k.isActive && groupEnabled && !isOnCooldown;
    }).toList()
      ..sort((a, b) {
        final gp =
            _groupPriority(a.provider).compareTo(_groupPriority(b.provider));
        if (gp != 0) return gp;
        return a.priority.compareTo(b.priority);
      });
  }

  /// Healthy keys from the highest-priority group (the group that carries the
  /// load; slower groups wait in reserve as fallback).
  List<AdminApiKey> getTopPriorityPool() {
    final healthy = getHealthyKeys();
    if (healthy.isEmpty) return const [];
    final top = _groupPriority(healthy.first.provider);
    return healthy.where((k) => _groupPriority(k.provider) == top).toList();
  }

  /// Round-robin selection over the top-priority pool. Returns the selected
  /// key plus the index to use for the next call (null key when empty).
  (AdminApiKey?, int) select(int currentIndex) {
    final pool = getTopPriorityPool();
    if (pool.isEmpty) return (null, 0);
    if (currentIndex >= pool.length) currentIndex = 0;
    return (pool[currentIndex], (currentIndex + 1) % pool.length);
  }

  int _groupPriority(String provider) => groups[provider]?.priority ?? 100;
}
