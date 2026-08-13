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
  final _baseUrlCtrl =
      TextEditingController(text: 'https://openrouter.ai/api/v1');
  final _modelCtrl = TextEditingController(text: 'gpt-4o-mini');
  String _provider = 'custom';
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

  Future<void> _deleteKey(AdminApiKey k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete key?'),
        content: Text('Delete "${k.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
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

  void _showForm({AdminApiKey? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
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
              TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
              TextField(controller: _keyCtrl, decoration: const InputDecoration(labelText: 'API Key')),
              TextField(controller: _baseUrlCtrl, decoration: const InputDecoration(labelText: 'Base URL')),
              TextField(controller: _modelCtrl, decoration: const InputDecoration(labelText: 'Model')),
              DropdownButtonFormField<String>(
                initialValue: _provider,
                items: const [
                  DropdownMenuItem(value: 'custom', child: Text('Custom')),
                  DropdownMenuItem(value: 'openrouter', child: Text('OpenRouter')),
                  DropdownMenuItem(value: 'google', child: Text('Google AI Studio')),
                ],
                onChanged: (v) => setState(() => _provider = v ?? 'custom'),
                decoration: const InputDecoration(labelText: 'Provider'),
              ),
              TextFormField(
                initialValue: _priority.toString(),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Priority (lower = tried first)'),
                onChanged: (v) => _priority = int.tryParse(v) ?? 1,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _saveKey(existing);
                },
                child: Text(existing != null ? 'Save changes' : 'Add key'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _clearForm() {
    _nameCtrl.clear();
    _keyCtrl.clear();
    _baseUrlCtrl.text = 'https://openrouter.ai/api/v1';
    _modelCtrl.text = 'gpt-4o-mini';
    _provider = 'custom';
    _priority = 1;
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API Keys')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _col.orderBy('priority').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
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
              return ListTile(
                title: Text(k.name),
                subtitle: Text('${k.provider} • ${k.model} • pri ${k.priority}'),
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
              );
            },
          );
        },
      ),
    );
  }
}
