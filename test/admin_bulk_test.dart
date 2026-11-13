import 'package:admin_api_key_manager/models/admin_api_key.dart';
import 'package:admin_api_key_manager/screens/admin_bulk.dart';
import 'package:flutter_test/flutter_test.dart';

AdminApiKey _key(
  String id, {
  bool isActive = true,
  int priority = 1,
  int errorCount = 0,
}) {
  return AdminApiKey(
    id: id,
    name: id,
    key: 'sk-$id',
    isActive: isActive,
    priority: priority,
    errorCount: errorCount,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

void main() {
  group('bulk targets', () {
    test('disable touches only the active keys', () {
      final keys = [_key('a'), _key('b', isActive: false), _key('c')];
      expect(keysToDisable(keys).map((k) => k.id), ['a', 'c']);
    });

    test('enable touches only the inactive keys', () {
      final keys = [_key('a'), _key('b', isActive: false)];
      expect(keysToEnable(keys).map((k) => k.id), ['b']);
    });

    test('delete only takes disabled keys that already failed', () {
      final keys = [
        _key('active-error', errorCount: 3),
        _key('disabled-clean', isActive: false),
        _key('disabled-error', isActive: false, errorCount: 2),
      ];
      // A disabled key with a clean record is probably parked on purpose; the
      // one irreversible action on this screen must not take it.
      expect(keysSafeToDelete(keys).map((k) => k.id), ['disabled-error']);
    });

    test('an empty pool yields no targets, so the dialog never opens', () {
      expect(keysToDisable(const []), isEmpty);
      expect(keysToEnable(const []), isEmpty);
      expect(keysSafeToDelete(const []), isEmpty);
    });
  });

  group('priorityAssignments', () {
    test('numbers the new order from 1', () {
      final order = [
        _key('c', priority: 3),
        _key('a', priority: 1),
        _key('b', priority: 2),
      ];
      expect(priorityAssignments(order), {'c': 1, 'a': 2, 'b': 3});
    });

    test('returns only the rows whose number actually changed', () {
      final order = [_key('a', priority: 1), _key('b', priority: 2)];
      // Nothing moved: no write at all.
      expect(priorityAssignments(order), isEmpty);
    });

    test('one moved row produces one update', () {
      final order = [
        _key('b', priority: 2),
        _key('a', priority: 1),
        _key('c', priority: 3),
      ];
      expect(priorityAssignments(order), {'b': 1, 'a': 2});
    });

    test('collapses duplicated priorities', () {
      // Firestore docs edited by hand often share a priority; the selector then
      // falls back to list order, which is not stable across devices.
      final order = [_key('a', priority: 1), _key('b', priority: 1)];
      expect(priorityAssignments(order), {'b': 2});
    });
  });
}
