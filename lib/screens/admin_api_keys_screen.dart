import 'package:admin_api_key_manager/models/admin_api_key.dart';
import 'package:admin_api_key_manager/services/api_key_manager.dart';
import 'package:admin_api_key_manager/screens/admin_bulk.dart';
import 'package:admin_api_key_manager/screens/admin_error_logs_screen.dart';
import 'package:admin_api_key_manager/screens/admin_free_models_screen.dart';
import 'package:admin_api_key_manager/screens/admin_key_groups_screen.dart';
import 'package:admin_api_key_manager/services/key_health_checker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';
import 'package:admin_api_key_manager/theme/key_admin_palette.dart';
import 'package:admin_api_key_manager/screens/widgets/admin_screen_widgets.dart';
export 'package:admin_api_key_manager/theme/key_admin_palette.dart';

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
///
/// Visual language, in one place so a host app can override it:
/// - every colour comes from `ColorScheme`, never a hard-coded hue, so the
///   screen follows whichever theme (and seed colour) the app installs;
/// - [KeyAdminPalette] is the one exception — a `ThemeExtension` carrying the
///   three *state* colours (healthy / attention / danger). Hosts that already
///   own a palette can register their own instance instead of this default;
/// - the state of a key is shown as a label + colour, never as colour alone:
///   docs redacted at a glance, and colour never carries meaning by itself.
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

  /// Revealed key ids. Empty by default: a captured screenshot or a shoulder
  /// behind you should not show a provider secret.
  final Set<String> _revealed = {};

  AdminKeyFilter _filter = AdminKeyFilter.all;

  /// The rows as last rendered. The app-bar bulk menu and the reorder action
  /// act on the whole pool, not on the filtered view — "disable all keys" must
  /// not quietly mean "all the ones that happen to be visible".
  List<AdminKeyRow> _rows = const [];

  /// Drag-to-reorder rewrites `priority` on every row, so it is a mode: an
  /// accidental drag on a normal list would silently reorder failover.
  bool _reordering = false;
  List<AdminKeyRow> _dragRows = const [];

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

    final baseUrl = _baseUrlCtrl.text.trim();
    final model = _modelCtrl.text.trim();
    final problem =
        _validate(provider: _provider, baseUrl: baseUrl, model: model);
    if (problem != null) {
      _toast(problem);
      return;
    }

    final data = {
      'name': name,
      'key': key,
      'baseUrl': baseUrl,
      'model': model,
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

  /// Catches the two mistakes that otherwise only surface as a 404 from the
  /// provider later: a missing API version on Gemini, and a bare model name on
  /// OpenRouter (it addresses models as `provider/model`).
  String? _validate({
    required String provider,
    required String baseUrl,
    required String model,
  }) {
    if (baseUrl.isEmpty) return 'Base URL is required';
    if (model.isEmpty) return 'Model is required';
    if (!baseUrl.startsWith('https://')) {
      return 'Base URL must start with https://';
    }
    if (provider == 'google' && !RegExp(r'/v\d').hasMatch(baseUrl)) {
      return 'Google needs the API version in the URL, e.g. …/v1beta';
    }
    if (baseUrl.contains('openrouter') && !model.contains('/')) {
      final fixed = resolveOpenRouterModel(baseUrl, model);
      return fixed == model
          ? 'OpenRouter needs a provider/model id, e.g. openai/gpt-4o-mini'
          : 'OpenRouter needs a provider/model id — did you mean "$fixed"?';
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
    final detail = switch (status) {
      200 => 'Connected successfully (HTTP 200).',
      401 || 403 => 'The provider rejected this key (HTTP $status). It may be '
          'revoked or from another project.',
      429 => 'Rate limited (HTTP 429). The key works but is over its quota.',
      0 => 'Could not reach the provider: network, timeout or bad URL.',
      _ => 'Failed with HTTP $status.',
    };
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Test: ${k.name}'),
        content: Text(detail),
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
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final theme = Theme.of(context);
          final defaults = AdminApiKey.defaultsFor(_provider);
          final urlIsCustom =
              defaults != null && _baseUrlCtrl.text.trim() != defaults.baseUrl;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              left: 20,
              right: 20,
              top: 4,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(existing != null ? 'Edit API key' : 'Add API key',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    _provider == 'custom'
                        ? 'Any endpoint that speaks /chat/completions.'
                        : 'These are stored in Firestore and read by every '
                            'device. Use a key you can rotate.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'Primary OpenRouter',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _keyCtrl,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'API key',
                      hintText: 'sk-or-…',
                      border: OutlineInputBorder(),
                      helperText: 'Hidden while typing. Test it before saving.',
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Provider first: it decides what the two fields below
                  // should contain, so choosing it afterwards reads backwards.
                  DropdownButtonFormField<String>(
                    initialValue: _provider,
                    decoration: const InputDecoration(
                      labelText: 'Provider',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'openrouter', child: Text('OpenRouter')),
                      DropdownMenuItem(
                          value: 'google', child: Text('Google AI Studio')),
                      DropdownMenuItem(
                          value: 'custom',
                          child: Text('Custom (OpenAI-compatible)')),
                    ],
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
                  const SizedBox(height: 12),

                  TextField(
                    controller: _baseUrlCtrl,
                    onChanged: (_) => setSheetState(() {}),
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'Base URL',
                      border: const OutlineInputBorder(),
                      helperText: _provider == 'google'
                          ? 'Include the API version, e.g. …/v1beta'
                          : _provider == 'custom'
                              ? 'Any endpoint serving /chat/completions'
                              : null,
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: _modelCtrl,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Model',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    initialValue: _priority.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Priority',
                      helperText: 'Lower is tried first.',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => _priority = int.tryParse(v) ?? 1,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _saveKey(existing);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child:
                          Text(existing != null ? 'Save changes' : 'Add key'),
                    ),
                  ),
                  const SizedBox(height: 8),
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

  // ── Bulk actions + reorder ──

  Future<void> _bulk(String action) async {
    final all = _rows.map((r) => r.key).toList();
    late final List<AdminApiKey> targets;
    late final String question;

    switch (action) {
      case 'enable':
        targets = keysToEnable(all);
        question = 'Enable ${targets.length} disabled key(s)?';
      case 'disable':
        targets = keysToDisable(all);
        question = 'Disable ${targets.length} active key(s)? No AI call will '
            'use them until you turn them back on.';
      case 'delete':
        targets = keysSafeToDelete(all);
        question = 'Permanently delete ${targets.length} disabled key(s) that '
            'have recorded errors? This cannot be undone.';
      default:
        return;
    }

    if (targets.isEmpty) {
      _toast(switch (action) {
        'enable' => 'Every key is already enabled.',
        'disable' => 'Every key is already disabled.',
        _ => 'No disabled key has errors, so nothing was deleted.',
      });
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(switch (action) {
          'enable' => 'Enable all?',
          'disable' => 'Disable all?',
          _ => 'Delete keys?',
        }),
        content: Text(question),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action == 'delete' ? 'Delete' : 'Yes'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      switch (action) {
        case 'enable':
          await setActive(_col, targets, isActive: true);
        case 'disable':
          await setActive(_col, targets, isActive: false);
        case 'delete':
          await deleteKeys(_col, targets);
      }
      _toast('${targets.length} key(s) updated');
    } catch (e) {
      _toast('Bulk update failed: $e');
    }
  }

  Future<void> _saveReorder(List<AdminKeyRow> current) async {
    final order = _dragRows.isEmpty ? current : _dragRows;
    // Renumber from 1 across the whole pool, so the numbers stay a clean order
    // rather than drifting upward every time something is dragged.
    final assignments = priorityAssignments(order.map((r) => r.key).toList());
    if (assignments.isEmpty) {
      setState(() {
        _reordering = false;
        _dragRows = const [];
      });
      _toast('Order unchanged');
      return;
    }
    try {
      await applyPriorities(_col, assignments);
      if (!mounted) return;
      setState(() {
        _reordering = false;
        _dragRows = const [];
      });
      _toast('Failover order saved');
    } catch (e) {
      _toast('Could not save the order: $e');
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // ── Rendering ──

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('API keys'),
        centerTitle: false,
        titleTextStyle:
            theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        actions: [
          IconButton(
            tooltip: 'Error log',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminErrorLogsScreen(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Provider groups',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminKeyGroupsScreen(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Free models',
            icon: const Icon(Icons.explore_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminFreeModelsScreen(),
              ),
            ),
          ),
          if (_rows.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Bulk actions',
              icon: const Icon(Icons.more_vert),
              onSelected: (value) => _bulk(value),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'enable', child: Text('Enable all keys')),
                PopupMenuItem(
                    value: 'disable', child: Text('Disable all keys')),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete erroring disabled keys'),
                ),
              ],
            ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddForm,
        icon: const Icon(Icons.add),
        label: const Text('Add key'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _col.orderBy('priority').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return AdminErrorState(error: snap.error);
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data!.docs
              .map((doc) => AdminApiKey.fromMap(doc.data(), doc.id))
              .map((key) => AdminKeyRow(
                    key: key,
                    onCooldownUntil: _cooldownUntil(key.id),
                  ))
              .toList();

          // Kept in a field because the app-bar bulk menu and the reorder
          // action operate on the pool, not on the current filter.
          _rows = rows;

          if (_reordering) {
            return AdminReorderView(
              rows: _dragRows.isEmpty ? rows : _dragRows,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  final list = List<AdminKeyRow>.from(
                      _dragRows.isEmpty ? rows : _dragRows);
                  if (newIndex > oldIndex) newIndex -= 1;
                  final moved = list.removeAt(oldIndex);
                  list.insert(newIndex, moved);
                  _dragRows = list;
                });
              },
              onSave: () => _saveReorder(rows),
              onCancel: () => setState(() {
                _reordering = false;
                _dragRows = const [];
              }),
            );
          }

          final visible = _applyFilter(rows);
          final broken = rows.where((r) => r.key.errorCount > 0).length;

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: AdminSummary(
                  total: rows.length,
                  active: rows.where((r) => r.key.isActive).length,
                  trouble: broken,
                  filter: _filter,
                  onFilter: (f) => setState(() => _filter = f),
                ),
              ),
              if (rows.length > 1)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() {
                          _reordering = true;
                          _dragRows = rows;
                        }),
                        icon: const Icon(Icons.swap_vert, size: 18),
                        label: const Text('Reorder failover'),
                      ),
                    ),
                  ),
                ),
              if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AdminEmptyState(
                    filtered: rows.isNotEmpty,
                    onClearFilter: () =>
                        setState(() => _filter = AdminKeyFilter.all),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  sliver: SliverList.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => AdminKeyCard(
                      row: visible[i],
                      revealed: _revealed.contains(visible[i].key.id),
                      onReveal: () => setState(() {
                        final id = visible[i].key.id;
                        _revealed.contains(id)
                            ? _revealed.remove(id)
                            : _revealed.add(id);
                      }),
                      onTest: () => _testConnection(visible[i].key),
                      onEdit: () => _edit(visible[i].key),
                      onDelete: () => _deleteKey(visible[i].key),
                      onToggle: (v) => _toggleActive(visible[i].key, v),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Cooldown end for this key, if the manager knows of one. Read-only: the
  /// manager stays the owner of that state.
  DateTime? _cooldownUntil(String keyId) =>
      ApiKeyManager.instance.cooldownUntil(keyId);

  List<AdminKeyRow> _applyFilter(List<AdminKeyRow> rows) {
    switch (_filter) {
      case AdminKeyFilter.all:
        return rows;
      case AdminKeyFilter.active:
        return rows.where((r) => r.key.isActive).toList();
      case AdminKeyFilter.trouble:
        return rows
            .where((r) =>
                r.key.errorCount > 0 || !r.key.isActive || r.isOnCooldown)
            .toList();
    }
  }
}
