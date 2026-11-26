import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'package:admin_api_key_manager/models/free_model.dart';
import 'package:admin_api_key_manager/models/free_source.dart';
import 'package:admin_api_key_manager/services/free_model_discovery.dart';
import 'package:admin_api_key_manager/screens/admin_api_keys_screen.dart';

/// Explorer for free models — fetches OpenRouter's public catalog and
/// shows which provider has which free model and where to get an API key.
///
/// No admin write is needed; this screen only reads a public endpoint and
/// optionally pushes [AdminApiKeysScreen] with a pre-filled model id.
class AdminFreeModelsScreen extends StatefulWidget {
  /// Injectable catalog source. Production leaves this null and the screen
  /// builds its own; a test passes one so the body can be rendered without
  /// the network — which is the only way to catch a build/layout failure in
  /// this screen on a plain JVM.
  final FreeModelDiscovery? discovery;

  const AdminFreeModelsScreen({super.key, this.discovery});

  @override
  State<AdminFreeModelsScreen> createState() => _AdminFreeModelsScreenState();
}

class _AdminFreeModelsScreenState extends State<AdminFreeModelsScreen> {
  late final FreeModelDiscovery _discovery;
  bool _ownsDiscovery = false;
  final _searchCtrl = TextEditingController();
  late Future<List<FreeModel>> _future;
  String _provider = 'all';
  bool _freeOnly = true;

  /// The catalog is 300+ free models and each card is ~250dp tall, so rendering
  /// all of them at once made the screen scroll forever — the reported "no
  /// matter how much I scroll it keeps scrolling". Pages of 50 keep the list
  /// finite and give the filter box something to do.
  static const int _pageSize = 50;
  int _visible = _pageSize;

  /// 0 = the live OpenRouter catalog, 1 = the hand-curated directory of free
  /// sources. The directory needs no network, so it still answers "where do I
  /// get a free key?" when the catalog fetch has just failed.
  int _tab = 0;
  final _sourceSearchCtrl = TextEditingController();
  bool _providersOnly = false;

  @override
  void initState() {
    super.initState();
    final injected = widget.discovery;
    _ownsDiscovery = injected == null;
    _discovery = injected ?? FreeModelDiscovery();
    _future = _discovery.fetchFree();
  }

  @override
  void dispose() {
    // Never close a client the caller owns.
    if (_ownsDiscovery) _discovery.close();
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
            // Expanded, not a bare Column: the subtitle is a full sentence and
            // a bare Column sizes to it, so on a 360-390dp phone the title row
            // overflowed the toolbar (RenderFlex overflow, clipped in release).
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Free models',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                  Text('OpenRouter catalog · live',
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _FreeModelsTabBar(
              index: _tab,
              labels: const ['Catalog', 'Free sources'],
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
          Expanded(child: _tabBody(theme, palette)),
        ],
      ),
    );
  }

  Widget _tabBody(ThemeData theme, KeyAdminPalette palette) {
    if (_tab == 1) {
      return _FreeSourcesList(
        searchCtrl: _sourceSearchCtrl,
        providersOnly: _providersOnly,
        onSearchChanged: (_) => setState(() {}),
        onProvidersOnlyChanged: (v) => setState(() => _providersOnly = v),
        onOpenUrl: _openUrl,
        onCopyBaseUrl: (baseUrl) async {
          // The base URL is what the key form asks for, and it is the one
          // field nobody remembers. Copy it, then the add-key sheet is one
          // paste away.
          await Clipboard.setData(ClipboardData(text: baseUrl));
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Base URL copied — $baseUrl'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        },
      );
    }
    return FutureBuilder<List<FreeModel>>(
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
          visibleCount: _visible,
          onShowMore: () =>
              setState(() => _visible += _AdminFreeModelsScreenState._pageSize),
          // Any filter change starts a new result set at page one.
          onProviderChanged: (v) => setState(() {
            _provider = v;
            _visible = _pageSize;
          }),
          onFreeOnlyChanged: (v) => setState(() {
            _freeOnly = v;
            _visible = _pageSize;
          }),
          onSearchChanged: (_) => setState(() => _visible = _pageSize),
          onOpenKeyUrl: _openUrl,
        );
      },
    );
  }
}

