import 'package:admin_api_key_manager/models/admin_api_key.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// The two bulk operations the key list offers, kept out of the widget so the
/// "which keys does this touch" decision is readable and testable at all.
///
/// Both are written as one Firestore batch: a half-applied bulk action (three
/// keys disabled, two not) is indistinguishable from a partial outage.

/// Keys a bulk "disable" should touch: every key that is currently active.
List<AdminApiKey> keysToDisable(Iterable<AdminApiKey> keys) =>
    keys.where((k) => k.isActive).toList();

/// Keys a bulk "enable" should touch: every key that is currently inactive.
List<AdminApiKey> keysToEnable(Iterable<AdminApiKey> keys) =>
    keys.where((k) => !k.isActive).toList();

/// Keys worth deleting in one go: the ones the admin disabled *and* that have
/// recorded failures. An inactive key with a clean record is probably parked
/// on purpose — deleting it is the one action here that cannot be undone.
List<AdminApiKey> keysSafeToDelete(Iterable<AdminApiKey> keys) =>
    keys.where((k) => !k.isActive && k.errorCount > 0).toList();

/// The priority assignment produced by a reorder: the given keys in their new
/// order, numbered from 1.
///
/// Firestore has no ordering of its own here — `priority` is the order, and the
/// selector sorts by it — so a drag has to rewrite the numbers. Only the keys
/// whose number actually changed come back, so a drag of one row does not
/// rewrite the whole collection.
Map<String, int> priorityAssignments(List<AdminApiKey> reordered) {
  final changes = <String, int>{};
  for (var i = 0; i < reordered.length; i++) {
    final key = reordered[i];
    final next = i + 1;
    if (key.priority != next) changes[key.id] = next;
  }
  return changes;
}

/// Writes [priorityAssignments] to Firestore in one batch.
Future<void> applyPriorities(
  CollectionReference<Map<String, dynamic>> collection,
  Map<String, int> assignments,
) async {
  if (assignments.isEmpty) return;
  final batch = FirebaseFirestore.instance.batch();
  assignments.forEach((id, priority) {
    batch.update(collection.doc(id), {
      'priority': priority,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  });
  await batch.commit();
}

/// Applies [isActive] to [keys] in one batch.
Future<void> setActive(
  CollectionReference<Map<String, dynamic>> collection,
  List<AdminApiKey> keys, {
  required bool isActive,
}) async {
  if (keys.isEmpty) return;
  final batch = FirebaseFirestore.instance.batch();
  for (final key in keys) {
    batch.update(collection.doc(key.id), {
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
}

/// Deletes [keys] in one batch.
Future<void> deleteKeys(
  CollectionReference<Map<String, dynamic>> collection,
  List<AdminApiKey> keys,
) async {
  if (keys.isEmpty) return;
  final batch = FirebaseFirestore.instance.batch();
  for (final key in keys) {
    batch.delete(collection.doc(key.id));
  }
  await batch.commit();
}
