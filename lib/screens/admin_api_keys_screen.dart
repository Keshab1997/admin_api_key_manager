import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:admin_api_key_manager/models/admin_api_key.dart';
import 'package:admin_api_key_manager/services/api_key_manager.dart';
import 'package:admin_api_key_manager/services/key_health_checker.dart';

/// Minimal, self-contained admin screen for managing the Firestore-backed
/// API key pool. Drop it behind your own admin gate:
///
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute(
///   builder: (_) => const AdminApiKeysScreen(),
/// ));
/// ```
///
/// Requires the same Firestore rules as `ApiKeyManager` (admin write access to
/// the `admin_api_keys` collection).
class AdminApiKeysScreen extends StatefulWidget {
  /// Collection name override — must match [ApiKeyManager.keysCollection].
  final String collection;

  const AdminApiKeysScreen({super.key, this.collection = 'admin_api_keys'});

  @override
  State<AdminApiKeysScreen> createState() => _AdminApiKeysScreenState();
}

class _AdminApiKeysScreenState extends State<AdminApiKeysScreen> {
  final _nameCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  // Start on a real provider rather than 'custom' with OpenRouter's URL
  // already filled in — that combination said two different things at once.
  static const _initialProvider = 'openrouter';

  final _baseUrlCtrl = TextEditingController(
      text: AdminApiKey.providerDefaults[_initialProvider]!.baseUrl);
  final _modelCtrl = TextEditingController(
      text: AdminApiKey.providerDefaults[_initialProvider]!.model);
  String _provider = _initialProvider;
  int _priority = 1;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _keyCtrl.dispose();
    _baseUrlCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection(widget.collection);

  Future<void> _saveKey([AdminApiKey? existing]) async {
    final key = _keyCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (key.isEmpty || name.isEmpty) {
      _toast('Name and key are required');
      return;
    }
    final endpointError = _endpointError(_provider, _baseUrlCtrl.text.trim());
    final modelError = _modelError(_provider, _modelCtrl.text.trim());
    if (endpointError != null || modelError != null) {
      _toast(endpointError ?? modelError!);
      return;
    }
    final data = {
      'name': name,
      'key': key,
      'baseUrl': _baseUrlCtrl.text.trim(),
      'model': _modelCtrl.text.trim(),
      'provider': _provider,
      'isActive': true,
      'priority': _priority,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      if (existing != null) {
        await _col.doc(existing.id).update(data);
        _toast('Key updated');
      } else {
        await _col.add({
          ...data,
          'usageCount': 0,
          'errorCount': 0,
          'addedBy': '',
          'createdAt': FieldValue.serverTimestamp(),
        });
        _toast('Key added');
      }
      _clearForm();
    } catch (e) {
      _toast('Save failed: $e');
    }
  }

  String? _endpointError(String provider, String value) {
    final uri = Uri.tryParse(value);
    if (value.isEmpty || uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'Enter a valid HTTPS base URL.';
    }
    if (uri.scheme != 'https') return 'Base URL must use HTTPS.';
    if (provider == 'google' &&
        !value.contains('generativelanguage.googleapis.com')) {
      return 'Google AI Studio keys require the Google Generative Language URL.';
    }
    if (provider == 'openrouter' && !value.contains('openrouter.ai')) {
      return 'OpenRouter keys require an openrouter.ai base URL.';
    }
    return null;
  }

  String? _modelError(String provider, String value) {
    if (value.isEmpty) return 'Enter a model name.';
    if (provider == 'openrouter' && !value.contains('/')) {
      return 'OpenRouter models use provider/model format.';
    }
    if (provider == 'google' && value.contains('/')) {
      return 'Google model names should not contain a provider prefix.';
    }
    return null;
  }

  Future<void> _deleteKey(AdminApiKey k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete key?'),
        content: Text('Delete "${k.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _col.doc(k.id).delete();
      _toast('Key deleted');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  Future<void> _toggleActive(AdminApiKey k, bool value) async {
    try {
      await _col.doc(k.id).update({'isActive': value});
    } catch (e) {
      _toast('Update failed: $e');
    }
  }

  Future<void> _testConnection(AdminApiKey k) async {
    _toast('Testing ${k.name}…');
    final status = await pingKeyStatus(
      provider: k.provider,
      baseUrl: k.baseUrl,
      apiKey: k.key,
      model: k.model,
    );
    if (!mounted) return;
    final ok = status == 200;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Test: ${k.name}'),
        content: Text(ok
            ? 'Connected successfully (HTTP 200).'
            : 'Failed with HTTP $status.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  void _edit(AdminApiKey k) {
    _nameCtrl.text = k.name;
    _keyCtrl.text = k.key;
    _baseUrlCtrl.text = k.baseUrl;
    _modelCtrl.text = k.model;
    _provider = k.provider;
    _priority = k.priority;
    _showForm(existing: k);
  }

  /// Opens a blank form.
  ///
  /// The reset matters: the form's controllers are owned by the screen, so
  /// without it, opening "add" after editing a key shows that key's values —
  /// including its secret — and saving would silently clone it.
  void _showAddForm() {
    _clearForm();
    _showForm();
  }

  void _showForm({AdminApiKey? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // StatefulBuilder, not the screen's setState: the sheet is built once by
      // its own route, so calling setState on the parent leaves this subtree
      // untouched and the provider hint would never appear.
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final defaults = AdminApiKey.defaultsFor(_provider);
          final urlIsCustom =
              defaults != null && _baseUrlCtrl.text.trim() != defaults.baseUrl;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(existing != null ? 'Edit API Key' : 'Add API Key',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  TextField(
                    controller: _keyCtrl,
                    decoration: const InputDecoration(labelText: 'API Key'),
                  ),

                  // Provider first: it decides what the two fields below
                  // should contain, so choosing it afterwards reads backwards.
                  DropdownButtonFormField<String>(
                    initialValue: _provider,
                    items: const [
                      DropdownMenuItem(
                          value: 'openrouter', child: Text('OpenRouter')),
                      DropdownMenuItem(
                          value: 'google', child: Text('Google AI Studio')),
                      DropdownMenuItem(
                          value: 'custom',
                          child: Text('Custom (OpenAI-compatible)')),
                    ],
                    decoration: const InputDecoration(labelText: 'Provider'),
                    onChanged: (v) {
                      final provider = v ?? 'custom';
                      final changed = _applyProviderDefaults(provider);
                      setSheetState(() => _provider = provider);
                      setState(() {});
                      if (changed) {
                        _toast('Base URL and model set for '
                            '${AdminApiKey.providerName(provider)}');
                      }
                    },
                  ),
                  const SizedBox(height: 4),

                  TextField(
                    controller: _baseUrlCtrl,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Base URL',
                      helperText: _provider == 'google'
                          ? 'Google Generative Language API · HTTPS · /v1beta'
                          : _provider == 'openrouter'
                              ? 'OpenRouter HTTPS endpoint · /api/v1'
                              : 'Custom HTTPS endpoint serving /chat/completions',
                      errorText:
                          _endpointError(_provider, _baseUrlCtrl.text.trim()),
                      // Only offered when the admin has typed something of
                      // their own — never as a nag on the normal path.
                      suffixIcon: urlIsCustom
                          ? IconButton(
                              tooltip: 'Use the '
                                  '${AdminApiKey.providerName(_provider)} default',
                              icon: const Icon(Icons.restart_alt, size: 20),
                              onPressed: () {
                                _applyProviderDefaults(_provider, force: true);
                                setSheetState(() {});
                              },
                            )
                          : null,
                    ),
                  ),
                  TextField(
                    controller: _modelCtrl,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Model',
                      helperText: _provider == 'google'
                          ? 'Example: gemini-2.0-flash'
                          : _provider == 'openrouter'
                              ? 'Example: openai/gpt-4o-mini'
                              : 'Use the model name expected by your endpoint',
                      errorText: _modelError(_provider, _modelCtrl.text.trim()),
                    ),
                  ),

                  TextFormField(
                    initialValue: _priority.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Priority (lower = tried first)'),
                    onChanged: (v) => _priority = int.tryParse(v) ?? 1,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _saveKey(existing);
                    },
                    child: Text(existing != null ? 'Save changes' : 'Add key'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _clearForm() {
    _nameCtrl.clear();
    _keyCtrl.clear();
    _provider = _initialProvider;
    final defaults = AdminApiKey.providerDefaults[_initialProvider]!;
    _baseUrlCtrl.text = defaults.baseUrl;
    _modelCtrl.text = defaults.model;
    _priority = 1;
  }

  /// Applies a provider's endpoint and model when the dropdown changes.
  ///
  /// Only overwrites a field that is empty or still holds a known default —
  /// i.e. one this form filled in. An admin who typed their own proxy URL
  /// keeps it, and gets an explicit button instead; silently destroying that
  /// value would make the `custom` provider useless.
  ///
  /// Returns true when anything was changed, so the caller can say so.
  bool _applyProviderDefaults(String provider, {bool force = false}) {
    final defaults = AdminApiKey.defaultsFor(provider);
    if (defaults == null) return false; // 'custom' has nothing to apply

    var changed = false;

    if (force || AdminApiKey.isDefaultBaseUrl(_baseUrlCtrl.text)) {
      if (_baseUrlCtrl.text.trim() != defaults.baseUrl) {
        _baseUrlCtrl.text = defaults.baseUrl;
        changed = true;
      }
    }
    if (force || AdminApiKey.isDefaultModel(_modelCtrl.text)) {
      if (_modelCtrl.text.trim() != defaults.model) {
        _modelCtrl.text = defaults.model;
        changed = true;
      }
    }
    return changed;
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API Keys')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddForm,
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _col.orderBy('priority').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            final error = snap.error.toString();
            final permissionDenied = error.contains('permission-denied');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      permissionDenied
                          ? Icons.lock_outline
                          : Icons.error_outline,
                      size: 42,
                      color: permissionDenied ? Colors.amber : Colors.redAccent,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      permissionDenied
                          ? 'Admin permission required'
                          : 'Could not load API keys',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      permissionDenied
                          ? 'Sign in with an account that has the admin claim, then try again.'
                          : 'Check your connection and try again.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('No keys yet. Tap + to add one.'));
          }
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final k = AdminApiKey.fromMap(docs[i].data(), docs[i].id);
              final maskedKey = k.key.length > 8
                  ? '${k.key.substring(0, 4)}••••${k.key.substring(k.key.length - 4)}'
                  : '••••••••';
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: ListTile(
                  title: Row(
                    children: [
                      Expanded(
                          child: Text(k.name, overflow: TextOverflow.ellipsis)),
                      Chip(
                        label: Text(k.isActive ? 'Active' : 'Disabled'),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: k.isActive
                            ? Colors.green.withValues(alpha: .15)
                            : Colors.grey.withValues(alpha: .15),
                      ),
                    ],
                  ),
                  subtitle: Text(
                      '${k.provider} • ${k.model}\n$maskedKey • used ${k.usageCount} • errors ${k.errorCount}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.cable),
                          tooltip: 'Test connection',
                          onPressed: () => _testConnection(k)),
                      IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _edit(k)),
                      IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _deleteKey(k)),
                      Switch(
                        value: k.isActive,
                        onChanged: (v) => _toggleActive(k, v),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
