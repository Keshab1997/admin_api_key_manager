import 'package:material_ui/material_ui.dart';
import 'package:admin_api_key_manager/models/admin_api_key.dart';
import 'package:admin_api_key_manager/services/key_pool_errors.dart';
import 'package:admin_api_key_manager/theme/key_admin_palette.dart';

/// The read-only form of a key that the list needs: the live key plus the
/// manager's device-local view (cooldown) merged in.
class AdminKeyRow {
  const AdminKeyRow({required this.key, required this.onCooldownUntil});

  final AdminApiKey key;
  final DateTime? onCooldownUntil;

  bool get isOnCooldown =>
      onCooldownUntil != null && onCooldownUntil!.isAfter(DateTime.now());

  /// "Cooling down" alone hides the interesting part: an auth failure parks a
  /// key for a year, a rate limit for a minute.
  String get cooldownLabel {
    if (!isOnCooldown) return 'Cooling down';
    final left = onCooldownUntil!.difference(DateTime.now());
    if (left.inDays >= 300) return 'Rejected — parked';
    if (left.inDays >= 1) return 'Cooling down ${left.inDays}d';
    if (left.inHours >= 1) return 'Cooling down ${left.inHours}h';
    return 'Cooling down ${left.inMinutes + 1}m';
  }
}

enum AdminKeyFilter { all, active, trouble }

/// Drag-to-reorder, in its own mode with an explicit save.
///
/// Priorities are rewritten across the pool, so the change is shown before it
/// is committed: Cancel leaves Firestore untouched.
class AdminReorderView extends StatelessWidget {
  const AdminReorderView({
    super.key,
    required this.rows,
    required this.onReorder,
    required this.onSave,
    required this.onCancel,
  });

  final List<AdminKeyRow> rows;
  final void Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Drag to set which key is tried first. Positions become '
                  'priority 1, 2, 3… when you save.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: rows.length,
            onReorderItem: onReorder,
            itemBuilder: (context, i) {
              final row = rows[i];
              return Card(
                key: ValueKey(row.key.id),
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                color: theme.colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      '${i + 1}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(
                    row.key.name.isEmpty ? 'Untitled key' : row.key.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${AdminApiKey.providerName(row.key.provider)} · '
                    '${row.key.isActive ? 'enabled' : 'disabled'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.drag_handle),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: onSave,
                    child: const Text('Save order'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class AdminSummary extends StatelessWidget {
  const AdminSummary({
    super.key,
    required this.total,
    required this.active,
    required this.trouble,
    required this.filter,
    required this.onFilter,
  });

  final int total;
  final int active;
  final int trouble;
  final AdminKeyFilter filter;
  final ValueChanged<AdminKeyFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = KeyAdminPalette.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AdminStat(
                  value: '$active', label: 'active', tone: palette.healthy),
              const SizedBox(width: 8),
              AdminStat(
                value: '$trouble',
                label: trouble == 0 ? 'no errors' : 'need attention',
                tone: trouble == 0
                    ? theme.colorScheme.onSurfaceVariant
                    : palette.attention,
              ),
              const SizedBox(width: 8),
              AdminStat(
                value: '$total',
                label: 'total',
                tone: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<AdminKeyFilter>(
            segments: const [
              ButtonSegment(value: AdminKeyFilter.all, label: Text('All')),
              ButtonSegment(
                  value: AdminKeyFilter.active, label: Text('Enabled')),
              ButtonSegment(
                  value: AdminKeyFilter.trouble, label: Text('Problems')),
            ],
            selected: {filter},
            showSelectedIcon: false,
            onSelectionChanged: (s) => onFilter(s.first),
          ),
        ],
      ),
    );
  }
}

class AdminStat extends StatelessWidget {
  const AdminStat(
      {super.key,
      required this.value,
      required this.label,
      required this.tone});

