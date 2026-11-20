import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/payment_outbox.dart';
import '../../core/payment_money.dart';
import 'balance_repository.dart';
import '../../core/network_status.dart';
import '../../core/pending_orders.dart';
import '../../core/money_format.dart';
import '../../core/app_theme.dart';

Future<void> showClientPayment(
  BuildContext context,
  BalanceRepository repository,
  String clientId,
  String name,
  Future<void> Function() refresh,
) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ClientPaymentDialog(
      repository: repository,
      clientId: clientId,
      clientName: name,
      onConfirmed: refresh,
    ),
  );
}

class ClientPaymentDialog extends StatefulWidget {
  const ClientPaymentDialog({
    super.key,
    required this.repository,
    required this.clientId,
    required this.clientName,
    required this.onConfirmed,
    this.store,
  });
  final BalanceRepository repository;
  final String clientId, clientName;
  final Future<void> Function() onConfirmed;
  final PaymentOutbox? store;
  @override
  State<ClientPaymentDialog> createState() => _ClientPaymentDialogState();
}

class _ClientPaymentDialogState extends State<ClientPaymentDialog> {
  final amount = TextEditingController(), observation = TextEditingController();
  String medium = 'Efectivo';
  PaymentOutbox? store;
  PaymentRequest? request;
  Map<String, dynamic>? result;
  String? message;
  int? balance;
  bool loading = true, busy = false, available = false, refreshed = false;

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    try {
      await widget.repository.requireAdmin();
      final capable = await widget.repository.paymentsAvailable();
      final account = await widget.repository.account(widget.clientId);
      final directory = widget.store == null
          ? p.join(
              (await getApplicationSupportDirectory()).path,
              'cobros_contextuales',
            )
          : null;
      if (!mounted) return;
      store = widget.store ?? PaymentOutbox.open(directory!);
      final saved = current();
      setState(() {
        available = capable;
        balance = paymentCents(account['saldo_pendiente']);
        request = saved;
        result = saved?.result;
        loading = false;
        if (saved?.state == 'review') {
          message = 'El pago requiere revisión. La solicitud se conserva.';
        } else if (!capable) {
          message =
              'Cobros deshabilitados: ${widget.repository.capabilityIssue ?? 'No se pudo verificar la capacidad contextual del servidor.'}';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          message =
              'No se pudo verificar la cuenta o la cola de cobros. Requiere revisión.';
        });
      }
    }
  }

  PaymentRequest? current() => store!.active(
    widget.repository.scope,
    widget.repository.actor,
    widget.clientId,
  );

  @override
  void dispose() {
    amount.dispose();
    observation.dispose();
    if (!busy && widget.store == null) store?.close();
    super.dispose();
  }

  bool reviewError(Object error) =>
      error is PostgrestException &&
      (const {
            'PT403',
            'PT404',
            'PT410',
            'PT412',
            'PT422',
            '42501',
            'P0001',
          }.contains(error.code) ||
          (error.code == 'PT409' && error.message != 'stock_en_mantenimiento'));

  Future<void> submit() async {
    if (busy || store == null || !widget.repository.sessionMatches) return;
    setState(() => busy = true);
    try {
      await widget.repository.requireAdmin();
      var saved = current();
      if (request == null && saved != null) {
        if (mounted) {
          setState(() {
            request = saved;
            result = saved!.result;
            message =
                'Existe un pago guardado desde otra pantalla. Revisá su contenido antes de recuperarlo.';
          });
        }
        return;
      }
      if (saved == null) {
        if (!await widget.repository.paymentsAvailable()) {
          if (mounted) {
            setState(() {
              available = false;
              message =
                  'Cobros deshabilitados: ${widget.repository.capabilityIssue ?? 'No se pudo verificar la capacidad contextual del servidor.'}';
            });
          }
          return;
        }
        final account = await widget.repository.account(widget.clientId);
        final debt = paymentCents(account['saldo_pendiente']);
        // "100.000" o "1.500,50" (con puntos de miles) → "100000.00" para paymentCents.
        final cents = paymentCents(leerImporte(amount.text)?.toStringAsFixed(2) ?? amount.text.trim());
        if (cents <= 0 || cents > debt) {
          if (mounted) {
            setState(
              () => message =
                  'El importe debe ser positivo y no superar el saldo actualizado.',
            );
          }
          return;
        }
        if (!widget.repository.sessionMatches) {
          throw StateError('Cambió la sesión.');
        }
        saved = store!.prepare(
          widget.repository.scope,
          widget.repository.actor,
          widget.clientId,
          {
            'p_cliente_id': widget.clientId,
            'p_importe': cents / 100,
            'p_medio_pago': medium,
            'p_observacion': observation.text.trim().isEmpty
                ? null
                : observation.text.trim(),
          },
        );
      } else if (saved.result == null &&
          !await widget.repository.paymentsAvailable()) {
        if (mounted) {
          setState(() {
            available = false;
            message =
                'Cobros deshabilitados: ${widget.repository.capabilityIssue ?? 'No se pudo verificar la capacidad contextual del servidor.'}';
          });
        }
        return;
      }
      if (mounted) setState(() => request = saved);
      final confirmed = await store!.send(
        scope: widget.repository.scope,
        actor: widget.repository.actor,
        client: widget.clientId,
        id: saved.id,
        sessionMatches: () => widget.repository.sessionMatches,
        rpc: widget.repository.pay,
        requiresReview: reviewError,
      );
      if (!mounted || !widget.repository.sessionMatches) return;
      setState(() {
        result = confirmed;
        message = 'Cobro confirmado.';
      });
      // Refresh failures keep the confirmed request reserved and recoverable.
      await widget.onConfirmed();
      final account = await widget.repository.account(widget.clientId);
      if (mounted && widget.repository.sessionMatches) {
        setState(() {
          balance = paymentCents(account['saldo_pendiente']);
          refreshed = true;
        });
      }
    } catch (error) {
      if (mounted) {
        try {
          request = current();
        } catch (_) {
          available = false;
        }
        final pending = request;
        if (pending != null &&
            pending.result == null &&
            pending.state != 'review' &&
            isUncertainRequestError(error)) {
          await _queueOffline(pending);
          return;
        }
        setState(
          () => message = request?.state == 'review'
              ? 'El pago requiere revisión. La solicitud se conserva.'
              : result != null
              ? 'Cobro confirmado. Falta actualizar los saldos; recuperá la confirmación.'
              : request == null
              ? 'No se pudo preparar el cobro. Revisá importe, permisos y disponibilidad del servidor.'
              : 'Resultado no confirmado. Usá Recuperar pago pendiente; se conserva el mismo UUID.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      } else if (widget.store == null) {
        store?.close();
      }
    }
  }

  /// Sin señal: el cobro (misma solicitud) queda en "Pendientes de enviar" con la hora de
  /// ahora y se envía solo. Si se recupera antes desde acá, el servidor no lo repite.
  Future<void> _queueOffline(PaymentRequest pending) async {
    final payload = pending.payload;
    await PendingOrders.instance.add(
      PendingOrder.stock(
        rpc: 'registrar_cobro_sin_conexion',
        args: {
          'p_id': pending.id,
          'p_cliente_id': payload['p_cliente_id'],
          'p_importe': payload['p_importe'],
          'p_medio_pago': payload['p_medio_pago'],
          'p_observacion': payload['p_observacion'],
          'p_fecha': DateTime.now().toUtc().toIso8601String(),
        },
        description: 'Cobro · ${widget.clientName}',
        total: (payload['p_importe'] as num?)?.toDouble() ?? 0,
      ),
      uid: widget.repository.actor,
    );
    if (mounted) {
      setState(
        () => message =
            'Sin señal: el cobro quedó guardado en el teléfono con la hora de ahora y se '
            'envía solo cuando vuelva la conexión. Lo ves en "Pendientes de enviar".',
      );
    }
  }

  void close() {
    if (busy) return;
    if (result != null && refreshed && widget.repository.sessionMatches) {
      store!.seen(
        widget.repository.scope,
        widget.repository.actor,
        widget.clientId,
        result!['solicitud_id'] as String,
      );
    }
    Navigator.pop(context);
  }

  /// Lo que queda debiendo con el importe escrito (null si no hay importe válido).
  double? get _quedaDebiendo {
    final b = balance;
    final value = leerImporte(amount.text);
    if (b == null || value == null || value <= 0) return null;
    return b / 100 - value;
  }

  @override
  Widget build(BuildContext context) {
    final t = Tonos.of(context);
    final editable = available && !busy;
    final rest = _quedaDebiendo;
    return AlertDialog(
    title: const Text('Registrar pago'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: loading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: t.oscuro ? Colors.white24 : AppColors.borde),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          balance == null ? widget.clientName : '${widget.clientName} · saldo actual',
                          style: TextStyle(color: t.secundario),
                        ),
                        if (balance != null)
                          Text(
                            centsMoney(balance!),
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: t.rojo),
                          ),
                      ],
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 10),
                    Text(message!, key: const ValueKey('payment-message')),
                  ],
                  if (request != null) ...[
                    const SizedBox(height: 10),
                    Text('Solicitud guardada: ${request!.id}'),
                    Text(
                      'Pago guardado: ${paymentMoney(request!.payload['p_importe'])} · ${request!.payload['p_medio_pago']}',
                    ),
                  ],
                  if (result == null && request == null) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: amount,
                            enabled: editable,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            decoration: const InputDecoration(
                              labelText: 'Importe que paga',
                              prefixText: '\$ ',
                              floatingLabelBehavior: FloatingLabelBehavior.always,
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: const [ImporteInputFormatter()],
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        if (balance != null && balance! > 0) ...[
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: editable
                                ? () => setState(() => amount.text = formatoNumero(balance! / 100))
                                : null,
                            child: const Text('Todo el saldo'),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Medio de pago', style: TextStyle(color: t.secundario)),
                    const SizedBox(height: 6),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'Efectivo',
                          icon: Icon(Icons.payments_outlined, color: t.verde),
                          label: Text('Efectivo', style: TextStyle(color: t.verde, fontWeight: FontWeight.w600)),
                        ),
                        ButtonSegment(
                          value: 'Transferencia',
                          icon: Icon(Icons.phone_android, color: t.azul),
                          label: Text('Transferencia', style: TextStyle(color: t.azul, fontWeight: FontWeight.w600)),
                        ),
                      ],
                      selected: {medium},
                      onSelectionChanged: editable ? (v) => setState(() => medium = v.first) : null,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: observation,
                      enabled: editable,
                      decoration: const InputDecoration(
                        labelText: 'Observación (opcional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      [
                        if (rest != null && rest > 0.005) 'Queda debiendo ${formatoPesos(rest)}.',
                        if (rest != null && rest.abs() <= 0.005) 'Con este pago queda sin deuda.',
                        if (rest != null && rest < -0.005) 'Es más que el saldo actual.',
                        'El pago se aplica primero a las deudas más antiguas.',
                      ].join(' '),
                      style: TextStyle(fontSize: 13, color: rest != null && rest < -0.005 ? t.rojo : t.secundario),
                    ),
                  ],
                  if (result != null) ...[
                    Text(
                      'Cobrado: ${paymentMoney(result!['importe'])} · ${result!['medio_pago']}',
                    ),
                    for (final line in result!['imputaciones'] as List)
                      Text(
                        'Pedido ${line['pedido_id']} · Aplicado ${paymentMoney(line['importe_aplicado'])} · Saldo ${paymentMoney(line['saldo_restante'])}',
                      ),
                  ],
                ],
              ),
      ),
    ),
    actions: [
      TextButton(onPressed: busy ? null : close, child: const Text('Cerrar')),
      if (!loading && (!refreshed || result == null))
        FilledButton(
          onPressed:
              busy ||
                  store == null ||
                  request?.state == 'review' ||
                  (result == null && !available)
              ? null
              : submit,
          child: Text(
            busy
                ? 'Consultando…'
                : request != null
                ? 'Recuperar pago pendiente'
                : 'Confirmar pago',
          ),
        ),
    ],
  );
  }
}
