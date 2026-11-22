import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

/// Un acceso del inicio: ícono y nombre. [badge]: cuántos hay pendientes (se ve en el botón).
/// [highlight]: lleno con el color del grupo (lo que más se usa, por ejemplo Anotar gasto).
class HomeAction {
  const HomeAction(this.icon, this.label, this.onTap, {this.badge, this.highlight = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int? badge;
  final bool highlight;
}

/// Cada grupo del inicio tiene su color, para encontrar las cosas sin leer.
enum HomeArea { ventas, reparto, facturacion, plata, herramientas }

/// Colores de un grupo: fondo del botón, letra, y el del título (claro y oscuro).
class AreaColors {
  const AreaColors(this.fondo, this.texto, this.titulo, this.fuerte);
  final Color fondo;
  final Color texto;
  final Color titulo;

  /// Para el botón destacado y los números.
  final Color fuerte;

  static AreaColors of(BuildContext context, HomeArea area) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    return switch ((area, oscuro)) {
      (HomeArea.ventas, false) => const AreaColors(Color(0xFFE6F1FB), Color(0xFF0C447C), Color(0xFF185FA5), Color(0xFF185FA5)),
      (HomeArea.ventas, true) => const AreaColors(Color(0xFF0C2A44), Color(0xFFB5D4F4), Color(0xFF85B7EB), Color(0xFF378ADD)),
      (HomeArea.reparto, false) => const AreaColors(Color(0xFFE1F5EE), Color(0xFF085041), Color(0xFF0F6E56), Color(0xFF0F6E56)),
      (HomeArea.reparto, true) => const AreaColors(Color(0xFF083A2F), Color(0xFF9FE1CB), Color(0xFF5DCAA5), Color(0xFF1D9E75)),
      (HomeArea.facturacion, false) => const AreaColors(Color(0xFFEEEDFE), Color(0xFF3C3489), Color(0xFF534AB7), Color(0xFF534AB7)),
      (HomeArea.facturacion, true) => const AreaColors(Color(0xFF26215C), Color(0xFFCECBF6), Color(0xFFAFA9EC), Color(0xFF7F77DD)),
      (HomeArea.plata, false) => const AreaColors(Color(0xFFFAEEDA), Color(0xFF633806), Color(0xFF854F0B), AppColors.dorado),
      (HomeArea.plata, true) => const AreaColors(Color(0xFF412402), Color(0xFFFAC775), Color(0xFFEF9F27), AppColors.dorado),
      (HomeArea.herramientas, false) => const AreaColors(Color(0xFFF1EFE8), Color(0xFF444441), Color(0xFF5F5E5A), Color(0xFF5F5E5A)),
      (HomeArea.herramientas, true) => const AreaColors(Color(0xFF2C2C2A), Color(0xFFD3D1C7), Color(0xFFB4B2A9), Color(0xFF888780)),
    };
  }
}

/// "Nuevo pedido": lo primero que se ve, grande y dorado (igual que en Windows).
class NewOrderButton extends StatelessWidget {
  const NewOrderButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Nuevo pedido',
    child: Material(
      color: AppColors.dorado,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(color: AppColors.negro, shape: BoxShape.circle),
                child: const Icon(Icons.add, color: AppColors.dorado, size: 30),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NUEVO PEDIDO',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: AppColors.negro,
                      ),
                    ),
                    Text('Tocá para empezar', style: TextStyle(fontSize: 13, color: Color(0xFF3D3000))),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.negro, size: 28),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Grupo de accesos ("VENTAS", "REPARTO Y STOCK"...) en tres columnas, con el color del grupo.
class HomeSection extends StatelessWidget {
  const HomeSection({super.key, required this.title, required this.actions, this.area = HomeArea.herramientas});
  final String title;
  final List<HomeAction> actions;
  final HomeArea area;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    final colors = AreaColors.of(context, area);
    const perRow = 3;
    final rows = <Widget>[];
    for (var i = 0; i < actions.length; i += perRow) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = i; j < i + perRow; j++) ...[
                  if (j > i) const SizedBox(width: 8),
                  Expanded(
                    child: j < actions.length ? _HomeTile(actions[j], colors) : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: colors.titulo,
            ),
          ),
        ),
        ...rows,
      ],
    );
  }
}

class _HomeTile extends StatelessWidget {
  const _HomeTile(this.action, this.colors);
  final HomeAction action;
  final AreaColors colors;

  @override
  Widget build(BuildContext context) {
    final fondo = action.highlight ? colors.fuerte : colors.fondo;
    final texto = action.highlight
        ? (colors.fuerte == AppColors.dorado ? AppColors.negro : Colors.white)
        : colors.texto;
    final badge = action.badge;
    return Material(
      color: fondo,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: action.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 84),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(action.icon, size: 28, color: texto),
                    if (badge != null && badge > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        key: ValueKey('badge-${action.label}'),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(
                          color: colors.fuerte,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$badge',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colors.fuerte == AppColors.dorado ? AppColors.negro : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  action.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: texto, height: 1.15),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Un cuadro de la tarjeta "Hoy": número (o texto) y qué es. Se toca para ir a esa pantalla.
class TodayItem {
  const TodayItem(this.area, this.value, this.label, this.onTap, {this.icon, this.alert = false});
  final HomeArea area;
  final String value;
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  /// En rojo (por ejemplo, productos en negativo).
  final bool alert;
}

/// "Hoy": lo pendiente del día de un vistazo (para facturar, para entregar, viaje, negativos).
class TodayCard extends StatelessWidget {
  const TodayCard({super.key, required this.title, required this.items, this.note});
  final String title;
  final List<TodayItem> items;

  /// Debajo, chiquito: por ejemplo "Sin señal: datos de las 9:40".
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = Tonos.of(context);
    Widget box(TodayItem item) {
      final c = AreaColors.of(context, item.area);
      final fondo = item.alert ? (t.oscuro ? const Color(0xFF501313) : const Color(0xFFFCEBEB)) : c.fondo;
      final texto = item.alert ? (t.oscuro ? const Color(0xFFF7C1C1) : const Color(0xFF791F1F)) : c.texto;
      return Material(
        color: fondo,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: item.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                if (item.icon != null) ...[
                  Icon(item.icon, size: 20, color: texto),
                  const SizedBox(width: 6),
                ] else ...[
                  Text(item.value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: texto)),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    item.icon != null ? '${item.value}${item.label.isEmpty ? '' : ' · ${item.label}'}' : item.label,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: texto, height: 1.15),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: box(items[i])),
                const SizedBox(width: 6),
                Expanded(child: i + 1 < items.length ? box(items[i + 1]) : const SizedBox.shrink()),
              ],
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        ...rows,
        if (note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Text(note!, style: TextStyle(fontSize: 12, color: t.secundario)),
          ),
      ],
    );
  }
}
