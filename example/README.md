# admin_api_key_manager — example

Minimal host app that shows how a real app wires this package.

### What it does

* `main.dart` — `Firebase.initializeApp()` → `Hive.initFlutter()` → `ApiKeyManager.instance.initialize()` → `MaterialApp` with three buttons: **Admin API Keys**, **Provider Groups**, **Error Logs**.
* No auth gate — so you can run it without a user system. In a real app, gate `AdminApiKeysScreen` behind your own admin check.

### Run

```bash
# 1. Add your Firebase config (or run flutterfire configure)
#    flutterfire configure --project your-project

# 2. Get deps
flutter pub get

# 3. Run (any device)
flutter run
```

> The package itself is consumed via `path: ../` here. In your own app use the git ref:
>
> ```yaml
> dependencies:
>   admin_api_key_manager:
>     git:
>       url: https://github.com/Keshab1997/admin_api_key_manager
>       ref: master   # or a tag like v1.4.0
> ```

### Firestore rules

The example needs the same rules as the package’s README sketch: **admin writes, signed-in reads** on `admin_api_keys` / `admin_key_groups`. Without them the admin screens show `permission-denied` — which the package now classifies and explains via `key_pool_errors.dart`.

See `../README.md` (Setup, Firestore structure) and `../docs/API_SECURITY.md` (why the pool is client-readable in the MVP and how the proxy migration looks).
