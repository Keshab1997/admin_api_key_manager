# admin_api_key_manager

[![Flutter CI](https://github.com/Keshab1997/admin_api_key_manager/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/Keshab1997/admin_api_key_manager/actions/workflows/ci.yml)

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
  caught before users hit them. `cooldownUntil(keyId)` and `getKeyHealth()`
  expose the exact end of a cooldown, so a UI can say "in 4 min".
- ⚠️ **All-keys-failed alert** — fires a pluggable callback when every key is
  exhausted (you wire your own push notification).
- 📊 **Usage & error stats** — written back to Firestore so the admin panel
  shows live numbers.
- 🖥️ **Admin screen** — key cards with a health label (healthy / cooling down /
  has errors / disabled), usage and error counts, per-filter view, masked keys
  with reveal-per-row, and add/edit/test/delete. Styled entirely from the host
  app's `ColorScheme`; the three state colours come from a `KeyAdminPalette`
  `ThemeExtension` you can replace. A static preview lives in
  [`design/admin_screen_preview.html`](design/admin_screen_preview.html).
- 🔗 **Provider-aware form** — picking a provider fills in its base URL and
  model. A URL you typed yourself is never overwritten; you get an explicit
  "use default" button instead.

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

### Pinning

`ref: master` follows every push to this repository. Two apps depend on this
package, so an unrelated change here reaches all of them at once. Once a release
is tagged, pin the tag instead:

```yaml
    git:
      url: https://github.com/Keshab1997/admin_api_key_manager
      ref: v1.2.0
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

  // Opens the package's own Hive box itself and is safe to await. Calling
  // KeyCache.init() first is optional. (Before 1.2.1 leaving it out threw a
  // StateError from inside the first cache read, and left the manager
  // un-initialized for the rest of the process.)
  await ApiKeyManager.instance.initialize();

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

### Theming it

The screen reads every colour from `ColorScheme`, so it inherits the app's
theme. The three *state* colours are the one exception, and they are a
`ThemeExtension` — register your own and the defaults disappear:

```dart
MaterialApp(
  theme: ThemeData(
    colorSchemeSeed: const Color(0xFF1B6EF3),
    extensions: const <ThemeExtension<dynamic>>[
      KeyAdminPalette(
        healthy: Color(0xFF43E0A0),
        attention: Color(0xFFFFB545),
        danger: Color(0xFFFF5D6C),
      ),
    ],
  ),
  // ...
);
```

Register nothing and `KeyAdminPalette.fallback` is used, so the screen never
depends on the host having heard of this package.

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

### Read this before shipping the rules

The rule sketch above — *every* signed-in client may read `admin_api_keys` —
means **the API keys ship to every device**. Anyone who installs the app can
read them out of Firestore and spend your provider quota; the admin UI is
protected, the secrets are not.

That is a deliberate MVP trade-off, not an oversight, but it has a direction of
travel: the endpoint that needs protecting is the *AI call itself*. A proxy
(e.g. a Cloud Function) that holds the keys server-side and exposes
`POST /reply` is the fix, and when that exists this package's selection,
cooldown and health-check logic belongs behind it, not on the client. Until
then, keep the key pool on keys you can afford to lose and rotate them if a
build leaks.

---

## Provider groups (admin UI)

`AdminKeyGroupsScreen` writes `admin_key_groups` — enable/disable a provider,
rank it, and override the three cooldown durations. The key screen links to it
from the app bar. Optional: the collection has always been read by
`ApiKeyManager`, so leaving the screen out only means those values stay
hand-edited in the console.

```dart
Navigator.of(context).push(MaterialPageRoute(
  builder: (_) => const AdminKeyGroupsScreen(),
));
```

An empty cooldown field means "use the built-in default" (429 → 60s,
5xx → 120s, other → 30s), which is deliberately different from `0`.

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
