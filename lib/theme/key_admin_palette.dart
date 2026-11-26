import 'package:material_ui/material_ui.dart';

/// State colours for the key list, as a `ThemeExtension` so the screen inherits
/// the host theme and a host can supply its own without forking the widget.
@immutable
class KeyAdminPalette extends ThemeExtension<KeyAdminPalette> {
  const KeyAdminPalette({
    required this.healthy,
    required this.attention,
    required this.danger,
  });

  final Color healthy;
  final Color attention;
  final Color danger;

  /// Deliberately readable on light and dark surfaces; a host app with its own
  /// brand states should add `KeyAdminPalette(...)` to `ThemeData.extensions`.
  static const KeyAdminPalette fallback = KeyAdminPalette(
    healthy: Color(0xFF18A06A),
    attention: Color(0xFFD98300),
    danger: Color(0xFFD64550),
  );

  static KeyAdminPalette of(BuildContext context) =>
      Theme.of(context).extension<KeyAdminPalette>() ?? fallback;

  @override
  KeyAdminPalette copyWith({Color? healthy, Color? attention, Color? danger}) {
    return KeyAdminPalette(
      healthy: healthy ?? this.healthy,
      attention: attention ?? this.attention,
      danger: danger ?? this.danger,
    );
  }

  @override
  KeyAdminPalette lerp(ThemeExtension<KeyAdminPalette>? other, double t) {
    if (other is! KeyAdminPalette) return this;
    return KeyAdminPalette(
      healthy: Color.lerp(healthy, other.healthy, t)!,
      attention: Color.lerp(attention, other.attention, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}
