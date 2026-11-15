import 'package:flutter/material.dart';

/// Paleta Alberdi (logo negro y dorado) pensada para leerse al sol.
/// Los colores de texto cumplen contraste >= 4,5:1 sobre blanco y siguen
/// siendo legibles sobre el tema oscuro de Windows.
class AppColors {
  AppColors._();

  static const negro = Color(0xFF1A1A1A);
  static const dorado = Color(0xFFD4A017);
  static const doradoOscuro = Color(0xFF8A6A00);
  static const borde = Color(0xFFBDBDBD);
  static const bordeFuerte = Color(0xFF6E6E6E);

  // Textos de estado y secundarios.
  static const gris = Color(0xFF737373);
  static const naranja = Color(0xFFC05A00);
  static const verde = Color(0xFF388E3C);
  static const rojo = Color(0xFFD32F2F);
  static const azul = Color(0xFF1976D2);

  // Fondos de listas de precios, siempre con texto blanco.
  static const listaNormal = Color(0xFF1565C0);
  static const listaPromo = Color(0xFFB45309);
  static const listaInterior = Color(0xFF2E7D32);
}

Color colorLista(String? tipo) => switch (tipo) {
  'promo' => AppColors.listaPromo,
  'interior' => AppColors.listaInterior,
  _ => AppColors.listaNormal,
};

String nombreLista(String? tipo) => switch (tipo) {
  'promo' => 'Promo',
  'interior' => 'Interior',
  _ => 'Normal',
};

const _bordeDorado = Border(
  bottom: BorderSide(color: AppColors.dorado, width: 3),
);

/// Tema claro (Android): barra negra, tarjetas blancas con borde marcado.
ThemeData temaClaro() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.dorado,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.negro,
        onPrimary: Colors.white,
        primaryContainer: AppColors.dorado,
        onPrimaryContainer: AppColors.negro,
        secondary: AppColors.doradoOscuro,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.dorado,
        onSecondaryContainer: AppColors.negro,
        surface: Colors.white,
        onSurface: AppColors.negro,
        onSurfaceVariant: const Color(0xFF4A4A4A),
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFFAFAFA),
        surfaceContainer: const Color(0xFFF5F5F5),
        surfaceContainerHigh: const Color(0xFFF0F0F0),
        surfaceContainerHighest: const Color(0xFFEAEAEA),
        outline: AppColors.bordeFuerte,
        outlineVariant: AppColors.borde,
        surfaceTint: Colors.transparent,
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.negro,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: _bordeDorado,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borde, width: 1.2),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(borderSide: BorderSide(width: 1.5)),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.bordeFuerte, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.negro, width: 2),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: const WidgetStatePropertyAll(
          BorderSide(color: AppColors.negro, width: 1.5),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.dorado
              : Colors.white,
        ),
        foregroundColor: const WidgetStatePropertyAll(AppColors.negro),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.borde, thickness: 1),
    listTileTheme: const ListTileThemeData(iconColor: AppColors.negro),
  );
}

/// Tema oscuro (Windows): el de siempre, con acento dorado.
ThemeData temaOscuro() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.dorado,
    brightness: Brightness.dark,
  ).copyWith(primary: AppColors.dorado, onPrimary: AppColors.negro);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF111111),
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: _bordeDorado,
    ),
  );
}
