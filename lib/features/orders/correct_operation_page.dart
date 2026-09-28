import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CorrectOperationPage extends StatefulWidget {
  final Map<String, dynamic> pedido;

  const CorrectOperationPage({super.key, required this.pedido});

  @override
  State<CorrectOperationPage> createState() => _CorrectOperationPageState();
}

class _CorrectOperationPageState extends State<CorrectOperationPage> {
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  List<Map<String, dynamic>> _detalles = [];

  final Map<String, TextEditingController> _entregadosControllers = {};

  final TextEditingController _motivoController = TextEditingController();

  double _totalAnterior = 0;
  double _totalPagado = 0;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await Supabase.instance.client
          .from('pedido_detalles')
          .select('''
            id,
            pedido_id,
            producto_id,
            cantidad,
            cantidad_facturada,
            cantidad_entregada,
            cantidad_no_entregada,
            precio_unitario,
            tipo_precio,
            costo_unitario,
            porcentaje_comision,
            importe_comision,
            agregado_en_entrega,
            productos (
              nombre,
              codigo_original
            )
          ''')
          .eq('pedido_id', widget.pedido['id'])
          .order('created_at');

      final pagosRespuesta = await Supabase.instance.client
          .from('pedido_pagos')
          .select('importe')
          .eq('pedido_id', widget.pedido['id']);

      if (!mounted) return;

      final detalles = List<Map<String, dynamic>>.from(respuesta);

      double totalAnterior = 0;

      for (final detalle in detalles) {
        final id = detalle['id'].toString();

        final entregada =
            double.tryParse(detalle['cantidad_entregada']?.toString() ?? '0') ??
            0;

        final precio =
            double.tryParse(detalle['precio_unitario']?.toString() ?? '0') ?? 0;

        totalAnterior += entregada * precio;

        _entregadosControllers[id] = TextEditingController(
          text: _numeroLimpio(entregada),
        );
      }

      double totalPagado = 0;

      for (final pago in pagosRespuesta) {
        totalPagado += double.tryParse(pago['importe']?.toString() ?? '0') ?? 0;
      }

