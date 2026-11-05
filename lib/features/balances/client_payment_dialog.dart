import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/payment_outbox.dart';
import '../../core/payment_money.dart';
import 'balance_repository.dart';

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
        final cents = paymentCents(amount.text);
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
    } catch (_) {
      if (mounted) {
        try {
          request = current();
        } catch (_) {
          available = false;
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

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Registrar pago de deudas'),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: loading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.clientName),
                  if (balance != null)
                    Text('Saldo actual: ${centsMoney(balance!)}'),
                  const Text(
                    'El importe se distribuirá automáticamente a las deudas más antiguas.',
                  ),
                  if (message != null)
                    Text(message!, key: const ValueKey('payment-message')),
                  if (request != null)
                    Text('Solicitud guardada: ${request!.id}'),
                  if (request != null)
                    Text(
                      'Pago guardado: ${paymentMoney(request!.payload['p_importe'])} · ${request!.payload['p_medio_pago']}',
                    ),
                  if (result == null && request == null) ...[
                    TextField(
                      controller: amount,
                      enabled: available && !busy,
                      decoration: const InputDecoration(
                        labelText: 'Importe a cobrar',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: medium,
                      decoration: const InputDecoration(
                        labelText: 'Medio de pago',
                      ),
                      items: const ['Efectivo', 'Transferencia']
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                      onChanged: available && !busy
                          ? (s) => setState(() => medium = s!)
                          : null,
                    ),
                    TextField(
                      controller: observation,
                      enabled: available && !busy,
                      decoration: const InputDecoration(
                        labelText: 'Observación opcional',
                      ),
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
