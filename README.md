# admin_api_key_manager

A **drop-in Flutter package** for managing a Firestore-backed pool of admin API
keys (Gemini / OpenRouter / any OpenAI-compatible `/chat/completions` endpoint)
with automatic failover, cooldowns, periodic health checks, batched error
logging, and a ready-made admin UI.

Originally extracted from the **SpeakEasy** app so it can be reused in any
Flutter project without copy-pasting.

---

## Features

- 🔑 **Firestore-backed key pool** — add/edit/disable keys from an admin screen;
  every device syncs live via snapshot listeners.
- 🔄 **Automatic failover** — round-robin selection within the highest-priority
  enabled provider group; slower groups wait in reserve.
- 🧊 **Smart cooldowns** — 429 / 5xx / auth failures each get their own cooldown
  (configurable per provider group), and cooldowns persist across app restarts
  via Hive.
- ⚕️ **Health checks** — proactively pings the primary key so dead keys are
  caught before users hit them.
- ⚠️ **All-keys-failed alert** — fires a pluggable callback when every key is
  exhausted (you wire your own push notification).
- 📊 **Usage & error stats** — written back to Firestore so the admin panel
  shows live numbers.
- 🖥️ **Minimal admin screen** — list, add, edit, delete, toggle, and
  "test connection" out of the box.

---

## Installation

### Compatibility

| | Supported |
|---|---|
| `cloud_firestore` | 5.x and 6.x |
| `firebase_core` | 3.x and 4.x |
| Dart / Flutter | Dart ^3.3, Flutter >= 3.19 |

The Firestore constraint is intentionally wide: the package only touches
long-stable API surface, and pinning a single major stopped it installing
alongside apps already on Firestore 6.

### Option A — Git dependency (easiest)

```yaml
dependencies:
  admin_api_key_manager:
    git:
      url: https://github.com/Keshab1997/admin_api_key_manager
      ref: master
```

### Option B — Local path

```yaml
dependencies:
  admin_api_key_manager:
    path: ../admin_api_key_manager
```

Then:

```bash
flutter pub get
```

---

## Setup

In `main.dart`, after `Firebase.initializeApp()` and `HiveFlutter.init()`:

```dart
import 'package:admin_api_key_manager/admin_api_key_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await HiveFlutter.init();          // or Hive.initFlutter()
  await KeyCache.init();             // <-- package's own Hive box
  ApiKeyManager.instance.initialize();

  // optional: your own push notification when all keys fail
  ApiKeyManager.instance.onAllKeysFailed = (keyCount, message) {
    // send your OneSignal / FCM push here
  };

  runApp(const MyApp());
}
```

---

## Using a key

```dart
final key = ApiKeyManager.instance.getNextKey();
if (key == null) {
  // no healthy key available
  return;
}

try {
  final response = await http.post(
    Uri.parse('${key.baseUrl}/chat/completions'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${key.key}',
    },
    body: jsonEncode({
      'model': key.model,
      'messages': [{'role': 'user', 'content': 'Hello'}],
    }),
  );

  if (response.statusCode == 200) {
    ApiKeyManager.instance.reportSuccess(key);
  } else {
    ApiKeyManager.instance.reportFailure(
      key, response.statusCode, 'my_feature', userId);
  }
} catch (e) {
  ApiKeyManager.instance.reportFailure(key, 0, 'my_feature', userId);
}
```

Use `ApiKeyManager.instance.ensureReady()` at startup if you make a call
immediately after launch, to avoid racing the Firestore listener.

---

## Opening the admin screen

Gate this behind your own admin check, then:

```dart
Navigator.of(context).push(
  MaterialPageRoute(builder: (_) => const AdminApiKeysScreen()),
);
```

---

## Firestore structure

### `admin_api_keys` (doc id = auto or custom)

```jsonc
{
  "name": "Primary OpenRouter",
  "key": "sk-or-...",
  "baseUrl": "https://openrouter.ai/api/v1",
  "model": "gpt-4o-mini",
  "provider": "openrouter",     // google | openrouter | custom
  "isActive": true,
  "priority": 1,
  "usageCount": 0,
  "errorCount": 0
}
```

### `admin_key_groups` (doc id = provider)

```jsonc
{
  "name": "OpenRouter",
  "enabled": true,
  "priority": 1,
  "rateLimitCooldownSeconds": 60,   // optional
  "serverErrorCooldownSeconds": 120, // optional
  "defaultCooldownSeconds": 30       // optional
}
```

### Also used (optional)

- `api_error_logs` — batched failure logs (auto-cleaned after 30 days).
- `admin_alerts` — outage banner when all keys fail.

### Firestore rules (sketch)

Allow reads for all users, but only **admin** writes/deletes on
`admin_api_keys` and `admin_key_groups`. Non-admin devices fail their writes
silently, which is fine — the first admin device to hit a failure threshold
does the deactivation.

---

## Configuration

All collection names are configurable on the singleton:

```dart
ApiKeyManager.instance.keysCollection = 'admin_api_keys';
ApiKeyManager.instance.groupsCollection = 'admin_key_groups';
ApiKeyManager.instance.errorLogsCollection = 'api_error_logs';
```

---

## License

MIT — see [LICENSE](LICENSE).
