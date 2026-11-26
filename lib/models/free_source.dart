/// A place that hands out free model access: either a provider running its own
/// free tier, or a gateway that resells one.
///
/// Curated by hand rather than scraped, on purpose. A scraped "free models"
/// page is wrong within a week — quotas move (NaraRouter cut its free plan from
/// ten models to one inside a fortnight), cards and phone numbers get added,
/// and a gateway can start logging prompts at any time. So every entry carries
/// the date it was last checked and a link to the page that is authoritative:
/// treat this list as an index of *where to look*, never as the price sheet.
library;

/// How a [FreeSource] relates to the models it serves.
enum FreeSourceKind {
  /// The model maker's own API (Google, Groq, Mistral, …). Free tier is a
  /// deliberate loss-leader, so it tends to last.
  provider,

  /// A company routing to other people's models behind one key. Free quota is
  /// usually generous and usually temporary.
  gateway,

  /// A marketplace of many providers behind one key (OpenRouter and friends).
  /// Free models are per-model `:free` variants.
  aggregator,
}

/// One free-model source in the directory.
class FreeSource {
  const FreeSource({
    required this.id,
    required this.name,
    required this.kind,
    required this.freeAllowance,
    required this.infoUrl,
    this.baseUrl,
    this.keyUrl,
    this.dailyTokens,
    this.maxRequestsPerMinute,
    this.needsCard = false,
    this.needsPhone = false,
    this.relay = false,
    this.verifiedOn = '2026-11-26',
    this.note,
  });

  /// Stable id, also used as the search key.
  final String id;

  /// Display name, e.g. `Google AI Studio`.
  final String name;

  final FreeSourceKind kind;

  /// The free allowance in the words the source itself uses, e.g.
  /// `7M tokens/day` or `20 req/min · 50 req/day`. Short enough for a pill.
  final String freeAllowance;

  /// OpenAI-compatible base URL to paste into a key's "Base URL" field. Null
  /// when the source is not OpenAI-compatible (the [infoUrl] explains its own
  /// shape) — Cloudflare Workers AI, for one, needs an account id in the path.
  final String? baseUrl;

  /// Where a human signs up / creates an API key.
  final String? keyUrl;

  /// Where the source documents its limits. This is the authority; the number
  /// above it is a snapshot.
  final String infoUrl;

  /// Daily token allowance, when the source quotes one — used for the pill,
  /// never for a hard limit.
  final int? dailyTokens;

  final int? maxRequestsPerMinute;

  /// A bank card is required before the free tier works.
  final bool needsCard;

  /// A phone number is required to sign up.
  final bool needsPhone;

  /// The source forwards prompts to upstream providers that may log or train on
  /// them. Fine for experiments, wrong for a student's essay or a prescription.
  final bool relay;

  /// The day the allowance was last confirmed by a human. Anything older than a
  /// couple of weeks deserves a re-check before it is trusted.
  final String verifiedOn;

  /// One line of practical advice — what actually bites when you sign up.
  final String? note;

  /// `gateway` / `aggregator` sources are the ones that may see prompts, so the
  /// warning is derived rather than repeated in every entry.
  bool get mayLogPrompts => relay || kind != FreeSourceKind.provider;

  /// `7.0M` style short form, or null when no daily token figure is quoted.
  String? get dailyTokensLabel {
    final daily = dailyTokens;
    if (daily == null) return null;
    if (daily >= 1000000) {
      final millions = daily / 1000000;
      return millions == millions.roundToDouble()
          ? '${millions.toStringAsFixed(0)}M/day'
          : '${millions.toStringAsFixed(1)}M/day';
    }
    if (daily >= 1000) return '${(daily / 1000).round()}k/day';
    return '$daily/day';
  }

  /// True when [baseUrl] can be pasted into a key form as-is.
  bool get isOpenAiCompatible => baseUrl != null;
}

