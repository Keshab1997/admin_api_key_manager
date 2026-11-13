import 'package:admin_api_key_manager/services/key_pool_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyKeyPoolError', () {
    test('the real Firestore permission-denied text is recognised', () {
      // This is the string an app prints today when the signed-in account is
      // not on the admin allowlist, and it used to be the *only* thing the
      // screen said — next to advice to check the network.
      expect(
        classifyKeyPoolError(
          '[cloud_firestore/permission-denied] Missing or insufficient '
          'permissions.',
        ),
        KeyPoolFailure.permissionDenied,
      );
    });

    test('permission wording without the bracket code still classifies', () {
      expect(
        classifyKeyPoolError(Exception('PERMISSION_DENIED: caller lacks')),
        KeyPoolFailure.permissionDenied,
      );
    });

    test('an uninitialised Firebase is not a permission problem', () {
      expect(
        classifyKeyPoolError(
          'FirebaseException: [core/no-app] No Firebase App "[DEFAULT]" has '
          'been created - call Firebase.initializeApp()',
        ),
        KeyPoolFailure.notConfigured,
      );
    });

    test('a network failure is not a permission problem either', () {
      for (final text in [
        '[cloud_firestore/unavailable] The service is currently unavailable.',
        'SocketException: Failed host lookup',
        'Deadline exceeded',
      ]) {
        expect(classifyKeyPoolError(text), KeyPoolFailure.unreachable,
            reason: text);
      }
    });

    test('no error at all stays unknown rather than borrowing a cause', () {
      expect(classifyKeyPoolError(null), KeyPoolFailure.unknown);
      expect(classifyKeyPoolError(''), KeyPoolFailure.unknown);
      expect(classifyKeyPoolError('weird'), KeyPoolFailure.unknown);
    });
  });

  group('describeKeyPoolFailure', () {
    test('every failure explains what to do, not just what broke', () {
      for (final failure in KeyPoolFailure.values) {
        final copy = describeKeyPoolFailure(failure);
        expect(copy.title, isNotEmpty, reason: '$failure');
        expect(copy.detail.length, greaterThan(40), reason: '$failure');
      }
    });

    test('permission-denied is told it is an allowlist problem', () {
      final copy = describeKeyPoolFailure(KeyPoolFailure.permissionDenied);
      expect(copy.detail, contains('admin_config/access'));
      expect(copy.title.toLowerCase(), contains('admin'));
    });

    test('not configured points at the working alternative', () {
      final copy = describeKeyPoolFailure(KeyPoolFailure.notConfigured);
      expect(copy.detail, contains('your own AI key'));
    });
  });
}