      setState(() {
        _detalles = detalles;
        _totalAnterior = totalAnterior;
        _totalPagado = totalPagado;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'No se pudo cargar la operación.';
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

  bool _esNuevaLinea(Map<String, dynamic> detalle) {
    return detalle['agregado_en_correccion_local'] == true;
  }

  bool _esAgregado(Map<String, dynamic> detalle) {
    return _esNuevaLinea(detalle) || detalle['agregado_en_entrega'] == true;
  }

  double _cantidadBase(Map<String, dynamic> detalle) {
    final facturada = detalle['cantidad_facturada'];

    if (facturada != null) {
      return double.tryParse(facturada.toString()) ?? 0;
    }

    return double.tryParse(detalle['cantidad']?.toString() ?? '0') ?? 0;
  }

  double _cantidadEntregada(Map<String, dynamic> detalle) {
    final id = detalle['id'].toString();

    return double.tryParse(
          _entregadosControllers[id]?.text.replaceAll(',', '.') ?? '0',
        ) ??
        0;
  }

  double _precio(Map<String, dynamic> detalle) {
    return double.tryParse(detalle['precio_unitario']?.toString() ?? '0') ?? 0;
  }

  double _totalCorregido() {
    return _detalles.fold<double>(0, (total, detalle) {
      return total + (_cantidadEntregada(detalle) * _precio(detalle));
    });
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

  double _comisionProductoSegunLista(
    Map<String, dynamic> producto,
    String tipoPrecio,
  ) {
    dynamic valor;

    switch (tipoPrecio) {
      case 'promo':
        valor = producto['comision_promo'];
        break;
      case 'interior':
        valor = producto['comision_interior'];
        break;
      default:
        valor = producto['comision_normal'];
    }

    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  Future<void> _agregarProducto() async {
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

      final idsIncluidos = _detalles
          .map((detalle) => detalle['producto_id']?.toString())
          .whereType<String>()
          .toSet();

      final productosDisponibles = List<Map<String, dynamic>>.from(respuesta)
          .where((producto) {
            return !idsIncluidos.contains(producto['id']?.toString());
          })
          .toList();

      final productoSeleccionado = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          String busqueda = '';

          return StatefulBuilder(
            builder: (context, setModalState) {
              final filtrados = productosDisponibles.where((producto) {
                final texto = busqueda.toLowerCase();

                final nombre =
                    producto['nombre']?.toString().toLowerCase() ?? '';

                final codigo =
                    producto['codigo_original']?.toString().toLowerCase() ?? '';

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
                          'Agregar producto a la corrección',
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
                                  child: Text('No hay productos disponibles.'),
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
                                      trailing: const Icon(
                                        Icons.add_circle_outline,
                                      ),
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

      if (productoSeleccionado == null || !mounted) {
        return;
      }

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

      if (tipoPrecio == null || !mounted) {
        return;
      }

      final productoId = productoSeleccionado['id'].toString();

      final idLocal = 'correccion_$productoId';

      final precio = _precioProductoSegunLista(
        productoSeleccionado,
        tipoPrecio,
      );

      final comision = _comisionProductoSegunLista(
        productoSeleccionado,
        tipoPrecio,
      );

      final costo =
          double.tryParse(productoSeleccionado['costo']?.toString() ?? '') ?? 0;

      _entregadosControllers[idLocal] = TextEditingController(text: '1');

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
          'costo_unitario': costo,
          'porcentaje_comision': comision,
          'productos': productoSeleccionado,
          'agregado_en_entrega': true,
          'agregado_en_correccion_local': true,
        });
      });
    } catch (_) {
      if (!mounted) return;

      _mostrarMensaje('No se pudieron cargar los productos.');
    }
  }

  void _quitarProductoNuevo(Map<String, dynamic> detalle) {
    if (!_esNuevaLinea(detalle)) return;

    final id = detalle['id'].toString();

    _entregadosControllers.remove(id)?.dispose();

    setState(() {
      _detalles.remove(detalle);
    });
  }

  bool _validar() {
    final motivo = _motivoController.text.trim();

    if (motivo.isEmpty) {
      _mostrarMensaje('Ingresá el motivo de la corrección.');
      return false;
    }

    for (final detalle in _detalles) {
      final entregada = _cantidadEntregada(detalle);

      if (entregada < 0) {
        _mostrarMensaje('Las cantidades no pueden ser negativas.');
        return false;
      }

      if (_esNuevaLinea(detalle) && entregada <= 0) {
        _mostrarMensaje(
          'Un producto nuevo debe tener cantidad mayor que cero.',
        );
        return false;
      }

      if (!_esAgregado(detalle)) {
        final base = _cantidadBase(detalle);

        if (entregada > base) {
          _mostrarMensaje(
            'Una cantidad entregada supera la cantidad original/facturada.',
          );
          return false;
        }
      }
    }

    final totalCorregido = _totalCorregido();

    if (totalCorregido < _totalPagado) {
      _mostrarMensaje(
        'El total corregido no puede ser menor que lo ya pagado. '
        'Ese caso requiere devolución o saldo a favor.',
      );
      return false;
    }

    return true;
  }

  Future<void> _guardarCorreccion() async {
    if (_guardando) return;
    if (!_validar()) return;

    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar corrección'),
          content: Text(
            'Total anterior: ${_formatearPrecio(_totalAnterior)}\n'
            'Total corregido: ${_formatearPrecio(_totalCorregido())}\n'
            'Pagado: ${_formatearPrecio(_totalPagado)}\n\n'
            'Esta acción modificará la mercadería efectivamente entregada.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('VOLVER'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('CONFIRMAR'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    final detallesRpc = _detalles.map((detalle) {
      final entregada = _cantidadEntregada(detalle);

      if (_esNuevaLinea(detalle)) {
        return <String, dynamic>{
          'producto_id': detalle['producto_id'],
          'cantidad_entregada': entregada,
          'precio_unitario': _precio(detalle),
          'costo_unitario':
              double.tryParse(detalle['costo_unitario']?.toString() ?? '0') ??
              0,
          'porcentaje_comision':
              double.tryParse(
                detalle['porcentaje_comision']?.toString() ?? '0',
              ) ??
              0,
          'tipo_precio': detalle['tipo_precio']?.toString() ?? 'normal',
        };
      }

      return <String, dynamic>{
        'id': detalle['id'],
        'cantidad_entregada': entregada,
      };
    }).toList();

    setState(() {
      _guardando = true;
    });

    try {
      final respuesta = await Supabase.instance.client.rpc(
        'corregir_operacion_finalizada',
        params: {
          'p_pedido_id': widget.pedido['id'],
          'p_motivo': _motivoController.text.trim(),
          'p_detalles': detallesRpc,
        },
      );

      if (!mounted) return;

      final datos = respuesta is Map
          ? Map<String, dynamic>.from(respuesta)
          : <String, dynamic>{};

      final totalNuevo =
          double.tryParse(datos['total_nuevo']?.toString() ?? '') ??
          _totalCorregido();

      final saldoNuevo =
          double.tryParse(datos['saldo_nuevo']?.toString() ?? '') ?? 0;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            icon: const Icon(Icons.check_circle_outline, size: 48),
            title: const Text('Operación corregida'),
            content: Text(
              'Nuevo total entregado: ${_formatearPrecio(totalNuevo)}\n'
              'Nuevo saldo: ${_formatearPrecio(saldoNuevo)}',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ACEPTAR'),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (!mounted) return;

      _mostrarMensaje('No se pudo corregir la operación: ${error.message}');
    } catch (_) {
      if (!mounted) return;

      _mostrarMensaje('Ocurrió un error al corregir la operación.');
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

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
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
    final nombreCliente =
        (widget.pedido['clientes'] as Map<String, dynamic>?)?['nombre_comercio']
            ?.toString() ??
        'Cliente';

    final totalCorregido = _totalCorregido();

    final diferencia = totalCorregido - _totalAnterior;

    final saldoNuevo = totalCorregido > _totalPagado
        ? totalCorregido - _totalPagado
        : 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text('Corregir operación')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Cliente',
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          nombreCliente,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Mercadería entregada',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                ..._detalles.map((detalle) {
                  final producto =
                      detalle['productos'] as Map<String, dynamic>?;

                  final nombre =
                      producto?['nombre']?.toString() ?? 'Producto sin nombre';

                  final id = detalle['id'].toString();

                  final agregado = _esAgregado(detalle);

                  final nuevaLinea = _esNuevaLinea(detalle);

                  final base = _cantidadBase(detalle);

                  final entregada = _cantidadEntregada(detalle);

                  final precio = _precio(detalle);

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
                              if (nuevaLinea)
                                IconButton(
                                  tooltip: 'Quitar producto nuevo',
                                  onPressed: () =>
                                      _quitarProductoNuevo(detalle),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                            ],
                          ),
                          if (agregado) ...[
                            const SizedBox(height: 4),
                            Text(
                              nuevaLinea
                                  ? 'Agregado en esta corrección'
                                  : 'Agregado durante una entrega anterior',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (!agregado) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Cantidad original/facturada: ${_numeroLimpio(base)}',
                            ),
                          ],
                          const SizedBox(height: 12),
                          TextField(
                            controller: _entregadosControllers[id],
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Cantidad entregada corregida',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) {
                              setState(() {});
                            },
                          ),
                          const SizedBox(height: 10),
                          Text('Precio: ${_formatearPrecio(precio)}'),
                          const SizedBox(height: 4),
                          Text(
                            'Subtotal corregido: ${_formatearPrecio(entregada * precio)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _guardando ? null : _agregarProducto,
                  icon: const Icon(Icons.add_shopping_cart_outlined),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('AGREGAR PRODUCTO'),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _filaResumen('Total anterior', _totalAnterior),
                        const SizedBox(height: 8),
                        _filaResumen('Total corregido', totalCorregido),
                        const SizedBox(height: 8),
                        _filaResumen('Diferencia', diferencia),
                        const Divider(height: 24),
                        _filaResumen('Ya pagado', _totalPagado),
                        const SizedBox(height: 8),
                        _filaResumen('Nuevo saldo', saldoNuevo),
                      ],
                    ),
                  ),
                ),
                if (totalCorregido < _totalPagado) ...[
                  const SizedBox(height: 12),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'El nuevo total es menor que lo ya pagado. '
                        'Esta corrección no se puede guardar todavía '
                        'porque requiere devolución o saldo a favor.',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _motivoController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Motivo de la corrección *',
                    hintText: 'Ej.: cliente cambió Gato Mix por Gato Pescado',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _guardando ? null : _guardarCorreccion,
                  icon: _guardando
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _guardando ? 'GUARDANDO...' : 'CONFIRMAR CORRECCIÓN',
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
    );
  }

  Widget _filaResumen(String texto, double valor) {
    return Row(
      children: [
        Expanded(child: Text(texto)),
        Text(
          _formatearPrecio(valor),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
