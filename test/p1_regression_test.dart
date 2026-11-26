import 'package:admin_api_key_manager/services/api_key_manager.dart';
import 'package:admin_api_key_manager/services/key_health_checker.dart';
import 'package:admin_api_key_manager/theme/key_admin_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P1 #8 — URL bugs', () {
    test('resolveOpenRouterModel is case-insensitive for baseUrl', () {
      expect(
        resolveOpenRouterModel('HTTPS://OPENROUTER.AI/api/v1', 'gpt-4o-mini'),
        'openai/gpt-4o-mini',
      );
      expect(
        resolveOpenRouterModel(
            'https://OpenRouter.ai/API/v1', 'claude-sonnet-4'),
        'anthropic/claude-sonnet-4',
      );
      // non-OpenRouter stays untouched even with upper case
      expect(
        resolveOpenRouterModel(
            'HTTPS://GENERATIVELANGUAGE.GOOGLEAPIS.COM/v1beta',
            'gemini-2.0-flash'),
        'gemini-2.0-flash',
      );
    });

    test('resolveOpenRouterModel still leaves prefixed ids alone', () {
      expect(
        resolveOpenRouterModel(
            'https://openrouter.ai/api/v1', 'openai/gpt-4o-mini'),
        'openai/gpt-4o-mini',
      );
    });
  });

  group('P1 #3 — palette still works from new location', () {
    testWidgets('KeyAdminPalette fallback via theme import', (tester) async {
      late KeyAdminPalette resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(),
          home: Builder(builder: (context) {
            resolved = KeyAdminPalette.of(context);
            return const SizedBox.shrink();
          }),
        ),
      );
      expect(resolved.healthy, KeyAdminPalette.fallback.healthy);
    });

    test('KeyAdminPalette lerp and copyWith still work', () {
      const a = KeyAdminPalette.fallback;
      const b = KeyAdminPalette(
        healthy: Color(0xFF000000),
        attention: Color(0xFF111111),
        danger: Color(0xFF222222),
      );
      expect(a.lerp(b, 0).healthy, a.healthy);
      expect(a.lerp(b, 1).healthy, b.healthy);
      expect(a.copyWith(healthy: const Color(0xFF123456)).healthy,
          const Color(0xFF123456));
    });
  });

  group('P1 #7 — refreshFromCache alias', () {
    test('refreshFromCache exists as alias for refreshKeys', () {
      final manager = ApiKeyManager.instance;
      expect(manager.refreshFromCache, isA<Function>());
      // ignore: deprecated_member_use
      expect(manager.refreshKeys, isA<Function>());
    });
  });
}
