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
              child: const Icon(Icons.explore_rounded,
                  size: 19, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Free models',
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                Text('OpenRouter catalog · live',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: _refresh,
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<FreeModel>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                        strokeWidth: 3, color: palette.accent),
                  ),
                  const SizedBox(height: 14),
                  Text('Fetching catalog…',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            );
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
    final palette = KeyAdminPalette.of(context);
    final providers = <String>{'all', ...all.map((m) => m.provider)}.toList()
      ..sort();
    final filtered = filterModels(all,
        query: searchCtrl.text, provider: provider, freeOnly: freeOnly);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: searchCtrl,
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search gpt, claude, gemma, llama…',
                    prefixIcon: Icon(Icons.search_rounded,
                        color: theme.colorScheme.onSurfaceVariant),
                    suffixIcon: searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              searchCtrl.clear();
                              onSearchChanged('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                            color: theme.colorScheme.outlineVariant
                                .withValues(alpha: 0.55))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                            color: theme.colorScheme.outlineVariant
                                .withValues(alpha: 0.55))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            BorderSide(color: palette.accent, width: 1.4)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.55)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: provider,
                            isExpanded: true,
                            icon: Icon(Icons.expand_more_rounded,
                                color: theme.colorScheme.onSurfaceVariant),
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                            items: providers
                                .map((p) => DropdownMenuItem(
                                      value: p,
                                      child: Row(
                                        children: [
                                          Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                  color: p == 'all'
                                                      ? palette.accent
                                                      : theme.colorScheme
                                                          .onSurfaceVariant,
                                                  shape: BoxShape.circle)),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                                p == 'all'
                                                    ? 'All providers'
                                                    : p,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          ),
                                        ],
                                      ),
                                    ))
                                .toList(),
                            onChanged: (v) => onProviderChanged(v ?? 'all'),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilterChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                              freeOnly
                                  ? Icons.check_circle_rounded
                                  : Icons.circle_outlined,
                              size: 16,
                              color: freeOnly
                                  ? palette.accent
                                  : theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          const Text('Free only',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      selected: freeOnly,
                      showCheckmark: false,
                      selectedColor: palette.accent.withValues(alpha: 0.12),
                      backgroundColor: theme.colorScheme.surface,
                      side: BorderSide(
                          color: freeOnly
                              ? palette.accent.withValues(alpha: 0.28)
                              : theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.6)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      onSelected: onFreeOnlyChanged,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                      Icon(Icons.auto_awesome_outlined,
                          size: 14, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${filtered.length} of ${all.length} models'
                          '${freeOnly ? ' · FREE' : ''}',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: palette.accent.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('openrouter.ai',
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: palette.accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 10)),
                      ),
                    ],
                  ),
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
                      child: Icon(Icons.search_off_rounded,
                          size: 32, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    Text('No models match',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                        'Try a broader search or turn off “Free only” to see paid models.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.5)),
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
              separatorBuilder: (_, __) => const SizedBox(height: 12),
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
    final palette = KeyAdminPalette.of(context);
    final isFree = model.isFree;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isFree
                ? palette.healthy.withValues(alpha: 0.22)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 4)),
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 32,
              offset: const Offset(0, 8)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
              height: 3,
              color:
                  isFree ? palette.healthy : theme.colorScheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: isFree
                            ? palette.healthy.withValues(alpha: 0.12)
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                            color: isFree
                                ? palette.healthy.withValues(alpha: 0.18)
                                : theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                  color: isFree
                                      ? palette.healthy
                                      : theme.colorScheme.onSurfaceVariant,
                                  shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                          Text(
                            isFree ? 'FREE' : 'PAID',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isFree
                                  ? palette.healthyText
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        model.providerDisplay,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    if (model.contextLength != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: palette.accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                              color: palette.accent.withValues(alpha: 0.14)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.memory_outlined,
                                size: 11, color: palette.accent),
                            const SizedBox(width: 4),
                            Text(
                              '${(model.contextLength! / 1000).toStringAsFixed(0)}k',
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: palette.accent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  model.id,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['Roboto Mono', 'Courier'],
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  model.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant, height: 1.4),
                ),
                if (model.description != null &&
                    model.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      model.description!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.45),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                    height: 1,
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.45)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Material(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () async {
                          await Clipboard.setData(
                              ClipboardData(text: model.id));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Copied ${model.id}'),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12))),
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.5)),
                          ),
                          child: Icon(Icons.copy_rounded,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => onOpenKeyUrl(model.apiKeyUrl),
                      icon: const Icon(Icons.key_rounded, size: 16),
                      label: const Text('Get key',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => const AdminApiKeysScreen()),
                        );
                      },
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Use',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
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

class _FreeModelsError extends StatelessWidget {
  const _FreeModelsError({required this.error, required this.onRetry});

  final Object? error;
  final Future<void> Function() onRetry;

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
            Text('Could not load catalog',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
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
              child: Column(
                children: [
                  Text(
                    '$error',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant, height: 1.5),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Source: openrouter.ai/api/v1/models',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
