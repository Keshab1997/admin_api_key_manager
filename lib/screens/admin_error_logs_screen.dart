import 'package:admin_api_key_manager/models/api_error_log.dart';
import 'package:admin_api_key_manager/services/api_key_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Error log'), centerTitle: false),
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
            return const Center(child: CircularProgressIndicator());
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  _summary(all, counts),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
              SizedBox(
                height: 40,
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
                          ),
                          selected: _filter == t,
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
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
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

  (Color, IconData, String) _tone(ColorScheme scheme) {
    switch (log.errorType) {
      case 'rate_limit':
        return (scheme.tertiary, Icons.speed_outlined, 'Rate limit');
      case 'auth_error':
        return (scheme.error, Icons.lock_outline, 'Auth');
      case 'server_error':
        return (scheme.error, Icons.cloud_off_outlined, 'Server');
      case 'network_error':
        return (scheme.secondary, Icons.wifi_off_outlined, 'Network');
      default:
        return (scheme.onSurfaceVariant, Icons.help_outline, 'Other');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (tone, icon, label) = _tone(theme.colorScheme);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: tone),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.labelLarge?.copyWith(
                            color: tone, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'HTTP ${log.statusCode}',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const Spacer(),
                      Text(
                        _ago(log.timestamp),
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // Honest about what the log does and does not hold: no
                    // message text, ever — only which key and which feature.
                    '${log.keyName.isEmpty ? 'unknown key' : log.keyName} · '
                    '${log.feature.isEmpty ? 'unknown feature' : log.feature}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (log.message.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      log.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
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
            Icon(
              filtered
                  ? Icons.filter_alt_off_outlined
                  : Icons.check_circle_outline,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              filtered ? 'No failures of this kind.' : 'No failures recorded.',
              style: theme.textTheme.bodyMedium
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text('Could not read the error log.',
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
            const SizedBox(height: 10),
            Text(
              'Rules must allow admin read on api_error_logs.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
