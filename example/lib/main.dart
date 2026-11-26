import 'package:material_ui/material_ui.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:admin_api_key_manager/admin_api_key_manager.dart';

// Replace with your Firebase options (flutterfire configure) or pass
// DefaultFirebaseOptions.currentPlatform from firebase_options.dart
// import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // await Firebase.initializeApp(
  //   options: DefaultFirebaseOptions.currentPlatform,
  // );
  await Firebase.initializeApp();
  await Hive.initFlutter();

  // ApiKeyManager opens its own Hive box; calling KeyCache.init() first
  // is optional but harmless.
  await ApiKeyManager.instance.initialize();

  // Optional: push when every key is exhausted.
  ApiKeyManager.instance.onAllKeysFailed = (count, message) {
    debugPrint('[example] $message');
  };

  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Admin Keys — Example',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1B6EF3),
        useMaterial3: true,
        extensions: const <ThemeExtension<dynamic>>[
          KeyAdminPalette.fallback,
        ],
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('admin_api_key_manager — example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'This tiny host app shows how a real app wires the package.\n'
            'Gate the admin screens behind your own auth check — this example '
            'leaves that gate out so you can run it without users.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.key),
            label: const Text('Open Admin API Keys'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdminApiKeysScreen()),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.group),
            label: const Text('Open Provider Groups'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdminKeyGroupsScreen()),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.bug_report),
            label: const Text('Open Error Logs'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdminErrorLogsScreen()),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          FutureBuilder<AdminApiKey?>(
            future: () async {
              await ApiKeyManager.instance.ensureReady();
              return ApiKeyManager.instance.getNextKey();
            }(),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const ListTile(
                  leading: CircularProgressIndicator(),
                  title: Text('Loading key pool…'),
                );
              }
              final key = snap.data;
              if (key == null) {
                return const ListTile(
                  leading: Icon(Icons.hourglass_empty),
                  title: Text('No healthy key'),
                  subtitle: Text('Add a key in the admin screen above.'),
                );
              }
              return ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: Text('Next key: ${key.name}'),
                subtitle: Text(
                    '${key.provider} • ${key.model} • pri ${key.priority}'),
              );
            },
          ),
        ],
      ),
    );
  }
}
