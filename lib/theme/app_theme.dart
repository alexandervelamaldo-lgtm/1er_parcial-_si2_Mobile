import 'package:flutter/material.dart';


abstract final class AppColors {
  // Brand
  static const primary = Color(0xFF2563EB);
  static const primaryDark = Color(0xFF1D4ED8);
  static const primaryLight = Color(0xFF3B82F6);

  // Surface
  static const backgroundDark = Color(0xFF0F172A);
  static const backgroundMid = Color(0xFF1E293B);

  // Semantic
  static const success = Color(0xFF16A34A);
  static const successLight = Color(0xFFDCFCE7);
  static const warning = Color(0xFFD97706);
  static const warningLight = Color(0xFFFEF3C7);
  static const error = Color(0xFFDC2626);
  static const errorLight = Color(0xFFFEE2E2);
  static const info = Color(0xFF0EA5E9);

  // Priority
  static const priorityUrgente = Color(0xFFDC2626);
  static const priorityAlta = Color(0xFFEA580C);
  static const priorityMedia = Color(0xFFD97706);
  static const priorityBaja = Color(0xFF16A34A);
}


abstract final class AppTheme {
  static ThemeData light() {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: base.surface,
        foregroundColor: base.onSurface,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
      ),
    );
  }

  static ThemeData dark() {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: base.surface,
        foregroundColor: base.onSurface,
      ),
    );
  }

  static Color priorityColor(String prioridad) {
    return switch (prioridad.toUpperCase()) {
      'URGENTE' => AppColors.priorityUrgente,
      'ALTA'    => AppColors.priorityAlta,
      'MEDIA'   => AppColors.priorityMedia,
      _         => AppColors.priorityBaja,
    };
  }

  static Color statusColor(String estado) {
    final e = estado.toLowerCase();
    if (e.contains('completad') || e.contains('cerrad') || e.contains('finaliz')) {
      return AppColors.success;
    }
    if (e.contains('cancel') || e.contains('rechaz')) {
      return AppColors.error;
    }
    if (e.contains('progress') || e.contains('proceso') || e.contains('asignad')) {
      return AppColors.info;
    }
    return AppColors.warning;
  }
}
