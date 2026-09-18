import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManageOrderPage extends StatefulWidget {
  final Map<String, dynamic> pedido;

  const ManageOrderPage({
    super.key,
    required this.pedido,
  });

  @override
  State<ManageOrderPage> createState() => _ManageOrderPageState();
}

class _ManageOrderPageState extends State<ManageOrderPage> {
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  String _estado = 'pendiente';
String? _modoEntrega;
  List<Map<String, dynamic>> _detalles = [];

  final Map<String, TextEditingController> _entregadosControllers = {};
  final TextEditingController _motivoController = TextEditingController();

  @override
  void initState() {
    super.initState();

    _estado = widget.pedido['estado']?.toString() ?? 'pendiente';

    _motivoController.text =
        widget.pedido['motivo_no_entrega']?.toString() ?? '';

    _cargarDetalles();
  }

  Future<void> _cargarDetalles() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await Supabase.instance.client
          .from('pedido_detalles')
          .select(
            '''
            id,
            pedido_id,
producto_id,
cantidad,
cantidad_facturada,
cantidad_entregada,
            cantidad_no_entregada,
            precio_unitario,
            tipo_precio,
            porcentaje_comision,
            importe_comision,
            productos (
              nombre,
              codigo_original,
              comision_normal,
              comision_promo,
              comision_interior
            )
            ''',
          )
          .eq('pedido_id', widget.pedido['id']);

      if (!mounted) return;

      final detalles =
          List<Map<String, dynamic>>.from(respuesta);

      for (final detalle in detalles) {
        final id = detalle['id'].toString();

        final entregada = double.tryParse(
              detalle['cantidad_entregada']?.toString() ?? '0',
            ) ??
            0;

        _entregadosControllers[id] = TextEditingController(
          text: _numeroLimpio(entregada),
        );
      }

      setState(() {
        _detalles = detalles;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'No se pudo cargar el pedido.';
        _cargando = false;
      });
    }
  }

  String _numeroLimpio(double valor) {
    if (valor == valor.roundToDouble()) {
      return valor.toInt().toString();
    }

    return valor.toStringAsFixed(2);
  }
