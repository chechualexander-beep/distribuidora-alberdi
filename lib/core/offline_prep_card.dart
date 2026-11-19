import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'network_status.dart';
import 'offline_queries.dart';

/// Tarjeta del inicio: "Preparar para trabajar sin señal".
/// Conviene tocarla a la mañana con wifi o buena señal, antes de salir.
class OfflinePrepCard extends StatefulWidget {
  const OfflinePrepCard({super.key, this.client});
  final SupabaseClient? client;
  @override
  State<OfflinePrepCard> createState() => _OfflinePrepCardState();
}

class _OfflinePrepCardState extends State<OfflinePrepCard> {
  SupabaseClient get _client => widget.client ?? Supabase.instance.client;
  PreparacionSinConexion? _ultima;
  bool _preparando = false;
  int _hechos = 0, _total = 0;

  @override
  void initState() {
    super.initState();
    final uid = _client.auth.currentUser?.id;
    if (uid != null) {
      leerPreparacion(uid).then((p) {
        if (mounted) setState(() => _ultima = p);
      });
    }
  }

  Future<void> _preparar() async {
    if (_preparando) return;
    setState(() {
      _preparando = true;
      _hechos = 0;
      _total = 0;
    });
    try {
      final resultado = await prepararSinConexion(
        _client,
        progreso: (hechos, total) {
          if (mounted) {
            setState(() {
              _hechos = hechos;
              _total = total;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() => _ultima = resultado);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Listo: ${resultado.clientes} clientes y ${resultado.productos} productos guardados en el teléfono.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo terminar de preparar. Probá con wifi o mejor señal. Lo que ya se guardó sirve igual.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _preparando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ultima = _ultima;
    final antigua =
        ultima == null || DateTime.now().difference(ultima.fecha).inHours >= 12;
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: oscuro ? Colors.white24 : AppColors.borde, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  antigua ? Icons.cloud_download_outlined : Icons.offline_pin_outlined,
                  color: antigua ? AppColors.naranja : AppColors.verde,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Trabajar sin señal',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        ultima == null
                            ? 'Prepará los datos con wifi antes de salir.'
                            : 'Datos guardados ${describeSavedAt(ultima.fecha)} · '
                                  '${ultima.clientes} clientes, ${ultima.productos} productos',
                        style: const TextStyle(fontSize: 13, color: AppColors.gris),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _preparando ? null : _preparar,
                  child: Text(_preparando ? 'Preparando…' : 'Preparar'),
                ),
              ],
            ),
            if (_preparando) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _total == 0 ? null : _hechos / _total),
              const SizedBox(height: 4),
              Text(
                _total == 0 ? 'Bajando clientes y productos…' : 'Saldos: $_hechos de $_total',
                style: const TextStyle(fontSize: 12, color: AppColors.gris),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
