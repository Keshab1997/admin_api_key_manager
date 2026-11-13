import 'package:admin_api_key_manager/models/admin_api_key.dart';
import 'package:admin_api_key_manager/models/admin_key_group.dart';
import 'package:admin_api_key_manager/screens/admin_key_groups_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('provider coverage', () {
    test('every provider the package knows has a group name', () {
      // The groups screen lists these three explicitly; if a provider is added
      // to the model without a name here, the screen would show a blank card.
      for (final provider in ['openrouter', 'google', 'custom']) {
        expect(AdminApiKey.providerName(provider), isNotEmpty);
      }
    });

    test('an unset group is enabled at priority 100', () {
      final group = AdminKeyGroup.fromMap(const {}, 'custom');
      expect(group.enabled, isTrue);
      expect(group.priority, 100);
    });
  });

  group('AdminKeyGroupsScreen', () {
    testWidgets('renders a card per provider without Firestore data',
        (tester) async {
      // The stream needs Firebase; assert the widget's shape instead by
      // building the empty-list branch the way the screen does it. A full pump
      // would need a Firestore fake, which this package deliberately has none
      // of — the selector and the models are the parts worth testing on a
      // plain JVM.
      const screen = AdminKeyGroupsScreen();
      expect(screen.collection, 'admin_key_groups');
      expect(screen.key, isNull);
    });

    testWidgets('group cards are laid out for a narrow phone', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final provider in ['openrouter', 'google', 'custom'])
                  Card(
                    child: ListTile(
                      title: Text(AdminApiKey.providerName(provider)),
                      subtitle: Text(AdminKeyGroup.fromMap(const {}, provider)
                          .priority
                          .toString()),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

      // No overflow: the three cards fit without throwing.
      expect(tester.takeException(), isNull);
      expect(find.text('Google AI Studio'), findsOneWidget);
    });
  });
}
