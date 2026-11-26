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

// ─────────────────────────────────────────────────────────────────────────────
// Reorder
// ─────────────────────────────────────────────────────────────────────────────

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
    final palette = KeyAdminPalette.of(context);

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: palette.accentSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.accent.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.swap_vert, size: 18, color: palette.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Drag to set failover order. Priority becomes 1, 2, 3… when you save.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
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
              return Container(
                key: ValueKey(row.key.id),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.6)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          palette.accent,
                          palette.accent.withValues(alpha: 0.75)
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: [
                        BoxShadow(
                          color: palette.accent.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '${i + 1}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    row.key.name.isEmpty ? 'Untitled key' : row.key.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${AdminApiKey.providerName(row.key.provider)} · '
                    '${row.key.isActive ? 'enabled' : 'disabled'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  trailing: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.drag_indicator,
                        size: 18, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: onSave,
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.accent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Save order',
                        style: TextStyle(fontWeight: FontWeight.w700)),
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

// ─────────────────────────────────────────────────────────────────────────────
// Summary + stats
// ─────────────────────────────────────────────────────────────────────────────

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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AdminStat(
                value: '$active',
                label: 'Active',
                sublabel: total == 0 ? '—' : '$total total',
                icon: Icons.verified_outlined,
                tone: palette.healthy,
              ),
              const SizedBox(width: 10),
              AdminStat(
                value: '$trouble',
                label: trouble == 0 ? 'Healthy' : 'Needs attention',
                sublabel: trouble == 0 ? 'no errors' : '$trouble flagged',
                icon: trouble == 0
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
                tone: trouble == 0
                    ? theme.colorScheme.onSurfaceVariant
                    : palette.attention,
              ),
              const SizedBox(width: 10),
              AdminStat(
                value: '$total',
                label: 'Keys',
                sublabel: active == total ? 'all active' : '$active active',
                icon: Icons.layers_outlined,
                tone: palette.accent,
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Premium segmented filter — icons + subtle accent when selected
          SegmentedButton<AdminKeyFilter>(
            segments: const [
              ButtonSegment(
                value: AdminKeyFilter.all,
                label: Text('All'),
                icon: Icon(Icons.apps_outlined, size: 16),
              ),
              ButtonSegment(
                value: AdminKeyFilter.active,
                label: Text('Enabled'),
                icon: Icon(Icons.bolt_outlined, size: 16),
              ),
              ButtonSegment(
                value: AdminKeyFilter.trouble,
                label: Text('Issues'),
                icon: Icon(Icons.error_outline, size: 16),
              ),
            ],
            selected: {filter},
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.comfortable,
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            onSelectionChanged: (s) => onFilter(s.first),
          ),
        ],
      ),
    );
  }
}

class AdminStat extends StatelessWidget {
  const AdminStat({
    super.key,
    required this.value,
    required this.label,
    required this.tone,
    this.sublabel,
    this.icon,
  });