class _FreeModelsList extends StatelessWidget {
  const _FreeModelsList({
    required this.all,
    required this.searchCtrl,
    required this.provider,
    required this.freeOnly,
    required this.visibleCount,
    required this.onShowMore,
    required this.onProviderChanged,
    required this.onFreeOnlyChanged,
    required this.onSearchChanged,
    required this.onOpenKeyUrl,
  });

  final List<FreeModel> all;
  final TextEditingController searchCtrl;
  final String provider;
  final bool freeOnly;
  final int visibleCount;
  final VoidCallback onShowMore;
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
    final shown = filtered.take(visibleCount).toList();

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
              itemCount: shown.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _FreeModelCard(
                model: shown[i],
                onOpenKeyUrl: onOpenKeyUrl,
              ),
            ),
          ),
        // More results than one page: the footer is what makes the end of the
        // page an explicit choice instead of an endless list.
        if (filtered.length > shown.length)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: OutlinedButton.icon(
                onPressed: onShowMore,
                icon: const Icon(Icons.expand_more_rounded, size: 18),
                label: Text(
                  'Show more · ${filtered.length - shown.length} left',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: theme.colorScheme.surface,
                  foregroundColor: palette.accent,
                  side:
                      BorderSide(color: palette.accent.withValues(alpha: 0.35)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
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
                    // Flexible, not fixed: the three actions need ~250dp and a
                    // 320dp phone only leaves ~230. The label shrinks with an
                    // ellipsis instead of the row overflowing.
                    Flexible(
                      child: OutlinedButton.icon(
                        onPressed: () => onOpenKeyUrl(model.apiKeyUrl),
                        icon: const Icon(Icons.key_rounded, size: 16),
                        label: const Text('Get key',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11)),
                          visualDensity: VisualDensity.compact,
                        ),
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

  /// How much of an exception message is safe to *render*.
  ///
  /// Not cosmetic. A failed catalog fetch can hand over an exception whose
  /// `toString()` is the whole ~900 kB response; the screen used to put that in
  /// a `Text` inside a non-scrollable `Column`, which measured **1,112,028 px**
  /// tall on a 353dp phone — a grey wall you can scroll forever and read
  /// nothing on. One bad response must never cost the screen.
  static const int _visibleChars = 240;
  static const int _copyChars = 10000;

  /// The one line worth reading first: what kind of failure this is.
  static String reason(Object? error) {
    if (error == null) return 'Unknown error';
    if (error is FreeModelFetchException) {
      return 'openrouter.ai answered HTTP ${error.statusCode}';
    }
    final text = error.toString();
    if (text.contains('TimeoutException')) {
      return 'The request timed out — openrouter.ai did not answer in time';
    }
    if (text.contains('SocketException') || text.contains('ClientException')) {
      return 'Could not reach openrouter.ai — check the connection';
    }
    if (text.contains('FormatException')) {
      return 'The catalog came back as something that is not valid JSON';
    }
    return error.runtimeType.toString();
  }

  static String _clamp(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = KeyAdminPalette.of(context);
    final full = error?.toString() ?? 'No error object was supplied.';
    final detail = _clamp(full, _visibleChars);
    final hidden = full.length - detail.length;

    // Scrollable and flex-free on purpose: an error state that can overflow is
    // a worse bug than the error it is reporting.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - 48).clamp(0.0, double.infinity),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: palette.danger.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: palette.danger.withValues(alpha: 0.18)),
                  ),
                  child: Icon(Icons.cloud_off_rounded,
                      size: 32, color: palette.danger),
                ),
                const SizedBox(height: 16),
                Text(
                  'Could not load catalog',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  reason(error),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant, height: 1.4),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                        detail,
                        textAlign: TextAlign.center,
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.5),
                      ),
                      if (hidden > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          '+$hidden more characters — use Copy details',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              fontSize: 10),
                        ),
                      ],
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
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Retry',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.accent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                    ),
                    // The escape hatch: the full text leaves the screen through
                    // the clipboard instead of being laid out as a widget.
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: _clamp(full, _copyChars)));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Error details copied'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy details',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FreeModelsTabBar extends StatelessWidget {
  const _FreeModelsTabBar({
    required this.index,
    required this.labels,
    required this.onChanged,
  });

  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = KeyAdminPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: i == index
                        ? palette.accent.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Center(
                    child: Text(
                      labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: i == index
                            ? palette.accent
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The directory of places that hand out free model access. Static data, so it
/// renders instantly and works offline — which matters most exactly when the
/// live catalog above it has failed.
class _FreeSourcesList extends StatelessWidget {
  const _FreeSourcesList({
    required this.searchCtrl,
    required this.providersOnly,
    required this.onSearchChanged,
    required this.onProvidersOnlyChanged,
    required this.onOpenUrl,
    required this.onCopyBaseUrl,
  });

  final TextEditingController searchCtrl;
  final bool providersOnly;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<bool> onProvidersOnlyChanged;
  final Future<void> Function(String url) onOpenUrl;
  final Future<void> Function(String url) onCopyBaseUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = KeyAdminPalette.of(context);
    final shown = filterSources(kFreeSources,
        query: searchCtrl.text, providersOnly: providersOnly);

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
                    hintText: 'Search groq, gemini, gateway…',
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
                    FilterChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                              providersOnly
                                  ? Icons.check_circle_rounded
                                  : Icons.circle_outlined,
                              size: 16,
                              color: providersOnly
                                  ? palette.accent
                                  : theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          const Text('First-party only',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      selected: providersOnly,
                      showCheckmark: false,
                      selectedColor: palette.accent.withValues(alpha: 0.12),
                      backgroundColor: theme.colorScheme.surface,
                      side: BorderSide(
                          color: providersOnly
                              ? palette.accent.withValues(alpha: 0.28)
                              : theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.6)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      onSelected: onProvidersOnlyChanged,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${shown.length} of ${kFreeSources.length} sources',
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: palette.attention.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: palette.attention.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 15, color: palette.attentionText),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Allowances change weekly — open a source before you '
                          'trust its number. Anything marked RELAY may log your '
                          'prompts, so no student data there.',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: palette.attentionText,
                              height: 1.45,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 96),
          sliver: SliverList.separated(
            itemCount: shown.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _FreeSourceCard(
              source: shown[i],
              onOpenUrl: onOpenUrl,
              onCopyBaseUrl: onCopyBaseUrl,
            ),
          ),
        ),
      ],
    );
  }
}

