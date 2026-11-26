import 'package:admin_api_key_manager/models/admin_api_key.dart';
import 'package:admin_api_key_manager/models/admin_key_group.dart';
import 'package:admin_api_key_manager/services/api_key_manager.dart';
import 'package:admin_api_key_manager/theme/key_admin_palette.dart';
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
    final theme = Theme.of(context);
    final palette = KeyAdminPalette.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [palette.accent, const Color(0xFF8B8CF8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                      color: palette.accent.withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 3)),
                ],
              ),
              child:
                  const Icon(Icons.tune_rounded, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Provider groups',
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                Text('Priority & cooldowns per provider',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection(collection).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _GroupsError(error: snap.error);
          }
          if (!snap.hasData) {
            return Center(
                child: CircularProgressIndicator(
                    strokeWidth: 3, color: palette.accent));
          }

          final stored = {
            for (final doc in snap.data!.docs)
              doc.id: AdminKeyGroup.fromMap(doc.data(), doc.id),
          };

          // Every provider the package knows about, stored or not — an admin
          // should see that `custom` exists and is enabled by default.
          const providers = ['openrouter', 'google', 'custom'];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: palette.accentSoft,
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: palette.accent.withValues(alpha: 0.14)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: palette.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.info_outline_rounded,
                          size: 16, color: palette.accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Lower priority wins. Enabled groups carry the load, the rest wait in reserve. Cooldowns survive restart.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
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
        SnackBar(
            content: Text('${next.name} updated'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Update failed: $e'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
      );
    }
  }

  Future<void> _editCooldowns(
      BuildContext context, AdminKeyGroup current) async {
    final next = await showModalBottomSheet<AdminKeyGroup>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('${current.name} priority',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Priority',
            helperText: 'Lower is tried first. 100 when unset.',
            filled: true,
            fillColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.5),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.5))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: KeyAdminPalette.of(context).accent, width: 1.4)),
          ),
          onSubmitted: (v) => Navigator.pop(dialogContext, int.tryParse(v)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: KeyAdminPalette.of(context).accent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            onPressed: () =>
                Navigator.pop(dialogContext, int.tryParse(controller.text)),
            child: const Text('Save',
                style: TextStyle(fontWeight: FontWeight.w700)),
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
    final palette = KeyAdminPalette.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    final (IconData icon, List<Color> grad) = switch (group.provider) {
      'google' => (
          Icons.auto_awesome_rounded,
          [const Color(0xFF4285F4), const Color(0xFF8AB4F8)]
        ),
      'openrouter' => (
          Icons.alt_route_rounded,
          [palette.accent, const Color(0xFF8B8CF8)]
        ),
      _ => (
          Icons.lan_rounded,
          [theme.colorScheme.secondary, theme.colorScheme.tertiary]
        ),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4)),
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 32,
              offset: const Offset(0, 8)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
              height: 3,
              color: group.enabled
                  ? palette.healthy
                  : theme.colorScheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: grad,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                              color: grad.first.withValues(alpha: 0.22),
                              blurRadius: 10,
                              offset: const Offset(0, 3)),
                        ],
                      ),
                      child: Icon(icon, size: 20, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                group.name,
                                style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.2),
                              ),
                              const SizedBox(width: 8),
                              if (!stored)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme
                                        .colorScheme.surfaceContainerHighest
                                        .withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('defaults',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                              color: muted,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 10)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            group.enabled
                                ? 'Enabled · priority ${group.priority}'
                                : 'Disabled · all keys skipped',
                            style: theme.textTheme.labelSmall?.copyWith(
                                color:
                                    group.enabled ? palette.healthyText : muted,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    Transform.scale(
                      scale: 0.88,
                      child: Switch(
                        value: group.enabled,
                        onChanged: (v) =>
                            _save(context, group.copyWith(enabled: v)),
                        thumbColor: WidgetStateProperty.resolveWith((s) =>
                            s.contains(WidgetState.selected)
                                ? palette.healthy
                                : null),
                        trackColor: WidgetStateProperty.resolveWith((s) =>
                            s.contains(WidgetState.selected)
                                ? palette.healthy.withValues(alpha: 0.22)
                                : null),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.timer_outlined,
                          size: 14, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _cooldownSummary(),
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                    height: 1,
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.45)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _editPriority(context, group),
                      icon: const Icon(Icons.sort_rounded, size: 16),
                      label: const Text('Priority',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: () => _editCooldowns(context, group),
                      icon: const Icon(Icons.timer_outlined, size: 16),
                      label: const Text('Cooldowns',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
    final palette = KeyAdminPalette.of(context);
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
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: label,
            hintText: '$hint (built-in: ${defaults[which]}s)',
            helperText: 'Seconds. Leave empty to use the built-in value.',
            prefixIcon: Icon(Icons.timer_outlined,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.45),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.5))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.45))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: palette.accent, width: 1.4)),
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
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: palette.accent.withValues(alpha: 0.18)),
                  ),
                  child: Icon(Icons.timer_rounded,
                      color: palette.accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.group.name} cooldowns',
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800, letterSpacing: -0.3),
                        ),
                        Text('How long a key is paused after failure',
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600)),
                      ]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.35)),
              ),
              child: Text(
                'Auth failures are not here on purpose: a rejected key is parked for a year, not retried on a timer.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant, height: 1.45),
              ),
            ),
            const SizedBox(height: 16),
            field('Rate limit', '429', _rateCtrl, '60'),
            field('Server error', '5xx', _serverCtrl, '120'),
            field('Other failures', 'other', _otherCtrl, '30'),
            const SizedBox(height: 4),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                final problem = _validate();
                if (problem != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(problem),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
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
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('Save',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, letterSpacing: 0.2)),
                ],
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
    final palette = KeyAdminPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: palette.danger.withValues(alpha: 0.10),
                shape: BoxShape.circle,
                border:
                    Border.all(color: palette.danger.withValues(alpha: 0.18)),
              ),
              child: Icon(Icons.cloud_off_rounded,
                  size: 32, color: palette.danger),
            ),
            const SizedBox(height: 16),
            Text('Could not read groups',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.5)),
              ),
              child: Text(
                '$error',
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
