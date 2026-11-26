import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'package:admin_api_key_manager/models/free_model.dart';
import 'package:admin_api_key_manager/services/free_model_discovery.dart';
import 'package:admin_api_key_manager/screens/admin_api_keys_screen.dart';

/// Explorer for free models — fetches OpenRouter's public catalog and
/// shows which provider has which free model and where to get an API key.
///
/// No admin write is needed; this screen only reads a public endpoint and
/// optionally pushes [AdminApiKeysScreen] with a pre-filled model id.
class AdminFreeModelsScreen extends StatefulWidget {
  const AdminFreeModelsScreen({super.key});

  @override
  State<AdminFreeModelsScreen> createState() => _AdminFreeModelsScreenState();
}

class _AdminFreeModelsScreenState extends State<AdminFreeModelsScreen> {
  final _discovery = FreeModelDiscovery();
  final _searchCtrl = TextEditingController();
  late Future<List<FreeModel>> _future;
  String _provider = 'all';
  bool _freeOnly = true;

  @override
  void initState() {
    super.initState();
    _future = _discovery.fetchFree();
  }

  @override
  void dispose() {
    _discovery.close();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _future = _discovery.fetchFree());
    await _future;
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await url_launcher.canLaunchUrl(uri)) {
      await url_launcher.launchUrl(uri,
          mode: url_launcher.LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open $url')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Free models'),
        centerTitle: false,
        titleTextStyle:
            theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: FutureBuilder<List<FreeModel>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _FreeModelsError(error: snap.error, onRetry: _refresh);
          }
          final all = snap.data ?? [];
          return _FreeModelsList(
            all: all,
            searchCtrl: _searchCtrl,
            provider: _provider,
            freeOnly: _freeOnly,
            onProviderChanged: (v) => setState(() => _provider = v),
            onFreeOnlyChanged: (v) => setState(() => _freeOnly = v),
            onSearchChanged: (_) => setState(() {}),
            onOpenKeyUrl: _openUrl,
          );
        },
      ),
    );
  }
}

class _FreeModelsList extends StatelessWidget {
  const _FreeModelsList({
    required this.all,
    required this.searchCtrl,
    required this.provider,
    required this.freeOnly,
    required this.onProviderChanged,
    required this.onFreeOnlyChanged,
    required this.onSearchChanged,
    required this.onOpenKeyUrl,
  });

  final List<FreeModel> all;
  final TextEditingController searchCtrl;
  final String provider;
  final bool freeOnly;
  final ValueChanged<String> onProviderChanged;
  final ValueChanged<bool> onFreeOnlyChanged;
  final ValueChanged<String> onSearchChanged;
  final Future<void> Function(String url) onOpenKeyUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final providers = <String>{'all', ...all.map((m) => m.provider)}.toList()
      ..sort();
    final filtered = filterModels(all,
        query: searchCtrl.text, provider: provider, freeOnly: freeOnly);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: searchCtrl,
                  onChanged: onSearchChanged,
                  decoration: const InputDecoration(
                    labelText: 'Search model',
                    hintText: 'gpt, claude, gemma, llama…',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: provider,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Provider',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: providers
                            .map((p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(p == 'all' ? 'All providers' : p,
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (v) => onProviderChanged(v ?? 'all'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilterChip(
                      label: const Text('Free only'),
                      selected: freeOnly,
                      onSelected: onFreeOnlyChanged,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${filtered.length} of ${all.length} models'
                  '${freeOnly ? ' · FREE' : ''} · source: openrouter.ai',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        if (filtered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search_off_outlined,
                        size: 40, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text('No models match.', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Text('Try a broader search or turn off "Free only".',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            sliver: SliverList.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _FreeModelCard(
                model: filtered[i],
                onOpenKeyUrl: onOpenKeyUrl,
              ),
            ),
          ),
      ],
    );
  }
}

class _FreeModelCard extends StatelessWidget {
  const _FreeModelCard({required this.model, required this.onOpenKeyUrl});

  final FreeModel model;
  final Future<void> Function(String url) onOpenKeyUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: model.isFree
                        ? Colors.green.withValues(alpha: 0.12)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    model.isFree ? 'FREE' : 'PAID',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: model.isFree
                          ? Colors.green.shade700
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    model.providerDisplay,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (model.contextLength != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${(model.contextLength! / 1000).toStringAsFixed(0)}k ctx',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              model.id,
              style: theme.textTheme.titleSmall?.copyWith(
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Roboto Mono', 'Courier'],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              model.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (model.description != null && model.description!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                model.description!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 8),
            const Divider(height: 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Copy model id',
                  icon: const Icon(Icons.copy_outlined, size: 20),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: model.id));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Copied ${model.id}')),
                      );
                    }
                  },
                ),
                TextButton.icon(
                  onPressed: () => onOpenKeyUrl(model.apiKeyUrl),
                  icon: const Icon(Icons.key_outlined, size: 18),
                  label: const Text('Get API key'),
                ),
                const SizedBox(width: 4),
                FilledButton.tonalIcon(
                  onPressed: () {
                    // Push the key screen — admin will paste their own key, model is pre-filled
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const AdminApiKeysScreen()),
                    );
                    // Hint: user copies model id, then pastes in the form. We keep it simple
                    // to avoid coupling the two screens via arguments.
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Use model'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FreeModelsError extends StatelessWidget {
  const _FreeModelsError({required this.error, required this.onRetry});

  final Object? error;
  final Future<void> Function() onRetry;

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
            Text('Could not load free models',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              'Source: https://openrouter.ai/api/v1/models — check connection and try again.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
