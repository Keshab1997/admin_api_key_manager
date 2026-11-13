import 'package:admin_api_key_manager/models/admin_api_key.dart';
import 'package:admin_api_key_manager/models/admin_key_group.dart';
import 'package:admin_api_key_manager/models/api_error_log.dart';
import 'package:admin_api_key_manager/services/key_health_checker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdminApiKey round-trip', () {
    test('toMap keeps the document id so the Hive cache can restore it', () {
      final key = AdminApiKey(
        id: 'doc-123',
        name: 'Primary',
        key: 'sk-or-abc',
        provider: 'openrouter',
        createdAt: DateTime(2026, 1, 2),
        updatedAt: DateTime(2026, 1, 3),
      );

      final restored =
          AdminApiKey.fromMap(key.toMap(), key.toMap()['id'] as String);

      expect(restored.id, 'doc-123');
      expect(restored.name, 'Primary');
      expect(restored.provider, 'openrouter');
    });

    test('a key cached with the old maps (no id field) still loads', () {
      // A map written by a pre-fix build, then handed back with no doc id.
      final legacy = AdminApiKey(
        id: 'doc-9',
        name: 'Legacy',
        key: 'sk-9',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ).toMap()
        ..remove('id');

      final restored =
          AdminApiKey.fromMap(legacy, legacy['id'] as String? ?? '');

      // The id is lost for that one launch, but nothing throws and the key is
      // usable — the Firestore snapshot replaces it immediately.
      expect(restored.id, '');
      expect(restored.name, 'Legacy');
    });
  });

  group('AdminApiKey provider helpers', () {
    test('inferProvider recognises the two known endpoints', () {
      expect(
        AdminApiKey.inferProvider(
            'https://generativelanguage.googleapis.com/v1beta'),
        'google',
      );
      expect(AdminApiKey.inferProvider('https://openrouter.ai/api/v1'),
          'openrouter');
      expect(AdminApiKey.inferProvider('https://my-proxy.example.com/v1'),
          'custom');
    });

    test('providerDefaults exist for every provider that is not custom', () {
      for (final provider in ['openrouter', 'google']) {
        expect(AdminApiKey.defaultsFor(provider), isNotNull,
            reason: '$provider must have a default endpoint');
      }
      expect(AdminApiKey.defaultsFor('custom'), isNull);
    });

    test('isDefaultBaseUrl ignores a trailing slash and case', () {
      expect(AdminApiKey.isDefaultBaseUrl('https://openrouter.ai/api/v1/'),
          isTrue);
      expect(
          AdminApiKey.isDefaultBaseUrl('HTTPS://OPENROUTER.AI/API/V1'), isTrue);
      expect(AdminApiKey.isDefaultBaseUrl('https://my-proxy.example.com'),
          isFalse);
    });

    test('isDefaultBaseUrl treats an empty field as "nothing to protect"', () {
      expect(AdminApiKey.isDefaultBaseUrl('   '), isTrue);
    });

    test('isDefaultModel knows the pre-1.2 default', () {
      expect(AdminApiKey.isDefaultModel('gpt-4o-mini'), isTrue);
      expect(AdminApiKey.isDefaultModel('openai/gpt-4o-mini'), isTrue);
      expect(AdminApiKey.isDefaultModel('my-finetune-v3'), isFalse);
      expect(AdminApiKey.isDefaultModel(''), isTrue);
    });

    test('a custom model survives a provider switch', () {
      // The admin screen protects this with isDefaultModel; assert the rule it
      // relies on, so the guard cannot be "simplified" into data loss.
      expect(AdminApiKey.isDefaultModel('my-finetune-v3'), isFalse);
    });
  });

  group('AdminKeyGroup', () {
    test('defaults match the documented fallbacks', () {
      final group = AdminKeyGroup.fromMap(const {}, 'google');
      expect(group.enabled, isTrue);
      expect(group.priority, 100);
      expect(group.rateLimitCooldownSeconds, isNull);
      expect(group.name, 'Google AI Studio');
    });

    test('cooldown overrides round-trip and nulls stay absent', () {
      const group = AdminKeyGroup(
        provider: 'openrouter',
        name: 'OpenRouter',
        priority: 1,
        rateLimitCooldownSeconds: 60,
      );
      final map = group.toMap();

      // Absent, not null: a null field in a Firestore merge set would erase the
      // override an admin typed.
      expect(map.containsKey('serverErrorCooldownSeconds'), isFalse);
      expect(map.containsKey('defaultCooldownSeconds'), isFalse);

      final restored = AdminKeyGroup.fromMap(map, 'openrouter');
      expect(restored.rateLimitCooldownSeconds, 60);
      expect(restored.priority, 1);
    });
  });

  group('ApiErrorLog', () {
    test('writes the at/timestamp pair the TTL policy needs', () {
      final log = ApiErrorLog(
        keyId: 'k1',
        keyName: 'Primary',
        userId: 'u1',
        feature: 'reply',
        errorType: 'rate_limit',
        statusCode: 429,
        message: 'Rate limit exceeded',
        timestamp: DateTime(2026, 5, 1),
      );
      final map = log.toMap();

      expect(map['at'], isA<Timestamp>());
      expect(map['timestamp'], isA<Timestamp>());
      expect((map['at'] as Timestamp).toDate(),
          (map['timestamp'] as Timestamp).toDate());
      // Default retention is +30 days.
      expect((map['ttlExpireAt'] as Timestamp).toDate(), DateTime(2026, 5, 31));
    });
  });

  group('resolveOpenRouterModel', () {
    test('leaves non-OpenRouter backends untouched', () {
      expect(
        resolveOpenRouterModel(
            'https://generativelanguage.googleapis.com/v1beta',
            'gemini-2.0-flash'),
        'gemini-2.0-flash',
      );
    });

    test('leaves an already-prefixed id alone', () {
      expect(
          resolveOpenRouterModel(
              'https://openrouter.ai/api/v1', 'openai/gpt-4o-mini'),
          'openai/gpt-4o-mini');
    });

    test('prefixes a bare model name for OpenRouter', () {
      expect(
          resolveOpenRouterModel('https://openrouter.ai/api/v1', 'gpt-4o-mini'),
          'openai/gpt-4o-mini');
      expect(
          resolveOpenRouterModel(
              'https://openrouter.ai/api/v1', 'claude-sonnet-4'),
          'anthropic/claude-sonnet-4');
      expect(
          resolveOpenRouterModel(
              'https://openrouter.ai/api/v1', 'gemini-2.0-flash'),
          'google/gemini-2.0-flash');
    });

    test('an unknown bare name is passed through rather than guessed', () {
      expect(
          resolveOpenRouterModel(
              'https://openrouter.ai/api/v1', 'my-finetune-v3'),
          'my-finetune-v3');
    });
  });
}