/// The directory, newest check first. Keep it short: a list of thirty gateways
/// nobody has verified is worse than twelve that were.
const List<FreeSource> kFreeSources = [
  FreeSource(
    id: 'openrouter',
    name: 'OpenRouter',
    kind: FreeSourceKind.aggregator,
    freeAllowance: '~17 free models · 20 req/min',
    baseUrl: 'https://openrouter.ai/api/v1',
    keyUrl: 'https://openrouter.ai/keys',
    infoUrl: 'https://openrouter.ai/docs/api-reference/limits',
    maxRequestsPerMinute: 20,
    note: 'Model ids ending in ":free". 50 requests/day until a one-off \$10 '
        'top-up lifts it. The catalog this screen already lists.',
  ),
  FreeSource(
    id: 'google-ai-studio',
    name: 'Google AI Studio',
    kind: FreeSourceKind.provider,
    freeAllowance: '5–30 req/min · 1M context',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    keyUrl: 'https://aistudio.google.com/app/apikey',
    infoUrl: 'https://ai.google.dev/gemini-api/docs/rate-limits',
    note: 'Best context window of any free tier. Free-tier prompts may be used '
        'to improve Google products — no student data.',
  ),
  FreeSource(
    id: 'groq',
    name: 'Groq',
    kind: FreeSourceKind.provider,
    freeAllowance: '30 req/min · 1k req/day',
    baseUrl: 'https://api.groq.com/openai/v1',
    keyUrl: 'https://console.groq.com/keys',
    infoUrl: 'https://console.groq.com/docs/rate-limits',
    maxRequestsPerMinute: 30,
    note:
        'Fastest tokens/sec here, open-weight models only (Llama, Qwen, GPT-OSS).',
  ),
  FreeSource(
    id: 'cerebras',
    name: 'Cerebras',
    kind: FreeSourceKind.provider,
    freeAllowance: 'free tier · daily token cap',
    baseUrl: 'https://api.cerebras.ai/v1',
    keyUrl: 'https://cloud.cerebras.ai',
    infoUrl: 'https://inference-docs.cerebras.ai/support/rate-limits',
    note: 'Wafer-scale silicon: very fast, small daily cap. Good for short '
        'question-generation bursts.',
  ),
  FreeSource(
    id: 'mistral',
    name: 'Mistral AI',
    kind: FreeSourceKind.provider,
    freeAllowance: 'large monthly free allowance',
    baseUrl: 'https://api.mistral.ai/v1',
    keyUrl: 'https://console.mistral.ai/api-keys',
    infoUrl: 'https://docs.mistral.ai/deployment/laplateforme/tier/',
    note: 'One of the biggest monthly volumes in any free tier; the exact cap '
        'changes with the experiment plan.',
  ),
  FreeSource(
    id: 'cloudflare-workers-ai',
    name: 'Cloudflare Workers AI',
    kind: FreeSourceKind.provider,
    freeAllowance: 'daily free allowance · 20+ models',
    keyUrl: 'https://dash.cloudflare.com/profile/api-tokens',
    infoUrl: 'https://developers.cloudflare.com/workers-ai/platform/pricing/',
    note: 'Not OpenAI-shaped: the URL carries your account id. Generous daily '
        'allowance in "neural units".',
  ),
  FreeSource(
    id: 'cohere',
    name: 'Cohere',
    kind: FreeSourceKind.provider,
    freeAllowance: 'trial key · 20 req/min',
    baseUrl: 'https://api.cohere.com',
    keyUrl: 'https://dashboard.cohere.com/api-keys',
    infoUrl: 'https://docs.cohere.com/docs/rate-limits',
    maxRequestsPerMinute: 20,
    note: 'Also gives free embeddings and rerank — useful if you ever add '
        'semantic search over the question bank.',
  ),
  FreeSource(
    id: 'nvidia-nim',
    name: 'NVIDIA NIM',
    kind: FreeSourceKind.provider,
    freeAllowance: '~40 req/min · 16 models',
    baseUrl: 'https://integrate.api.nvidia.com/v1',
    keyUrl: 'https://build.nvidia.com',
    infoUrl: 'https://docs.api.nvidia.com/nim/reference/models-1',
    needsPhone: true,
    maxRequestsPerMinute: 40,
    note: 'Hosts the big Nemotron models. Sign-up asks for a phone number.',
  ),
  FreeSource(
    id: 'github-models',
    name: 'GitHub Models',
    kind: FreeSourceKind.provider,
    freeAllowance: 'free with a GitHub account',
    baseUrl: 'https://models.github.ai/inference',
    keyUrl: 'https://github.com/settings/tokens',
    infoUrl: 'https://docs.github.com/en/github-models',
    note: 'Auth is a GitHub PAT, rate-limited per account. Handy because you '
        'already own the account this repo lives in.',
  ),
  FreeSource(
    id: 'hugging-face',
    name: 'Hugging Face Inference',
    kind: FreeSourceKind.provider,
    freeAllowance: 'monthly credit · many models',
    baseUrl: 'https://router.huggingface.co/v1',
    keyUrl: 'https://huggingface.co/settings/tokens',
    infoUrl: 'https://huggingface.co/docs/inference-providers/pricing',
    note: 'Small free monthly credit spread across providers; the model ids '
        'are the open-weight ones you can also self-host later.',
  ),
  FreeSource(
    id: 'nararouter',
    name: 'NaraRouter',
    kind: FreeSourceKind.gateway,
    freeAllowance: '7M tokens/day · 15 req/min',
    baseUrl: 'https://router.bynara.id/v1',
    keyUrl: 'https://router.bynara.id',
    infoUrl: 'https://router.bynara.id',
    dailyTokens: 7000000,
    maxRequestsPerMinute: 15,
    relay: true,
    note: 'Indonesian gateway, no card. Free plan was cut from 10 models to 1 '
        'in October 2026, and free access wants Telegram linked or a \$1 top-up. '
        'Assume prompts are logged.',
  ),
];

/// Case-insensitive search over the directory, plus a provider-only switch —
/// "no relay, no surprises" is the filter most people actually want.
List<FreeSource> filterSources(
  List<FreeSource> sources, {
  String query = '',
  bool providersOnly = false,
}) {
  final q = query.trim().toLowerCase();
  return sources.where((s) {
    if (providersOnly && s.kind != FreeSourceKind.provider) return false;
    if (q.isEmpty) return true;
    return s.name.toLowerCase().contains(q) ||
        s.id.toLowerCase().contains(q) ||
        s.freeAllowance.toLowerCase().contains(q) ||
        (s.baseUrl?.toLowerCase().contains(q) ?? false) ||
        (s.note?.toLowerCase().contains(q) ?? false);
  }).toList();
}
