/// admin_api_key_manager
///
/// A drop-in Flutter package for managing a Firestore-backed pool of admin
/// API keys (Gemini / OpenRouter / any OpenAI-compatible endpoint) with
/// automatic failover, cooldowns, health checks, and an admin UI.
library admin_api_key_manager;

export 'models/admin_api_key.dart';
export 'models/admin_key_group.dart';
export 'models/api_error_log.dart';
export 'services/api_key_manager.dart';
export 'services/key_cache.dart';
export 'services/key_pool_selector.dart';
export 'services/key_health_checker.dart';
export 'screens/admin_api_keys_screen.dart';
