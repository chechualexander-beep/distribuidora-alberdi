import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

/// Un acceso del inicio: ícono y nombre.
class HomeAction {
  const HomeAction(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
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

/// Grupo de accesos ("TRABAJO DIARIO", "ADMINISTRACIÓN") en dos columnas, todos iguales.
class HomeSection extends StatelessWidget {
  const HomeSection({super.key, required this.title, required this.actions});
  final String title;
  final List<HomeAction> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    final rows = <Widget>[];
    for (var i = 0; i < actions.length; i += 2) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _HomeTile(actions[i])),
                const SizedBox(width: 10),
                Expanded(
                  child: i + 1 < actions.length ? _HomeTile(actions[i + 1]) : const SizedBox.shrink(),
                ),
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
              fontWeight: FontWeight.w600,
              color: Tonos.of(context).secundario,
            ),
          ),
        ),
        ...rows,
      ],
    );
  }
}

class _HomeTile extends StatelessWidget {
  const _HomeTile(this.action);
  final HomeAction action;

  @override
  Widget build(BuildContext context) {
    final t = Tonos.of(context);
    final foreground = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: t.fila,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: t.oscuro ? Colors.white24 : AppColors.borde, width: 1.2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: action.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 92),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(action.icon, size: 30, color: foreground),
                const SizedBox(height: 10),
                Text(
                  action.label,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
