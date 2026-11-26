# Changelog

All notable changes to `admin_api_key_manager` are documented here.
This package follows [Keep a Changelog](https://keepachangelog.com/) and
uses [Semantic Versioning](https://semver.org/).

## 1.7.1 — 2026-11-27

### Fixed
- **A failed catalog fetch could blank the Free models screen.** `_FreeModelsError`
  printed the raw exception with `Text('$error')` inside a non-scrollable
  `Column`. A network failure whose exception text carries the response body
  (OpenRouter's catalog is ~900 kB) made that Column want **1,112,028 px** of
  height on a 353dp phone: a grey wall you can scroll forever and read nothing
  on — the exact symptom reported from the device. The error state now:
  - reads the failure *type* in one line ("openrouter.ai answered HTTP 500",
    "The request timed out", "Could not reach openrouter.ai", "not valid JSON");
  - renders at most 240 characters of the message, with `+N more characters`
    and a **Copy details** button that puts the full text on the clipboard
    instead of laying it out;
  - lives in a `SingleChildScrollView` with a min-height box, so it cannot
    overflow at any screen width;
  - sits below the tab bar, so **Free sources** stays usable while the catalog
    is down.
- Regression test added: a 1 MB exception at 320/353/390dp must render without
  an exception, keep every `Text` under 400 characters, and still offer Retry.

## 1.7.0 — 2026-11-26

### Added
- **Free sources tab** (`lib/models/free_source.dart`, `AdminFreeModelsScreen`):
  a hand-curated directory of where free model access comes from — first-party
  free tiers (Google AI Studio, Groq, Cerebras, Mistral, Cloudflare Workers AI,
  Cohere, NVIDIA NIM, GitHub Models, Hugging Face) plus gateways (OpenRouter,
  NaraRouter). Each `FreeSource` carries the OpenAI-compatible base URL, the
  allowance in the source's own words, `needsCard` / `needsPhone` / `relay`
  flags, a `verifiedOn` date and a link that owns the real limits. Copy the base
  URL, open the key page, done. The tab is static data, so it still answers when
  the catalog fetch fails — which is exactly when you ask "where do I get a key?".
  `filterSources()` gives case-insensitive search plus a `providersOnly` switch.
- **`tool/free_model_radar.py`**: keyless diff of OpenRouter's public catalog
  against `tool/free_models_snapshot.json` — `+ added` / `- gone`, `--update`,
  `--all`, `--json`, optional `--telegram` push. No workflow file is added: a
  scheduled job is a repo-owner decision, not something a library should install.

### Changed
- `AdminFreeModelsScreen` body is now a two-tab shell (`Catalog` / `Free
  sources`) with the hand-rolled `_FreeModelsTabBar`; the catalog tab keeps the
  50-per-page paging and filter behaviour from 1.6.2.
- README documents the directory, how to add a source, and the radar.

## 1.6.2 — 2026-11-26

### Fixed
- **Free-model screen layout**: the app-bar title row put a full-sentence
  subtitle in a bare `Column` next to the 36dp badge, so it overflowed by ~32px
  on a 390dp phone (and more on 320–360dp) — clipped and invisible in a release
  build. The title/subtitle now sit in `Expanded` with `maxLines: 1` + ellipsis,
  on all four admin screens. The card action row's "Get key" button is
  `Flexible`, so copy / Get key / Use no longer overflow on a narrow phone.
- **Endless free-model scroll**: OpenRouter's catalog has 300+ free entries at
  ~250dp per card, so the list was ~100,000px long. It now pages 50 at a time
  with an explicit "Show more · N left" footer; changing the search, provider or
  "Free only" filter starts a new page.
- **Adding a key could silently fail**: the sheet called
  `Navigator.pop()` *before* `_saveKey()`, so a rejected write (validation or
  Firestore) closed the sheet, discarded the typed key and left only a toast.
  The sheet now saves first — spinner on the CTA, closes only on success, stays
  open with the form intact on failure — and cannot submit twice. The duplicate
  drag handle (sheet `showDragHandle` + a hand-rolled one) is gone.
- **Testability**: `AdminFreeModelsScreen` takes an optional `FreeModelDiscovery`,
  so the screen's body can be rendered in a widget test (`test/free_models_screen_test.dart`)
  without the network; the injected client is never closed by the screen.

## 1.6.1 — 2026-11-26

### Fixed
- **Test latency**: `pingKeyStatus` timeout 15s → 8s (5-token Hi ping rarely needs >3s; worst-case now half as long). `AdminApiKeysScreen._testConnection` now shows an instant modal spinner with provider/model and “usually <3s” hint instead of a fleeting toast, plus elapsed time (e.g. “HTTP 200 in 1.2s”) and a Cancel button; perceived delay feels like progress, not freeze.

## 1.6.0 — 2026-11-26

### Changed
- **Premium design overhaul**: `KeyAdminPalette` now carries `accent`/`accentSoft` (indigo) with emerald/amber/rose jewel tones, soft containers and `copyWith`/`lerp` updated; all admin screens rebuilt as premium dashboard — gradient avatars, top accent strips, soft shadows, rounded 20, premium empty/error states.
- **`AdminApiKeysScreen`**: new indigo app bar with key count subtitle, surface background, indigo FAB, polished bottom sheet (section labels, filled inputs with icons, tonal/test + accent CTA).
- **`AdminFreeModelsScreen`**: indigo header, filled search with clear, pill provider dropdown, chip for “Free only”, free cards with accent strip, soft badges, tonal actions.
- **`AdminErrorLogsScreen` / `AdminKeyGroupsScreen`**: matching indigo headers, soft info banners, premium group cards with gradient avatars, cooldown chips, tonal buttons and polished error/empty states.
- **`AdminScreenWidgets`**: `AdminStat` with top colour strip + icon, `AdminKeyCard` with shadow, key container, pill dots and tonal actions, `ProviderAvatar` gradient, `AdminReorderView` with banner and gradient numbers.

## 1.5.0 — 2026-11-26

### Added
- **Free Model Explorer**: `FreeModel` + `FreeModelDiscovery` (live `openrouter.ai/api/v1/models` fetch, free filter, search) + `AdminFreeModelsScreen` (provider dropdown, search, `FREE` badge, context-length, Copy / Get API key / Use model). AppBar of `AdminApiKeysScreen` now has a 🔍 button.
- **UX split**: `KeyAdminPalette` → `lib/theme/key_admin_palette.dart`, card/summary/states → `lib/screens/widgets/admin_screen_widgets.dart` (screen 1333 → 724 loc).

### Changed
- `example` now uses `material_ui` so `ThemeData` and `KeyAdminPalette` share the same `ThemeExtension` type; added `material_ui` dep.
- `pubspec`: added `url_launcher: ^6.2.5` for “Get API key” links.

## 1.4.0 — 2026-11-26

### Fixed
- **Core selection**: `_keyPool` now sorts by `(groupPriority, keyPriority)` — the Firestore listener and `getKeyHealth()` previously used only key priority, so `peekFirstKey()` and the admin health list disagreed with `KeyPoolSelector` on group order.
- **Dispose re-arm**: `dispose()` clears pool/groups/cooldowns/counters/error queue, resets `_readyCompleter` and closes the Hive box so `initialize()` after `dispose()` no longer returns instantly with an empty pool ([#4](https://github.com/Keshab1997/admin_api_key_manager/issues)).
- **Cooldown leak**: deactivating a key (3× 401/403) now drops its 365-day cooldown and persists the pruned list — previously the Year-long entry survived restarts via Hive.
- **Health-check pollute**: health pings no longer `reportFailure('health_check','')`; a local dedup map + Firestore `lastErrorAt` dedup prevents 10 devices logging the same dead key every 30 min, and `api_error_logs` stays free of `userId=''` rows.
- **URL bugs**: `resolveOpenRouterModel` is case-insensitive for `openrouter`; `pingKeyStatus` trims trailing `/` so `https://…/v1/` + `/models` does not become `//models`.

### Changed
- `refreshKeys()` → deprecated alias for `refreshFromCache()` (docs now say it reads only the Hive cache, not Firestore).
- `KeyCache` gains `close()` for clean test re-init.

## 1.3.0 — 2026-11-20

- **Git**: stale `main` (3 commits ahead of `master`) archived as `archive/main-2026-10-05` and deleted — `master` is canonical.
- **Admin UI**: error copy now uses `key_pool_errors.dart` — `permission-denied` (allowlist the uid) vs `unavailable` (network) are told apart instead of raw Firestore text.
- **Docs**: `docs/API_SECURITY.md` added — the client-readable key pool is a documented MVP trade-off with a 5-step proxy migration.
- **CI**: pinned to `flutter-builder@v1.18.9`; `flutter analyze --fatal-infos` + `flutter test` gates match the sibling apps.

## 1.2.0 — 2026-11-15

- **Provider groups**: `AdminKeyGroupsScreen` (`admin_key_groups` collection) — enable/disable a provider, rank it, override 3 cooldown durations.
- **Cooldown**: `cooldownUntil(keyId)` + `getKeyHealth()` now expose the exact expiry so UI can say “in 4 min”.
- **Setup**: `ApiKeyManager.initialize()` opens `KeyCache` itself — host no longer must call `KeyCache.init()` first.

## 1.1.0 — 2026-11-10

- **Admin screen** rebuilt as cards (health label + colour via `KeyAdminPalette`, usage/error counts, masked key with reveal, per-filter view, test-connection).
- **Error logs**: `AdminErrorLogsScreen` + batched `api_error_logs` (30-day sweep, TTL-ready).
- **Bulk**: enable/disable all keys, delete disabled+errored keys, drag-to-reorder failover → batched Firestore writes.

## 1.0.0 — 2026-10-20

- **Initial release**: `ApiKeyManager` (Firestore `admin_api_keys` pool, round-robin over top-priority enabled group, cooldowns persisted via Hive, health checks, `onAllKeysFailed`), `AdminApiKeysScreen`, `KeyPoolSelector` (Firebase-free).

## 0.x — 2026-08-13 to 2026-10-15

- Widened `cloud_firestore` to `>=5.0.0 <7.0.0` and `firebase_core` to `>=3.0.0 <5.0.0` so the package installs alongside apps on Firestore 6 / Core 4.
- Provider-aware form: picking `google`/`openrouter` fills `baseUrl`/`model`; custom URLs are never overwritten.