  final String value;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: theme.textTheme.titleLarge
                    ?.copyWith(color: tone, fontWeight: FontWeight.w700)),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class AdminKeyCard extends StatelessWidget {
  const AdminKeyCard({
    super.key,
    required this.row,
    required this.revealed,
    required this.onReveal,
    required this.onTest,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final AdminKeyRow row;
  final bool revealed;
  final VoidCallback onReveal;
  final VoidCallback onTest;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  /// Masked always-short form: never leaks length, which alone hints at the
  /// provider.
  String get _masked => '••••••••••••';

  String get _shown {
    final key = row.key.key;
    if (revealed) return key;
    if (key.length <= 8) return _masked;
    // Prefix only: enough to tell two keys apart, useless as a credential.
    return '${key.substring(0, 4)}$_masked';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = KeyAdminPalette.of(context);
    final k = row.key;

    final (Color tone, String state) = !k.isActive
        ? (theme.colorScheme.onSurfaceVariant, 'Disabled')
        : row.isOnCooldown
            ? (palette.attention, row.cooldownLabel)
            : k.errorCount > 0
                ? (palette.danger, 'Has errors')
                : (palette.healthy, 'Healthy');

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProviderAvatar(provider: k.provider),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        k.name.isEmpty ? 'Untitled key' : k.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${AdminApiKey.providerName(k.provider)} · ${k.model}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: k.isActive,
                  onChanged: onToggle,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                AdminPill(label: state, tone: tone),
                const SizedBox(width: 6),
                AdminPill(
                  label: 'P${k.priority}',
                  tone: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                if (k.usageCount > 0)
                  AdminPill(
                    label: '${k.usageCount} uses',
                    tone: theme.colorScheme.onSurfaceVariant,
                  ),
                if (k.errorCount > 0) ...[
                  const SizedBox(width: 6),
                  AdminPill(
                    label: '${k.errorCount} errors',
                    tone: palette.danger,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _shown,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontFamilyFallback: const ['Roboto Mono', 'Courier'],
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: revealed ? 0 : 1.5,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: revealed ? 'Hide key' : 'Reveal key',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    revealed
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                  ),
                  onPressed: onReveal,
                ),
              ],
            ),
            const Divider(height: 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onTest,
                  icon: const Icon(Icons.bolt_outlined, size: 18),
                  label: const Text('Test'),
                ),
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: onEdit,
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  color: palette.danger,
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ProviderAvatar extends StatelessWidget {
  const ProviderAvatar({super.key, required this.provider});

  final String provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (IconData icon, Color tone) = switch (provider) {
      'google' => (Icons.auto_awesome_outlined, theme.colorScheme.primary),
      'openrouter' => (Icons.alt_route_outlined, theme.colorScheme.tertiary),
      _ => (Icons.lan_outlined, theme.colorScheme.secondary),
    };

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: tone),
    );
  }
}

class AdminPill extends StatelessWidget {
  const AdminPill({super.key, required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: tone, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class AdminEmptyState extends StatelessWidget {
  const AdminEmptyState(
      {super.key, required this.filtered, required this.onClearFilter});

  final bool filtered;
  final VoidCallback onClearFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              filtered ? Icons.filter_alt_off_outlined : Icons.key_outlined,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              filtered
                  ? 'No keys match this filter.'
                  : 'No keys yet. Tap “Add key” to add one.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (filtered) ...[
              const SizedBox(height: 12),
              TextButton(
                  onPressed: onClearFilter, child: const Text('Show all')),
            ],
          ],
        ),
      ),
    );
  }
}

class AdminErrorState extends StatelessWidget {
  const AdminErrorState({super.key, required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = KeyAdminPalette.of(context);
    // The four failures have four different fixes. Rendering them all as
    // "Could not read the key pool" plus raw Firestore text meant an admin
    // whose account simply was not allowlisted was sent to check the network.
    final failure = classifyKeyPoolError(error);
    final copy = describeKeyPoolFailure(failure);
    final icon = switch (failure) {
      KeyPoolFailure.permissionDenied => Icons.lock_outline,
      KeyPoolFailure.notConfigured => Icons.settings_suggest_outlined,
      KeyPoolFailure.unreachable => Icons.cloud_off_outlined,
      KeyPoolFailure.unknown => Icons.error_outline,
    };
    final tint = switch (failure) {
      KeyPoolFailure.permissionDenied => palette.attention,
      KeyPoolFailure.notConfigured => palette.attention,
      KeyPoolFailure.unreachable => palette.danger,
      KeyPoolFailure.unknown => palette.danger,
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: tint),
            const SizedBox(height: 12),
            Text(
              copy.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              copy.detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            // Only for a genuinely unexplained error: the other three already
            // said what to do, and a raw provider string under them is noise.
            if (failure == KeyPoolFailure.unknown) ...[
              const SizedBox(height: 10),
              Text(
                '$error',
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
