import 'package:admin_api_key_manager/screens/admin_free_models_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The package's screens must work under a host app that uses the framework's
/// material — `package:flutter/material.dart` — and not only under one that
/// migrated to `package:material_ui`.
///
/// Why this file exists. Commit 7767893 moved the admin screens' import to
/// `package:material_ui/material_ui.dart`. That package is a *separate copy* of
/// material: its `Text`, `TextStyle`, `ThemeData`, `Theme` and
/// `MaterialLocalizations` are different types from the framework's. The
/// package's own tests kept passing because they pumped `material_ui`'s
/// `MaterialApp`, so nothing noticed that a host on `flutter/material` was now
/// broken — and it was broken on the phone in the worst possible way:
///
///   Null check operator used on a null value
///   #0 MaterialLocalizations.of (material_ui/src/material_localizations.dart)
///   #1 TextFieldState._getEffectiveDecoration (material_ui/src/text_field.dart)
///
/// on *every* TextField, which is the whole of "adding a key does nothing,
/// testing a key does nothing, and Free models is a blank page".
///
/// So this test deliberately does the opposite of the other screen tests: it
/// builds the screens inside a **framework** `MaterialApp` with framework
/// localization delegates. If the package's imports ever drift back to
/// `material_ui` while the host apps are on `flutter/material`, the TextField
/// throws here instead of on a tester's phone.
///
/// It is a smoke test, not a golden: the screens read Firestore in initState
/// and that failure is expected and harmless — a rules/network failure renders
/// the error state, which is exactly the widget tree we want built.
Widget _hostApp(Widget home) => MaterialApp(
      // The delegates a real host app installs. Without them the framework's
      // MaterialLocalizations is absent and every TextField throws — which is the
      // failure this file guards against.
      localizationsDelegates: const [
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: home,
    );

void main() {
  testWidgets(
    'the Free models screen builds under a framework-material host',
    (tester) async {
      await tester.pumpWidget(_hostApp(const AdminFreeModelsScreen()));
      // A couple of frames: the catalog fetch is in flight and is allowed to
      // fail here (the test HttpClient answers 400). What matters is that the
      // build itself does not throw — a material-localizations mismatch throws
      // during build, not later.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      // The screen really did build, rather than failing into an error widget.
      expect(find.byType(Scaffold), findsWidgets);
    },
  );

  testWidgets('a TextField renders its decoration under that host', (
    tester,
  ) async {
    // The narrowest possible reproduction of the reported crash: the crash
    // lived in TextFieldState._getEffectiveDecoration, so one bare TextField in
    // a framework MaterialApp is enough to prove the types line up.
    await tester.pumpWidget(
      _hostApp(
        const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(hintText: 'paste a key'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('paste a key'), findsOneWidget);
  });
}
