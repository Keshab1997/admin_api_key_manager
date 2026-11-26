import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:admin_api_key_manager/models/admin_api_key.dart';

/// Self-contained Hive cache for the key manager. The original app kept these
/// values on its big shared `settings` box; here they live on their own box so
/// the package is drop-in with zero coupling to your app's Hive setup.
class KeyCache {
  static const String _boxName = 'admin_api_key_manager';
  static Box<dynamic>? _box;

  /// Open the cache box (after `HiveFlutter.init()` / `Hive.initFlutter()`).
  ///
  /// `ApiKeyManager.initialize()` calls this itself, so a host app does not have
  /// to — but calling it early is still fine and stays idempotent.
  static Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      _box = await Hive.openBox(_boxName);
    } else {
      _box = Hive.box(_boxName);
    }
  }

  static Box<dynamic> get _b {
    if (_box == null) {
      throw StateError(
          'KeyCache not initialized. Call KeyCache.init() before use.');
    }
    return _box!;
  }

  /// Closes the Hive box. Called by [ApiKeyManager.dispose] so a later
  /// `initialize()` can re-open it cleanly (testable, and avoids leaking
  /// the box across hot-restarts in tests).
  static Future<void> close() async {
    if (Hive.isBoxOpen(_boxName)) {
      await Hive.box(_boxName).close();
    }
    _box = null;
  }

  // ── Admin API keys cache ──

  static List<AdminApiKey> getCachedAdminKeys() {
    final data =
        _b.get('cachedAdminKeys', defaultValue: <Map<dynamic, dynamic>>[])
            as List<dynamic>;
    return data.map<AdminApiKey>((m) {
      final map = Map<String, dynamic>.from(m as Map<dynamic, dynamic>);
      // Convert ISO strings back to Timestamp
      for (final field in [
        'createdAt',
        'updatedAt',
        'lastErrorAt',
        'lastUsedAt'
      ]) {
        if (map[field] is String) {
          map[field] = Timestamp.fromDate(DateTime.parse(map[field] as String));
        }
      }
      return AdminApiKey.fromMap(map, map['id'] as String? ?? '');
    }).toList();
  }

  static Future<void> saveCachedAdminKeys(List<AdminApiKey> keys) async {
    final data = keys.map((k) {
      final map = k.toMap();
      // Convert Timestamp to ISO string for Hive compatibility
      for (final field in [
        'createdAt',
        'updatedAt',
        'lastErrorAt',
        'lastUsedAt'
      ]) {
        if (map[field] is Timestamp) {
          map[field] = (map[field] as Timestamp).toDate().toIso8601String();
        }
      }
      return map;
    }).toList();
    await _b.put('cachedAdminKeys', data);
  }

  /// Key cooldowns survive app restarts, so a known-bad key (e.g. one that got
  /// 401) isn't retried again right after relaunch. Each entry is
  /// {keyId, until (ISO-8601)}.
  static List<Map<String, dynamic>> getCachedAdminKeyCooldowns() {
    final data =
        _b.get('adminKeyCooldowns', defaultValue: <Map<dynamic, dynamic>>[])
            as List<dynamic>;
    return data
        .map<Map<String, dynamic>>(
            (m) => Map<String, dynamic>.from(m as Map<dynamic, dynamic>))
        .toList();
  }

  static Future<void> saveCachedAdminKeyCooldowns(
      List<Map<String, dynamic>> cooldowns) async {
    await _b.put('adminKeyCooldowns', cooldowns);
  }
}
