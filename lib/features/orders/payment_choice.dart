import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/money_format.dart';

/// Cómo pagó el cliente al recibir: todo con un medio (un toque) o mixto / dejó saldo.
class PaymentChoice {
  const PaymentChoice({this.todo, this.efectivo = 0, this.transferencia = 0});

  /// 'Efectivo' o 'Transferencia' si pagó todo con ese medio.
  final String? todo;
  final double efectivo;
  final double transferencia;
}

/// Lo que se manda: la entrega lleva un pago (completo o parcial) y, si fue mixto, la otra
/// parte va como un cobro más del cliente.
class PaymentPlan {
  const PaymentPlan({this.completo, this.parcialImporte, this.parcialMedio, this.segundoImporte, this.segundoMedio});

  /// Medio si pagó todo.
  final String? completo;
  final double? parcialImporte;
  final String? parcialMedio;
  final double? segundoImporte;
  final String? segundoMedio;

  bool get sinPago => completo == null && parcialImporte == null;
}

PaymentPlan planPago(PaymentChoice c, double aCobrar) {
  if (c.todo != null) return PaymentPlan(completo: c.todo);
  final e = c.efectivo;
  final t = c.transferencia;
  if (e <= 0 && t <= 0) return const PaymentPlan();
  if (e > 0 && t > 0) {
    return PaymentPlan(parcialImporte: e, parcialMedio: 'Efectivo', segundoImporte: t, segundoMedio: 'Transferencia');
  }
  final (medio, importe) = e > 0 ? ('Efectivo', e) : ('Transferencia', t);
  // Un solo medio por todo lo que había que cobrar: es un pago completo.
  if ((importe - aCobrar).abs() < 0.005) return PaymentPlan(completo: medio);
  return PaymentPlan(parcialImporte: importe, parcialMedio: medio);
}

/// Ventana "¿Cómo quedó el pago?". null = cancelar.
Future<PaymentChoice?> showPaymentChoice(BuildContext context, {required double aCobrar, String? detalle}) {
  final transfer = TextEditingController();
  final cash = TextEditingController();
  var mixed = false;
  var cashTouched = false;
  var transferTouched = false;
  return showDialog<PaymentChoice>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, set) {
        final t = Tonos.of(context);
        final e = leerImporte(cash.text) ?? 0;
        final tr = leerImporte(transfer.text) ?? 0;
        final paid = e + tr;
        final over = paid - aCobrar > 0.005;
        final owes = aCobrar - paid;
        void autoFill(TextEditingController other, double typed, bool otherTouched) {
          if (otherTouched) return;
          final rest = aCobrar - typed;
          other.text = rest > 0 ? formatoNumero(rest) : '';
        }

        Widget field(String label, TextEditingController c, {required bool isCash}) => TextField(
          key: ValueKey(isCash ? 'pago-efectivo' : 'pago-transferencia'),
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: const [ImporteInputFormatter()],
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          decoration: InputDecoration(labelText: label, prefixText: '\$', border: const OutlineInputBorder()),
          onChanged: (_) => set(() {
            if (isCash) {
              cashTouched = true;
              autoFill(transfer, leerImporte(cash.text) ?? 0, transferTouched);
            } else {
              transferTouched = true;
              autoFill(cash, leerImporte(transfer.text) ?? 0, cashTouched);
            }
          }),
        );

        return AlertDialog(
          title: const Text('¿Cómo quedó el pago?'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (detalle != null) Text(detalle, style: TextStyle(color: t.secundario)),
                  const SizedBox(height: 6),
                  const Text('A cobrar'),
                  Text(formatoPesos(aCobrar), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (!mixed) ...[
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => Navigator.pop(context, const PaymentChoice(todo: 'Efectivo')),
                            icon: const Icon(Icons.payments_outlined),
                            label: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Text('TODO EFECTIVO', textAlign: TextAlign.center),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => Navigator.pop(context, const PaymentChoice(todo: 'Transferencia')),
                            icon: const Icon(Icons.phone_android),
                            label: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Text('TODO TRANSFERENCIA', textAlign: TextAlign.center),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => set(() => mixed = true),
                      icon: const Icon(Icons.call_split),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text('MIXTO O DEJÓ SALDO'),
                      ),
                    ),
                  ] else ...[
                    field('Transferencia', transfer, isCash: false),
                    const SizedBox(height: 10),
                    field('Efectivo', cash, isCash: true),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (over || owes > 0.005 ? t.etiquetaRoja : t.etiquetaVerde).$1,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        over
                            ? 'Es más de lo que hay que cobrar (${formatoPesos(aCobrar)}).'
                            : owes > 0.005
                            ? 'Cobrado ${formatoPesos(paid)} · queda debiendo ${formatoPesos(owes)}'
                            : 'Cobrado ${formatoPesos(paid)} · no queda saldo',
                        style: TextStyle(
                          color: (over || owes > 0.005 ? t.etiquetaRoja : t.etiquetaVerde).$2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => mixed ? set(() => mixed = false) : Navigator.pop(context),
              child: Text(mixed ? 'VOLVER' : 'CANCELAR'),
            ),
            if (mixed)
              FilledButton(
                onPressed: over ? null : () => Navigator.pop(context, PaymentChoice(efectivo: e, transferencia: tr)),
                child: const Text('CONFIRMAR'),
              ),
          ],
        );
      },
    ),
  );
}
