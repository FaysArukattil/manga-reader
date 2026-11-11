import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Dark Theme Surfaces
  static const Color darkBackground = Color(0xFF0D0E11);
  static const Color darkSurface = Color(0xFF16171C);
  static const Color darkSurfaceContainer = Color(0xFF1F2027);
  static const Color darkSurfaceCard = Color(0xFF272932);
  static const Color darkBorder = Color(0x1FFFFFFF);

  // Light Theme Surfaces
  static const Color lightBackground = Color(0xFFF8F9FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceContainer = Color(0xFFF1F3F5);
  static const Color lightSurfaceCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0x12000000);

  // Distinctive Accents
  static const Color primary = Color(0xFF00C875);
  static const Color primaryGlow = Color(0x3300C875);
  static const Color secondary = Color(0xFF6366F1);
  static const Color amber = Color(0xFFFFB020);
  static const Color crimson = Color(0xFFFF4D4F);

  // Typography Tokens
  static const Color textDarkPrimary = Color(0xFFF5F6F8);
  static const Color textDarkSecondary = Color(0xFFA0A4B2);
  static const Color textDarkTertiary = Color(0xFF666A78);

  static const Color textLightPrimary = Color(0xFF111216);
  static const Color textLightSecondary = Color(0xFF5A5E6B);
  static const Color textLightTertiary = Color(0xFF8F94A0);
}

@immutable
class AppThemeTokens extends ThemeExtension<AppThemeTokens> {
  const AppThemeTokens({
    required this.bg,
    required this.surface,
    required this.surfaceCard,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
  });

  final Color bg;
  final Color surface;
  final Color surfaceCard;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;

  static const dark = AppThemeTokens(
    bg: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    surfaceCard: AppColors.darkSurfaceCard,
    border: AppColors.darkBorder,
    textPrimary: AppColors.textDarkPrimary,
    textSecondary: AppColors.textDarkSecondary,
    textTertiary: AppColors.textDarkTertiary,
    accent: AppColors.primary,
  );

  static const light = AppThemeTokens(
    bg: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    surfaceCard: AppColors.lightSurfaceCard,
    border: AppColors.lightBorder,
    textPrimary: AppColors.textLightPrimary,
    textSecondary: AppColors.textLightSecondary,
    textTertiary: AppColors.textLightTertiary,
    accent: AppColors.primary,
  );

  @override
  AppThemeTokens copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceCard,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
  }) =>
      AppThemeTokens(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surfaceCard: surfaceCard ?? this.surfaceCard,
        border: border ?? this.border,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textTertiary: textTertiary ?? this.textTertiary,
        accent: accent ?? this.accent,
      );

  @override
  AppThemeTokens lerp(ThemeExtension<AppThemeTokens>? other, double t) {
    if (other is! AppThemeTokens) return this;
    return AppThemeTokens(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceCard: Color.lerp(surfaceCard, other.surfaceCard, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
    );
  }
}

/// Shorthand for reading the current theme tokens anywhere in the UI:
/// `context.tokens.textPrimary`. Falls back to the dark tokens (the app is
/// dark-first) if the extension is missing, e.g. in a bare MaterialApp test.
extension AppTokensX on BuildContext {
  AppThemeTokens get tokens =>
      Theme.of(this).extension<AppThemeTokens>() ?? AppThemeTokens.dark;
}
