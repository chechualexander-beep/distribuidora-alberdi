import '../../core/app_config.dart';
import 'package:distribuidora_alberdi/core/app_theme.dart';
import 'delivery_quantity.dart';
import '../balances/balance_repository.dart';
import '../balances/balances_page.dart';
import '../clients/client_detail_link.dart';
import 'finalization_request.dart';
import '../../core/desktop_records.dart';
import '../../core/desktop_table.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/network_status.dart';
import '../../core/pending_orders.dart';
import 'package:distribuidora_alberdi/core/money_format.dart';
import 'payment_choice.dart';
import '../invoicing/atomic_invoice.dart' show newInvoiceRequestId;

class ManageOrderPage extends StatefulWidget {
  final Map<String, dynamic> pedido;
  final SupabaseClient? client;
  final FinalizationRequestStore? requestStore;
  final BalanceRepository? balanceRepository;

  const ManageOrderPage({
    super.key,
    required this.pedido,
    this.client,
    this.requestStore,
    this.balanceRepository,
  });

  @override
  State<ManageOrderPage> createState() => _ManageOrderPageState();
}

class _ManageOrderPageState extends State<ManageOrderPage> {
  SupabaseClient get _client => widget.client ?? Supabase.instance.client;
  bool _cargando = true;
  bool _guardando = false;
  FinalizationRequestStore? _solicitudes;
  Map<String, dynamic>? _pendiente;
  bool _esCatalogo = false;
  bool _catalogoConPreventista = false;
  bool _entregaCerrada = false;
  String? _error;

  String _estado = 'pendiente';
  String? _modoEntrega;
  List<Map<String, dynamic>> _detalles = [];

  final Map<String, TextEditingController> _entregadosControllers = {};
  final TextEditingController _motivoController = TextEditingController();

