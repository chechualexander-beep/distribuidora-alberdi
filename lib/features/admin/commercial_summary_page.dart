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
  Future<void> _probarConexion() async {
  await _supabase
      .from('pedido_detalles')
      .select('cantidad_entregada, precio_unitario')
      .limit(1);
}
@override
void initState() {
  super.initState();
  _probarConexion();
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

          const Expanded(
            child: Center(
              child: Text(
                'Aquí aparecerá la información comercial.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}