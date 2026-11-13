import 'package:admin_api_key_manager/models/admin_api_key.dart';
import 'package:admin_api_key_manager/models/admin_key_group.dart';
import 'package:admin_api_key_manager/services/api_key_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';

/// Per-provider settings for the key pool, stored in Firestore
/// `admin_key_groups` (doc id = provider).
///
/// This existed as data and as behaviour — `ApiKeyManager` has always read
/// `enabled`, `priority` and the three cooldown overrides — but there was no
/// way to write it short of the Firestore console. Getting a cooldown wrong by
/// hand is silent: too short and a dead key is retried, too long and a healthy
/// provider sits unused.
///
/// Nothing here is written on open. A group doc is created the first time an
/// admin actually changes something, so a fresh project never grows three empty
/// documents that look like configuration.
class AdminKeyGroupsScreen extends StatelessWidget {
  /// Collection name override — must match [ApiKeyManager.groupsCollection].
  final String collection;

  const AdminKeyGroupsScreen({super.key, this.collection = 'admin_key_groups'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Provider groups'), centerTitle: false),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection(collection).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _GroupsError(error: snap.error);
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final stored = {
            for (final doc in snap.data!.docs)
              doc.id: AdminKeyGroup.fromMap(doc.data(), doc.id),
          };

          // Every provider the package knows about, stored or not — an admin
          // should see that `custom` exists and is enabled by default.
          const providers = ['openrouter', 'google', 'custom'];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                'Lower priority wins: keys from the best-ranked enabled group '
                'carry the load, the rest wait in reserve. Cooldowns are '
                'per-device and survive a restart.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
              ),
              const SizedBox(height: 12),
              for (final provider in providers)
                _GroupCard(
                  key: ValueKey(provider),
                  group: stored[provider] ??
                      AdminKeyGroup(
                        provider: provider,
                        name: AdminApiKey.providerName(provider),
                      ),
                  stored: stored.containsKey(provider),
                  collection: collection,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    super.key,
    required this.group,
    required this.stored,
    required this.collection,
  });

  final AdminKeyGroup group;
  final bool stored;
  final String collection;

  Future<void> _save(BuildContext context, AdminKeyGroup next) async {
    try {
      await FirebaseFirestore.instance
          .collection(collection)
          .doc(next.provider)
          .set(next.toMap(), SetOptions(merge: true));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${next.name} updated')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    }
  }

  Future<void> _editCooldowns(
      BuildContext context, AdminKeyGroup current) async {
    final next = await showModalBottomSheet<AdminKeyGroup>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CooldownSheet(group: current),
    );
    if (next == null || !context.mounted) return;
    await _save(context, next);
  }

  Future<void> _editPriority(
      BuildContext context, AdminKeyGroup current) async {
    final controller = TextEditingController(text: current.priority.toString());
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${current.name} priority'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Priority',
            helperText: 'Lower is tried first. 100 when unset.',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(dialogContext, int.tryParse(v)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, int.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !context.mounted) return;
    await _save(context, current.copyWith(priority: value));
  }

  String _cooldownSummary() {
    String part(int? value, String label) =>
        value == null ? '$label default' : '$label ${value}s';
    return [
      part(group.rateLimitCooldownSeconds, '429'),
      part(group.serverErrorCooldownSeconds, '5xx'),
      part(group.defaultCooldownSeconds, 'other'),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        group.enabled
                            ? 'Enabled · priority ${group.priority}'
                            : 'Disabled · all keys in this group are skipped',
                        style:
                            theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: group.enabled,
                  onChanged: (v) => _save(context, group.copyWith(enabled: v)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _cooldownSummary(),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _editPriority(context, group),
                  icon: const Icon(Icons.sort_outlined, size: 18),
                  label: const Text('Priority'),
                ),
                TextButton.icon(
                  onPressed: () => _editCooldowns(context, group),
                  icon: const Icon(Icons.timer_outlined, size: 18),
                  label: const Text('Cooldowns'),
                ),
                const Spacer(),
                if (!stored)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      'defaults',
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The three cooldown overrides. Empty means "use the built-in default", which
/// is distinct from 0 — 0 would retry a failing key immediately.
class _CooldownSheet extends StatefulWidget {
  const _CooldownSheet({required this.group});

  final AdminKeyGroup group;

  @override
  State<_CooldownSheet> createState() => _CooldownSheetState();
}

class _CooldownSheetState extends State<_CooldownSheet> {
  late final _rateCtrl = _controller(widget.group.rateLimitCooldownSeconds);
  late final _serverCtrl = _controller(widget.group.serverErrorCooldownSeconds);
  late final _otherCtrl = _controller(widget.group.defaultCooldownSeconds);

  TextEditingController _controller(int? value) =>
      TextEditingController(text: value?.toString() ?? '');

  @override
  void dispose() {
    _rateCtrl.dispose();
    _serverCtrl.dispose();
    _otherCtrl.dispose();
    super.dispose();
  }

  /// Empty field -> null (unset), so the built-in default applies.
  int? _read(TextEditingController c) {
    final text = c.text.trim();
    if (text.isEmpty) return null;
    final value = int.tryParse(text);
    if (value == null || value < 0) return null;
    return value;
  }

  String? _validate() {
    for (final c in [_rateCtrl, _serverCtrl, _otherCtrl]) {
      final text = c.text.trim();
      if (text.isEmpty) continue;
      final value = int.tryParse(text);
      if (value == null) return 'Cooldowns must be whole seconds';
      if (value < 0) return 'Cooldowns cannot be negative';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaults = {
      '429': 60,
      '5xx': 120,
      'other': 30,
    };

    Widget field(
      String label,
      String which,
      TextEditingController controller,
      String hint,
    ) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: label,
            hintText: '$hint (built-in: ${defaults[which]}s)',
            helperText: 'Seconds. Leave empty to use the built-in value.',
            border: const OutlineInputBorder(),
          ),
        ),
      );
    }

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
            Text(
              '${widget.group.name} cooldowns',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'How long a key is left out after a failure. An auth failure is '
              'not on this list on purpose: a key the provider rejects is '
              'parked for a year rather than retried on a timer.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            field('Rate limit', '429', _rateCtrl, '60'),
            field('Server error', '5xx', _serverCtrl, '120'),
            field('Other failures', 'other', _otherCtrl, '30'),
            const SizedBox(height: 4),
            FilledButton(
              onPressed: () {
                final problem = _validate();
                if (problem != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(problem)),
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  widget.group.copyWith(
                    rateLimitCooldownSeconds: _read(_rateCtrl),
                    serverErrorCooldownSeconds: _read(_serverCtrl),
                    defaultCooldownSeconds: _read(_otherCtrl),
                  ),
                );
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('Save'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _GroupsError extends StatelessWidget {
  const _GroupsError({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text('Could not read the group settings.',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
