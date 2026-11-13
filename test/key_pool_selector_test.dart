import 'package:admin_api_key_manager/models/admin_api_key.dart';
import 'package:admin_api_key_manager/models/admin_key_group.dart';
import 'package:admin_api_key_manager/services/key_pool_selector.dart';
import 'package:flutter_test/flutter_test.dart';

AdminApiKey _key(
  String id, {
  String provider = 'custom',
  int priority = 1,
  bool isActive = true,
}) {
  return AdminApiKey(
    id: id,
    name: id,
    key: 'sk-$id',
    provider: provider,
    priority: priority,
    isActive: isActive,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

KeyPoolSelector _selector(
  List<AdminApiKey> keys, {
  Map<String, AdminKeyGroup> groups = const {},
  List<KeyCooldown> cooldowns = const [],
}) =>
    KeyPoolSelector(keys: keys, groups: groups, cooldowns: cooldowns);

void main() {
  group('getHealthyKeys', () {
    test('drops inactive keys', () {
      final keys = [_key('a'), _key('b', isActive: false)];
      expect(_selector(keys).getHealthyKeys().map((k) => k.id), ['a']);
    });

    test('drops keys of a disabled group', () {
      final keys = [_key('a', provider: 'google'), _key('b')];
      final s = _selector(keys, groups: {
        'google': const AdminKeyGroup(provider: 'google', name: 'G', enabled: false),
      });
      expect(s.getHealthyKeys().map((k) => k.id), ['b']);
    });

    test('drops keys on a cooldown that has not expired', () {
      final keys = [_key('a'), _key('b')];
      final s = _selector(keys, cooldowns: [
        KeyCooldown(keyId: 'a', until: DateTime.now().add(const Duration(minutes: 5))),
      ]);
      expect(s.getHealthyKeys().map((k) => k.id), ['b']);
    });

    test('keeps a key whose cooldown has expired', () {
      final keys = [_key('a')];
      final s = _selector(keys, cooldowns: [
        KeyCooldown(keyId: 'a', until: DateTime.now().subtract(const Duration(minutes: 5))),
      ]);
      expect(s.getHealthyKeys().map((k) => k.id), ['a']);
    });

    test('sorts by group priority first, then key priority', () {
      final keys = [
        _key('slow-first', provider: 'custom', priority: 1),
        _key('fast-second', provider: 'google', priority: 2),
        _key('fast-first', provider: 'google', priority: 1),
      ];
      final s = _selector(keys, groups: {
        'google': const AdminKeyGroup(provider: 'google', name: 'G', priority: 1),
        'custom': const AdminKeyGroup(provider: 'custom', name: 'C', priority: 2),
      });
      expect(
        s.getHealthyKeys().map((k) => k.id),
        ['fast-first', 'fast-second', 'slow-first'],
      );
    });

    test('a provider with no group config sorts last (priority 100)', () {
      final keys = [_key('ungrouped'), _key('grouped', provider: 'google')];
      final s = _selector(keys, groups: {
        'google': const AdminKeyGroup(provider: 'google', name: 'G', priority: 50),
      });
      expect(s.getHealthyKeys().map((k) => k.id), ['grouped', 'ungrouped']);
    });
  });

  group('getTopPriorityPool', () {
    test('returns only the load-carrying group', () {
      final keys = [_key('fast', provider: 'google'), _key('slow')];
      final s = _selector(keys, groups: {
        'google': const AdminKeyGroup(provider: 'google', name: 'G', priority: 1),
        'custom': const AdminKeyGroup(provider: 'custom', name: 'C', priority: 2),
      });
      expect(s.getTopPriorityPool().map((k) => k.id), ['fast']);
    });

    test('is empty when nothing is healthy', () {
      expect(_selector([]).getTopPriorityPool(), isEmpty);
    });
  });

  group('select', () {
    test('rotates round-robin inside one group', () {
      final s = _selector([_key('a'), _key('b'), _key('c')]);

      var index = 0;
      final seen = <String>[];
      for (var i = 0; i < 4; i++) {
        final (key, next) = s.select(index);
        seen.add(key!.id);
        index = next;
      }

      // Three keys, four picks: the fourth wraps back to the first.
      expect(seen, ['a', 'b', 'c', 'a']);
      expect(index, 1);
    });

    test('returns a null key and resets the index when the pool is empty', () {
      final (key, next) = _selector([]).select(2);
      expect(key, isNull);
      expect(next, 0);
    });

    test('recovers from an index past the end of a shrunken pool', () {
      final (key, next) = _selector([_key('only')]).select(7);
      expect(key!.id, 'only');
      expect(next, 0);
    });
  });
}
