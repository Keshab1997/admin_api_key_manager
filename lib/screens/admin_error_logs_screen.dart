import 'package:admin_api_key_manager/models/api_error_log.dart';
import 'package:admin_api_key_manager/services/api_key_manager.dart';
import 'package:admin_api_key_manager/theme/key_admin_palette.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Read-only view of `api_error_logs`, the collection [ApiKeyManager] fills in
/// batches whenever a call fails.
///
/// The logs were being written all along and were only visible in the Firestore
/// console. That is the wrong place to look when a user says "AI stopped
/// working": the interesting question is *which* key, *which* feature and *what
/// kind* of failure, and the answer is a table, not a document tree.
///
/// Deliberately read-only. Deleting is left to the retention sweep the manager
/// already runs (30 days, throttled hourly, cleaned from admin devices because
/// Firestore TTL needs a paid plan), so this screen cannot be the thing that
/// loses evidence.
class AdminErrorLogsScreen extends StatefulWidget {
  /// Collection name override — must match [ApiKeyManager.errorLogsCollection].
  final String collection;

  /// How many rows to read. A bound, not pagination: the failure mode of an
  /// outage is thousands of identical rows, and 200 is enough to see the shape.
  final int limit;

  const AdminErrorLogsScreen({
    super.key,
    this.collection = 'api_error_logs',
    this.limit = 200,
  });

  @override
  State<AdminErrorLogsScreen> createState() => _AdminErrorLogsScreenState();
}

enum _Type { all, rateLimit, auth, server, network, other }

class _AdminErrorLogsScreenState extends State<AdminErrorLogsScreen> {
  _Type _filter = _Type.all;

  static const Map<_Type, String> _typeLabels = {
    _Type.all: 'All',
    _Type.rateLimit: 'Rate limit',
    _Type.auth: 'Auth',
    _Type.server: 'Server',
    _Type.network: 'Network',
    _Type.other: 'Other',
  };

  static const Map<String, _Type> _errorTypeToFilter = {
    'rate_limit': _Type.rateLimit,
    'auth_error': _Type.auth,
    'server_error': _Type.server,
    'network_error': _Type.network,
    'unknown': _Type.other,
  };

  /// The Firestore field the retention sweep filters on. Ordered descending so
  /// the newest failure is the first thing read.
  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection(widget.collection);

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
                color: palette.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: palette.danger.withValues(alpha: 0.18)),
              ),
              child: Icon(Icons.receipt_long_rounded,
                  size: 18, color: palette.danger),
            ),
            const SizedBox(width: 10),
            // Expanded, not a bare Column: the subtitle is a full sentence and
            // a bare Column sizes to it, so on a 360-390dp phone the title row
            // overflowed the toolbar (RenderFlex overflow, clipped in release).
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Error log',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                  Text('Last ${widget.limit} failures · newest first',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _col
            .orderBy('timestamp', descending: true)
            .limit(widget.limit)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _LogsError(error: snap.error);
          }
          if (!snap.hasData) {
            return Center(
                child: CircularProgressIndicator(
                    strokeWidth: 3, color: palette.accent));
          }

          final all = snap.data!.docs
              .map((doc) => ApiErrorLog.fromMap(doc.data(), doc.id))
              .toList();

          final counts = <_Type, int>{for (final t in _Type.values) t: 0};
          for (final log in all) {
            final t = _errorTypeToFilter[log.errorType] ?? _Type.other;
            counts[t] = (counts[t] ?? 0) + 1;
          }

          final visible = _filter == _Type.all
              ? all
              : all
                  .where((l) =>
                      (_errorTypeToFilter[l.errorType] ?? _Type.other) ==
                      _filter)
                  .toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.55)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 12,
                        offset: const Offset(0, 3)),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.insights_outlined,
                          size: 15, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _summary(all, counts),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final t in _Type.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            t == _Type.all
                                ? 'All ${all.length}'
                                : '${_typeLabels[t]} ${counts[t] ?? 0}',
                            style: TextStyle(
                                fontWeight: _filter == t
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                fontSize: 13),
                          ),
                          selected: _filter == t,
                          selectedColor: palette.accent.withValues(alpha: 0.13),
                          backgroundColor: theme.colorScheme.surface,
                          side: BorderSide(
                              color: _filter == t
                                  ? palette.accent.withValues(alpha: 0.28)
                                  : theme.colorScheme.outlineVariant
                                      .withValues(alpha: 0.6)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          onSelected: (_) => setState(() => _filter = t),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: visible.isEmpty
                    ? _LogsEmpty(filtered: all.isNotEmpty)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _LogTile(log: visible[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _summary(List<ApiErrorLog> all, Map<_Type, int> counts) {
    if (all.isEmpty) {
      return 'No failures recorded. That is the healthy state — nothing has '
          'written here.';
    }
    final newest = all.first.timestamp;
    final features =
        all.map((l) => l.feature).where((f) => f.isNotEmpty).toSet();
    final keys = all.map((l) => l.keyName).where((k) => k.isNotEmpty).toSet();
    return '${all.length} failure${all.length == 1 ? '' : 's'} in the last '
        '${_ago(newest)} · ${keys.length} key(s) · '
        '${features.isEmpty ? 'unknown feature' : features.join(', ')}';
  }
}

/// "3m ago", "2h ago", "4d ago" — precise enough to correlate with a report,
/// short enough to sit in one line.
String _ago(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'moments';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  return '${diff.inDays}d';
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log});

  final ApiErrorLog log;

  (Color, IconData, String) _tone(ColorScheme scheme, KeyAdminPalette palette) {
    switch (log.errorType) {
      case 'rate_limit':
        return (palette.attention, Icons.speed_rounded, 'Rate limit');
      case 'auth_error':
        return (palette.danger, Icons.lock_rounded, 'Auth');
      case 'server_error':
        return (palette.danger, Icons.cloud_off_rounded, 'Server');
      case 'network_error':
        return (scheme.secondary, Icons.wifi_off_rounded, 'Network');
      default:
        return (scheme.onSurfaceVariant, Icons.help_outline_rounded, 'Other');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = KeyAdminPalette.of(context);
    final (tone, icon, label) = _tone(theme.colorScheme, palette);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tone.withValues(alpha: 0.18)),
              ),
              child: Icon(icon, size: 18, color: tone),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          label,
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: tone,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                              fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'HTTP ${log.statusCode}',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              fontSize: 11),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          _ago(log.timestamp),
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${log.keyName.isEmpty ? 'unknown key' : log.keyName} · '
                    '${log.feature.isEmpty ? 'unknown feature' : log.feature}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600, height: 1.4),
                  ),
                  if (log.message.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      log.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogsEmpty extends StatelessWidget {
  const _LogsEmpty({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                color: theme.colorScheme.surfaceContainerHigh,
                shape: BoxShape.circle,
                border: Border.all(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.6)),
              ),
              child: Icon(
                filtered
                    ? Icons.filter_alt_off_rounded
                    : Icons.check_circle_rounded,
                size: 32,
                color: filtered
                    ? theme.colorScheme.onSurfaceVariant
                    : const Color(0xFF0EA67A),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              filtered ? 'No failures of this kind' : 'All clear — no failures',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              filtered
                  ? 'Try another filter.'
                  : 'Failures will appear here with key and feature.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogsError extends StatelessWidget {
  const _LogsError({required this.error});

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
            Text('Could not read the error log',
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
            const SizedBox(height: 10),
            Text(
              'Rules must allow admin read on api_error_logs.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
