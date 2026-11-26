import 'package:material_ui/material_ui.dart';

/// State + accent colours for the admin screens, as a [ThemeExtension] so the
/// host theme owns them and a host can supply its own without forking.
///
/// Every colour is chosen to stay readable on light **and** dark surfaces
/// at 4.5:1 — the screen never relies on colour alone, but when it does use
/// colour it should still pass contrast.
@immutable
class KeyAdminPalette extends ThemeExtension<KeyAdminPalette> {
  const KeyAdminPalette({
    required this.healthy,
    required this.attention,
    required this.danger,
    this.accent = const Color(0xFF6366F1),
    this.accentSoft = const Color(0xFFEEF2FF),
  });

  final Color healthy;
  final Color attention;
  final Color danger;

  /// Brand accent — used for primary CTAs, active filters and the top
  /// highlight on cards. Indigo keeps it distinct from the three state
  /// colours so "healthy green" never competes with "brand indigo".
  final Color accent;
  final Color accentSoft;

  /// Premium fallback tuned for contrast on both light/dark.
  /// Emerald / amber / rose — jewel tones that feel admin-grade, not alert-red.
  static const KeyAdminPalette fallback = KeyAdminPalette(
    healthy: Color(0xFF0EA67A),
    attention: Color(0xFFE67E22),
    danger: Color(0xFFE11D48),
    accent: Color(0xFF6366F1),
    accentSoft: Color(0xFFEEF2FF),
  );

  static KeyAdminPalette of(BuildContext context) =>
      Theme.of(context).extension<KeyAdminPalette>() ?? fallback;

  // Soft containers — 12% tint, used for pill / badge backgrounds.
  Color get healthySoft => healthy.withValues(alpha: 0.12);
  Color get attentionSoft => attention.withValues(alpha: 0.12);
  Color get dangerSoft => danger.withValues(alpha: 0.12);

  // On-soft text colours — slightly darker so the label reads as text, not wash.
  Color get healthyText => const Color(0xFF0B7A5A);
  Color get attentionText => const Color(0xFF9A5A0A);
  Color get dangerText => const Color(0xFFBE123C);

  @override
  KeyAdminPalette copyWith({
    Color? healthy,
    Color? attention,
    Color? danger,
    Color? accent,
    Color? accentSoft,
  }) {
    return KeyAdminPalette(
      healthy: healthy ?? this.healthy,
      attention: attention ?? this.attention,
      danger: danger ?? this.danger,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
    );
  }

  @override
  KeyAdminPalette lerp(ThemeExtension<KeyAdminPalette>? other, double t) {
    if (other is! KeyAdminPalette) return this;
    return KeyAdminPalette(
      healthy: Color.lerp(healthy, other.healthy, t)!,
      attention: Color.lerp(attention, other.attention, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
    );
  }
}
