import 'package:flutter/material.dart';

import 'app_config.dart';

/// Outside the Navigator, so routes, dialogs and session lock retain the label.
class EnvironmentFrame extends StatelessWidget {
  const EnvironmentFrame({
    super.key,
    required this.config,
    required this.child,
  });

  final AppConfig config;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!config.isTesting) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: const Color(0xFFFFC107),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'TESTING — SOLO DATOS FICTICIOS\n'
                'Notificaciones y catálogo deshabilitados',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
