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

/// Colores de fondo y texto que cambian con el tema: en Windows (modo oscuro) nada de
/// fondos blancos ni claros; los números conservan su color, un poco más claros.
class Tonos {
  const Tonos._(this.oscuro);
  final bool oscuro;

  static Tonos of(BuildContext context) => Tonos._(Theme.of(context).brightness == Brightness.dark);

  /// Filas de listas (resumen, cargar vehículo).
  Color get fila => oscuro ? const Color(0xFF1C1B1F) : Colors.white;
  Color get filaTexto => oscuro ? const Color(0xFFE6E1E5) : Colors.black87;
  Color get cebra => oscuro ? const Color(0xFF0C2A44) : const Color(0xFFE6F1FB);
  Color get cebraTexto => oscuro ? const Color(0xFFB5D4F4) : const Color(0xFF0C447C);
  Color get secundario => oscuro ? const Color(0xFFB0B0B0) : AppColors.gris;

  /// Lo cargado: como el marcador flúor sobre el papel.
  Color get fluor => oscuro ? const Color(0xFF4A4000) : const Color(0xFFFFF176);
  Color get fluorBorde => const Color(0xFFF2D600);
  Color get fluorTexto => oscuro ? Colors.white : Colors.black87;

  /// Barra fija de arriba y casilleros de cantidad.
  Color get barra => oscuro ? const Color(0xFF26252A) : const Color(0xFFF4F4F2);
  Color get campo => oscuro ? const Color(0xFF121212) : Colors.white;

  /// Números de estado.
  Color get verde => oscuro ? const Color(0xFF81C784) : AppColors.verde;
  Color get rojo => oscuro ? const Color(0xFFEF8A8A) : AppColors.rojo;
  Color get azul => oscuro ? const Color(0xFF64B5F6) : const Color(0xFF1565C0);

  /// Etiquetas: (fondo, texto).
  (Color, Color) get etiquetaVerde =>
      oscuro ? (const Color(0xFF173404), const Color(0xFFC0DD97)) : (const Color(0xFFEAF3DE), const Color(0xFF27500A));
  (Color, Color) get etiquetaRoja =>
      oscuro ? (const Color(0xFF501313), const Color(0xFFF7C1C1)) : (const Color(0xFFFCEBEB), const Color(0xFF791F1F));
  (Color, Color) get etiquetaVioleta =>
      oscuro ? (const Color(0xFF26215C), const Color(0xFFCECBF6)) : (const Color(0xFFEEEDFE), const Color(0xFF3C3489));
  (Color, Color) get etiquetaAmarilla =>
      oscuro ? (const Color(0xFF412402), const Color(0xFFFAC775)) : (const Color(0xFFFAEEDA), const Color(0xFF633806));
  (Color, Color) get etiquetaGris =>
      oscuro ? (const Color(0xFF2C2C2A), const Color(0xFFD3D1C7)) : (const Color(0xFFF1EFE8), const Color(0xFF444441));

  /// Cajitas de aviso (fondo).
  Color get avisoFondo => oscuro ? const Color(0xFF3A2A12) : const Color(0xFFFFF3E0);
  Color get errorFondo => oscuro ? const Color(0xFF3B1818) : const Color(0xFFFDECEA);
  Color get exitoFondo => oscuro ? const Color(0xFF16301A) : const Color(0xFFE8F5E9);
  Color get infoFondo => oscuro ? const Color(0xFF14243B) : const Color(0xFFF0F5FF);
  Color get infoCirculo => oscuro ? const Color(0xFF1E3A5F) : const Color(0xFFD8E6FF);
  Color get infoIcono => oscuro ? const Color(0xFF85B7EB) : const Color(0xFF1565C0);
  Color get infoTitulo => oscuro ? const Color(0xFFB5D4F4) : const Color(0xFF0B4A91);
}
