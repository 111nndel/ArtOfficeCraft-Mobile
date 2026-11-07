import 'package:flutter/material.dart';

abstract final class OfficeTheme {
  static const primary = Color(0xff345be8);
  static const touch = 52.0;
  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(surface: dark ? const Color(0xff232b39) : Colors.white);
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
    );
    const buttonText = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final buttonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(touch, touch)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
      textStyle: const WidgetStatePropertyAll(buttonText),
      shape: WidgetStatePropertyAll(shape),
      visualDensity: VisualDensity.standard,
      tapTargetSize: MaterialTapTargetSize.padded,
    );
    return base.copyWith(
      scaffoldBackgroundColor: dark
          ? const Color(0xff171d27)
          : const Color(0xfff6f7fb),
      textTheme: base.textTheme.copyWith(
        bodyLarge: base.textTheme.bodyLarge!.copyWith(
          fontSize: 17,
          height: 1.45,
        ),
        bodyMedium: base.textTheme.bodyMedium!.copyWith(
          fontSize: 16,
          height: 1.4,
        ),
        bodySmall: base.textTheme.bodySmall!.copyWith(
          fontSize: 14,
          height: 1.35,
        ),
        labelLarge: base.textTheme.labelLarge!.merge(buttonText),
        labelMedium: base.textTheme.labelMedium!.copyWith(fontSize: 14),
        labelSmall: base.textTheme.labelSmall!.copyWith(fontSize: 14),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 72,
        titleSpacing: 4,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: buttonStyle.copyWith(
          iconSize: const WidgetStatePropertyAll(24),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(14)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
      textButtonTheme: TextButtonThemeData(style: buttonStyle),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        height: 80,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 14, color: scheme.onSurface),
        ),
      ),
    );
  }
}
