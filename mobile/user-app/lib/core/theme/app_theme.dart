import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFFFF2B66);
  static const Color primaryPink = Color(0xFFFF2B66);
  static const Color primaryHover = Color(0xFFFF4D80);
  static const Color primaryDark = Color(0xFFE61952);
  static const Color primaryLight = Color(0xFFFFF0F4);
  static const Color primaryIndicator = Color(0xFFFFE7EE);
  static const Color violet = Color(0xFF7C3AED);
  static const Color violetLight = Color(0xFFF1ECFF);
  static const Color ink = Color(0xFF17111F);

  static const Color background = Color(0xFFFAF8F7);
  static const Color backgroundCard = Colors.white;
  static const Color surface = Colors.white;
  static const Color surfaceAlt = Color(0xFFF7F7F9);
  static const Color textPrimary = Color(0xFF17111F);
  static const Color textSecondary = Color(0xFF374151);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color textLight = Color(0xFF9CA3AF);
  static const Color border = Color(0xFFE5E7EB);
  static const Color cardBorder = Color(0xFFE5E7EB);
  static const Color borderSubtle = Color(0xFFF0F0F2);

  static const Color darkBackground = Color(0xFF111018);
  static const Color darkBackgroundCard = Color(0xFF1C1824);
  static const Color darkSurface = Color(0xFF1C1824);
  static const Color darkTextPrimary = Color(0xFFFFFBFE);
  static const Color darkTextSecondary = Color(0xFFD0C8D5);
  static const Color darkTextMuted = Color(0xFFA59AAE);
  static const Color darkBorder = Color(0xFF352C3D);
  static const Color darkCardBorder = Color(0xFF352C3D);

  static const Color danger = Color(0xFFDC2626);
  static const Color dangerBg = Color(0xFFFEE2E2);
  static const Color dangerBorder = Color(0xFFFCA5A5);
  static const Color success = Color(0xFF10B981);
  static const Color successBg = Color(0xFFD1FAE5);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFFF2B66), Color(0xFFFF4D80)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static Color surfaceFor(BuildContext context) =>
      Theme.of(context).colorScheme.surface;
  static Color surfaceAltFor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? darkBackgroundCard
      : surfaceAlt;
  static Color violetContainerFor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF2A2140)
      : violetLight;
  static Color textPrimaryFor(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;
  static Color textSecondaryFor(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;
  static Color textMutedFor(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: .78);
  static Color borderFor(BuildContext context) =>
      Theme.of(context).dividerColor;
  static Color dangerFor(BuildContext context) =>
      Theme.of(context).colorScheme.error;
  static Color dangerContainerFor(BuildContext context) =>
      Theme.of(context).colorScheme.errorContainer;
  static Color onDangerContainerFor(BuildContext context) =>
      Theme.of(context).colorScheme.onErrorContainer;
}

class AppTheme {
  static ThemeData get theme => lightTheme;

  static ThemeData get lightTheme => _build(
    brightness: Brightness.light,
    scheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textMuted,
      error: AppColors.danger,
    ),
    scaffold: AppColors.background,
    surface: AppColors.surface,
    text: AppColors.textPrimary,
    secondaryText: AppColors.textMuted,
    border: AppColors.border,
    navBackground: AppColors.surface,
    navIndicator: AppColors.primaryIndicator,
  );

  static ThemeData get darkTheme => _build(
    brightness: Brightness.dark,
    scheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      primary: AppColors.primary,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkTextPrimary,
      onSurfaceVariant: AppColors.darkTextMuted,
      error: AppColors.danger,
    ),
    scaffold: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    text: AppColors.darkTextPrimary,
    secondaryText: AppColors.darkTextMuted,
    border: AppColors.darkBorder,
    navBackground: AppColors.darkSurface,
    navIndicator: const Color(0x33FF2B66),
  );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required Color scaffold,
    required Color surface,
    required Color text,
    required Color secondaryText,
    required Color border,
    required Color navBackground,
    required Color navIndicator,
  }) {
    final dark = brightness == Brightness.dark;
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: border),
    );
    final textTheme = ThemeData(brightness: brightness).textTheme.apply(
      fontFamily: 'Plus Jakarta Sans',
      bodyColor: text,
      displayColor: text,
      decorationColor: secondaryText,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'Plus Jakarta Sans',
      textTheme: textTheme,
      scaffoldBackgroundColor: scaffold,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: text),
        titleTextStyle: TextStyle(
          color: text,
          fontFamily: 'Plus Jakarta Sans',
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: navBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 72,
        indicatorColor: navIndicator,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'Plus Jakarta Sans',
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: text,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? AppColors.darkBackgroundCard : AppColors.surface,
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        labelStyle: TextStyle(color: secondaryText),
        hintStyle: TextStyle(color: secondaryText.withValues(alpha: .75)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Plus Jakarta Sans',
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: dark
              ? AppColors.primaryHover
              : AppColors.primaryDark,
          side: BorderSide(
            color: dark ? AppColors.primaryHover : AppColors.primary,
          ),
          minimumSize: const Size.fromHeight(50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Plus Jakarta Sans',
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: dark
              ? AppColors.primaryHover
              : AppColors.primaryDark,
          minimumSize: const Size(48, 46),
          textStyle: const TextStyle(
            fontFamily: 'Plus Jakarta Sans',
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: dark
            ? AppColors.darkBackgroundCard
            : AppColors.surface,
        selectedColor: dark
            ? const Color(0x33FF2B66)
            : AppColors.primaryIndicator,
        disabledColor: dark
            ? AppColors.darkBackgroundCard
            : AppColors.surfaceAlt,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        labelStyle: TextStyle(
          fontFamily: 'Plus Jakarta Sans',
          color: text,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(22)),
        ),
      ),
      dividerColor: border,
      splashFactory: InkSparkle.splashFactory,
    );
  }
}
