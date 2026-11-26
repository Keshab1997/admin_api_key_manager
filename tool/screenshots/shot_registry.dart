import 'shot_framework.dart';
import 'package:material_ui/material_ui.dart';
import 'package:admin_api_key_manager/models/admin_api_key.dart';
import 'package:admin_api_key_manager/theme/key_admin_palette.dart';
import 'package:admin_api_key_manager/screens/widgets/admin_screen_widgets.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ── Mock data ──

AdminApiKey _mk(String id, String title, String provider, String model,
    {bool isActive = true, int priority = 1, int usage = 42, int errors = 0}) {
  return AdminApiKey.fromMap({
    'name': title,
    'key': 'sk-or-v1-abcdefghijklmnopqrstuvwxyz0123456789',
    'baseUrl': AdminApiKey.providerDefaults[provider]?.baseUrl ??
        'https://api.openrouter.ai/api/v1',
    'model': model,
    'provider': provider,
    'isActive': isActive,
    'priority': priority,
    'usageCount': usage,
    'errorCount': errors,
    'addedBy': 'admin',
    'createdAt': Timestamp.now(),
    'updatedAt': Timestamp.now(),
  }, id);
}

final _mockRows = [
  AdminKeyRow(
      key: _mk('1', 'Primary OpenRouter', 'openrouter', 'openai/gpt-4o-mini',
          usage: 128, errors: 0, priority: 1),
      onCooldownUntil: null),
  AdminKeyRow(
      key: _mk('2', 'Gemini Flash', 'google', 'gemini-2.0-flash',
          usage: 87, errors: 3, priority: 2),
      onCooldownUntil: DateTime.now().add(const Duration(minutes: 4))),
  AdminKeyRow(
      key: _mk('3', 'Backup Custom', 'custom', 'llama-3.1-70b',
          isActive: false, usage: 12, errors: 12, priority: 3),
      onCooldownUntil: null),
];

// ── Helper: premium AppBar ──
AppBar _premiumAppBar(BuildContext context,
    {required String title,
    required String subtitle,
    required IconData icon,
    Color? iconBg,
    Color? iconColor}) {
  final theme = Theme.of(context);
  final palette = KeyAdminPalette.of(context);
  final bg = iconBg ?? palette.accent;
  return AppBar(
    backgroundColor: theme.colorScheme.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    titleSpacing: 16,
    title: Row(children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [bg, bg.withValues(alpha: 0.72)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 16, color: iconColor ?? Colors.white),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800, letterSpacing: -0.2)),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      fontSize: 11)),
            ]),
      ),
    ]),
    centerTitle: false,
  );
}

// ── Shots ──

class _AdminKeysShot extends StatelessWidget {
  const _AdminKeysShot();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: _premiumAppBar(context,
          title: 'API keys',
          subtitle: '3 keys · 2 active',
          icon: Icons.key_rounded),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: KeyAdminPalette.of(context).accent,
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: () {},
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add key',
            style: TextStyle(fontWeight: FontWeight.w700)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(
              child: AdminSummary(
                  total: 3,
                  active: 2,
                  trouble: 1,
                  filter: AdminKeyFilter.all,
                  onFilter: _noop)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.swap_vert, size: 18),
                      label: const Text('Reorder failover'))),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            sliver: SliverList.separated(
              itemCount: _mockRows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => AdminKeyCard(
                  row: _mockRows[i],
                  revealed: i == 1,
                  onReveal: () {},
                  onTest: () {},
                  onEdit: () {},
                  onDelete: () {},
                  onToggle: (_) {}),
            ),
          ),
        ],
      ),
    );
  }
}

void _noop(AdminKeyFilter _) {}

