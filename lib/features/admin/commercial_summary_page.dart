import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommercialSummaryPage extends StatefulWidget {
  const CommercialSummaryPage({super.key});

  @override
  State<CommercialSummaryPage> createState() =>
      _CommercialSummaryPageState();
}

class _CommercialSummaryPageState extends State<CommercialSummaryPage> {
    
  int _periodoSeleccionado = 0;

final _supabase = Supabase.instance.client;

bool _cargando = false;
String? _error;
double _ventaTotal = 0;

Future<void> _cargarResumen() async {
  setState(() {
    _cargando = true;
    _error = null;
  });

  try {
    final hoy = DateTime.now();

    final inicio = DateTime(
      hoy.year,
      hoy.month,
      hoy.day,
    );

    final fin = inicio.add(const Duration(days: 1));

    final pedidos = await _supabase
        .from('pedidos')
        .select('''
          id,
          created_at,
          resultado_entrega,
          pedido_detalles (
            cantidad_entregada,
            precio_unitario
          )
        ''')
        .gte('created_at', inicio.toIso8601String())
        .lt('created_at', fin.toIso8601String());

    double venta = 0;

    for (final pedido in pedidos) {
      final detalles = pedido['pedido_detalles'] as List<dynamic>? ?? [];

      for (final detalle in detalles) {
        final cantidadEntregada = double.tryParse(
              detalle['cantidad_entregada']?.toString() ?? '',
            ) ??
            0;

        final precioUnitario = double.tryParse(
              detalle['precio_unitario']?.toString() ?? '',
            ) ??
            0;

        venta += cantidadEntregada * precioUnitario;
      }
    }

    if (!mounted) return;

    setState(() {
      _ventaTotal = venta;
      _cargando = false;
    });
  } catch (e) {
    if (!mounted) return;

    setState(() {
      _error = 'No se pudo cargar el resumen comercial.';
      _cargando = false;
    });
  }
}

@override
void initState() {
  super.initState();
  _cargarResumen();
}

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumen comercial',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ventas, recaudaciones, comisiones y rentabilidad',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(
                value: 0,
                icon: Icon(Icons.today_outlined),
                label: Text('Hoy'),
              ),
              ButtonSegment<int>(
                value: 1,
                icon: Icon(Icons.date_range_outlined),
                label: Text('Semana'),
              ),
              ButtonSegment<int>(
                value: 2,
                icon: Icon(Icons.calendar_month_outlined),
                label: Text('Personalizado'),
              ),
            ],
            selected: {_periodoSeleccionado},
            onSelectionChanged: (seleccion) {
              setState(() {
                _periodoSeleccionado = seleccion.first;
              });
            },
          ),

          const SizedBox(height: 32),

          Expanded(
  child: Center(
    child: _cargando
        ? const CircularProgressIndicator()
        : _error != null
            ? Text(_error!)
            : Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'VENTA TOTAL',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '\$${_ventaTotal.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Mercadería efectivamente entregada',
                      ),
                    ],
                  ),
                ),
              ),
  ),
),
        ],
      ),
    );
  }
}