import 'package:flutter/material.dart';

import 'edit_client_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
class ClientDetailPage extends StatefulWidget {
  final Map<String, dynamic> cliente;

  const ClientDetailPage({
    super.key,
    required this.cliente,
  });

  @override
  State<ClientDetailPage> createState() => _ClientDetailPageState();
}

class _ClientDetailPageState extends State<ClientDetailPage> {
bool _cargandoCompras = true;
String? _errorCompras;

List<Map<String, dynamic>> _ultimasCompras = [];
@override
void initState() {
  super.initState();
  _cargarUltimasCompras();
}

Future<void> _cargarUltimasCompras() async {
  try {
    final clienteId =
        widget.cliente['id']?.toString();

    if (clienteId == null || clienteId.isEmpty) {
      throw Exception('Cliente sin ID');
    }

    final respuesta =
        await Supabase.instance.client
            .from('pedidos')
            .select(
              '''
              id,
              created_at,
              total,
              estado,
              pedido_detalles (
                cantidad,
                precio_unitario,
                subtotal,
                tipo_precio,
                productos (
                  nombre,
                  codigo
                )
              )
              ''',
            )
            .eq('cliente_id', clienteId)
            .order('created_at', ascending: false)
            .limit(2);

    if (!mounted) return;

    setState(() {
      _ultimasCompras =
          List<Map<String, dynamic>>.from(
        respuesta,
      );
      _cargandoCompras = false;
    });
  } catch (_) {
    if (!mounted) return;

    setState(() {
      _errorCompras =
          'No se pudieron cargar las últimas compras.';
      _cargandoCompras = false;
    });
  }
}
  String _texto(dynamic valor) {
    if (valor == null) return 'Sin información';

    final texto = valor.toString().trim();

    return texto.isEmpty ? 'Sin información' : texto;
  }

  @override
  Widget build(BuildContext context) {
    final comercio = _texto(widget.cliente['nombre_comercio']);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ficha del cliente'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const CircleAvatar(
            radius: 42,
            child: Icon(
              Icons.storefront,
              size: 42,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            comercio,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 30),

          _DatoCliente(
            icono: Icons.location_on_outlined,
            titulo: 'Dirección',
            valor: _texto(widget.cliente['direccion']),
          ),

          _DatoCliente(
            icono: Icons.location_city_outlined,
            titulo: 'Localidad',
            valor: _texto(widget.cliente['localidad']),
          ),

          _DatoCliente(
            icono: Icons.person_outline,
            titulo: 'Propietario',
            valor: _texto(widget.cliente['propietario']),
          ),

          _DatoCliente(
            icono: Icons.phone_outlined,
            titulo: 'Teléfono',
            valor: _texto(widget.cliente['telefono']),
          ),

          _DatoCliente(
            icono: Icons.map_outlined,
            titulo: 'Zona',
            valor: _texto(widget.cliente['zona']),
          ),

          _DatoCliente(
            icono: Icons.notes_outlined,
            titulo: 'Observaciones',
            valor: _texto(widget.cliente['observaciones']),
          ),
const SizedBox(height: 24),

const Align(
  alignment: Alignment.centerLeft,
  child: Text(
    'Últimas compras',
    style: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.bold,
    ),
  ),
),

const SizedBox(height: 12),

if (_cargandoCompras)
  const Center(
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: CircularProgressIndicator(),
    ),
  )
else if (_errorCompras != null)
  Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      _errorCompras!,
      style: const TextStyle(
        color: Colors.red,
      ),
    ),
  )
else if (_ultimasCompras.isEmpty)
  const Padding(
    padding: EdgeInsets.symmetric(vertical: 12),
    child: Text(
      'Este cliente todavía no tiene compras registradas.',
    ),
  )
else
 ..._ultimasCompras.map((pedido) {
  final fecha = DateTime.tryParse(
    pedido['created_at']?.toString() ?? '',
  );

  final fechaTexto = fecha == null
      ? 'Fecha sin información'
      : '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/'
        '${fecha.year}';

  final detalles =
      (pedido['pedido_detalles'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

  return Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined),
              const SizedBox(width: 8),
              Text(
                fechaTexto,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          ...detalles.map((detalle) {
            final producto =
                detalle['productos'] as Map<String, dynamic>?;

            final nombreProducto =
                producto?['nombre']?.toString() ?? 'Producto';

            final cantidad =
                detalle['cantidad']?.toString() ?? '0';

            final precio =
                detalle['precio_unitario']?.toString() ?? '0';

            final tipoPrecio =
                detalle['tipo_precio']?.toString() ?? 'normal';

            String nombreTipoPrecio;

            switch (tipoPrecio) {
              case 'promo':
                nombreTipoPrecio = 'Promo';
                break;
              case 'interior':
                nombreTipoPrecio = 'Interior';
                break;
              default:
                nombreTipoPrecio = 'Normal';
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombreProducto,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text('Cantidad: $cantidad'),
                  Text('Precio utilizado: \$$precio'),
                  Text('Lista: $nombreTipoPrecio'),
                ],
              ),
            );
          }),
        ],
      ),
    ),
  );
}),
          const SizedBox(height: 28),

          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: () async {
                final actualizado =
                    await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => EditClientPage(
                      cliente: widget.cliente,
                    ),
                  ),
                );

                if (actualizado == true && context.mounted) {
                  Navigator.of(context).pop(true);
                }
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('EDITAR CLIENTE'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatoCliente extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String valor;

  const _DatoCliente({
    required this.icono,
    required this.titulo,
    required this.valor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icono),
        title: Text(
          titulo,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(valor),
      ),
    );
  }
}