class _FreeSourceCard extends StatelessWidget {
  const _FreeSourceCard({
    required this.source,
    required this.onOpenUrl,
    required this.onCopyBaseUrl,
  });

  final FreeSource source;
  final Future<void> Function(String url) onOpenUrl;
  final Future<void> Function(String url) onCopyBaseUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = KeyAdminPalette.of(context);
    final isProvider = source.kind == FreeSourceKind.provider;
    final daily = source.dailyTokensLabel;

    return Container(
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
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
              height: 3,
              color: isProvider ? palette.healthy : palette.attention),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        source.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SourcePill(
                      label: isProvider ? 'FIRST-PARTY' : 'GATEWAY',
                      color: isProvider ? palette.healthy : palette.attention,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _SourcePill(
                        label: source.freeAllowance,
                        color: theme.colorScheme.onSurfaceVariant),
                    if (daily != null)
                      _SourcePill(label: daily, color: palette.accent),
                    if (source.needsCard)
                      _SourcePill(label: 'CARD', color: palette.danger),
                    if (source.needsPhone)
                      _SourcePill(label: 'PHONE', color: palette.attention),
                    if (source.mayLogPrompts)
                      _SourcePill(label: 'RELAY ⚠', color: palette.danger),
                  ],
                ),
                if (source.note != null && source.note!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    source.note!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.45),
                  ),
                ],
                if (source.baseUrl != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
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
                      source.baseUrl!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                          fontFamily: 'monospace',
                          fontFamilyFallback: const ['Roboto Mono', 'Courier'],
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (source.baseUrl != null)
                      Flexible(
                        child: OutlinedButton.icon(
                          onPressed: () => onCopyBaseUrl(source.baseUrl!),
                          icon: const Icon(Icons.copy_rounded, size: 15),
                          label: const Text('Copy URL',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(11)),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: FilledButton.icon(
                        onPressed: () =>
                            onOpenUrl(source.keyUrl ?? source.infoUrl),
                        icon: const Icon(Icons.key_rounded, size: 15),
                        label: Text(source.keyUrl != null ? 'Get key' : 'Open',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        style: FilledButton.styleFrom(
                          backgroundColor: palette.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11)),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Limits & docs',
                      onPressed: () => onOpenUrl(source.infoUrl),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'checked ${source.verifiedOn}',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.8),
                      fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourcePill extends StatelessWidget {
  const _SourcePill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: color,
        ),
      ),
    );
  }
}