class _FreeModelsShot extends StatelessWidget {
  const _FreeModelsShot();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = KeyAdminPalette.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: _premiumAppBar(context,
          title: 'Free models',
          subtitle: 'OpenRouter catalog · live',
          icon: Icons.explore_rounded),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Search gpt, claude, gemma, llama…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: theme.colorScheme.surface,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.55))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: theme.colorScheme.outlineVariant
                                          .withValues(alpha: 0.55))),
                              child: Row(children: [
                                Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                        color: palette.accent,
                                        shape: BoxShape.circle)),
                                const SizedBox(width: 7),
                                const Expanded(
                                    child: Text('All providers',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13))),
                                const Icon(Icons.expand_more_rounded, size: 16)
                              ]))),
                      const SizedBox(width: 8),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                              color: palette.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color:
                                      palette.accent.withValues(alpha: 0.28))),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.check_circle_rounded,
                                size: 14, color: palette.accent),
                            const SizedBox(width: 5),
                            const Text('Free only',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 12))
                          ])),
                    ]),
                  ]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            sliver: SliverList.separated(
              itemCount: 2,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _MockFreeCard(free: i == 0),
            ),
          ),
        ],
      ),
    );
  }
}

class _MockFreeCard extends StatelessWidget {
  const _MockFreeCard({required this.free});
  final bool free;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = KeyAdminPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: free
                ? palette.healthy.withValues(alpha: 0.22)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            height: 3,
            color: free ? palette.healthy : theme.colorScheme.outlineVariant),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                      color: free
                          ? palette.healthy.withValues(alpha: 0.12)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                          color: free
                              ? palette.healthy.withValues(alpha: 0.18)
                              : theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.4))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                            color: free
                                ? palette.healthy
                                : theme.colorScheme.onSurfaceVariant,
                            shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text(free ? 'FREE' : 'PAID',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: free
                                ? const Color(0xFF0B7A5A)
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                            fontSize: 11))
                  ])),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(free ? 'Meta' : 'OpenAI',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700))),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                          color: palette.accent.withValues(alpha: 0.14))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.memory_outlined,
                        size: 11, color: palette.accent),
                    const SizedBox(width: 4),
                    Text(free ? '128k' : '32k',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: palette.accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 11))
                  ])),
            ]),
            const SizedBox(height: 12),
            Text(
                free
                    ? 'meta-llama/llama-3.1-70b-instruct:free'
                    : 'openai/gpt-4o-mini',
                style: theme.textTheme.titleSmall?.copyWith(
                    fontFamily: 'monospace', fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
                free
                    ? 'Meta Llama 3.1 70B Instruct — free tier, great for reasoning'
                    : 'GPT-4o mini — fast, cheap, reliable',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Container(
                height: 1,
                color:
                    theme.colorScheme.outlineVariant.withValues(alpha: 0.45)),
            const SizedBox(height: 8),
            Row(children: [
              Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.5))),
                  child: Icon(Icons.copy_rounded,
                      size: 16, color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.key_rounded, size: 16),
                  label: const Text('Get key',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11)),
                      visualDensity: VisualDensity.compact)),
              const Spacer(),
              FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Use',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  style: FilledButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11)),
                      visualDensity: VisualDensity.compact)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _ErrorLogsShot extends StatelessWidget {
  const _ErrorLogsShot();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = KeyAdminPalette.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: _premiumAppBar(context,
          title: 'Error log',
          subtitle: 'Last 200 failures · newest first',
          icon: Icons.receipt_long_rounded,
          iconBg: palette.danger,
          iconColor: palette.danger),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.55))),
            child: Row(children: [
              Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.insights_outlined,
                      size: 15, color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                      '4 failures in the last 2h · 2 keys · chat, completion',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500)))
            ]),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final label in ['All 4', 'Rate 1', 'Auth 1', 'Server 1'])
                Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                        label: Text(label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 11)),
                        selected: label == 'All 4',
                        selectedColor: palette.accent.withValues(alpha: 0.13),
                        backgroundColor: theme.colorScheme.surface,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onSelected: (_) {})),
            ]),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < 3; i++)
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MockLogTile(i: i)),
        ],
      ),
    );
  }
}

class _MockLogTile extends StatelessWidget {
  const _MockLogTile({required this.i});
  final int i;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = KeyAdminPalette.of(context);
    final tones = [
      (palette.attention, Icons.speed_rounded, 'Rate limit'),
      (palette.danger, Icons.lock_rounded, 'Auth'),
      (palette.danger, Icons.cloud_off_rounded, 'Server')
    ];
    final (tone, icon, label) = tones[i % 3];
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
                offset: const Offset(0, 3))
          ]),
      child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tone.withValues(alpha: 0.18))),
                child: Icon(icon, size: 18, color: tone)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: tone.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(label,
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: tone,
                                fontWeight: FontWeight.w800,
                                fontSize: 10))),
                    const SizedBox(width: 5),
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text('HTTP ${[429, 401, 500][i]}',
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                                fontSize: 10))),
                    const Spacer(),
                    Text('${[5, 12, 30][i]}m ago',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            fontSize: 11))
                  ]),
                  const SizedBox(height: 6),
                  Text('Primary OpenRouter · chat',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('Provider returned an error for this key.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ])),
          ])),
    );
  }
}

