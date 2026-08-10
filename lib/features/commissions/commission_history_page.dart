import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'commission_history_detail_page.dart';
class CommissionHistoryPage extends StatefulWidget {
  const CommissionHistoryPage({super.key});

  @override
  State<CommissionHistoryPage> createState() =>
      _CommissionHistoryPageState();
}

class _CommissionHistoryPageState
    extends State<CommissionHistoryPage> {
  bool _cargando = true;
  String? _error;

  List<Map<String, dynamic>> _liquidaciones = [];

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  Future<void> _cargarHistorial() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await Supabase.instance.client
          .from('liquidaciones')
          .select(
            '''
            id,
            fecha_desde,
            fecha_hasta,
            venta_entregada,
            comision_total,
            estado,
            fecha_pago,
            created_at,
            usuarios (
              nombre,
              apellido
            )
            ''',
          )
          .order('fecha_hasta', ascending: false);

      if (!mounted) return;

      setState(() {
        _liquidaciones =
            List<Map<String, dynamic>>.from(respuesta);
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'No se pudo cargar el historial.';
        _cargando = false;
      });
    }
  }

  double _numero(dynamic valor) {
    return double.tryParse(
          valor?.toString() ?? '0',
        ) ??
        0;
  }

  String _formatearPrecio(double valor) {
    final entero = valor.round().toString();

    final buffer = StringBuffer();
    int contador = 0;

    for (int i = entero.length - 1; i >= 0; i--) {
      buffer.write(entero[i]);
      contador++;

      if (contador == 3 && i != 0) {
        buffer.write('.');
        contador = 0;
      }
    }

    return '\$${buffer.toString().split('').reversed.join()}';
  }

  String _formatearFecha(dynamic valor) {
    if (valor == null) return '';

    final fecha = DateTime.tryParse(valor.toString());

    if (fecha == null) {
      return valor.toString();
    }

    final local = fecha.toLocal();

    final dia = local.day.toString().padLeft(2, '0');
    final mes = local.month.toString().padLeft(2, '0');

    return '$dia/$mes/${local.year}';
  }

  String _nombrePreventista(
    Map<String, dynamic> liquidacion,
  ) {
    final usuario =
        liquidacion['usuarios'] as Map<String, dynamic>?;

    final nombre =
        usuario?['nombre']?.toString() ?? '';

    final apellido =
        usuario?['apellido']?.toString() ?? '';

    final nombreCompleto = [
      nombre,
      apellido,
    ].where((e) => e.isNotEmpty).join(' ');

    return nombreCompleto.isEmpty
        ? 'Preventista'
        : nombreCompleto;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Historial de liquidaciones',
        ),
      ),
      body: _construirContenido(),
    );
  }

  Widget _construirContenido() {
    if (_cargando) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 56,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _cargarHistorial,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_liquidaciones.isEmpty) {
      return const Center(
        child: Text(
          'Todavía no hay liquidaciones registradas.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargarHistorial,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _liquidaciones.length,
        separatorBuilder: (_, _) =>
            const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final liquidacion =
              _liquidaciones[index];

          final preventista =
              _nombrePreventista(liquidacion);

          final fechaDesde =
              _formatearFecha(
                liquidacion['fecha_desde'],
              );

          final fechaHasta =
              _formatearFecha(
                liquidacion['fecha_hasta'],
              );

          final estado =
              liquidacion['estado']
                      ?.toString()
                      .toUpperCase() ??
                  'PENDIENTE';

          final comision =
              _numero(
                liquidacion['comision_total'],
              );

          final ventaEntregada =
              _numero(
                liquidacion['venta_entregada'],
              );

          return Card(
            child: ListTile(
              contentPadding:
                  const EdgeInsets.all(14),
              leading: const CircleAvatar(
                child: Icon(
                  Icons.receipt_long_outlined,
                ),
              ),
              title: Text(
                preventista,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Padding(
                padding:
                    const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$fechaDesde → $fechaHasta',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Venta entregada: ${_formatearPrecio(ventaEntregada)}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Estado: $estado',
                    ),
                  ],
                ),
              ),
              trailing: Column(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                crossAxisAlignment:
                    CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Comisión',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatearPrecio(comision),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
             onTap: () {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CommissionHistoryDetailPage(
        liquidacion: liquidacion,
      ),
    ),
  );
},
            ),
          );
        },
      ),
    );
  }
}