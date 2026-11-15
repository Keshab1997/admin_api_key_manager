// The one file in tool/screenshots/ that belongs to THIS project.
//
// The installer writes this once, only when it is missing, and never touches it
// again - everything else in this directory is replaced by the pack. So: edit
// it freely, commit it, and treat it as app code.
//
// WHY THIS FILE IS STILL EMPTY HERE
//
// The three admin screens (AdminApiKeysScreen, AdminKeyGroupsScreen,
// AdminErrorLogsScreen) read `FirebaseFirestore.instance` in initState, so a
// widget test has to hand them an in-memory Firestore. `fake_cloud_firestore`
// is the usual way, and it does not fit this package: its latest release (4.5.0)
// targets cloud_firestore_platform_interface 4.x, while this package resolves
// cloud_firestore 6.x (platform interface 8.x) because the constraint is
// deliberately wide - pinning Firestore down to 5.x to make screenshots work
// would defeat the reason the constraint is wide. So the screenshot tool is
// installed and working, with nothing to photograph yet.
//
// Two ways out, both a decision rather than a chore:
//   * add a tiny fake of the three calls the screens make (collection, snapshots,
//     doc.set/update) behind an injection point, then register the shots; or
//   * wait for a fake_cloud_firestore release that supports platform interface 8.
// Until then `test/admin_groups_screen_test.dart` keeps saying the same thing:
// the shape is asserted, the pump is not.
//
// It has to compile in a project that has just installed the pack, which is why
// the shot list starts empty and the env is a placeholder. Fill both in:
//
//   1. env - the app's real theme (the same function main() gives MaterialApp),
//      the font files it ships, the MethodChannel it talks to Kotlin/Java on,
//      and whatever its widget tests have to initialise first (Hive, a clock).
//   2. shots - one entry per screen worth looking at, named in kebab-case.
//
// A worked example, from a real project:
//
//   final ShotEnv env = ShotEnv(
//     // The app's real shell. Note it is *your* import of Material/Cupertino:
//     // the pack names neither, because Flutter's material move makes
//     // package:flutter/material.dart and package:material_ui/material_ui.dart
//     // different ThemeData types.
//     app: (shot, home) => MaterialApp(
//       theme: shot.dark ? AppTheme.dark() : AppTheme.light(),
//       home: home,
//     ),
//     wrap: (child) => ProviderScope(child: child),
//     fontAssets: const <String, String>{
//       'Inter': 'assets/fonts/Inter-Variable.ttf',
//     },
//     bridgeChannel: AppConstants.channelName,
//     bridgeAnswers: const <String, Object?>{
//       'isListenerEnabled': false,
//       'overlayGranted': false,
//     },
//     setUpAll: () async {
//       Hive.init(Directory.systemTemp.createTempSync('shots').path);
//     },
//   );
//
//   final List<Shot> shots = <Shot>[
//     Shot(name: 'home', build: () => const HomeScreen()),
//     Shot(name: 'settings', build: () => const SettingsScreen()),
//     // The case that catches what a comfortable phone hides.
//     Shot(
//       name: 'settings-narrow',
//       build: () => const SettingsScreen(),
//       logicalSize: const Size(320, 1400),
//     ),
//   ];
import 'shot_framework.dart';

/// No shots yet - add the app's screens here.
final List<Shot> shots = <Shot>[];

/// A pass-through until you fill it in: with no app shell there is no theme, so
/// the first real shot needs the block in the comment above.
final ShotEnv env = ShotEnv(app: (shot, home) => home);