  Future<void> _openBalances() async {
    if (_guardando) return;
    try {
      var clientId = widget.pedido['cliente_id']?.toString();
      if (clientId == null) {
        final row = await _client
            .from('pedidos')
            .select('cliente_id')
            .eq('id', widget.pedido['id'])
            .single();
        clientId = row['cliente_id'].toString();
      }
      final pending =
          _pendiente != null ||
          _solicitudes?.read(widget.pedido['id'].toString()) != null;
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ClientBalancePage(
            clientId: clientId!,
            readOnly: pending,
            repository: widget.balanceRepository ?? BalanceRepository(_client),
          ),
        ),
      );
    } catch (_) {
      _mostrarMensaje('No se pudo abrir la cuenta del cliente.');
    }
  }

  List<Widget> get _balanceActions => [
    IconButton(
      tooltip: 'Ver saldo / Registrar pago',
      onPressed: _guardando ? null : _openBalances,
      icon: const Icon(Icons.account_balance_wallet_outlined),
    ),
  ];

  @override
  void initState() {
    super.initState();

    _estado = widget.pedido['estado']?.toString() ?? 'pendiente';

    _motivoController.text =
        widget.pedido['motivo_no_entrega']?.toString() ?? '';

    _iniciar();
  }

  Future<void> _iniciar() async {
    try {
      if (appConfig.usesV2For(widget.pedido['tipo_operacion']?.toString())) {
        _solicitudes = widget.requestStore ?? await finalizationStore(_client);
        _pendiente = _solicitudes!.read(widget.pedido['id'].toString());
      }
      if (mounted) await _cargarDetalles();
    } catch (_) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error =
              'No se pudo recuperar la solicitud local. No inicies otra gestión.';
        });
      }
    }
  }

  /// Pago mixto: la parte que no fue con la entrega va como un cobro más del cliente. Sin
  /// señal queda en "Pendientes de enviar", detrás de la entrega (la cola respeta el orden).
  (double, String)? _segundoPago;

  Future<String?> _registrarSegundoPago({bool soloEncolar = false}) async {
    final segundo = _segundoPago;
    if (segundo == null) return null;
    _segundoPago = null;
    final (importe, medio) = segundo;
    final client = Supabase.instance.client;
    final cliente = widget.pedido['clientes'];
    final nombre = cliente is Map ? cliente['nombre_comercio']?.toString() ?? 'Cliente' : 'Cliente';
    final texto = '${formatoPesos(importe)} en ${medio.toLowerCase()}';
    final clienteId = widget.pedido['cliente_id']?.toString();
    if (clienteId == null) return 'No se registró $texto: anotalo en Saldos.';
    final args = <String, dynamic>{
      'p_id': newInvoiceRequestId(),
      'p_cliente_id': clienteId,
      'p_importe': importe,
      'p_medio_pago': medio,
      'p_observacion': 'Pago mixto de la entrega',
      'p_fecha': DateTime.now().toUtc().toIso8601String(),
    };
    Future<String> encolar() async {
      await PendingOrders.instance.add(
        PendingOrder.stock(
          rpc: 'registrar_cobro_sin_conexion',
          args: args,
          description: 'Cobro $medio · $nombre',
          total: importe,
        ),
        uid: client.auth.currentUser?.id,
      );
      return '$texto: se envía solo cuando haya señal.';
    }

    if (soloEncolar) return encolar();
    try {
      await client.rpc('registrar_cobro_sin_conexion', params: args).timeout(const Duration(seconds: 20));
      return '$texto registrado.';
    } catch (error) {
      if (isUncertainRequestError(error)) return encolar();
      return 'No se registró $texto (${error is PostgrestException ? error.message : error}). Anotalo en Saldos.';
    }
  }

  Future<void> _enviarPendiente() async {
    final payload = _pendiente;
    if (payload == null) return;
    try {
      final result = await reconcileFinalization(
        Supabase.instance.client,
        payload,
        store: _solicitudes!,
        retry: true,
      );
      await _solicitudes!.acknowledge(widget.pedido['id'].toString());
      final segundo = await _registrarSegundoPago();
      if (!mounted) return;
      _pendiente = null;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Gestión confirmada'),
          content: Text(
            'Resultado: ${_nombreResultado(result['resultado_entrega'].toString())}'
            '${segundo == null ? '' : '\nPago mixto: $segundo'}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ACEPTAR'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (error) {
      // These SQL failures definitively rolled back this exact request.
      // Conflicts and transport/server ambiguity remain available for reconciliation.
      if ((error.code == 'PT422' && !isFinalizationDateError(error)) ||
          error.message.toLowerCase().contains('stock insuficiente') ||
          error.message.toLowerCase().contains('no inicializado')) {
        try {
          _solicitudes!.markForReview(
            widget.pedido['id'].toString(),
            error.code ?? 'server_rejection',
          );
        } on LocalOutboxException catch (storageError) {
          _mostrarMensaje(storageError.message);
          return;
        }
      }
      _mostrarMensaje(finalizationErrorMessage(error));
    } on LocalOutboxException catch (error) {
      _mostrarMensaje(error.message);
    } catch (_) {
      // La entrega quedó guardada para reintentar: la otra parte del pago espera en la cola.
      await _registrarSegundoPago(soloEncolar: true);
      _mostrarMensaje(
        'No se conoce el resultado. La solicitud quedó guardada; revisá o reintentá con la misma solicitud.',
      );
    }
  }

  Future<void> _cargarDetalles() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      try {
        final origen = await _client
            .from('pedidos')
            .select('origen,catalogo_preventista_id,resultado_entrega')
            .eq('id', widget.pedido['id'])
            .single();
        // La asignación queda guardada en cada pedido, independiente del enlace actual.
        _esCatalogo = origen['origen'] == 'catalogo';
        _catalogoConPreventista = origen['catalogo_preventista_id'] != null;
        _entregaCerrada =
            (origen['resultado_entrega'] ?? 'pendiente') != 'pendiente';
      } on PostgrestException catch (error) {
        // Compatibilidad mientras todavía no se instaló la migración.
        if (error.code != '42703' && error.code != 'PGRST204') rethrow;
        _esCatalogo = false;
      }
      final respuesta = await _client
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
            porcentaje_comision,
            importe_comision,
            productos (
              nombre,
              codigo_original,
              precio_normal,
              precio_promo,
              precio_interior,
              comision_normal,
              comision_promo,
              comision_interior
            )
            ''')
          .eq('pedido_id', widget.pedido['id']);

      if (!mounted) return;

      final detalles = List<Map<String, dynamic>>.from(respuesta);

      for (final detalle in detalles) {
        final id = detalle['id'].toString();

        final entregada =
            double.tryParse(detalle['cantidad_entregada']?.toString() ?? '0') ??
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

  bool get _aumentoContextual {
    final tipo = widget.pedido['tipo_operacion']?.toString();
    return tipo == 'venta_directa' && appConfig.usesV2For(tipo);
  }

  bool _esExcedente(Map<String, dynamic> detalle) =>
      detalle['excedente_local'] == true;

  bool get _confirmada =>
      _entregaCerrada ||
      (widget.pedido['resultado_entrega'] ?? 'pendiente') != 'pendiente';

  Map<String, dynamic>? _excedenteDe(Map<String, dynamic> original) {
    for (final detalle in _detalles) {
      if (detalle['original_id_local'] == original['id']) return detalle;
    }
    return null;
  }

  String _textoCantidad(Map<String, dynamic> detalle) =>
      _entregadosControllers[detalle['id'].toString()]?.text ?? '0';

  String? _desgloseExcedente(Map<String, dynamic> original) {
    final extra = _excedenteDe(original);
    if (extra == null) return null;
    return '${_numeroLimpio(_cantidadEntregada(original))} del pedido a '
        '${desktopMoney(_precio(original))} + '
        '${_numeroLimpio(_cantidadEntregada(extra))} adicionales a '
        '${desktopMoney(_precio(extra))}';
  }

  void _cambiarCantidad(Map<String, dynamic> detalle) {
    setState(() {
      if (!_aumentoContextual || _esAgregadoEnEntrega(detalle)) return;
      final base = (_cantidadPedida(detalle) * 100).round();
      final propuesta = splitDeliveryQuantity(
        _textoCantidad(detalle),
        base,
        allowsAdditional: true,
      );
      final previo = _excedenteDe(detalle);
      if (propuesta == null || propuesta.additional == 0) {
        if (previo != null) _eliminarAgregado(previo);
        return;
      }
      final producto = detalle['productos'] as Map<String, dynamic>?;
      final lista = detalle['tipo_precio']?.toString() ?? 'normal';
      final precio = producto == null
          ? 0.0
          : _precioProductoSegunLista(producto, lista);
      if (!precio.isFinite || precio <= 0) return;
      final cantidad = _numeroLimpio(propuesta.additional / 100);
      if (previo != null) {
        _entregadosControllers[previo['id'].toString()]!.text = cantidad;
        return;
      }
      final id = 'excedente_${detalle['id']}';
      _entregadosControllers[id] = TextEditingController(text: cantidad);
      _detalles.add({
        ...detalle,
        'id': id,
        'cantidad': 0,
        'cantidad_facturada': 0,
        'precio_unitario': precio,
        'tipo_precio': lista,
        'agregado_en_entrega_local': true,
        'excedente_local': true,
        'original_id_local': detalle['id'],
      });
    });
  }

  void _eliminarAgregado(Map<String, dynamic> detalle) {
    _entregadosControllers.remove(detalle['id'].toString())?.dispose();
    _detalles.remove(detalle);
  }

  void _seleccionarModo(String? modo) {
    if (modo == null || modo == _modoEntrega) return;
    setState(() {
      if (modo != 'parcial' || _modoEntrega == null) {
        for (final extra in _detalles.where(_esAgregadoEnEntrega).toList()) {
          _eliminarAgregado(extra);
        }
        for (final detalle in _detalles) {
          _entregadosControllers[detalle['id'].toString()]?.text =
              modo == 'rechazado'
              ? '0'
              : _numeroLimpio(_cantidadPedida(detalle));
        }
      }
      _modoEntrega = modo;
    });
  }

  void _quitarProductoAgregado(Map<String, dynamic> detalle) {
    if (!_esAgregadoEnEntrega(detalle)) return;

    setState(() => _eliminarAgregado(detalle));
  }

  double _cantidadPedida(Map<String, dynamic> detalle) {
    final cantidadFacturada = detalle['cantidad_facturada'];

    if (cantidadFacturada != null) {
      return double.tryParse(cantidadFacturada.toString()) ?? 0;
    }

    return double.tryParse(detalle['cantidad']?.toString() ?? '') ?? 0;
  }

  double _cantidadEntregada(Map<String, dynamic> detalle) {
    final cantidad = deliveryHundredths(_textoCantidad(detalle));
    if (cantidad == null) return 0;
    if (_aumentoContextual && !_esAgregadoEnEntrega(detalle)) {
      final base = (_cantidadPedida(detalle) * 100).round();
      return (cantidad > base ? base : cantidad) / 100;
    }
    return cantidad / 100;
  }

  double _cantidadNoEntregada(Map<String, dynamic> detalle) {
    final pedida = _cantidadPedida(detalle);
    final entregada = _cantidadEntregada(detalle);

    final resultado = pedida - entregada;

    return resultado < 0 ? 0 : resultado;
  }

  double _precio(Map<String, dynamic> detalle) {
    return double.tryParse(detalle['precio_unitario']?.toString() ?? '0') ?? 0;
  }

  double _porcentajeComision(Map<String, dynamic> detalle) {
    if (_esCatalogo && !_catalogoConPreventista) return 0;
    if (_esCatalogo && detalle['agregado_en_entrega_local'] != true) {
      return double.tryParse(
            detalle['porcentaje_comision']?.toString() ?? '',
          ) ??
          0;
    }
    final producto = detalle['productos'] as Map<String, dynamic>?;

    final tipoPrecio = detalle['tipo_precio']?.toString() ?? 'normal';

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
          .from('productos_administracion')
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

      final productosDisponibles = List<Map<String, dynamic>>.from(respuesta)
          .where(
            (producto) => !idsYaIncluidos.contains(producto['id']?.toString()),
          )
          .toList();

      final productoSeleccionado = await showModalBottomSheet<Map<String, dynamic>>(
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
                final nombre =
                    producto['nombre']
                        ?.toString()
                        .toLowerCase()
                        .replaceAll('á', 'a')
                        .replaceAll('é', 'e')
                        .replaceAll('í', 'i')
                        .replaceAll('ó', 'o')
                        .replaceAll('ú', 'u') ??
                    '';

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

      _mostrarMensaje('No se pudieron cargar los productos.');
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

  String _formatearPrecio(double valor) => formatoPesos(valor);

  double _totalEntregadoActual() {
    return _detalles.fold<double>(0, (total, detalle) {
      final cantidadEntregada = _cantidadEntregada(detalle);
      final precio = _precio(detalle);

      return total + (cantidadEntregada * precio);
    });
  }

  bool _validarCantidades() {
    for (final detalle in _detalles) {
      final total = deliveryHundredths(_textoCantidad(detalle));
      if (total == null) {
        _mostrarMensaje('Ingresá una cantidad válida con hasta dos decimales.');
        return false;
      }
      if (_esAgregadoEnEntrega(detalle)) continue;
      final base = (_cantidadPedida(detalle) * 100).round();
      final propuesta = splitDeliveryQuantity(
        _textoCantidad(detalle),
        base,
        allowsAdditional: _aumentoContextual,
      );
      if (propuesta == null) {
        _mostrarMensaje(
          'En este pedido la cantidad entregada no puede superar la original.',
        );
        return false;
      }
      final extra = _excedenteDe(detalle);
      if (propuesta.additional > 0 &&
          (extra == null ||
              deliveryHundredths(_textoCantidad(extra)) !=
                  propuesta.additional)) {
        _mostrarMensaje(
          'No hay un precio válido para las unidades adicionales.',
        );
        return false;
      }
    }

    return true;
  }

  Future<void> _cancelarVentaDirecta() async {
    if (_guardando) return;

    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancelar venta directa'),
          content: const Text(
            '¿Seguro que querés cancelar esta venta directa?\n\n'
            'La operación todavía no fue finalizada y será eliminada.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('VOLVER'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('CANCELAR VENTA'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    setState(() {
      _guardando = true;
    });

    try {
      await Supabase.instance.client.rpc(
        'eliminar_pedido_pendiente',
        params: {'p_pedido_id': widget.pedido['id']},
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (!mounted) return;

      _mostrarMensaje('No se pudo cancelar la venta: ${error.message}');
    } catch (_) {
      if (!mounted) return;

      _mostrarMensaje('Ocurrió un error al cancelar la venta directa.');
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }
    }
  }

  Future<void> _guardarGestion() async {
    if (_guardando) return;
    setState(() => _guardando = true);
    try {
      if (_pendiente != null) {
        await _enviarPendiente();
      } else {
        await _prepararGestion();
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _prepararGestion() async {
    if (_confirmada) return;
    if (appConfig.blocksOrderOperation(
      widget.pedido['tipo_operacion']?.toString() ?? '',
    )) {
      _mostrarMensaje(AppConfig.directSalesTestingMessage);
      return;
    }
    if (_modoEntrega == null) {
      _mostrarMensaje('Seleccioná cómo fue la entrega antes de guardar.');
      return;
    }
    if (!_validarCantidades()) return;

    final resultado = _resultadoEntrega();

    final totalEntregado = _totalEntregadoActual();
    double creditoAplicable = 0;
    // Sin señal no se puede consultar el saldo a favor: la gestión se guarda en el teléfono
    // y el servidor aplica el crédito y cobra el saldo real al recibirla.
    var sinSenal = false;
    double efectivoCompleto = totalEntregado;
    if (resultado != 'no_entregado' && totalEntregado > 0) {
      try {
        final pedido = await Supabase.instance.client
            .from('pedidos')
            .select('cliente_id')
            .eq('id', widget.pedido['id'])
            .single();
        final cuenta = await Supabase.instance.client
            .from('saldos_pendientes_clientes')
            .select('saldo_a_favor,saldo_pendiente')
            .eq('cliente_id', pedido['cliente_id'])
            .single();
        final favor = double.tryParse(cuenta['saldo_a_favor'].toString()) ?? 0;
        final deudaAnterior =
            double.tryParse(cuenta['saldo_pendiente'].toString()) ?? 0;
        creditoAplicable = (favor - deudaAnterior)
            .clamp(0, totalEntregado)
            .toDouble();
        efectivoCompleto = totalEntregado - creditoAplicable;
      } catch (error) {
        if (!isUncertainRequestError(error)) {
          _mostrarMensaje(
            'No se pudo consultar el saldo a favor. Intentá nuevamente.',
          );
          return;
        }
        sinSenal = true;
      }
      if (!mounted) return;
    }
    String? medioPagoCompleto;
    double? importePagoParcial;
    String? medioPagoParcial;
    _segundoPago = null;

    if (resultado != 'no_entregado' && totalEntregado > 0) {
      final eleccion = await showPaymentChoice(
        context,
        aCobrar: efectivoCompleto,
        detalle: creditoAplicable > 0
            ? 'Mercadería ${_formatearPrecio(totalEntregado)} · saldo a favor aplicado ${_formatearPrecio(creditoAplicable)}'
            : 'Mercadería entregada: ${_formatearPrecio(totalEntregado)}',
      );
      if (eleccion == null || !mounted) return;
      final plan = planPago(eleccion, efectivoCompleto);
      if (plan.completo != null) {
        medioPagoCompleto = plan.completo;
      } else {
        // Mixto o dejó saldo: la entrega lleva una parte; la otra, un cobro más del cliente.
        medioPagoCompleto = 'Parcial';
        importePagoParcial = plan.parcialImporte;
        medioPagoParcial = plan.parcialMedio;
        if (plan.segundoImporte != null && plan.segundoMedio != null) {
          _segundoPago = (plan.segundoImporte!, plan.segundoMedio!);
        }
      }
    }
    if (resultado != 'no_entregado' && medioPagoCompleto == null) {
      return;
    }
    if (!mounted) return;

    if ((resultado == 'no_entregado' || resultado == 'parcial') &&
        _motivoController.text.trim().isEmpty) {
      _mostrarMensaje('Ingresá un motivo para la mercadería no entregada.');
      return;
    }

    try {
      final detallesGestion = _detalles
          .where(
            (detalle) =>
                !_esAgregadoEnEntrega(detalle) ||
                _cantidadEntregada(detalle) > 0,
          )
          .map((detalle) {
            final esAgregado = _esAgregadoEnEntrega(detalle);

            final entregada = _cantidadEntregada(detalle);
            final noEntregada = esAgregado ? 0 : _cantidadNoEntregada(detalle);

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
              'tipo_precio': detalle['tipo_precio']?.toString() ?? 'normal',
            };
          })
          .toList();

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
        importePago = efectivoCompleto;
        medioPago = medioPagoCompleto;
      }

      if (appConfig.usesV2For(widget.pedido['tipo_operacion']?.toString())) {
        final client = Supabase.instance.client;
        _solicitudes ??= await finalizationStore(client);
        final pedidoId = widget.pedido['id'].toString();
        final entrada = <String, dynamic>{
          'p_estado': _estado,
          ...contextualDeliveryLines(detallesGestion),
          'p_motivo_no_entrega': resultado == 'entregado'
              ? null
              : _motivoController.text.trim(),
          'p_tipo_pago': tipoPago,
          'p_importe_pago': importePago,
          'p_medio_pago': medioPago,
        };
        try {
          if (sinSenal) throw const FinalizationClockException();
          _pendiente = await prepareCurrentFinalization(
            client,
            _solicitudes!,
            pedidoId,
            entrada,
          );
        } on FinalizationClockException {
          // Sin señal: queda en el teléfono con la hora real de la entrega y se envía sola.
          // "Pago completo" sin importe: el servidor cobra el saldo real de ese momento.
          _pendiente = await prepareOfflineFinalization(
            client,
            _solicitudes!,
            pedidoId,
            {
              ...entrada,
              if (tipoPago == 'completo') 'p_importe_pago': null,
            },
          );
          final cliente = widget.pedido['clientes'];
          await PendingOrders.instance.add(
            PendingOrder.delivery(
              orderId: pedidoId,
              clientName: cliente is Map
                  ? cliente['nombre_comercio']?.toString() ?? 'Cliente'
                  : 'Cliente',
              total: totalEntregado,
            ),
            uid: client.auth.currentUser?.id,
          );
          await _registrarSegundoPago(soloEncolar: true);
          if (!mounted) return;
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              icon: const Icon(Icons.cloud_upload_outlined, size: 48),
              title: const Text('Guardado en el teléfono'),
              content: Text(
                'No hay señal: la gestión (${_nombreResultado(resultado)}) quedó guardada con la hora '
                'de ahora y se envía sola cuando vuelva la conexión. '
                'La ves en "Pendientes de enviar".',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ACEPTAR'),
                ),
              ],
            ),
          );
          if (mounted) Navigator.of(context).pop(true);
          return;
        }
        if (mounted) setState(() {});
        await _enviarPendiente();
        return;
      }
      await Supabase.instance.client.rpc(
        'finalizar_gestion_pedido',
        params: {
          'p_pedido_id': widget.pedido['id'],
          'p_estado': _estado,
          'p_resultado_entrega': resultado,
          'p_motivo_no_entrega': resultado == 'entregado'
              ? null
              : _motivoController.text.trim(),
          'p_detalles': detallesGestion,
          'p_tipo_pago': tipoPago,
          'p_importe_pago': importePago,
          'p_medio_pago': medioPago,
        },
      );
      final segundo = await _registrarSegundoPago();

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            icon: const Icon(Icons.check_circle_outline, size: 48),
            title: const Text('Gestión guardada'),
            content: Text(
              'Resultado: ${_nombreResultado(resultado)}${segundo == null ? '' : '\nPago mixto: $segundo'}',
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
    } on LocalOutboxException catch (error) {
      _mostrarMensaje(error.message);
    } on FinalizationClockException catch (error) {
      _mostrarMensaje(error.toString());
    } on PostgrestException catch (error) {
      _mostrarMensaje(finalizationErrorMessage(error));
    } catch (_) {
      _mostrarMensaje('Ocurrió un error al guardar la gestión.');
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
    final cliente = widget.pedido['clientes'] as Map<String, dynamic>?;

    final clienteNombre =
        cliente?['nombre_comercio']?.toString() ?? 'Cliente sin nombre';

    if (_cargando) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gestionar pedido')),
        body: DesktopForm(
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gestionar pedido')),
        body: DesktopForm(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 60),
                  const SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _iniciar,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_pendiente != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Gestión por confirmar'),
          actions: _balanceActions,
        ),
        body: DesktopForm(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Hay una solicitud guardada. Sus cantidades, pago y fecha física se conservarán exactamente al reintentar.',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _guardando ? null : _guardarGestion,
                  child: Text(
                    _guardando
                        ? 'CONSULTANDO…'
                        : 'REVISAR / REINTENTAR SOLICITUD',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_confirmada) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gestionar pedido')),
        body: const Center(child: Text('La entrega ya fue confirmada.')),
      );
    }
    final resultado = _resultadoEntrega();
    final totalEntregadoActual = _totalEntregadoActual();
    final esVentaDirecta =
        widget.pedido['tipo_operacion']?.toString() == 'venta_directa';

    final facturado = widget.pedido['facturado'] == true;

    final resultadoGuardado =
        widget.pedido['resultado_entrega']?.toString() ?? 'pendiente';

    final puedeCancelarVentaDirecta =
        esVentaDirecta && !facturado && resultadoGuardado == 'pendiente';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestionar pedido'),
        actions: _balanceActions,
      ),
      body: DesktopForm(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Cliente', style: TextStyle(color: AppColors.gris)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            clienteNombre,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        ClientDetailLink(
                          clientId: widget.pedido['cliente_id']?.toString(),
                          client: _client,
                          enabled: !_guardando,
                        ),
                      ],
                    ),
                    if (widget.pedido['tipo_operacion']?.toString() ==
                        'venta_directa') ...[
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
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            Card(
              child: Column(
                children: [
                  RadioListTile<String>(
                    value: 'completo',
                    groupValue: _modoEntrega,
                    title: const Text('TODO ENTREGADO'),
                    subtitle: const Text('El cliente recibió todo el pedido'),
                    onChanged: _seleccionarModo,
                  ),

                  const Divider(height: 1),

                  RadioListTile<String>(
                    value: 'rechazado',
                    groupValue: _modoEntrega,
                    title: const Text('TODO NO ENTREGADO'),
                    subtitle: const Text(
                      'El cliente no recibió ningún producto',
                    ),
                    onChanged: _seleccionarModo,
                  ),

                  const Divider(height: 1),

                  RadioListTile<String>(
                    value: 'parcial',
                    groupValue: _modoEntrega,
                    title: const Text('MODIFICAR ENTREGA'),
                    subtitle: const Text(
                      'Ajustá cantidades o agregá otros productos',
                    ),
                    onChanged: _seleccionarModo,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            if (_modoEntrega == 'parcial' && useDesktopLayout(context))
              DesktopRecords(
                embedded: true,
                records: _detalles.where((d) => !_esExcedente(d)).toList(),
                fields: [
                  DesktopField(
                    'Producto',
                    (r) => (r['productos'] as Map?)?['nombre'],
                    width: 240,
                  ),
                  DesktopField(
                    'Pedida',
                    _cantidadPedida,
                    numeric: true,
                    width: 80,
                  ),
                  DesktopField(
                    'Entregada',
                    (r) => SizedBox(
                      width: 110,
                      child: TextField(
                        key: ValueKey('entregar-${r['id']}'),
                        controller: _entregadosControllers[r['id'].toString()],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => _cambiarCantidad(r),
                        decoration: const InputDecoration(
                          labelText: 'Cantidad',
                          isDense: true,
                        ),
                      ),
                    ),
                    width: 110,
                  ),
                  DesktopField(
                    'No entregada',
                    _cantidadNoEntregada,
                    numeric: true,
                    width: 105,
                  ),
                  DesktopField(
                    'Precio',
                    (r) => desktopMoney(_precio(r)),
                    numeric: true,
                    width: 110,
                  ),
                  // Sin comisión: esta pantalla se le muestra al cliente.
                  DesktopField(
                    'Subtotal',
                    (r) => desktopMoney(_precio(r) * _cantidadEntregada(r)),
                    numeric: true,
                    width: 120,
                  ),
                  DesktopField(
                    'Origen',
                    (r) =>
                        _desgloseExcedente(r) ??
                        (_esAgregadoEnEntrega(r)
                            ? 'Agregado en entrega'
                            : 'Pedido'),
                    width: 265,
                  ),
                ],
                actions: (r) => _esAgregadoEnEntrega(r)
                    ? IconButton(
                        tooltip: 'Quitar producto agregado',
                        onPressed: () => _quitarProductoAgregado(r),
                        icon: const Icon(Icons.delete_outline, size: 20),
                      )
                    : const SizedBox.shrink(),
              ),
            if (_modoEntrega == 'parcial' && !useDesktopLayout(context))
              ..._detalles.where((d) => !_esExcedente(d)).map((detalle) {
                final producto = detalle['productos'] as Map<String, dynamic>?;

                final nombre =
                    producto?['nombre']?.toString() ?? 'Producto sin nombre';

                final id = detalle['id'].toString();
                final esAgregado = _esAgregadoEnEntrega(detalle);

                final pedida = _cantidadPedida(detalle);
                final noEntregada = _cantidadNoEntregada(detalle);

                final subtotal = _precio(detalle) * _cantidadEntregada(detalle);

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
                                onPressed: () =>
                                    _quitarProductoAgregado(detalle),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: AppColors.naranja,
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
                                color: AppColors.naranja,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Agregado durante la entrega',
                                style: TextStyle(
                                  color: AppColors.naranja,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text('Cantidad pedida: ${_numeroLimpio(pedida)}'),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _entregadosControllers[id],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Cantidad entregada',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => _cambiarCantidad(detalle),
                        ),
                        const SizedBox(height: 10),
                        Text('No entregada: ${_numeroLimpio(noEntregada)}'),
                        const SizedBox(height: 8),
                        Text('Precio: ${_formatearPrecio(_precio(detalle))}'),
                        if (_desgloseExcedente(detalle) case final desglose?)
                          Text(desglose),
                        // Sin comisión: esta pantalla se le muestra al cliente.
                        const SizedBox(height: 4),
                        Text(
                          'Subtotal: ${_formatearPrecio(subtotal)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
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
            if (_modoEntrega != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TOTAL ACTUAL DE LA ENTREGA',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Se actualiza según la mercadería entregada',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.gris,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formatearPrecio(totalEntregadoActual),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            Card(
              child: ListTile(
                title: const Text(
                  'Resultado de entrega',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(_nombreResultado(resultado)),
              ),
            ),

            if (resultado == 'parcial' || resultado == 'no_entregado') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _motivoController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motivo de mercadería no entregada *',
                  hintText: 'Ej.: cliente cerrado, rechazó parte del pedido...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (puedeCancelarVentaDirecta) ...[
              OutlinedButton.icon(
                onPressed: _guardando ? null : _cancelarVentaDirecta,
                icon: const Icon(Icons.cancel_outlined),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('CANCELAR VENTA DIRECTA'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 20),

            FilledButton.icon(
              onPressed: _guardando ? null : _guardarGestion,
              icon: _guardando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_guardando ? 'GUARDANDO...' : 'GUARDAR GESTIÓN'),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