bool _esAgregadoEnEntrega(Map<String, dynamic> detalle) {
  return detalle['agregado_en_entrega_local'] == true;
}
void _quitarProductoAgregado(Map<String, dynamic> detalle) {
  if (!_esAgregadoEnEntrega(detalle)) return;

  final id = detalle['id'].toString();

  _entregadosControllers.remove(id)?.dispose();

  setState(() {
    _detalles.remove(detalle);
  });
}

  double _cantidadPedida(Map<String, dynamic> detalle) {
  final cantidadFacturada = detalle['cantidad_facturada'];

  if (cantidadFacturada != null) {
    return double.tryParse(
          cantidadFacturada.toString(),
        ) ??
        0;
  }

  return double.tryParse(
        detalle['cantidad']?.toString() ?? '',
      ) ??
      0;
}

  double _cantidadEntregada(Map<String, dynamic> detalle) {
    final id = detalle['id'].toString();


    return double.tryParse(
          _entregadosControllers[id]?.text.replaceAll(',', '.') ?? '0',
        ) ??
        0;
  }

  double _cantidadNoEntregada(Map<String, dynamic> detalle) {
    final pedida = _cantidadPedida(detalle);
    final entregada = _cantidadEntregada(detalle);

    final resultado = pedida - entregada;

    return resultado < 0 ? 0 : resultado;
  }

  double _precio(Map<String, dynamic> detalle) {
    return double.tryParse(
          detalle['precio_unitario']?.toString() ?? '0',
        ) ??
        0;
  }

  double _porcentajeComision(Map<String, dynamic> detalle) {
    final producto =
        detalle['productos'] as Map<String, dynamic>?;

    final tipoPrecio =
        detalle['tipo_precio']?.toString() ?? 'normal';

    dynamic valor;

    switch (tipoPrecio) {
      case 'promo':
        valor = producto?['comision_promo'];
        break;
      case 'interior':
        valor = producto?['comision_interior'];
        break;
      default:
        valor = producto?['comision_normal'];
    }

    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  double _importeComision(Map<String, dynamic> detalle) {
    final entregada = _cantidadEntregada(detalle);
    final precio = _precio(detalle);
    final porcentaje = _porcentajeComision(detalle);

    return entregada * precio * porcentaje / 100;
  }
  double _precioProductoSegunLista(
  Map<String, dynamic> producto,
  String tipoPrecio,
) {
  dynamic valor;

  switch (tipoPrecio) {
    case 'promo':
      valor = producto['precio_promo'];
      break;
    case 'interior':
      valor = producto['precio_interior'];
      break;
    default:
      valor = producto['precio_normal'];
  }

  return double.tryParse(valor?.toString() ?? '') ?? 0;
}

Future<void> _agregarProductoEnEntrega() async {
  try {
    final respuesta = await Supabase.instance.client
        .from('productos')
        .select('''
          id,
          nombre,
          codigo_original,
          precio_normal,
          precio_promo,
          precio_interior,
          costo,
          comision_normal,
          comision_promo,
          comision_interior
        ''')
        .eq('activo', true)
        .order('nombre');

    if (!mounted) return;

    final idsYaIncluidos = _detalles
        .map((detalle) => detalle['producto_id']?.toString())
        .whereType<String>()
        .toSet();

    final productosDisponibles =
        List<Map<String, dynamic>>.from(respuesta)
            .where(
              (producto) =>
                  !idsYaIncluidos.contains(producto['id']?.toString()),
            )
            .toList();

    final productoSeleccionado =
        await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        String busqueda = '';

        return StatefulBuilder(
          builder: (context, setModalState) {
            final texto = busqueda
                .toLowerCase()
                .replaceAll('á', 'a')
                .replaceAll('é', 'e')
                .replaceAll('í', 'i')
                .replaceAll('ó', 'o')
                .replaceAll('ú', 'u');

            final filtrados = productosDisponibles.where((producto) {
              final nombre = producto['nombre']
                      ?.toString()
                      .toLowerCase()
                      .replaceAll('á', 'a')
                      .replaceAll('é', 'e')
                      .replaceAll('í', 'i')
                      .replaceAll('ó', 'o')
                      .replaceAll('ú', 'u') ??
                  '';

              final codigo =
                  producto['codigo_original']?.toString().toLowerCase() ??
                      '';

              return nombre.contains(texto) || codigo.contains(texto);
            }).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.75,
                  child: Column(
                    children: [
                      const Text(
                        'Agregar producto a la entrega',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Buscar producto',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (valor) {
                          setModalState(() {
                            busqueda = valor.trim();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: filtrados.isEmpty
                            ? const Center(
                                child: Text(
                                  'No hay productos disponibles.',
                                ),
                              )
                            : ListView.separated(
                                itemCount: filtrados.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final producto = filtrados[index];

                                  return ListTile(
                                    title: Text(
                                      producto['nombre']?.toString() ??
                                          'Producto sin nombre',
                                    ),
                                    subtitle: Text(
                                      'Código: ${producto['codigo_original'] ?? '-'}',
                                    ),
                                    trailing:
                                        const Icon(Icons.add_circle_outline),
                                    onTap: () {
                                      Navigator.pop(context, producto);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (productoSeleccionado == null || !mounted) return;

    final tipoPrecio = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Lista de precios'),
          content: Text(
            productoSeleccionado['nombre']?.toString() ??
                'Producto seleccionado',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'normal'),
              child: const Text('NORMAL'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'promo'),
              child: const Text('PROMO'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'interior'),
              child: const Text('INTERIOR'),
            ),
          ],
        );
      },
    );

    if (tipoPrecio == null || !mounted) return;

    final productoId = productoSeleccionado['id'].toString();
    final idLocal = 'agregado_$productoId';

    final precio = _precioProductoSegunLista(
      productoSeleccionado,
      tipoPrecio,
    );

    _entregadosControllers[idLocal] = TextEditingController(
      text: '1',
    );

    setState(() {
      _detalles.add({
        'id': idLocal,
        'pedido_id': widget.pedido['id'],
        'producto_id': productoId,
        'cantidad': 0,
        'cantidad_facturada': 0,
        'cantidad_entregada': 1,
        'cantidad_no_entregada': 0,
        'precio_unitario': precio,
        'tipo_precio': tipoPrecio,
        'costo_unitario':
            double.tryParse(
              productoSeleccionado['costo']?.toString() ?? '',
            ) ??
            0,
        'productos': productoSeleccionado,
        'agregado_en_entrega_local': true,
      });
    });
  } catch (_) {
    if (!mounted) return;

    _mostrarMensaje(
      'No se pudieron cargar los productos.',
    );
  }
}
  

  String _resultadoEntrega() {
  double totalPedido = 0;
  double totalEntregadoOriginal = 0;
  double totalEntregadoGeneral = 0;

  for (final detalle in _detalles) {
    final entregada = _cantidadEntregada(detalle);

    totalEntregadoGeneral += entregada;

    if (_esAgregadoEnEntrega(detalle)) {
      continue;
    }

    totalPedido += _cantidadPedida(detalle);
    totalEntregadoOriginal += entregada;
  }

  if (totalEntregadoGeneral <= 0) {
    return 'no_entregado';
  }

  if (totalEntregadoOriginal >= totalPedido) {
    return 'entregado';
  }

  return 'parcial';
}

  String _nombreResultado(String resultado) {
    switch (resultado) {
      case 'entregado':
        return 'ENTREGADO';
      case 'no_entregado':
        return 'NO ENTREGADO';
      case 'parcial':
        return 'ENTREGA PARCIAL';
      default:
        return 'PENDIENTE';
    }
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

  bool _validarCantidades() {
  for (final detalle in _detalles) {
    final entregada = _cantidadEntregada(detalle);

    if (_esAgregadoEnEntrega(detalle)) {
      if (entregada <= 0) {
        _mostrarMensaje(
          'La cantidad del producto agregado debe ser mayor que 0.',
        );
        return false;
      }

      continue;
    }

    final pedida = _cantidadPedida(detalle);

    if (entregada < 0 || entregada > pedida) {
      _mostrarMensaje(
        'La cantidad entregada no puede ser menor que 0 ni mayor que la pedida.',
      );
      return false;
    }
  }

  return true;
}

  Future<void> _guardarGestion() async {
    if (_guardando) return;
if (_modoEntrega == null) {
  _mostrarMensaje(
    'Seleccioná cómo fue la entrega antes de guardar.',
  );
  return;
}
    if (!_validarCantidades()) return;

    final resultado = _resultadoEntrega();

final totalEntregado = _detalles.fold<double>(
  0,
  (total, detalle) {
    final cantidadEntregada = _cantidadEntregada(detalle);
    final precio = _precio(detalle);

    return total + (cantidadEntregada * precio);
  },
);
String? medioPagoCompleto;
double? importePagoParcial;
String? medioPagoParcial;

if (resultado != 'no_entregado' && totalEntregado > 0) {
  medioPagoCompleto = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: const Text('¿Cómo quedó el pago?'),
        content: Text(
  'Mercadería entregada: ${_formatearPrecio(totalEntregado)}\n\n'
  '¿Cómo pagó el cliente lo entregado?',
),
        actions: [
          TextButton(
  onPressed: () => Navigator.pop(context, null),
  child: const Text('CANCELAR'),
),
          TextButton(
           onPressed: () => Navigator.pop(context, 'Parcial'),
            child: const Text('DEJÓ SALDO'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'Efectivo'),
            child: const Text('EFECTIVO'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'Transferencia'),
            child: const Text('TRANSFERENCIA'),
          ),
        ],
      );
    },
  );
}
if (resultado != 'no_entregado' &&
    medioPagoCompleto == null) {
  return;
}
if (!mounted) return;
if (resultado != 'no_entregado' &&
    medioPagoCompleto == 'Parcial') {
  final controller = TextEditingController();

  final importe = await showDialog<double>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Pago parcial'),
        content: TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Importe pagado',
            prefixText: r'$ ',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('NO PAGÓ NADA'),
          ),
          FilledButton(
            onPressed: () {
              final valor = double.tryParse(
                controller.text.trim().replaceAll(',', '.'),
              );

              if (valor == null || valor <= 0) return;

              Navigator.pop(dialogContext, valor);
            },
            child: const Text('CONTINUAR'),
          ),
        ],
      );
    },
  );

  await Future<void>.delayed(const Duration(milliseconds: 300));

if (!mounted) return;

controller.dispose();

if (importe != null) {
    importePagoParcial = importe;

    medioPagoParcial = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Medio de pago'),
          content: Text(
            'Importe recibido: \$${importe.toStringAsFixed(0)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'Efectivo'),
              child: const Text('EFECTIVO'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'Transferencia'),
              child: const Text('TRANSFERENCIA'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
  }
}

    if ((resultado == 'no_entregado' || resultado == 'parcial') &&
        _motivoController.text.trim().isEmpty) {
      _mostrarMensaje(
        'Ingresá un motivo para la mercadería no entregada.',
      );
      return;
    }

    setState(() {
      _guardando = true;
    });

    try {
      final detallesGestion = _detalles.map((detalle) {
  final esAgregado = _esAgregadoEnEntrega(detalle);

  final entregada = _cantidadEntregada(detalle);
  final noEntregada =
      esAgregado ? 0 : _cantidadNoEntregada(detalle);

  final porcentaje = _porcentajeComision(detalle);
  final importeComision = _importeComision(detalle);

  return <String, dynamic>{
    'id': esAgregado ? null : detalle['id'],
    'producto_id': detalle['producto_id'],
    'agregado_en_entrega': esAgregado,
    'cantidad_entregada': entregada,
    'cantidad_no_entregada': noEntregada,
    'precio_unitario': _precio(detalle),
    'costo_unitario':
        double.tryParse(
          detalle['costo_unitario']?.toString() ?? '',
        ) ??
        0,
    'porcentaje_comision': porcentaje,
    'importe_comision': importeComision,
    'tipo_precio':
        detalle['tipo_precio']?.toString() ?? 'normal',
  };
}).toList();

String tipoPago = 'sin_pago';
double? importePago;
String? medioPago;

if (importePagoParcial != null &&
    medioPagoParcial != null &&
    importePagoParcial > 0) {
  tipoPago = 'parcial';
  importePago = importePagoParcial;
  medioPago = medioPagoParcial;
} else if (resultado != 'no_entregado' &&
    totalEntregado > 0 &&
    medioPagoCompleto != null &&
    medioPagoCompleto != 'Parcial') {
  tipoPago = 'completo';
  medioPago = medioPagoCompleto;
}

await Supabase.instance.client.rpc(
  'finalizar_gestion_pedido',
  params: {
    'p_pedido_id': widget.pedido['id'],
    'p_estado': _estado,
    'p_resultado_entrega': resultado,
    'p_motivo_no_entrega':
        resultado == 'entregado'
            ? null
            : _motivoController.text.trim(),
    'p_detalles': detallesGestion,
    'p_tipo_pago': tipoPago,
    'p_importe_pago': importePago,
    'p_medio_pago': medioPago,
  },
);

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            icon: const Icon(
              Icons.check_circle_outline,
              size: 48,
            ),
            title: const Text('Gestión guardada'),
            content: Text(
              'Resultado: ${_nombreResultado(resultado)}',
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('ACEPTAR'),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      _mostrarMensaje(
        'No se pudo guardar: ${error.message}',
      );
    } catch (_) {
      _mostrarMensaje(
        'Ocurrió un error al guardar la gestión.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }
    }
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in _entregadosControllers.values) {
      controller.dispose();
    }

    _motivoController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cliente =
        widget.pedido['clientes'] as Map<String, dynamic>?;

    final clienteNombre =
        cliente?['nombre_comercio']?.toString() ??
            'Cliente sin nombre';

    if (_cargando) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Gestionar pedido'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Gestionar pedido'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 60,
                ),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _cargarDetalles,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final resultado = _resultadoEntrega();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestionar pedido'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Cliente',
                    style: TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    clienteNombre,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (widget.pedido['tipo_operacion']?.toString() == 'venta_directa') ...[
  const SizedBox(height: 8),
  const Text(
    'VENTA DIRECTA',
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
    ),
  ),
],
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: _estado,
                    decoration: const InputDecoration(
                      labelText: 'Estado operativo',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'pendiente',
                        child: Text('Pendiente'),
                      ),
                      DropdownMenuItem(
                        value: 'preparado',
                        child: Text('Preparado'),
                      ),
                      DropdownMenuItem(
                        value: 'en_reparto',
                        child: Text('En reparto'),
                      ),
                    ],
                    onChanged: (valor) {
                      if (valor == null) return;

                      setState(() {
                        _estado = valor;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
      const Text(
  'Mercadería entregada',
  style: TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
  ),
),
const SizedBox(height: 10),

Card(
  child: Column(
    children: [
      RadioListTile<String>(
        value: 'completo',
        groupValue: _modoEntrega,
        title: const Text('TODO ENTREGADO'),
        subtitle: const Text(
          'El cliente recibió todo el pedido',
        ),
        onChanged: (valor) {
          if (valor == null) return;

          setState(() {
            _modoEntrega = valor;

            for (final detalle in _detalles) {
              final id = detalle['id'].toString();
              final cantidad = _cantidadPedida(detalle);

              _entregadosControllers[id]?.text =
                  _numeroLimpio(cantidad);
            }
          });
        },
      ),

      const Divider(height: 1),

      RadioListTile<String>(
        value: 'rechazado',
        groupValue: _modoEntrega,
        title: const Text('TODO NO ENTREGADO'),
        subtitle: const Text(
          'El cliente no recibió ningún producto',
        ),
        onChanged: (valor) {
          if (valor == null) return;

          setState(() {
            _modoEntrega = valor;

            for (final detalle in _detalles) {
              final id = detalle['id'].toString();
              _entregadosControllers[id]?.text = '0';
            }
          });
        },
      ),

      const Divider(height: 1),

      RadioListTile<String>(
        value: 'parcial',
        groupValue: _modoEntrega,
        title: const Text('ENTREGA PARCIAL'),
        subtitle: const Text(
          'Indicar cantidades producto por producto',
        ),
        onChanged: (valor) {
  if (valor == null) return;

  setState(() {
    _modoEntrega = valor;

    for (final detalle in _detalles) {
      if (_esAgregadoEnEntrega(detalle)) {
        continue;
      }

      final id = detalle['id'].toString();
      final cantidad = _cantidadPedida(detalle);

      _entregadosControllers[id]?.text =
          _numeroLimpio(cantidad);
    }
  });
},
      ),
    ],
  ),
),

const SizedBox(height: 16),

if (_modoEntrega == 'parcial')
  ..._detalles.map((detalle) {
            final producto =
                detalle['productos'] as Map<String, dynamic>?;

            final nombre =
                producto?['nombre']?.toString() ??
                    'Producto sin nombre';

            final id = detalle['id'].toString();
            final esAgregado = _esAgregadoEnEntrega(detalle);

            final pedida = _cantidadPedida(detalle);
            final noEntregada =
                _cantidadNoEntregada(detalle);

            final porcentaje =
                _porcentajeComision(detalle);

            final importe =
                _importeComision(detalle);

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
  children: [
    Expanded(
      child: Text(
        nombre,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
    if (esAgregado)
      IconButton(
        tooltip: 'Quitar producto agregado',
        onPressed: () => _quitarProductoAgregado(detalle),
        icon: const Icon(
          Icons.delete_outline,
          color: Colors.orange,
        ),
      ),
  ],
),
if (esAgregado) ...[
  const SizedBox(height: 4),
  const Row(
    children: [
      Icon(
        Icons.add_circle_outline,
        size: 17,
        color: Colors.orange,
      ),
      SizedBox(width: 6),
      Text(
        'Agregado durante la entrega',
        style: TextStyle(
          color: Colors.orange,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  ),
],
                    const SizedBox(height: 8),
                    Text(
                      'Cantidad pedida: ${_numeroLimpio(pedida)}',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _entregadosControllers[id],
                      keyboardType:
                          const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Cantidad entregada',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No entregada: ${_numeroLimpio(noEntregada)}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Precio: ${_formatearPrecio(_precio(detalle))}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Comisión: ${_numeroLimpio(porcentaje)}%',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Comisión generada: ${_formatearPrecio(importe)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (_modoEntrega == 'parcial')
  Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 16),
    child: OutlinedButton.icon(
      onPressed: _guardando ? null : _agregarProductoEnEntrega,
      icon: const Icon(Icons.add_shopping_cart_outlined),
      label: const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('AGREGAR PRODUCTO'),
      ),
    ),
  ),

          const SizedBox(height: 12),

          Card(
            child: ListTile(
              title: const Text(
                'Resultado de entrega',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                _nombreResultado(resultado),
              ),
            ),
          ),

          if (resultado == 'parcial' ||
              resultado == 'no_entregado') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _motivoController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motivo de mercadería no entregada *',
                hintText:
                    'Ej.: cliente cerrado, rechazó parte del pedido...',
                border: OutlineInputBorder(),
              ),
            ),
          ],

          const SizedBox(height: 20),

          FilledButton.icon(
            onPressed:
                _guardando ? null : _guardarGestion,
            icon: _guardando
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(
              _guardando
                  ? 'GUARDANDO...'
                  : 'GUARDAR GESTIÓN',
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}