  final String value;
  final String label;
  final String? sublabel;
  final Color tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null)
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 14, color: tone),
                  ),
                const Spacer(),
                Container(
                    width: 28,
                    height: 3,
                    decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(99))),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: tone,
                fontWeight: FontWeight.w800,
                height: 1,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            if (sublabel != null)
              Text(
                sublabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Key card — premium
// ─────────────────────────────────────────────────────────────────────────────

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

  String get _masked => '••••••••••••';

  String get _shown {
    final key = row.key.key;
    if (revealed) return key;
    if (key.length <= 8) return _masked;
    return '${key.substring(0, 4)}$_masked';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = KeyAdminPalette.of(context);
    final k = row.key;

    final (Color tone, String state, IconData stateIcon) = !k.isActive
        ? (
            theme.colorScheme.onSurfaceVariant,
            'Disabled',
            Icons.pause_circle_outline
          )
        : row.isOnCooldown
            ? (palette.attention, row.cooldownLabel, Icons.timer_outlined)
            : k.errorCount > 0
                ? (palette.danger, 'Has errors', Icons.error_outline)
                : (palette.healthy, 'Healthy', Icons.check_circle_outline);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top accent strip — 3px state colour
          Container(height: 3, color: tone),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ProviderAvatar(provider: k.provider, tone: tone),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            k.name.isEmpty ? 'Untitled key' : k.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  AdminApiKey.providerName(k.provider),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                child: Container(
                                  width: 3,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.outlineVariant,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  k.model,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontFamily: 'monospace',
                                    fontFamilyFallback: const [
                                      'Roboto Mono',
                                      'Courier'
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Transform.scale(
                      scale: 0.88,
                      child: Switch(
                        value: k.isActive,
                        onChanged: onToggle,
                        thumbColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return palette.healthy;
                          }
                          return null;
                        }),
                        trackColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return palette.healthy.withValues(alpha: 0.22);
                          }
                          return null;
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    AdminPill(
                        label: state, tone: tone, icon: stateIcon, dot: true),
                    AdminPill(
                      label: 'P${k.priority}',
                      tone: theme.colorScheme.onSurfaceVariant,
                      icon: Icons.flag_outlined,
                    ),
                    if (k.usageCount > 0)
                      AdminPill(
                        label: '${k.usageCount} uses',
                        tone: theme.colorScheme.onSurfaceVariant,
                        icon: Icons.show_chart,
                      ),
                    if (k.errorCount > 0)
                      AdminPill(
                        label: '${k.errorCount} errors',
                        tone: palette.danger,
                        icon: Icons.warning_amber_rounded,
                        dot: true,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.vpn_key_outlined,
                          size: 16, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _shown,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            fontFamilyFallback: const [
                              'Roboto Mono',
                              'Courier'
                            ],
                            color: revealed
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurfaceVariant,
                            letterSpacing: revealed ? 0 : 1.2,
                            fontWeight:
                                revealed ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Material(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(9),
                        child: InkWell(
                          onTap: onReveal,
                          borderRadius: BorderRadius.circular(9),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                  color: theme.colorScheme.outlineVariant
                                      .withValues(alpha: 0.6)),
                            ),
                            child: Icon(
                              revealed
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                    height: 1,
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.5)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: onTest,
                      icon: const Icon(Icons.bolt_outlined, size: 16),
                      label: const Text('Test',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Delete',
                      onPressed: onDelete,
                      icon: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: palette.danger.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: palette.danger.withValues(alpha: 0.14)),
                        ),
                        child: Icon(Icons.delete_outline,
                            size: 16, color: palette.danger),
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

class ProviderAvatar extends StatelessWidget {
  const ProviderAvatar({super.key, required this.provider, this.tone});

  final String provider;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = KeyAdminPalette.of(context);
    final (IconData icon, Color base, List<Color> grad) = switch (provider) {
      'google' => (
          Icons.auto_awesome_rounded,
          const Color(0xFF4285F4),
          [const Color(0xFF4285F4), const Color(0xFF8AB4F8)]
        ),
      'openrouter' => (
          Icons.alt_route_rounded,
          palette.accent,
          [palette.accent, const Color(0xFF8B8CF8)]
        ),
      _ => (
          Icons.lan_rounded,
          theme.colorScheme.secondary,
          [theme.colorScheme.secondary, theme.colorScheme.tertiary]
        ),
    };

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: grad,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(13),
        boxShadow: [
          BoxShadow(
            color: base.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, size: 22, color: Colors.white),
    );
  }
}

class AdminPill extends StatelessWidget {
  const AdminPill({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.dot = false,
  });

  final String label;
  final Color tone;
  final IconData? icon;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: tone.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot)
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
            )
          else if (icon != null)
            Icon(icon, size: 12, color: tone),
          if (dot || icon != null) const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: tone,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.15,
              fontSize: 11.5,
            ),
          ),
        ],
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
                color: filtered
                    ? theme.colorScheme.surfaceContainerHigh
                    : palette.accentSoft,
                shape: BoxShape.circle,
                border: Border.all(
                    color: filtered
                        ? theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.6)
                        : palette.accent.withValues(alpha: 0.14)),
              ),
              child: Icon(
                filtered ? Icons.filter_alt_off_rounded : Icons.key_rounded,
                size: 32,
                color: filtered
                    ? theme.colorScheme.onSurfaceVariant
                    : palette.accent,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              filtered ? 'No matching keys' : 'No keys yet',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              filtered
                  ? 'Try a different filter — nothing matches the current view.'
                  : 'Tap “Add key” to add your first provider key. It will appear here and be available to every device.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            if (filtered) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onClearFilter,
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('Show all keys'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
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
    final failure = classifyKeyPoolError(error);
    final copy = describeKeyPoolFailure(failure);
    final (IconData icon, Color tint) = switch (failure) {
      KeyPoolFailure.permissionDenied => (
          Icons.lock_rounded,
          palette.attention
        ),
      KeyPoolFailure.notConfigured => (
          Icons.settings_suggest_rounded,
          palette.attention
        ),
      KeyPoolFailure.unreachable => (Icons.cloud_off_rounded, palette.danger),
      KeyPoolFailure.unknown => (Icons.error_outline_rounded, palette.danger),
    };
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
                color: tint.withValues(alpha: 0.10),
                shape: BoxShape.circle,
                border: Border.all(color: tint.withValues(alpha: 0.18)),
              ),
              child: Icon(icon, size: 32, color: tint),
            ),
            const SizedBox(height: 16),
            Text(
              copy.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
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
                copy.detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
            if (failure == KeyPoolFailure.unknown) ...[
              const SizedBox(height: 12),
              Text(
                '$error',
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                  fontFamilyFallback: const ['Roboto Mono', 'Courier'],
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
