import 'dart:convert';

import 'package:admin_api_key_manager/models/free_source.dart';
import 'package:admin_api_key_manager/screens/admin_free_models_screen.dart';
import 'package:admin_api_key_manager/services/free_model_discovery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';

/// A catalog shaped like OpenRouter's real answer: hundreds of entries, long
/// descriptions, free and paid mixed, a couple of odd ids. The screen has to
/// survive this without an exception — a build/layout failure here is
/// invisible in a release build (it clips or paints a bare box) and was
/// reported from the phone as "the free-model screen is broken".
String _catalog(int count) {
  final data = <Map<String, dynamic>>[];
  for (var i = 0; i < count; i++) {
    final free = i % 3 != 0;
    data.add({
      'id': free ? 'vendor$i/model-$i:free' : 'vendor$i/model-$i',
      'name': 'Model $i',
      'description': 'A very long description for model $i. ' * 4,
      'context_length': 4096 + i * 1000,
      'pricing': {
        'prompt': free ? '0' : '0.000001',
        'completion': free ? '0' : '0.000002',
      },
    });
  }
  // Shapes that a hand-written parser tends to assume away.
  data.add({
    'id': 'bare-id',
    'name': 'No provider prefix',
    'pricing': {'prompt': '0', 'completion': '0'},
  });
  data.add({'id': 'x/no-pricing'});
  return jsonEncode({'data': data});
}

Widget _app(Widget child) => MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6366F1), brightness: Brightness.light),
        useMaterial3: true,
      ),
      home: child,
    );

FreeModelDiscovery _fakeCatalog(int count) => FreeModelDiscovery(
      client: MockClient((_) async => http.Response(_catalog(count), 200)),
    );

void main() {
  testWidgets('a 400-model catalog renders one finite page, not forever',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final discovery = _fakeCatalog(400);
    addTearDown(discovery.close);

    await tester.pumpWidget(_app(AdminFreeModelsScreen(discovery: discovery)));
    await tester.pump(); // let the FutureBuilder resolve
    await tester.pump();

    expect(tester.takeException(), isNull);

    // The header must be on screen: if the body failed to build, only the
    // app bar survives and everything below it stays blank.
    expect(find.text('Free models'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);

    // Scrolling must be bounded: an unbounded extent is what "it scrolls
    // forever and never reaches the end" looks like from the outside.
    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scrollable.position.maxScrollExtent.isFinite, isTrue);
    expect(scrollable.position.maxScrollExtent, greaterThan(0));

    // The end of the page offers the rest instead of an endless list.
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();
    expect(tester.takeException(), isNull);
    final showMore = find.textContaining('Show more');
    expect(showMore, findsOneWidget);

    // Tapping it must not throw: the next page is appended, not re-fetched.
    await tester.ensureVisible(showMore);
    await tester.pump();
    await tester.tap(showMore);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a 1 MB exception cannot turn the error state into a grey wall',
      (tester) async {
    // The regression: a failed fetch whose exception carries the whole response
    // body was rendered in full inside a non-scrollable Column. Measured on a
    // 353dp phone that Column wanted 1,112,028 px of height — the screen became
    // a blank wall you could scroll forever.
    for (final width in [320.0, 353.0, 390.0]) {
      tester.view.physicalSize = Size(width * 2, 780 * 2);
      tester.view.devicePixelRatio = 2.0;

      final discovery = FreeModelDiscovery(
        client: MockClient((_) async => throw Exception('x' * 1000000)),
      );
      await tester
          .pumpWidget(_app(AdminFreeModelsScreen(discovery: discovery)));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'width $width');
      expect(find.text('Could not load catalog'), findsOneWidget,
          reason: 'width $width');
      expect(find.text('Retry'), findsOneWidget, reason: 'width $width');
      expect(find.text('Copy details'), findsOneWidget, reason: 'width $width');
      expect(find.textContaining('more characters'), findsOneWidget,
          reason: 'width $width');

      // Nothing huge may reach a Text widget: that is the whole point.
      final longest = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => (t.data ?? '').length)
          .fold<int>(0, (a, b) => a > b ? a : b);
      expect(longest, lessThan(400), reason: 'width $width');
      discovery.close();
    }
    tester.view.reset();
  });

  testWidgets('the app-bar title row fits a narrow phone', (tester) async {
    // The premium app bar puts a 36dp badge next to a title + a full-sentence
    // subtitle. Without a flex child, that row overflowed by 32px at 390dp —
    // clipped and invisible in a release build.
    for (final width in [320.0, 360.0, 390.0, 412.0]) {
      tester.view.physicalSize = Size(width * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;

      final discovery = _fakeCatalog(20);
      await tester
          .pumpWidget(_app(AdminFreeModelsScreen(discovery: discovery)));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'width $width');
      expect(find.text('Free models'), findsOneWidget, reason: 'width $width');
      discovery.close();
    }
    tester.view.reset();
  });

  testWidgets('the Free sources tab answers even when the catalog fails',
      (tester) async {
    // The directory is static data: when OpenRouter is down or the phone is
    // offline, "where do I get a free key?" must still have an answer.
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final discovery = FreeModelDiscovery(
      client: MockClient((_) async => http.Response('nope', 500)),
    );
    addTearDown(discovery.close);

    await tester.pumpWidget(_app(AdminFreeModelsScreen(discovery: discovery)));
    await tester.pump();
    await tester.pump();
    expect(find.text('Could not load catalog'), findsOneWidget);

    await tester.tap(find.text('Free sources'));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('OpenRouter'), findsWidgets);
    expect(find.text('Google AI Studio'), findsOneWidget);
    expect(find.textContaining('Get key'), findsWidgets);
    // The relay warning is part of the directory, not an optional extra.
    expect(find.textContaining('RELAY'), findsWidgets);
    // The trickier entries further down the list: gateways are still listed,
    // and the daily-token pill is covered by test/free_source_test.dart.
    expect(find.textContaining('of ${kFreeSources.length} sources'),
        findsOneWidget);
  });

  testWidgets('the sources tab filters to first-party providers',
      (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final discovery = _fakeCatalog(10);
    addTearDown(discovery.close);

    await tester.pumpWidget(_app(AdminFreeModelsScreen(discovery: discovery)));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Free sources'));
    await tester.pump();

    await tester.tap(find.text('First-party only'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField).last, 'nararouter');
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('No models match'), findsNothing);
  });

  testWidgets('search filters the list in place', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final discovery = _fakeCatalog(30);
    addTearDown(discovery.close);

    await tester.pumpWidget(_app(AdminFreeModelsScreen(discovery: discovery)));
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'model-1');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