class _GroupsShot extends StatelessWidget {
  const _GroupsShot();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = KeyAdminPalette.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: _premiumAppBar(context,
          title: 'Provider groups',
          subtitle: 'Priority & cooldowns per provider',
          icon: Icons.tune_rounded),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                  color: palette.accentSoft,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: palette.accent.withValues(alpha: 0.14))),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                        color: palette.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.info_outline_rounded,
                        size: 16, color: palette.accent)),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(
                        'Lower priority wins. Enabled groups carry the load, the rest wait in reserve.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w500)))
              ])),
          const SizedBox(height: 14),
          for (final p in ['openrouter', 'google', 'custom'])
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _MockGroupCard(provider: p)),
        ],
      ),
    );
  }
}

class _MockGroupCard extends StatelessWidget {
  const _MockGroupCard({required this.provider});
  final String provider;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = KeyAdminPalette.of(context);
    final name = AdminApiKey.providerName(provider);
    final grad = provider == 'google'
        ? [const Color(0xFF4285F4), const Color(0xFF8AB4F8)]
        : provider == 'openrouter'
            ? [palette.accent, const Color(0xFF8B8CF8)]
            : [theme.colorScheme.secondary, theme.colorScheme.tertiary];
    final icon = provider == 'google'
        ? Icons.auto_awesome_rounded
        : provider == 'openrouter'
            ? Icons.alt_route_rounded
            : Icons.lan_rounded;
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
                offset: const Offset(0, 4))
          ]),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(height: 3, color: palette.healthy),
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: grad,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, size: 20, color: Colors.white)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(name,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                          'Enabled · priority ${provider == 'openrouter' ? 1 : provider == 'google' ? 2 : 100}',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: const Color(0xFF0B7A5A),
                              fontWeight: FontWeight.w600))
                    ])),
                Transform.scale(
                    scale: 0.88,
                    child: Switch(
                        value: true,
                        onChanged: (_) {},
                        thumbColor: WidgetStatePropertyAll(palette.healthy),
                        trackColor: WidgetStatePropertyAll(
                            palette.healthy.withValues(alpha: 0.22)))),
              ]),
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
                              .withValues(alpha: 0.35))),
                  child: Row(children: [
                    Icon(Icons.timer_outlined,
                        size: 14, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 7),
                    Expanded(
                        child: Text('429 60s · 5xx 120s · other 30s',
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600)))
                  ])),
              const SizedBox(height: 10),
              Container(
                  height: 1,
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.45)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.sort_rounded, size: 16),
                    label: const Text('Priority',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11)),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8))),
                FilledButton.tonalIcon(
                    onPressed: () {},
                    icon: const Icon(Icons.timer_outlined, size: 16),
                    label: const Text('Cooldowns',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11)),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8))),
              ]),
            ])),
      ]),
    );
  }
}

final List<Shot> shots = <Shot>[
  Shot(name: 'admin-keys', build: () => const _AdminKeysShot()),
  Shot(name: 'free-models', build: () => const _FreeModelsShot()),
  Shot(
      name: 'error-logs',
      build: () => const _ErrorLogsShot(),
      logicalSize: const Size(400, 900)),
  Shot(
      name: 'provider-groups',
      build: () => const _GroupsShot(),
      logicalSize: const Size(390, 900)),
];

final ShotEnv env = ShotEnv(
  app: (shot, home) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1), brightness: Brightness.light),
      useMaterial3: true,
      extensions: const [KeyAdminPalette.fallback],
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1), brightness: Brightness.dark),
      useMaterial3: true,
      extensions: const [KeyAdminPalette.fallback],
    ),
    themeMode: shot.dark ? ThemeMode.dark : ThemeMode.light,
    home: home,
  ),
);
