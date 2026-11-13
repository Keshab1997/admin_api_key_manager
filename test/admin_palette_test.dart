import 'package:admin_api_key_manager/screens/admin_api_keys_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads [KeyAdminPalette.of] through a real context, once per pumped theme.
Widget _probe(ThemeData theme, void Function(KeyAdminPalette) onResolved) {
  return MaterialApp(
    theme: theme,
    home: Builder(
      builder: (context) {
        onResolved(KeyAdminPalette.of(context));
        return const SizedBox.shrink();
      },
    ),
  );
}

void main() {
  group('KeyAdminPalette', () {
    testWidgets('falls back when the host registers no extension',
        (tester) async {
      late KeyAdminPalette resolved;
      await tester.pumpWidget(_probe(ThemeData(), (p) => resolved = p));

      // A host that knows nothing about this package still gets a usable
      // palette — never a null, never a crash on the key list.
      expect(resolved.healthy, KeyAdminPalette.fallback.healthy);
      expect(resolved.danger, KeyAdminPalette.fallback.danger);
    });

    testWidgets('a host palette overrides the fallback', (tester) async {
      const hostPalette = KeyAdminPalette(
        healthy: Color(0xFF43E0A0),
        attention: Color(0xFFFFB545),
        danger: Color(0xFFFF5D6C),
      );
      late KeyAdminPalette resolved;
      await tester.pumpWidget(
        _probe(
          ThemeData(extensions: const <ThemeExtension<dynamic>>[hostPalette]),
          (p) => resolved = p,
        ),
      );

      expect(resolved.healthy, const Color(0xFF43E0A0));
      expect(resolved.attention, const Color(0xFFFFB545));
    });

    test('copyWith replaces one tone and keeps the rest', () {
      const base = KeyAdminPalette.fallback;
      final next = base.copyWith(danger: const Color(0xFF000000));

      expect(next.danger, const Color(0xFF000000));
      expect(next.healthy, base.healthy);
      expect(next.attention, base.attention);
    });

    test('lerp reaches both endpoints', () {
      const a = KeyAdminPalette.fallback;
      const b = KeyAdminPalette(
        healthy: Color(0xFF000000),
        attention: Color(0xFF111111),
        danger: Color(0xFF222222),
      );

      expect(a.lerp(b, 0).healthy, a.healthy);
      expect(a.lerp(b, 1).healthy, b.healthy);
    });
  });
}
