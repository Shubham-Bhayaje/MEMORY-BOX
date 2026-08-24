import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';

/// Design system for Memory Box — based on Google Stitch M3 palette.
class AppTheme {
  AppTheme._();

  // ───── RADII ─────
  static const double radiusXs = 4.0;
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;
  static const double radiusFull = 9999.0;

  // ───── SPACING ─────
  static const double unit = 8.0;
  static const double gutter = 16.0;
  static const double containerPadding = 24.0;
  static const double chatSpacing = 12.0;
  static const double memoryCardGap = 20.0;

  // ───── COLORS (Material 3 Stitch Palette) ─────
  static const Color primary = Color(0xFF27227B);
  static const Color primaryContainer = Color(0xFF3E3B92);
  static const Color primaryFixed = Color(0xFFE2DFFF);
  static const Color primaryFixedDim = Color(0xFFC3C0FF);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFFAFADFF);
  static const Color onPrimaryFixed = Color(0xFF0F0267);

  static const Color secondary = Color(0xFF6B38D4);
  static const Color secondaryContainer = Color(0xFF8455EF);
  static const Color secondaryFixed = Color(0xFFE9DDFF);
  static const Color secondaryFixedDim = Color(0xFFD0BCFF);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onSecondaryContainer = Color(0xFFFFFBFF);

  static const Color tertiary = Color(0xFF003640);
  static const Color tertiaryContainer = Color(0xFF004E5C);
  static const Color tertiaryFixed = Color(0xFFACEDFF);
  static const Color tertiaryFixedDim = Color(0xFF4CD7F6);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color onTertiaryContainer = Color(0xFF30C5E3);

  static const Color surface = Color(0xFFF7F9FB);
  static const Color surfaceDim = Color(0xFFD8DADC);
  static const Color surfaceBright = Color(0xFFF7F9FB);
  static const Color surfaceContainer = Color(0xFFECEEF0);
  static const Color surfaceContainerLow = Color(0xFFF2F4F6);
  static const Color surfaceContainerHigh = Color(0xFFE6E8EA);
  static const Color surfaceContainerHighest = Color(0xFFE0E3E5);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFE0E3E5);
  static const Color surfaceTint = Color(0xFF5654AC);

  static const Color onSurface = Color(0xFF191C1E);
  static const Color onSurfaceVariant = Color(0xFF474551);
  static const Color onBackground = Color(0xFF191C1E);
  static const Color inverseSurface = Color(0xFF2D3133);
  static const Color inverseOnSurface = Color(0xFFEFF1F3);
  static const Color inversePrimary = Color(0xFFC3C0FF);

  static const Color outline = Color(0xFF777683);
  static const Color outlineVariant = Color(0xFFC8C5D3);

  static const Color error = Color(0xFFBA1A1A);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color onErrorContainer = Color(0xFF93000A);

  // Legacy aliases for backward compat during migration
  static const Color background = surface;
  static const Color textPrimary = onSurface;
  static const Color textSecondary = onSurfaceVariant;
  static const Color textTertiary = outline;
  static const Color border = outlineVariant;
  static const Color borderLight = surfaceVariant;
  static const Color surfaceAlt = surfaceContainerLow;
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF97316);
  static const Color accent = Color(0xFFF59E0B);
  static const Color primaryLight = primaryFixedDim;
  static const Color primaryDark = primaryContainer;
  static const Color secondaryLight = secondaryFixedDim;

  // ───── MEMORY TYPE COLORS ─────
  static const Color typeText = primary;
  static const Color typeVoice = secondary;
  static const Color typePhoto = primaryContainer;
  static const Color typeScreenshot = secondaryContainer;

  // ───── GRADIENTS ─────
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, secondary],
  );

  static const LinearGradient fabGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, secondary],
  );

  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, Color(0xFF7C3AED)],
  );

  // Legacy
  static const LinearGradient cardShimmer = LinearGradient(
    colors: [Color(0xFFEEF2FF), Color(0xFFF0FDFA)],
  );

  // ───── SHADOWS ─────
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: onSurface.withValues(alpha: 0.05),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get mediumShadow => [
        BoxShadow(
          color: onSurface.withValues(alpha: 0.09),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> coloredShadow(Color color) => [
        BoxShadow(
          color: color.withValues(alpha: 0.25),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: const Color(0xFF5654AC).withValues(alpha: 0.1),
          blurRadius: 20,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get navShadow => [
        BoxShadow(
          color: const Color(0xFF5654AC).withValues(alpha: 0.1),
          blurRadius: 20,
          offset: const Offset(0, -4),
        ),
      ];

  static List<BoxShadow> get fabShadow => [
        BoxShadow(
          color: primary.withValues(alpha: 0.3),
          blurRadius: 30,
          offset: const Offset(0, 8),
        ),
      ];

  // ───── GLASS EFFECT HELPERS ─────
  static BoxDecoration glassDecoration({
    double opacity = 0.7,
    double borderOpacity = 0.05,
    double radius = 16.0,
  }) {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: opacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.black.withValues(alpha: borderOpacity)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 20,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  static Widget glassContainer({
    required Widget child,
    double opacity = 0.7,
    double blur = 20.0,
    double radius = 16.0,
    EdgeInsetsGeometry padding = const EdgeInsets.all(24),
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: glassDecoration(opacity: opacity, radius: radius),
          child: child,
        ),
      ),
    );
  }

  // ───── MEMORY TYPE HELPERS ─────
  static Color getMemoryTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'text':
        return typeText;
      case 'voice':
        return typeVoice;
      case 'photo':
        return typePhoto;
      case 'screenshot':
        return typeScreenshot;
      default:
        return primary;
    }
  }

  static IconData getMemoryTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'text':
        return Icons.notes_rounded;
      case 'voice':
        return Icons.mic_rounded;
      case 'photo':
        return Icons.photo_camera_rounded;
      case 'screenshot':
        return Icons.screenshot_rounded;
      default:
        return Icons.memory_rounded;
    }
  }

  static String getMemoryTypeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'text':
        return 'Text';
      case 'voice':
        return 'Voice';
      case 'photo':
        return 'Photo';
      case 'screenshot':
        return 'Screenshot';
      default:
        return 'Memory';
    }
  }

  // ───── TYPOGRAPHY HELPERS ─────
  static TextStyle get displayLg => GoogleFonts.hankenGrotesk(
        fontSize: 48,
        fontWeight: FontWeight.w700,
        height: 56 / 48,
        letterSpacing: -0.96,
        color: onSurface,
      );

  static TextStyle get headlineMd => GoogleFonts.hankenGrotesk(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        height: 40 / 32,
        letterSpacing: -0.32,
        color: onSurface,
      );

  static TextStyle get headlineMdMobile => GoogleFonts.hankenGrotesk(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 32 / 24,
        color: onSurface,
      );

  static TextStyle get titleSm => GoogleFonts.hankenGrotesk(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 28 / 20,
        color: onSurface,
      );

  static TextStyle get bodyLg => GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w400,
        height: 28 / 18,
        color: onSurface,
      );

  static TextStyle get bodyMd => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 24 / 16,
        color: onSurface,
      );

  static TextStyle get chatBubble => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 22 / 15,
      );

  static TextStyle get labelCaps => GoogleFonts.jetBrainsMono(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 16 / 12,
        letterSpacing: 0.6,
        color: outline,
      );

  // ───── THEME DATA ─────
  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: surface,
      colorScheme: const ColorScheme.light(
        primary: primary,
        primaryContainer: primaryContainer,
        onPrimary: onPrimary,
        onPrimaryContainer: onPrimaryContainer,
        secondary: secondary,
        secondaryContainer: secondaryContainer,
        onSecondary: onSecondary,
        onSecondaryContainer: onSecondaryContainer,
        tertiary: tertiary,
        tertiaryContainer: tertiaryContainer,
        onTertiary: onTertiary,
        onTertiaryContainer: onTertiaryContainer,
        surface: surface,
        onSurface: onSurface,
        surfaceContainerHighest: surfaceContainerHighest,
        error: error,
        errorContainer: errorContainer,
        onError: onError,
        onErrorContainer: onErrorContainer,
        outline: outline,
        outlineVariant: outlineVariant,
        inverseSurface: inverseSurface,
        onInverseSurface: inverseOnSurface,
        inversePrimary: inversePrimary,
        surfaceTint: surfaceTint,
      ),
      textTheme: TextTheme(
        displayLarge: displayLg,
        headlineMedium: headlineMd,
        titleSmall: titleSm,
        bodyLarge: bodyLg,
        bodyMedium: bodyMd,
        labelSmall: labelCaps,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: onSurface,
        titleTextStyle: GoogleFonts.hankenGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: primary,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 8,
        highlightElevation: 12,
        backgroundColor: primary,
        foregroundColor: onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusFull),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        hintStyle: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: outlineVariant,
        ),
        border: UnderlineInputBorder(
          borderSide: BorderSide(color: outlineVariant.withValues(alpha: 0.3), width: 2),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(radiusSm)),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: outlineVariant.withValues(alpha: 0.3), width: 2),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(radiusSm)),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: secondary, width: 2),
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusSm)),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: error, width: 2),
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusSm)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 2,
          shadowColor: primary.withValues(alpha: 0.2),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: GoogleFonts.hankenGrotesk(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: GoogleFonts.hankenGrotesk(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: surface,
        indicatorColor: secondaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return labelCaps.copyWith(color: onSecondaryContainer);
          }
          return labelCaps.copyWith(color: onSurfaceVariant);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: onSecondaryContainer, size: 24);
          }
          return const IconThemeData(color: onSurfaceVariant, size: 24);
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: tertiaryContainer.withValues(alpha: 0.1),
        labelStyle: labelCaps.copyWith(color: tertiaryContainer),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusFull),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: inverseSurface,
        contentTextStyle: GoogleFonts.inter(
          color: inverseOnSurface,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        modalBackgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
        space: 1,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return onPrimary;
          return outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return surfaceVariant;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return outlineVariant.withValues(alpha: 0.3);
        }),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        textStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: onSurface,
        ),
      ),
    );
  }
}
