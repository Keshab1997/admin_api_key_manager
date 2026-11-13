/// Reading the pool can fail for reasons a person can act on, and the raw
/// Firestore text does not say which. `permission-denied` is the one that
/// matters most: it is not a broken key pool, it is a signed-in account that is
/// not on the admin allowlist — and the fix ("add this uid to
/// `admin_config/access`") is nothing like the fix for a network failure.
///
/// This lives in the package because the *app* hitting it is where the confusion
/// happens: the admin gate lets you in, the screen then shows
/// `[cloud_firestore/permission-denied] Missing or insufficient permissions.`
/// and the natural reading is "the package is broken".
library;

/// Why a key-pool read failed, in the four shapes a screen should render
/// differently.
enum KeyPoolFailure {
  /// The signed-in account is not an admin. Actionable: allowlist the uid.
  permissionDenied,

  /// Firebase was never configured (no `Firebase.initializeApp`, no project).
  notConfigured,

  /// Offline, DNS, timeout — the pool is fine, the device cannot reach it.
  unreachable,

  /// Anything else. Shown as-is; never silently swallowed.
  unknown,
}

/// Classify a Firestore/stream error without importing Firestore types, so the
/// mapping is testable on a plain JVM and the package keeps its wide version
/// range intact (no `FirebaseException` import here on purpose).
KeyPoolFailure classifyKeyPoolError(Object? error) {
  final text = (error ?? '').toString().toLowerCase();
  if (text.isEmpty) return KeyPoolFailure.unknown;
  // Hyphen, space and underscore all appear in the wild: Firestore prints
  // `permission-denied`, gRPC prints `PERMISSION_DENIED`, and a wrapped
  // exception can arrive either way.
  if (text.contains('permission-denied') ||
      text.contains('permission denied') ||
      text.contains('permission_denied') ||
      text.contains('missing or insufficient permissions')) {
    return KeyPoolFailure.permissionDenied;
  }
  if (text.contains('not-initialized') ||
      text.contains('no firebase app') ||
      text.contains("has not been created") ||
      text.contains('firebase_options') ||
      text.contains('not configured')) {
    return KeyPoolFailure.notConfigured;
  }
  if (text.contains('unavailable') ||
      text.contains('network') ||
      text.contains('socket') ||
      text.contains('timeout') ||
      text.contains('failed to connect') ||
      text.contains('deadline')) {
    return KeyPoolFailure.unreachable;
  }
  return KeyPoolFailure.unknown;
}

/// The two lines a screen shows for a failure: what happened, and what to do.
///
/// Kept together and phrased as an instruction, because the alternative — one
/// generic "Could not read the key pool" — is exactly the state the app was in
/// when an admin with a good key and a valid session was told nothing.
({String title, String detail}) describeKeyPoolFailure(KeyPoolFailure failure) {
  switch (failure) {
    case KeyPoolFailure.permissionDenied:
      return (
        title: 'This account is not an admin',
        detail: 'Signing in worked, so this is not a password problem. Add this '
            "account's uid (or email) to admin_config/access in Firestore, then "
            'pull to refresh. Until then the key pool stays closed.',
      );
    case KeyPoolFailure.notConfigured:
      return (
        title: 'Firebase is not configured',
        detail: 'This build has no google-services.json, so there is no key '
            'pool to read. Reply generation still works with your own AI key '
            'in Settings.',
      );
    case KeyPoolFailure.unreachable:
      return (
        title: 'Could not reach the key pool',
        detail: 'The keys are fine; this device could not load them. Check the '
            'connection and try again — nothing was changed.',
      );
    case KeyPoolFailure.unknown:
      return (
        title: 'Could not read the key pool',
        detail: 'The exact error is shown below so it can be reported rather '
            'than guessed at.',
      );
  }
}
